"""
app/engine/liveness_detector.py
────────────────────────────────
MiniFASNet liveness detection (anti-spoofing).

Uses TWO complementary models (V2 + V1SE) and averages their output
for more robust spoof detection. If only one model is available,
falls back gracefully to that single model's output.

Input:  Cropped face region from a video frame (BGR)
Output: Liveness probability [0.0 – 1.0]
        1.0 = definitely real person
        0.0 = definitely spoofed (photo, screen, mask)
"""

import logging
from typing import Optional

import cv2
import numpy as np

from app.engine.loader import get_models

logger = logging.getLogger(__name__)

# MiniFASNet expects 80×80 input
MODEL_INPUT_SIZE = (80, 80)

# Class indices in MiniFASNet output:
# Index 1 = "real/live" probability
REAL_CLASS_INDEX = 1


def _preprocess_face_crop(face_crop: np.ndarray) -> np.ndarray:
    """
    Resize and normalize a BGR face crop to MiniFASNet input tensor.
    Shape: [1, 3, 80, 80] — NCHW format, float32.
    """
    resized = cv2.resize(face_crop, MODEL_INPUT_SIZE)
    # Normalize to [-1, 1]
    normalized = (resized.astype(np.float32) - 127.5) / 128.0
    # HWC → CHW → add batch dim
    chw = np.transpose(normalized, (2, 0, 1))
    return chw[np.newaxis, ...]  # shape: [1, 3, 80, 80]


def _run_session(
    session,
    input_tensor: np.ndarray,
    model_name: str,
) -> float:
    """Run a single ONNX liveness session and return real-probability."""
    try:
        input_name = session.get_inputs()[0].name
        outputs = session.run(None, {input_name: input_tensor})
        # Output shape: [1, 2] — [fake_prob, real_prob]
        probs = np.squeeze(outputs[0])
        # Apply softmax for numerical stability
        exp_probs = np.exp(probs - np.max(probs))
        softmax = exp_probs / exp_probs.sum()
        return float(softmax[REAL_CLASS_INDEX])
    except Exception as exc:
        logger.error("Liveness model %s inference failed: %s", model_name, exc)
        return 0.5  # Neutral fallback


def compute_liveness_score(
    frame: np.ndarray,
    bbox: np.ndarray,
) -> float:
    """
    Compute a liveness score [0.0–1.0] for a detected face.

    Parameters
    ----------
    frame : np.ndarray
        Full BGR video frame.
    bbox : np.ndarray
        Bounding box [x1, y1, x2, y2] of the detected face.

    Returns
    -------
    float
        Ensemble liveness probability (0 = spoof, 1 = real).
    """
    models = get_models()

    if models.liveness_session_v2 is None and models.liveness_session_v1se is None:
        logger.warning("No liveness models loaded. Returning neutral score 0.7.")
        return 0.7  # Neutral — will still require manual review threshold

    # Expand bounding box by 30% for context (MiniFASNet needs surroundings)
    h, w = frame.shape[:2]
    x1, y1, x2, y2 = bbox
    pad_x = int((x2 - x1) * 0.3)
    pad_y = int((y2 - y1) * 0.3)
    x1 = max(0, x1 - pad_x)
    y1 = max(0, y1 - pad_y)
    x2 = min(w, x2 + pad_x)
    y2 = min(h, y2 + pad_y)

    face_crop = frame[y1:y2, x1:x2]
    if face_crop.size == 0:
        logger.warning("Empty face crop — returning neutral liveness.")
        return 0.5

    input_tensor = _preprocess_face_crop(face_crop)
    scores = []

    if models.liveness_session_v2 is not None:
        scores.append(_run_session(models.liveness_session_v2, input_tensor, "V2"))

    if models.liveness_session_v1se is not None:
        scores.append(_run_session(models.liveness_session_v1se, input_tensor, "V1SE"))

    final_score = float(np.mean(scores))
    logger.debug("Liveness score: %.4f (from %d models)", final_score, len(scores))
    return final_score
