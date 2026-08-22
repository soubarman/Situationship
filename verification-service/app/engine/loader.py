"""
app/engine/loader.py
─────────────────────
Loads ALL ML models exactly once at application startup.

InsightFace `antelopev2` provides:
  • SCRFD face detection
  • 5-point landmark alignment
  • ArcFace face embeddings (512-d)
  • Gender / age estimation

MiniFASNetV2 provides liveness (anti-spoofing) inference.

Both are loaded into a global singleton so worker processes
share the same weights without repeated disk I/O.
"""

import logging
import os
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional

import numpy as np
import onnxruntime as ort

from app.core.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


@dataclass
class VerificationModels:
    """Container for all loaded ML models."""
    face_app: object = None                  # InsightFace FaceAnalysis
    liveness_session_v2: Optional[ort.InferenceSession] = None
    liveness_session_v1se: Optional[ort.InferenceSession] = None
    is_ready: bool = False


# ── Global singleton ──────────────────────────────────────────────────────────
_models = VerificationModels()


def get_models() -> VerificationModels:
    """Return the globally loaded model singleton."""
    return _models


def load_all_models() -> None:
    """
    Load InsightFace + MiniFASNet models into the global singleton.
    Called once at FastAPI startup and at Celery worker startup.
    Thread-safe: only writes to _models.is_ready at the very end.
    """
    global _models
    logger.info("Loading verification models — this happens once at startup.")

    # ── 1. InsightFace (detection + alignment + embedding) ────────────────────
    try:
        import insightface
        from insightface.app import FaceAnalysis

        face_app = FaceAnalysis(
            name=settings.INSIGHTFACE_MODEL_PACK,
            root=settings.MODEL_DIR,
            allowed_modules=["detection", "recognition", "genderage"],
        )
        # ctx_id = -1 → CPU only.
        # Change to ctx_id = 0 if a CUDA GPU is available on the server.
        face_app.prepare(ctx_id=-1, det_size=(640, 640))
        _models.face_app = face_app
        logger.info("InsightFace (%s) loaded successfully.", settings.INSIGHTFACE_MODEL_PACK)
    except Exception as exc:
        logger.critical("FATAL: Could not load InsightFace: %s", exc)
        raise RuntimeError(f"InsightFace loading failed: {exc}") from exc

    # ── 2. MiniFASNet Liveness models ─────────────────────────────────────────
    sess_options = ort.SessionOptions()
    sess_options.intra_op_num_threads = 2     # Keep CPU usage bounded
    sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

    _load_liveness_session(settings.LIVENESS_MODEL_PATH, "V2", sess_options)
    _load_liveness_session(settings.LIVENESS_MODEL_PATH_2, "V1SE", sess_options)

    _models.is_ready = True
    logger.info("All verification models ready.")


def _load_liveness_session(
    path: str,
    name: str,
    opts: ort.SessionOptions,
) -> None:
    """Attempt to load a MiniFASNet ONNX session; warn if not found."""
    global _models

    if not os.path.exists(path):
        logger.warning(
            "Liveness model %s not found at %s. "
            "Run scripts/download_models.py first.",
            name, path
        )
        return

    try:
        session = ort.InferenceSession(
            path,
            sess_options=opts,
            providers=["CPUExecutionProvider"],
        )
        if name == "V2":
            _models.liveness_session_v2 = session
        else:
            _models.liveness_session_v1se = session
        logger.info("MiniFASNet%s loaded from %s", name, path)
    except Exception as exc:
        logger.error("Could not load liveness model %s: %s", name, exc)
