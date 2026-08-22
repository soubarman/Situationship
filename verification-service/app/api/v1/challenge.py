"""
app/api/v1/challenge.py
────────────────────────
POST /api/v1/challenge

Generates a unique, time-limited verification challenge.
Every call returns a different combination of:
  • 6-digit code
  • Phrase to say
  • Facial action (smile, blink, etc.)
  • Head movement direction

Challenge TTL: 15 minutes (configurable).
One-time use: marked as used after video submission.
"""

import logging
import random
import string
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from firebase_admin import firestore

from app.core.config import get_settings
from app.core.security import verify_firebase_token
from app.schemas.challenge_schema import ChallengeResponse
from app.services.firestore_service import (
    create_challenge,
    get_verification_record,
)

logger = logging.getLogger(__name__)
settings = get_settings()
router = APIRouter(prefix="/challenge", tags=["Challenge"])

# ── Challenge content pools ───────────────────────────────────────────────────

ACTIONS = [
    "smile", "blink twice", "open your mouth slightly",
    "raise your eyebrows", "wink your left eye", "wink your right eye",
]

MOVEMENTS = [
    "turn your head slightly to the left",
    "turn your head slightly to the right",
    "nod your head slowly",
    "tilt your head to the left",
    "tilt your head to the right",
    "look up briefly then back at camera",
]


def _generate_code() -> str:
    return "".join(random.choices(string.digits, k=6))


@router.post("", response_model=ChallengeResponse, status_code=status.HTTP_201_CREATED)
async def generate_challenge(
    decoded_token: dict = Depends(verify_firebase_token),
) -> ChallengeResponse:
    """
    Generate a fresh verification challenge for the authenticated user.

    Rate limited to 10 requests/hour per user.
    Blocked if the user has exceeded MAX_VERIFICATION_ATTEMPTS.
    """
    user_id = decoded_token["uid"]

    # ── Check attempt limit ───────────────────────────────────────
    record = get_verification_record(user_id)
    if record:
        attempts = record.get("verificationAttempts", 0)
        if attempts >= settings.MAX_VERIFICATION_ATTEMPTS:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail=(
                    f"Maximum verification attempts ({settings.MAX_VERIFICATION_ATTEMPTS}) "
                    "reached. Please contact support."
                ),
            )

        # Check 24-hour cooldown between attempts
        if attempts > 0:
            last_attempt = record.get("lastAttemptAt")
            if last_attempt:
                # Firestore timestamps come as datetime
                if isinstance(last_attempt, datetime):
                    cooldown_end = last_attempt + timedelta(hours=settings.ATTEMPT_COOLDOWN_HOURS)
                    now = datetime.now(timezone.utc)
                    if hasattr(last_attempt, 'tzinfo') and last_attempt.tzinfo is None:
                        last_attempt = last_attempt.replace(tzinfo=timezone.utc)
                        cooldown_end = last_attempt + timedelta(hours=settings.ATTEMPT_COOLDOWN_HOURS)
                    if now < cooldown_end:
                        wait_minutes = int((cooldown_end - now).total_seconds() / 60)
                        raise HTTPException(
                            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                            detail=f"Please wait {wait_minutes} minutes before trying again.",
                        )

    # ── Generate challenge ────────────────────────────────────────
    code = _generate_code()
    action = random.choice(ACTIONS)
    movement = random.choice(MOVEMENTS)
    challenge_id = str(uuid.uuid4())

    expires_at = datetime.now(timezone.utc) + timedelta(seconds=settings.CHALLENGE_TTL_SECONDS)

    challenge_data = {
        "id": challenge_id,
        "userId": user_id,
        "code": code,
        "phrase": f"My verification code is {code}",
        "action": action,
        "movement": movement,
        "expiresAt": expires_at,
    }

    create_challenge(challenge_data)
    logger.info("Challenge %s created for user %s", challenge_id, user_id)

    return ChallengeResponse(
        challengeId=challenge_id,
        code=code,
        phrase=f"My verification code is {code}",
        action=action,
        movement=movement,
        expiresAt=expires_at.isoformat(),
        ttlSeconds=settings.CHALLENGE_TTL_SECONDS,
    )
