"""
app/workers/celery_app.py
──────────────────────────
Celery application configuration.
Uses Redis as both message broker and result backend.
"""

from celery import Celery
from app.core.config import get_settings

settings = get_settings()

celery_app = Celery(
    "verification",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
    include=["app.workers.verification_worker"],
)

celery_app.conf.update(
    # Task serialization
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,

    # Result TTL (24 hours)
    result_expires=settings.RESULT_EXPIRES_SECONDS,

    # Worker settings
    worker_prefetch_multiplier=1,      # Process 1 task at a time per worker
    task_acks_late=True,               # Acknowledge only after successful completion
    worker_max_tasks_per_child=100,    # Restart worker every 100 tasks (memory hygiene)

    # Retry on connection failures
    broker_connection_retry_on_startup=True,
)
