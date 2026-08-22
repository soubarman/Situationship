"""
app/api/v1/verification.py
───────────────────────────
POST /api/v1/verify        — Submit a verification video
GET  /api/v1/status/{id}   — Poll job status
"""

import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.config import get_settings
from app.core.security import verify_firebase_token
from app.schemas.verification_schema import VerifyRequest, VerifyResponse, StatusResponse
from app.services.firestore_service import (
    get_verification_record,
    get_challenge,
    increment_attempt_count,
    save_verification_pending,
)
from app.workers.verification_worker import run_verification

logger = logging.getLogger(__name__)
settings = get_settings()
router = APIRouter(prefix="/verify", tags=["Verification"])


@router.post("", response_model=VerifyResponse, status_code=status.HTTP_202_ACCEPTED)
async def submit_verification(
    body: VerifyRequest,
    decoded_token: dict = Depends(verify_firebase_token),
) -> VerifyResponse:
    """
    Accept a verification submission.

    The Flutter app:
    1. Uploads video directly to Firebase Storage via signed URL
    2. Calls this endpoint with the storage path + challenge ID

    This endpoint:
    1. Validates the challenge (not expired, not used, belongs to this user)
    2. Checks attempt limits
    3. Enqueues the Celery job
    4. Returns a job_id for status polling
    """
    user_id = decoded_token["uid"]

    # ── Validate challenge ────────────────────────────────────────
    challenge = get_challenge(body.challengeId)
    if not challenge:
        raise HTTPException(status_code=400, detail="Challenge not found.")

    if challenge.get("userId") != user_id:
        raise HTTPException(status_code=403, detail="Challenge does not belong to this user.")

    if challenge.get("used", False):
        raise HTTPException(status_code=409, detail="Challenge already used.")

    # Check expiry
    expires_at = challenge.get("expiresAt")
    if expires_at:
        if isinstance(expires_at, datetime):
            exp = expires_at if expires_at.tzinfo else expires_at.replace(tzinfo=timezone.utc)
            if datetime.now(timezone.utc) > exp:
                raise HTTPException(status_code=410, detail="Challenge has expired. Please request a new one.")

    # ── Attempt limit ─────────────────────────────────────────────
    record = get_verification_record(user_id)
    current_attempts = record.get("verificationAttempts", 0) if record else 0

    if current_attempts >= settings.MAX_VERIFICATION_ATTEMPTS:
        raise HTTPException(
            status_code=429,
            detail=(
                f"Maximum verification attempts ({settings.MAX_VERIFICATION_ATTEMPTS}) reached. "
                "Please contact support."
            ),
        )

    # ── Generate signed download URL for the worker ───────────────
    # The worker downloads the video using a Firebase Admin SDK signed URL.
    # We pass the storage path; the worker generates the signed URL itself.
    # (Avoids exposing raw URLs in API responses)
    job_id = str(uuid.uuid4())
    new_attempt_count = increment_attempt_count(user_id)

    # Save pending status in Firestore
    save_verification_pending(
        user_id=user_id,
        job_id=job_id,
        challenge_id=body.challengeId,
        video_storage_path=body.videoStoragePath,
        attempt_number=new_attempt_count,
    )

    # ── Enqueue Celery task ───────────────────────────────────────
    # We pass the storage PATH; the worker generates a signed download URL.
    run_verification.apply_async(
        kwargs={
            "user_id": user_id,
            "video_download_url": body.videoDownloadUrl,  # Short-lived signed URL from client
            "challenge_id": body.challengeId,
            "attempt_number": new_attempt_count,
        },
        task_id=job_id,
    )

    logger.info(
        "Verification job %s queued for user %s (attempt %d/%d)",
        job_id, user_id, new_attempt_count, settings.MAX_VERIFICATION_ATTEMPTS,
    )

    return VerifyResponse(
        jobId=job_id,
        status="pending",
        attemptsUsed=new_attempt_count,
        attemptsRemaining=settings.MAX_VERIFICATION_ATTEMPTS - new_attempt_count,
    )


@router.get("/status/{job_id}", response_model=StatusResponse)
async def get_status(
    job_id: str,
    decoded_token: dict = Depends(verify_firebase_token),
) -> StatusResponse:
    """
    Poll the status of a verification job.

    The Flutter app polls this every 3 seconds until:
      • status == "completed" (check Firestore for decision)
      • status == "failed"
      • timeout (60 seconds)
    """
    from celery.result import AsyncResult
    from app.workers.celery_app import celery_app

    result = AsyncResult(job_id, app=celery_app)

    if result.state == "PENDING":
        return StatusResponse(jobId=job_id, status="pending", message="Processing…")
    elif result.state == "SUCCESS":
        payload = result.result or {}
        return StatusResponse(
            jobId=job_id,
            status="completed",
            decision=payload.get("decision"),
            score=payload.get("score"),
            message=payload.get("reason"),
        )
    elif result.state == "FAILURE":
        return StatusResponse(
            jobId=job_id,
            status="failed",
            message="Verification processing failed. Please try again.",
        )
    else:
        return StatusResponse(jobId=job_id, status="processing", message="Running AI pipeline…")
