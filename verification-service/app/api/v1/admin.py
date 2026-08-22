"""
app/api/v1/admin.py
────────────────────
Admin-only endpoints for the verification dashboard.

All routes require:
  1. Valid Firebase ID token
  2. `admin: true` custom claim in Firebase

Endpoints:
  GET  /admin/verifications/pending   — List manual review queue
  GET  /admin/verifications/all       — List all (paginated)
  POST /admin/verifications/{uid}/approve
  POST /admin/verifications/{uid}/reject
  POST /admin/verifications/{uid}/request-new
  GET  /admin/stats                   — Dashboard stats
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import verify_firebase_token, require_admin
from app.services.firestore_service import (
    admin_update_verification,
    get_pending_verifications,
    get_verification_record,
)
from app.schemas.verification_schema import AdminActionRequest, AdminStatsResponse

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/admin", tags=["Admin"])


async def _get_admin_token(
    decoded_token: dict = Depends(verify_firebase_token),
) -> dict:
    """Dependency: verify token AND admin claim."""
    return await require_admin(decoded_token)


@router.get("/verifications/pending")
async def list_pending(
    limit: int = 50,
    admin: dict = Depends(_get_admin_token),
) -> list[dict]:
    """Return all verifications awaiting manual review."""
    return get_pending_verifications(limit=limit)


@router.get("/verifications/{user_id}")
async def get_verification_detail(
    user_id: str,
    admin: dict = Depends(_get_admin_token),
) -> dict:
    """Return full verification record for one user."""
    record = get_verification_record(user_id)
    if not record:
        raise HTTPException(status_code=404, detail="No verification record found.")
    return {"userId": user_id, **record}


@router.post("/verifications/{user_id}/approve", status_code=200)
async def approve_verification(
    user_id: str,
    body: AdminActionRequest,
    admin: dict = Depends(_get_admin_token),
) -> dict:
    """Manually approve a verification and grant the S badge."""
    admin_update_verification(
        user_id=user_id,
        new_status="approved",
        admin_uid=admin["uid"],
        reason=body.reason or "Manually approved by admin",
    )
    logger.info("Admin %s approved verification for %s", admin["uid"], user_id)
    return {"success": True, "message": f"User {user_id} verified."}


@router.post("/verifications/{user_id}/reject", status_code=200)
async def reject_verification(
    user_id: str,
    body: AdminActionRequest,
    admin: dict = Depends(_get_admin_token),
) -> dict:
    """Manually reject a verification."""
    if not body.reason:
        raise HTTPException(
            status_code=400,
            detail="A rejection reason is required.",
        )
    admin_update_verification(
        user_id=user_id,
        new_status="rejected",
        admin_uid=admin["uid"],
        reason=body.reason,
    )
    logger.info("Admin %s rejected verification for %s: %s", admin["uid"], user_id, body.reason)
    return {"success": True, "message": f"Verification for {user_id} rejected."}


@router.post("/verifications/{user_id}/request-new", status_code=200)
async def request_new_verification(
    user_id: str,
    body: AdminActionRequest,
    admin: dict = Depends(_get_admin_token),
) -> dict:
    """
    Reset a user's verification so they can try again.
    Decrements their attempt count by 1 so they don't lose a slot.
    """
    from firebase_admin import firestore as fs
    db = fs.client()
    ref = db.collection("verifications").document(user_id)
    doc = ref.get()
    if doc.exists:
        current = doc.to_dict().get("verificationAttempts", 0)
        new_count = max(0, current - 1)
        ref.update({
            "verificationStatus": "not_started",
            "verificationAttempts": new_count,
            "resetReason": body.reason or "Reset by admin",
            "resetBy": admin["uid"],
        })

    logger.info("Admin %s reset verification for %s", admin["uid"], user_id)
    return {"success": True, "message": f"User {user_id} can now re-attempt verification."}


@router.get("/stats")
async def get_stats(
    admin: dict = Depends(_get_admin_token),
) -> dict:
    """Return dashboard stats (counts per status)."""
    from firebase_admin import firestore as fs
    db = fs.client()
    verifications = db.collection("verifications")

    stats = {
        "pending_review": 0,
        "approved": 0,
        "rejected": 0,
        "total": 0,
    }

    for status_val in ["manual_review", "approved", "rejected", "pending"]:
        count = len(list(verifications.where("verificationStatus", "==", status_val).stream()))
        if status_val == "manual_review":
            stats["pending_review"] = count
        elif status_val in stats:
            stats[status_val] = count
        stats["total"] += count

    return stats


@router.post("/set-admin/{user_id}")
async def set_admin_claim(
    user_id: str,
    admin: dict = Depends(_get_admin_token),
) -> dict:
    """
    Grant admin Firebase custom claim to a user.
    Only callable by an existing admin.
    """
    from firebase_admin import auth
    auth.set_custom_user_claims(user_id, {"admin": True})
    logger.info("Admin %s granted admin claim to %s", admin["uid"], user_id)
    return {"success": True, "message": f"User {user_id} is now an admin."}
