"""
app/core/security.py
─────────────────────
Firebase JWT validation middleware.
Every protected endpoint calls `verify_firebase_token()`
to ensure the request comes from an authenticated Firebase user.
"""

import logging
from typing import Optional
from fastapi import HTTPException, Header, status
import firebase_admin
from firebase_admin import auth as firebase_auth
from app.core.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


async def verify_firebase_token(
    authorization: Optional[str] = Header(None),
) -> dict:
    """
    Extract and verify a Firebase ID token from the Authorization header.

    Returns the decoded token payload including uid, email, and custom claims.
    Raises HTTP 401 if missing, expired, or invalid.
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authorization header missing",
        )

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Authorization format. Use: Bearer <token>",
        )

    try:
        decoded = firebase_auth.verify_id_token(token, check_revoked=True)
        return decoded
    except firebase_auth.RevokedIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has been revoked. Please sign in again.",
        )
    except firebase_auth.ExpiredIdTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired. Please sign in again.",
        )
    except firebase_auth.InvalidIdTokenError as exc:
        logger.warning("Invalid Firebase token: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token.",
        )
    except Exception as exc:
        logger.error("Unexpected auth error: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Authentication service error.",
        )


async def require_admin(
    decoded_token: dict,
) -> dict:
    """
    Verify that the authenticated user has admin privileges.
    Admin status is stored in Firebase custom claims: { "admin": true }
    """
    if not decoded_token.get("admin", False):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required.",
        )
    return decoded_token
