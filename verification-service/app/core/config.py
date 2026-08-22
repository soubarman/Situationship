"""
app/core/config.py
──────────────────
Central configuration loaded from environment variables.
All secrets live in .env — never hardcoded.
"""

from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # ── App ──────────────────────────────────────────────────────
    APP_NAME: str = "Situationship Verification Service"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    SECRET_KEY: str = "change-me-in-production"

    # ── Server ───────────────────────────────────────────────────
    API_V1_PREFIX: str = "/api/v1"
    ALLOWED_ORIGINS: list[str] = ["https://situatioship.netlify.app"]

    # ── Redis ────────────────────────────────────────────────────
    REDIS_URL: str = "redis://redis:6379/0"
    RESULT_EXPIRES_SECONDS: int = 86_400  # 24 hours

    # ── Firebase ─────────────────────────────────────────────────
    FIREBASE_SERVICE_ACCOUNT_JSON: str = ""   # Path to service account JSON
    FIREBASE_PROJECT_ID: str = "situation-ship"
    FIREBASE_STORAGE_BUCKET: str = "situation-ship.appspot.com"

    # ── Verification Pipeline ─────────────────────────────────────
    MAX_VERIFICATION_ATTEMPTS: int = 5
    ATTEMPT_COOLDOWN_HOURS: int = 24
    CHALLENGE_TTL_SECONDS: int = 900          # 15 minutes

    # Auto-decision thresholds
    AUTO_APPROVE_THRESHOLD: float = 0.82
    MANUAL_REVIEW_THRESHOLD: float = 0.65

    # Video constraints
    VIDEO_MAX_DURATION_SECONDS: int = 15
    VIDEO_MAX_SIZE_MB: int = 10               # Allow slight overhead
    FRAMES_PER_SECOND: int = 1               # Extract 1 frame/sec from video
    BLUR_THRESHOLD: float = 100.0             # Laplacian variance threshold

    # Video retention
    VIDEO_RETENTION_DAYS: int = 7            # Delete after N days
    DELETE_VIDEO_ON_APPROVE: bool = True

    # ── Rate Limiting ─────────────────────────────────────────────
    RATE_LIMIT_VERIFY: str = "3/day"
    RATE_LIMIT_CHALLENGE: str = "10/hour"
    RATE_LIMIT_STATUS: str = "60/minute"

    # ── Models ───────────────────────────────────────────────────
    INSIGHTFACE_MODEL_PACK: str = "antelopev2"
    MODEL_DIR: str = "/app/models"
    LIVENESS_MODEL_PATH: str = "/app/models/liveness/2.7_80x80_MiniFASNetV2.onnx"
    LIVENESS_MODEL_PATH_2: str = "/app/models/liveness/4_0_0_80x80_MiniFASNetV1SE.onnx"

    # ── Admin ────────────────────────────────────────────────────
    ADMIN_EMAILS: list[str] = []             # Email list of admin users

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache
def get_settings() -> Settings:
    """Return cached settings instance (loaded once on startup)."""
    return Settings()
