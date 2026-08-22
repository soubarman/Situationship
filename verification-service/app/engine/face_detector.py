"""
app/engine/face_detector.py
────────────────────────────
Wraps InsightFace SCRFD face detector.

Returns detected faces with bounding boxes and 5-point landmarks.
Rejects frames with:
  • No face found
  • Multiple faces (ambiguous identity)
  • Face too small (< 80px wide — likely too far)
"""

import logging
from dataclasses import dataclass
from typing import Optional

import cv2
import numpy as np

from app.engine.loader import get_models

logger = logging.getLogger(__name__)

# Minimum face width (pixels) to consider the frame usable
MIN_FACE_WIDTH_PX = 80


@dataclass
class DetectedFace:
    bbox: np.ndarray            # [x1, y1, x2, y2]
    keypoints: np.ndarray       # 5-point landmarks (nose, eyes, mouth corners)
    detection_score: float
    embedding: Optional[np.ndarray] = None
    gender: Optional[str] = None
    age: Optional[int] = None


def detect_faces(frame: np.ndarray) -> list[DetectedFace]:
    """
    Run SCRFD face detection on a single BGR frame.
    Returns a list of DetectedFace objects.
    """
    models = get_models()
    if not models.is_ready or models.face_app is None:
        raise RuntimeError("Models not loaded. Call load_all_models() first.")

    faces = models.face_app.get(frame)
    if not faces:
        return []

    result = []
    for face in faces:
        bbox = face.bbox.astype(int)
        face_width = bbox[2] - bbox[0]

        if face_width < MIN_FACE_WIDTH_PX:
            logger.debug("Face too small (%dpx) — skipping frame.", face_width)
            continue

        result.append(DetectedFace(
            bbox=bbox,
            keypoints=face.kps,
            detection_score=float(face.det_score),
            embedding=face.normed_embedding if hasattr(face, "normed_embedding") else None,
            gender="male" if face.gender == 1 else "female" if hasattr(face, "gender") else None,
            age=int(face.age) if hasattr(face, "age") and face.age is not None else None,
        ))

    return result


def get_primary_face(frame: np.ndarray) -> Optional[DetectedFace]:
    """
    Return the single largest face in the frame, or None if:
      • No faces are found
      • No face passes the minimum size threshold
    """
    faces = detect_faces(frame)
    if not faces:
        return None

    # Pick largest face by bounding-box area
    primary = max(
        faces,
        key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]),
    )
    return primary
