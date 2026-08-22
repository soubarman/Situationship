"""
app/engine/face_comparator.py
──────────────────────────────
Face similarity computation using ArcFace 512-d embeddings.

Cosine similarity between two normalized embedding vectors:
  similarity = dot(e1, e2)  [both are already L2-normalized by InsightFace]

Interpretation:
  >= 0.5   → Strong match (same person)
  0.3–0.5  → Possible match (needs context)
  < 0.3    → Different person
"""

import logging
from typing import Optional

import numpy as np
import cv2

from app.engine.face_detector import get_primary_face

logger = logging.getLogger(__name__)


def get_face_embedding(image: np.ndarray) -> Optional[np.ndarray]:
    """
    Detect the primary face in `image` and return its ArcFace embedding.
    Returns None if no valid face is found.
    """
    face = get_primary_face(image)
    if face is None or face.embedding is None:
        return None
    return face.embedding  # Already L2-normalized by InsightFace


def compute_similarity(
    embedding_a: np.ndarray,
    embedding_b: np.ndarray,
) -> float:
    """
    Compute cosine similarity between two L2-normalized face embeddings.
    Both embeddings must be 512-dimensional float32 arrays.

    Returns a similarity score in [0.0, 1.0].
    (Theoretically [-1, 1] but practically [0, 1] for ArcFace embeddings.)
    """
    dot_product = float(np.dot(embedding_a, embedding_b))
    # Clamp to [0, 1] to avoid floating-point edge cases
    return max(0.0, min(1.0, dot_product))


def compare_face_to_reference(
    video_frame: np.ndarray,
    reference_embedding: np.ndarray,
) -> tuple[float, float]:
    """
    Compare a video frame's face against a reference ArcFace embedding.

    Returns
    -------
    (similarity_score, detection_confidence)
        similarity_score      : ArcFace cosine similarity [0–1]
        detection_confidence  : SCRFD detection score [0–1]
    """
    face = get_primary_face(video_frame)
    if face is None or face.embedding is None:
        return 0.0, 0.0

    similarity = compute_similarity(face.embedding, reference_embedding)
    return similarity, face.detection_score


def compute_face_quality(frame: np.ndarray, bbox: np.ndarray) -> float:
    """
    Estimate face image quality using Laplacian variance (sharpness).
    High variance = sharp = good quality.
    Returns a normalized score [0.0–1.0].
    """
    x1, y1, x2, y2 = bbox
    face_crop = frame[y1:y2, x1:x2]
    if face_crop.size == 0:
        return 0.0

    gray = cv2.cvtColor(face_crop, cv2.COLOR_BGR2GRAY)
    laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()

    # Normalize: 0 = completely blurry, 1 = sharp (capped at 500)
    quality = min(1.0, laplacian_var / 500.0)
    return float(quality)
