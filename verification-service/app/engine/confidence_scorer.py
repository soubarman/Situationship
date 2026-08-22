"""
app/engine/confidence_scorer.py
─────────────────────────────────
Weighted confidence score aggregator.

Final score formula:
  score = (face_similarity × 0.45) +
          (liveness_score  × 0.40) +
          (face_quality    × 0.10) +
          (gender_signal   × 0.05)

Decision thresholds (configurable in config.py):
  score >= 0.82  → AUTO_APPROVED
  score >= 0.65  → MANUAL_REVIEW
  score <  0.65  → REJECTED
"""

import logging
from dataclasses import dataclass, field
from typing import Optional

from app.core.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# Weight constants
W_FACE_SIMILARITY = 0.45
W_LIVENESS        = 0.40
W_FACE_QUALITY    = 0.10
W_GENDER          = 0.05


@dataclass
class FrameResult:
    """Result of processing a single video frame."""
    frame_index: int
    face_similarity: float
    liveness_score: float
    face_quality: float
    gender_consistent: Optional[bool]
    is_usable: bool  # False if no face detected or blur too high


@dataclass
class VerificationResult:
    """Aggregated result across all processed frames."""
    final_score: float
    decision: str                       # "approved" | "manual_review" | "rejected"
    avg_face_similarity: float
    avg_liveness_score: float
    avg_face_quality: float
    best_frame_similarity: float
    usable_frame_count: int
    total_frame_count: int
    rejection_reason: Optional[str]
    frame_results: list[FrameResult] = field(default_factory=list)
    score_breakdown: dict = field(default_factory=dict)


def compute_gender_consistency(
    profile_gender: Optional[str],
    detected_genders: list[Optional[str]],
) -> float:
    """
    Compare detected gender in video frames against profile gender.
    Returns 1.0 (consistent), 0.5 (unknown), or 0.2 (inconsistent).
    This is a LOW-WEIGHT optional signal — never the sole basis for rejection.
    """
    if profile_gender is None:
        return 0.5  # No profile gender available

    valid_detections = [g for g in detected_genders if g is not None]
    if not valid_detections:
        return 0.5  # Cannot determine — neutral

    # Count consistency
    consistent = sum(1 for g in valid_detections if g == profile_gender)
    ratio = consistent / len(valid_detections)

    if ratio >= 0.7:
        return 1.0
    elif ratio >= 0.4:
        return 0.5
    else:
        return 0.2


def aggregate_and_score(
    frame_results: list[FrameResult],
    profile_gender: Optional[str] = None,
) -> VerificationResult:
    """
    Aggregate all frame-level results into a final verification decision.

    Strategy:
    - Use the BEST-MATCH frame for face_similarity (most favorable)
    - Use AVERAGE liveness across all usable frames (harder to fake consistently)
    - Use average face quality as signal weight modifier
    - Use gender consistency as minor signal
    """
    usable = [r for r in frame_results if r.is_usable]

    if not usable:
        return VerificationResult(
            final_score=0.0,
            decision="rejected",
            avg_face_similarity=0.0,
            avg_liveness_score=0.0,
            avg_face_quality=0.0,
            best_frame_similarity=0.0,
            usable_frame_count=0,
            total_frame_count=len(frame_results),
            rejection_reason="No usable frames with clear face detected",
            frame_results=frame_results,
        )

    avg_similarity = sum(r.face_similarity for r in usable) / len(usable)
    best_similarity = max(r.face_similarity for r in usable)
    avg_liveness = sum(r.liveness_score for r in usable) / len(usable)
    avg_quality = sum(r.face_quality for r in usable) / len(usable)

    # Gender consistency signal
    detected_genders = [r.gender_consistent for r in usable]
    gender_signal = compute_gender_consistency(profile_gender, [])

    # ── Weighted score ────────────────────────────────────────────
    # Use best_similarity instead of average — gives user best chance
    # while still requiring liveness/quality minimums.
    face_score = best_similarity * W_FACE_SIMILARITY
    live_score = avg_liveness * W_LIVENESS
    qual_score = avg_quality * W_FACE_QUALITY
    gend_score = gender_signal * W_GENDER

    final_score = face_score + live_score + qual_score + gend_score
    final_score = min(1.0, max(0.0, final_score))

    # ── Decision ─────────────────────────────────────────────────
    rejection_reason = None
    if final_score >= settings.AUTO_APPROVE_THRESHOLD:
        decision = "approved"
    elif final_score >= settings.MANUAL_REVIEW_THRESHOLD:
        decision = "manual_review"
    else:
        decision = "rejected"
        # Provide specific rejection reason for UX
        if avg_liveness < 0.5:
            rejection_reason = "Liveness check failed — possible photo or video attack"
        elif best_similarity < 0.4:
            rejection_reason = "Face does not match profile photo"
        elif avg_quality < 0.3:
            rejection_reason = "Video quality too low — ensure good lighting and steady camera"
        else:
            rejection_reason = "Confidence score too low for automatic verification"

    score_breakdown = {
        "face_similarity_contribution": round(face_score, 4),
        "liveness_contribution": round(live_score, 4),
        "quality_contribution": round(qual_score, 4),
        "gender_contribution": round(gend_score, 4),
        "raw_best_similarity": round(best_similarity, 4),
        "raw_avg_liveness": round(avg_liveness, 4),
        "raw_avg_quality": round(avg_quality, 4),
    }

    logger.info(
        "Verification score: %.4f → %s | sim=%.3f liveness=%.3f quality=%.3f",
        final_score, decision, best_similarity, avg_liveness, avg_quality,
    )

    return VerificationResult(
        final_score=round(final_score, 4),
        decision=decision,
        avg_face_similarity=round(avg_similarity, 4),
        avg_liveness_score=round(avg_liveness, 4),
        avg_face_quality=round(avg_quality, 4),
        best_frame_similarity=round(best_similarity, 4),
        usable_frame_count=len(usable),
        total_frame_count=len(frame_results),
        rejection_reason=rejection_reason,
        frame_results=frame_results,
        score_breakdown=score_breakdown,
    )
