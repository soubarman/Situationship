"""
app/workers/verification_worker.py
────────────────────────────────────
The core Celery task that runs the full verification pipeline.

Pipeline:
  1. Download video from Firebase Storage
  2. Download profile photo from Firebase Storage
  3. Extract reference face embedding from profile photo
  4. FFmpeg: extract 1 frame/sec from video
  5. For each frame:
     a. Detect face
     b. Compute liveness score
     c. Compute similarity vs reference embedding
     d. Compute frame quality
  6. Aggregate → weighted confidence score
  7. Auto-decide: approved / manual_review / rejected
  8. Write result to Firestore
  9. Delete temp files
  10. Optionally delete video from storage

This task runs asynchronously. FastAPI returns a job_id immediately;
the Flutter app polls GET /status/{job_id} until complete.
"""

import logging
import os
import shutil
import tempfile
import urllib.request
from typing import Optional

import cv2

from app.workers.celery_app import celery_app
from app.core.config import get_settings
from app.engine.loader import get_models, load_all_models
from app.engine.face_detector import get_primary_face
from app.engine.face_comparator import (
    get_face_embedding,
    compute_similarity,
    compute_face_quality,
)
from app.engine.liveness_detector import compute_liveness_score
from app.engine.confidence_scorer import (
    FrameResult,
    aggregate_and_score,
)
from app.services.video_processor import process_verification_video
from app.services.firestore_service import (
    get_user_profile_photo_url,
    save_verification_result,
    mark_challenge_used,
)

logger = logging.getLogger(__name__)
settings = get_settings()

ENGINE_VERSION = "1.0.0"


def _ensure_models_loaded() -> None:
    """Load models if not yet loaded (handles Celery worker startup)."""
    models = get_models()
    if not models.is_ready:
        logger.info("Worker: Models not loaded yet — loading now.")
        load_all_models()


def _download_file(url: str, dest_path: str) -> None:
    """Download a file from a URL to a local path."""
    urllib.request.urlretrieve(url, dest_path)


def _get_profile_photo_array(profile_url: str, tmp_dir: str) -> Optional[object]:
    """Download profile photo and return as BGR numpy array."""
    photo_path = os.path.join(tmp_dir, "profile_photo.jpg")
    try:
        _download_file(profile_url, photo_path)
        img = cv2.imread(photo_path)
        if img is None:
            logger.error("Could not decode profile photo from %s", profile_url)
        return img
    except Exception as exc:
        logger.error("Failed to download profile photo: %s", exc)
        return None


@celery_app.task(
    bind=True,
    name="tasks.run_verification",
    max_retries=2,
    default_retry_delay=30,
    autoretry_for=(ConnectionError, TimeoutError),
)
def run_verification(
    self,
    *,
    user_id: str,
    video_download_url: str,
    challenge_id: str,
    attempt_number: int,
) -> dict:
    """
    Full verification pipeline Celery task.

    Parameters (passed as kwargs to avoid positional arg issues):
      user_id            : Firebase UID
      video_download_url : Signed Firebase Storage download URL
      challenge_id       : The challenge this verification answers
      attempt_number     : Which attempt this is (1–5)

    Returns a status dict (also stored in Celery result backend).
    """
    logger.info(
        "Starting verification for user=%s attempt=%d job=%s",
        user_id, attempt_number, self.request.id,
    )

    tmp_dir = tempfile.mkdtemp(prefix=f"verify_{user_id}_")

    try:
        _ensure_models_loaded()

        # ── Step 1: Download video ────────────────────────────────
        video_path = os.path.join(tmp_dir, "verification.mp4")
        logger.info("Downloading verification video…")
        _download_file(video_download_url, video_path)

        # ── Step 2: Get profile photo ────────────────────────────
        profile_url = get_user_profile_photo_url(user_id)
        if not profile_url:
            return _save_failure(
                user_id,
                "User has no profile photo. Please set a profile photo first.",
                0.0,
            )

        profile_img = _get_profile_photo_array(profile_url, tmp_dir)
        if profile_img is None:
            return _save_failure(user_id, "Could not load profile photo.", 0.0)

        # ── Step 3: Reference embedding from profile photo ────────
        reference_embedding = get_face_embedding(profile_img)
        if reference_embedding is None:
            return _save_failure(
                user_id,
                "No face detected in profile photo. Please update your profile photo.",
                0.0,
            )

        # ── Step 4: Extract video frames ──────────────────────────
        logger.info("Processing video frames…")
        try:
            frames = process_verification_video(video_path)
        except ValueError as exc:
            return _save_failure(user_id, str(exc), 0.0)

        if not frames:
            return _save_failure(
                user_id,
                "No usable frames found in video. Please record in better lighting.",
                0.0,
            )

        # ── Step 5: Per-frame analysis ────────────────────────────
        frame_results: list[FrameResult] = []

        for idx, frame in enumerate(frames):
            face = get_primary_face(frame)

            if face is None:
                frame_results.append(FrameResult(
                    frame_index=idx,
                    face_similarity=0.0,
                    liveness_score=0.0,
                    face_quality=0.0,
                    gender_consistent=None,
                    is_usable=False,
                ))
                continue

            # Face similarity vs reference
            if face.embedding is not None:
                similarity = compute_similarity(face.embedding, reference_embedding)
            else:
                similarity = 0.0

            # Liveness
            liveness = compute_liveness_score(frame, face.bbox)

            # Quality
            quality = compute_face_quality(frame, face.bbox)

            frame_results.append(FrameResult(
                frame_index=idx,
                face_similarity=similarity,
                liveness_score=liveness,
                face_quality=quality,
                gender_consistent=None,  # Not used for decision
                is_usable=True,
            ))

            logger.debug(
                "Frame %d: sim=%.3f liveness=%.3f quality=%.3f",
                idx, similarity, liveness, quality,
            )

        # ── Step 6: Aggregate & score ─────────────────────────────
        result = aggregate_and_score(frame_results)

        # ── Step 7: Save to Firestore ─────────────────────────────
        save_verification_result(
            user_id=user_id,
            result=result,
            engine_version=ENGINE_VERSION,
            verified_by="auto" if result.decision == "approved" else "auto:pending_review",
        )

        # Mark challenge as used (replay protection)
        try:
            mark_challenge_used(challenge_id)
        except Exception as exc:
            logger.warning("Could not mark challenge as used: %s", exc)

        logger.info(
            "Verification complete for user=%s: %s (%.4f)",
            user_id, result.decision, result.final_score,
        )

        return {
            "status": "completed",
            "decision": result.decision,
            "score": result.final_score,
            "reason": result.rejection_reason,
        }

    except Exception as exc:
        logger.exception("Verification pipeline failed for user=%s: %s", user_id, exc)
        save_verification_result(
            user_id=user_id,
            result=_make_error_result(str(exc)),
            engine_version=ENGINE_VERSION,
        )
        raise

    finally:
        # Always clean up temp directory
        shutil.rmtree(tmp_dir, ignore_errors=True)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _save_failure(user_id: str, reason: str, score: float) -> dict:
    """Save a failure result and return a status dict."""
    from app.engine.confidence_scorer import VerificationResult
    result = VerificationResult(
        final_score=score,
        decision="rejected",
        avg_face_similarity=0.0,
        avg_liveness_score=0.0,
        avg_face_quality=0.0,
        best_frame_similarity=0.0,
        usable_frame_count=0,
        total_frame_count=0,
        rejection_reason=reason,
    )
    save_verification_result(user_id=user_id, result=result)
    return {"status": "completed", "decision": "rejected", "reason": reason}


def _make_error_result(error_message: str):
    """Create an error VerificationResult for exception handling."""
    from app.engine.confidence_scorer import VerificationResult
    return VerificationResult(
        final_score=0.0,
        decision="rejected",
        avg_face_similarity=0.0,
        avg_liveness_score=0.0,
        avg_face_quality=0.0,
        best_frame_similarity=0.0,
        usable_frame_count=0,
        total_frame_count=0,
        rejection_reason=f"Internal error: {error_message}",
    )
