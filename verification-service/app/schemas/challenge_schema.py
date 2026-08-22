"""
app/schemas/challenge_schema.py
app/schemas/verification_schema.py
───────────────────────────────────
Pydantic request/response models.
"""

from pydantic import BaseModel
from typing import Optional


class ChallengeResponse(BaseModel):
    challengeId: str
    code: str
    phrase: str
    action: str
    movement: str
    expiresAt: str
    ttlSeconds: int
