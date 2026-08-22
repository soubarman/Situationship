"""
app/services/video_processor.py
────────────────────────────────
FFmpeg-based video processing service.

Responsibilities:
  1. Validate video duration and file size
  2. Strip metadata (privacy)
  3. Extract one frame per second
  4. Reject blurry frames (Laplacian variance threshold)
  5. Return clean list of BGR numpy frames
"""

import logging
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

import cv2
import numpy as np

from app.core.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# Laplacian variance below this = too blurry to use
BLUR_REJECT_THRESHOLD = settings.BLUR_THRESHOLD


def _run_ffmpeg(*args: str) -> subprocess.CompletedProcess:
    """Run an FFmpeg command and raise on non-zero exit."""
    cmd = ["ffmpeg", "-y", "-loglevel", "error", *args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"FFmpeg error: {result.stderr}")
    return result


def validate_video(video_path: str) -> tuple[bool, str]:
    """
    Check video file size and duration constraints.

    Returns (is_valid, error_message).
    """
    size_mb = os.path.getsize(video_path) / (1024 * 1024)
    if size_mb > settings.VIDEO_MAX_SIZE_MB:
        return False, f"Video too large: {size_mb:.1f}MB (max {settings.VIDEO_MAX_SIZE_MB}MB)"

    # Get duration via ffprobe
    cmd = [
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        video_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    try:
        duration = float(result.stdout.strip())
    except (ValueError, AttributeError):
        # If ffprobe can't read duration, let it proceed
        return True, ""

    if duration > settings.VIDEO_MAX_DURATION_SECONDS + 5:
        return False, f"Video too long: {duration:.0f}s (max {settings.VIDEO_MAX_DURATION_SECONDS}s)"

    return True, ""


def strip_metadata(input_path: str, output_path: str) -> None:
    """Remove all metadata from video file for privacy."""
    _run_ffmpeg(
        "-i", input_path,
        "-map_metadata", "-1",
        "-c:v", "copy",
        "-c:a", "copy",
        output_path,
    )


def is_blurry(frame: np.ndarray) -> bool:
    """Return True if the frame's Laplacian variance is below the threshold."""
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    variance = cv2.Laplacian(gray, cv2.CV_64F).var()
    return variance < BLUR_REJECT_THRESHOLD


def extract_frames(video_path: str) -> tuple[list[np.ndarray], list[int]]:
    """
    Extract frames from video at the configured FPS rate (default: 1/sec).
    Skips blurry frames automatically.

    Returns
    -------
    (frames, frame_timestamps)
        frames           : List of BGR numpy arrays
        frame_timestamps : List of second offsets (e.g., [1, 2, 3, 5, 7])
    """
    tmp_dir = tempfile.mkdtemp(prefix="frames_")
    frames: list[np.ndarray] = []
    timestamps: list[int] = []

    try:
        output_pattern = os.path.join(tmp_dir, "frame_%04d.jpg")

        # Extract 1 frame per second (or configured rate)
        _run_ffmpeg(
            "-i", video_path,
            "-vf", f"fps={settings.FRAMES_PER_SECOND}",
            "-q:v", "2",           # High quality JPEG
            "-f", "image2",
            output_pattern,
        )

        frame_files = sorted(Path(tmp_dir).glob("frame_*.jpg"))
        logger.info("Extracted %d raw frames from video.", len(frame_files))

        for idx, frame_file in enumerate(frame_files):
            frame = cv2.imread(str(frame_file))
            if frame is None:
                continue

            if is_blurry(frame):
                logger.debug("Frame %d rejected (blurry).", idx)
                continue

            frames.append(frame)
            timestamps.append(idx + 1)  # 1-indexed seconds

        logger.info(
            "%d/%d frames passed blur filter.",
            len(frames), len(frame_files),
        )

    finally:
        # Always clean up temp files
        shutil.rmtree(tmp_dir, ignore_errors=True)

    return frames, timestamps


def process_verification_video(raw_video_path: str) -> list[np.ndarray]:
    """
    Full pipeline: validate → strip metadata → extract frames.

    Raises ValueError on validation failure.
    Returns list of usable BGR frames.
    """
    # Step 1: Validate
    valid, reason = validate_video(raw_video_path)
    if not valid:
        raise ValueError(f"Video validation failed: {reason}")

    # Step 2: Strip metadata into a temp file
    stripped_path = raw_video_path + "_stripped.mp4"
    try:
        strip_metadata(raw_video_path, stripped_path)
    except RuntimeError:
        # If stripping fails (corrupt codec etc.), use original
        stripped_path = raw_video_path

    # Step 3: Extract frames
    try:
        frames, _ = extract_frames(stripped_path)
    finally:
        if stripped_path != raw_video_path and os.path.exists(stripped_path):
            os.unlink(stripped_path)

    return frames
