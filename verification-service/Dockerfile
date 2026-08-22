
# ─────────────────────────────────────────────────────────────────
# API Server Dockerfile
# ─────────────────────────────────────────────────────────────────
FROM python:3.11-slim

# Install system dependencies:
#   FFmpeg        — video processing
#   libgl1        — OpenCV headless requirement
#   libglib2.0-0  — InsightFace dependency
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/
COPY scripts/ ./scripts/

# Create model directory
RUN mkdir -p /app/models/liveness

# Download liveness models on build (or run scripts/download_models.py manually)
# They are small (~4MB total) so baking into the image is fine.
RUN python scripts/download_models.py || echo "Model download skipped (run manually)"

# Non-root user for security
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Startup: uvicorn with 2 workers (scale via docker-compose replicas)
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
