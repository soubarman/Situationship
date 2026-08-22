"""
scripts/download_models.py
───────────────────────────
Downloads required ML model files on first run.

MiniFASNet liveness models are downloaded from the official
MinivisionTech Silent-Face-Anti-Spoofing repository.
These are ~2MB each and are MIT-compatible licensed.

InsightFace models (antelopev2) are downloaded automatically
by the insightface Python library on first use.
"""

import os
import urllib.request
import hashlib
from pathlib import Path

MODELS_DIR = Path(os.environ.get("MODEL_DIR", "/app/models"))
LIVENESS_DIR = MODELS_DIR / "liveness"

# MiniFASNet model URLs (from official MinivisionTech repository)
# These are the ONNX-converted versions used in production
LIVENESS_MODELS = [
    {
        "name": "2.7_80x80_MiniFASNetV2.onnx",
        "url": (
            "https://github.com/minivision-ai/Silent-Face-Anti-Spoofing/raw/master"
            "/resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.onnx"
        ),
        "dest": LIVENESS_DIR / "2.7_80x80_MiniFASNetV2.onnx",
    },
    {
        "name": "4_0_0_80x80_MiniFASNetV1SE.onnx",
        "url": (
            "https://github.com/minivision-ai/Silent-Face-Anti-Spoofing/raw/master"
            "/resources/anti_spoof_models/4_0_0_80x80_MiniFASNetV1SE.onnx"
        ),
        "dest": LIVENESS_DIR / "4_0_0_80x80_MiniFASNetV1SE.onnx",
    },
]


def download_file(url: str, dest: Path) -> None:
    print(f"  Downloading {dest.name}...")
    os.makedirs(dest.parent, exist_ok=True)
    try:
        urllib.request.urlretrieve(url, dest)
        size_kb = dest.stat().st_size / 1024
        print(f"  ✓ {dest.name} ({size_kb:.0f} KB)")
    except Exception as exc:
        print(f"  ✗ Failed to download {dest.name}: {exc}")
        print(f"    Please download manually from:\n    {url}")


def main():
    print("=" * 60)
    print("Situationship Verification — Model Downloader")
    print("=" * 60)

    print("\n[1/2] Liveness detection models (MiniFASNet):")
    for model in LIVENESS_MODELS:
        dest = model["dest"]
        if dest.exists():
            print(f"  ✓ {model['name']} already exists — skipping.")
        else:
            download_file(model["url"], dest)

    print("\n[2/2] InsightFace face recognition models (antelopev2):")
    print("  These are downloaded automatically on first model load.")
    print("  First startup may take 2–3 minutes while models download.")

    print("\n✓ Setup complete.\n")


if __name__ == "__main__":
    main()
