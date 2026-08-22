"""
app/main.py
────────────
FastAPI application entry point.

Startup sequence:
  1. Initialize Firebase Admin SDK
  2. Load all ML models into memory
  3. Register API routers
  4. Configure CORS, rate limiting, logging
"""

import logging
import os
from contextlib import asynccontextmanager

import firebase_admin
from firebase_admin import credentials
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from app.core.config import get_settings
from app.engine.loader import load_all_models
from app.api.v1 import challenge, verification, admin

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)
logger = logging.getLogger(__name__)
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan context manager:
      - Startup: Init Firebase + load ML models
      - Shutdown: Cleanup (graceful)
    """
    # ── Firebase initialization ───────────────────────────────────
    if not firebase_admin._apps:
        sa_path = settings.FIREBASE_SERVICE_ACCOUNT_JSON
        if sa_path and os.path.exists(sa_path):
            cred = credentials.Certificate(sa_path)
        else:
            # Use Application Default Credentials (for Google Cloud / CI)
            cred = credentials.ApplicationDefault()

        firebase_admin.initialize_app(cred, {
            "projectId": settings.FIREBASE_PROJECT_ID,
            "storageBucket": settings.FIREBASE_STORAGE_BUCKET,
        })
        logger.info("Firebase Admin SDK initialized.")

    # ── ML models ─────────────────────────────────────────────────
    logger.info("Loading ML models…")
    load_all_models()
    logger.info("Startup complete. Verification service is ready.")

    yield

    logger.info("Shutting down verification service.")


# ── App instance ──────────────────────────────────────────────────────────────

limiter = Limiter(key_func=get_remote_address)

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    docs_url="/docs" if settings.DEBUG else None,   # Hide Swagger in production
    redoc_url=None,
    lifespan=lifespan,
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS — only allow the Situationship frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)

# ── Routers ───────────────────────────────────────────────────────────────────
PREFIX = settings.API_V1_PREFIX

app.include_router(challenge.router, prefix=PREFIX)
app.include_router(verification.router, prefix=PREFIX)
app.include_router(admin.router, prefix=PREFIX)


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint for Docker/load balancer probes."""
    from app.engine.loader import get_models
    models = get_models()
    return {
        "status": "ok",
        "version": settings.APP_VERSION,
        "models_ready": models.is_ready,
    }
