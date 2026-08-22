"""
app/services/firestore_service.py
──────────────────────────────────
Firestore read/write service for the verification pipeline.

Follows the repository pattern — all Firestore access goes through here.
The Celery worker and API layer never touch Firestore directly.
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional, Any

from firebase_admin import firestore
from google.cloud.firestore_v1 import SERVER_TIMESTAMP

from app.core.config import get_settings
from app.engine.confidence_scorer import VerificationResult

logger = logging.getLogger(__name__)
settings = get_settings()


def _db():
    """Return the Firestore client (lazily initialized)."""
    return firestore.client()


# ── Challenge ─────────────────────────────────────────────────────────────────

def create_challenge(challenge_data: dict) -> None:
    """Save a new challenge document to Firestore."""
    _db().collection("challenges").document(challenge_data["id"]).set({
        **challenge_data,
        "createdAt": SERVER_TIMESTAMP,
        "used": False,
    })


def get_challenge(challenge_id: str) -> Optional[dict]:
    """Fetch a challenge by ID. Returns None if not found."""
    doc = _db().collection("challenges").document(challenge_id).get()
    return doc.to_dict() if doc.exists else None


def mark_challenge_used(challenge_id: str) -> None:
    """Mark challenge as used (one-time replay protection)."""
    _db().collection("challenges").document(challenge_id).update({
        "used": True,
        "usedAt": SERVER_TIMESTAMP,
    })


# ── Verification ──────────────────────────────────────────────────────────────

def get_verification_record(user_id: str) -> Optional[dict]:
    """Fetch the verification record for a user."""
    doc = _db().collection("verifications").document(user_id).get()
    return doc.to_dict() if doc.exists else None


def increment_attempt_count(user_id: str) -> int:
    """
    Atomically increment the attempt counter.
    Returns the NEW attempt count after increment.
    """
    ref = _db().collection("verifications").document(user_id)
    doc = ref.get()
    current = doc.to_dict().get("verificationAttempts", 0) if doc.exists else 0
    new_count = current + 1
    ref.set(
        {
            "verificationAttempts": new_count,
            "lastAttemptAt": SERVER_TIMESTAMP,
        },
        merge=True,
    )
    return new_count


def save_verification_pending(
    user_id: str,
    job_id: str,
    challenge_id: str,
    video_storage_path: str,
    attempt_number: int,
) -> None:
    """Set the verification status to pending while the job is running."""
    _db().collection("verifications").document(user_id).set(
        {
            "verificationStatus": "pending",
            "currentJobId": job_id,
            "challengeId": challenge_id,
            "videoStoragePath": video_storage_path,
            "verificationAttempts": attempt_number,
            "lastAttemptAt": SERVER_TIMESTAMP,
            "autoDeleteAt": datetime.now(timezone.utc)
            + timedelta(days=settings.VIDEO_RETENTION_DAYS),
        },
        merge=True,
    )


def save_verification_result(
    user_id: str,
    result: VerificationResult,
    engine_version: str = "1.0.0",
    verified_by: str = "auto",
) -> None:
    """Write the final verification outcome to Firestore."""
    status_map = {
        "approved": "approved",
        "manual_review": "manual_review",
        "rejected": "rejected",
    }
    status = status_map.get(result.decision, "rejected")

    update_data: dict[str, Any] = {
        "verificationStatus": status,
        "verificationScore": result.final_score,
        "verificationVersion": engine_version,
        "verificationDate": SERVER_TIMESTAMP,
        "verificationReason": result.rejection_reason or "",
        "verifiedBy": verified_by,
        "scoreBreakdown": result.score_breakdown,
        "usableFrames": result.usable_frame_count,
        "totalFrames": result.total_frame_count,
    }

    if status == "approved":
        update_data["verifiedBadge"] = "S"
        # Also update the user's profile for quick read
        _db().collection("users").document(user_id).update({
            "isVerified": True,
            "verifiedBadge": "S",
        })

    _db().collection("verifications").document(user_id).set(update_data, merge=True)
    logger.info("Verification result saved for user %s: %s (%.4f)", user_id, status, result.final_score)


def admin_update_verification(
    user_id: str,
    new_status: str,           # "approved" | "rejected" | "pending"
    admin_uid: str,
    reason: str = "",
) -> None:
    """Allow an admin to manually override the verification decision."""
    update: dict[str, Any] = {
        "verificationStatus": new_status,
        "verifiedBy": f"admin:{admin_uid}",
        "verificationReason": reason,
        "adminReviewedAt": SERVER_TIMESTAMP,
    }
    if new_status == "approved":
        update["verifiedBadge"] = "S"
        _db().collection("users").document(user_id).update({
            "isVerified": True,
            "verifiedBadge": "S",
        })
    elif new_status == "rejected":
        _db().collection("users").document(user_id).update({
            "isVerified": False,
            "verifiedBadge": None,
        })

    _db().collection("verifications").document(user_id).set(update, merge=True)

    # Audit log
    _db().collection("verification_audit_logs").add({
        "userId": user_id,
        "action": f"admin_{new_status}",
        "adminUid": admin_uid,
        "reason": reason,
        "timestamp": SERVER_TIMESTAMP,
    })
    logger.info("Admin %s updated verification for %s → %s", admin_uid, user_id, new_status)


def get_pending_verifications(limit: int = 50) -> list[dict]:
    """Fetch all pending (manual review) verifications for admin dashboard."""
    docs = (
        _db()
        .collection("verifications")
        .where("verificationStatus", "==", "manual_review")
        .order_by("lastAttemptAt")
        .limit(limit)
        .stream()
    )
    return [{"userId": d.id, **d.to_dict()} for d in docs]


def get_user_profile_photo_url(user_id: str) -> Optional[str]:
    """Fetch the profile photo URL from the user document."""
    doc = _db().collection("users").document(user_id).get()
    if not doc.exists:
        return None
    return doc.to_dict().get("profileImage") or doc.to_dict().get("profilePicture")
