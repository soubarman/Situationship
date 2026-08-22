"""
verification-service/simple_server.py
──────────────────────────────────────
A single-file, zero-dependency FastAPI server for account verification.
No Docker, no Celery, no Redis, no Nginx required.

How to run:
  1. Install Python 3.10+
  2. pip install fastapi uvicorn python-multipart pydantic firebase-admin insightface onnxruntime numpy opencv-python-headless pillow
  3. python simple_server.py
"""

import os
import uuid
import random
import string
import logging
import tempfile
import shutil
import urllib.request
import threading
from datetime import datetime, timedelta, timezone
from typing import Optional

import cv2
import numpy as np
import onnxruntime as ort
import uvicorn
from pydantic import BaseModel
from fastapi import FastAPI, Depends, HTTPException, Header, status
from fastapi.middleware.cors import CORSMiddleware

import firebase_admin
from firebase_admin import credentials, auth as firebase_auth, firestore

# ── Logging Setup ─────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger("SimpleVerifier")

# ── Config / Settings ──────────────────────────────────────────────────────────
PORT = 8000
FIREBASE_PROJECT_ID = "situation-ship"
FIREBASE_STORAGE_BUCKET = "situation-ship.appspot.com"
FIREBASE_SERVICE_ACCOUNT = "firebase-service-account.json"
ALLOWED_ORIGINS = ["*"]  # Allow all for simplicity

# Thresholds
AUTO_APPROVE_THRESHOLD = 0.82
MANUAL_REVIEW_THRESHOLD = 0.65
MAX_ATTEMPTS = 5

# ── ML Models Singletons ───────────────────────────────────────────────────────
face_app = None
liveness_session = None

def load_models():
    global face_app, liveness_session
    logger.info("Loading AI Models (InsightFace + MiniFASNet)...")
    
    # 1. InsightFace
    import insightface
    from insightface.app import FaceAnalysis
    face_app = FaceAnalysis(name="antelopev2", allowed_modules=["detection", "recognition"])
    face_app.prepare(ctx_id=-1, det_size=(640, 640))
    logger.info("✓ InsightFace Loaded")

    # 2. Liveness (Download if missing)
    model_dir = Path("models")
    model_dir.mkdir(exist_ok=True)
    model_path = model_dir / "2.7_80x80_MiniFASNetV2.onnx"
    
    if not model_path.exists():
        logger.info("Downloading liveness model...")
        url = "https://github.com/minivision-ai/Silent-Face-Anti-Spoofing/raw/master/resources/anti_spoof_models/2.7_80x80_MiniFASNetV2.onnx"
        urllib.request.urlretrieve(url, model_path)
    
    liveness_session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    logger.info("✓ Liveness Model Loaded")

# ── Firebase Init ─────────────────────────────────────────────────────────────
if not firebase_admin._apps:
    if os.path.exists(FIREBASE_SERVICE_ACCOUNT):
        cred = credentials.Certificate(FIREBASE_SERVICE_ACCOUNT)
    else:
        cred = credentials.ApplicationDefault()
    firebase_admin.initialize_app(cred, {
        "projectId": FIREBASE_PROJECT_ID,
        "storageBucket": FIREBASE_STORAGE_BUCKET,
    })
    logger.info("✓ Firebase Admin SDK Initialized")

db = firestore.client()

# ── Security Auth Helper ──────────────────────────────────────────────────────
async def verify_token(authorization: Optional[str] = Header(None)) -> dict:
    if not authorization:
        raise HTTPException(status_code=401, detail="Header missing")
    try:
        token = authorization.split(" ")[1]
        return firebase_auth.verify_id_token(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")

# ── FastAPI App ───────────────────────────────────────────────────────────────
app = FastAPI(title="Situationship Verification API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Schemas ───────────────────────────────────────────────────────────────────
class VerifyRequest(BaseModel):
    challengeId: str
    videoStoragePath: str
    videoDownloadUrl: str

# ── Challenge Pools ───────────────────────────────────────────────────────────
ACTIONS = ["smile", "blink twice", "raise eyebrows"]
MOVEMENTS = ["turn head left", "turn head right", "nod head slowly"]

# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.post("/api/v1/challenge")
async def get_challenge(decoded_token: dict = Depends(verify_token)):
    user_id = decoded_token["uid"]
    
    # Check attempts
    rec_ref = db.collection("verifications").document(user_id)
    rec = rec_ref.get().to_dict() or {}
    attempts = rec.get("verificationAttempts", 0)
    if attempts >= MAX_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Max attempts reached (5/5).")

    challenge_id = str(uuid.uuid4())
    code = "".join(random.choices(string.digits, k=6))
    action = random.choice(ACTIONS)
    movement = random.choice(MOVEMENTS)
    expires = datetime.now(timezone.utc) + timedelta(minutes=15)

    challenge_data = {
        "id": challenge_id,
        "userId": user_id,
        "code": code,
        "phrase": f"My verification code is {code}",
        "action": action,
        "movement": movement,
        "expiresAt": expires,
        "used": False
    }
    db.collection("challenges").document(challenge_id).set(challenge_data)
    
    return {
        "challengeId": challenge_id,
        "code": code,
        "phrase": challenge_data["phrase"],
        "action": action,
        "movement": movement,
        "expiresAt": expires.isoformat(),
        "ttlSeconds": 900
    }

@app.post("/api/v1/verify")
async def verify(body: VerifyRequest, decoded_token: dict = Depends(verify_token)):
    user_id = decoded_token["uid"]
    challenge_id = body.challengeId

    # Validate challenge
    chal_ref = db.collection("challenges").document(challenge_id)
    chal = chal_ref.get().to_dict()
    if not chal or chal["userId"] != user_id or chal["used"]:
        raise HTTPException(status_code=400, detail="Invalid or expired challenge.")

    chal_ref.update({"used": True})

    # Increment attempts
    rec_ref = db.collection("verifications").document(user_id)
    rec = rec_ref.get().to_dict() or {}
    attempts = rec.get("verificationAttempts", 0) + 1
    
    job_id = str(uuid.uuid4())
    rec_ref.set({
        "verificationStatus": "pending",
        "currentJobId": job_id,
        "challengeId": challenge_id,
        "videoStoragePath": body.videoStoragePath,
        "verificationAttempts": attempts,
        "lastAttemptAt": firestore.SERVER_TIMESTAMP
    }, merge=True)

    # Launch background thread to process verification
    threading.Thread(
        target=process_verification_bg,
        args=(user_id, body.videoDownloadUrl, attempts)
    ).start()

    return {
        "jobId": job_id,
        "status": "pending",
        "attemptsUsed": attempts,
        "attemptsRemaining": MAX_ATTEMPTS - attempts
    }

@app.get("/api/v1/verify/status/{job_id}")
async def get_status(job_id: str, decoded_token: dict = Depends(verify_token)):
    # Find verification record with this job ID
    user_id = decoded_token["uid"]
    rec = db.collection("verifications").document(user_id).get().to_dict() or {}
    
    if rec.get("currentJobId") != job_id:
        return {"jobId": job_id, "status": "pending", "message": "In queue..."}
    
    status_val = rec.get("verificationStatus", "pending")
    return {
        "jobId": job_id,
        "status": "completed" if status_val in ["approved", "rejected", "manual_review"] else "processing",
        "decision": status_val,
        "score": rec.get("verificationScore"),
        "message": rec.get("verificationReason")
    }

# ── Verification Core Pipeline (Threaded) ─────────────────────────────────────

def process_verification_bg(user_id: str, video_url: str, attempt: int):
    tmp_dir = tempfile.mkdtemp()
    try:
        logger.info(f"Processing verification background thread for user {user_id}")
        
        # 1. Download profile photo URL
        user_doc = db.collection("users").document(user_id).get().to_dict() or {}
        profile_url = user_doc.get("profileImage") or user_doc.get("avatarUrl")
        if not profile_url:
            save_fail(user_id, "No profile photo found on your account.")
            return

        # 2. Download profile image & video files
        photo_path = os.path.join(tmp_dir, "ref.jpg")
        video_path = os.path.join(tmp_dir, "video.mp4")
        urllib.request.urlretrieve(profile_url, photo_path)
        urllib.request.urlretrieve(video_url, video_path)

        # 3. Extract reference embedding
        ref_img = cv2.imread(photo_path)
        ref_faces = face_app.get(ref_img)
        if not ref_faces:
            save_fail(user_id, "Could not detect a clear face in your profile photo.")
            return
        
        ref_emb = ref_faces[0].normed_embedding

        # 4. Extract frames from video
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS) or 30
        frame_interval = int(fps) # Extract 1 frame per second
        
        frame_idx = 0
        similarities = []
        liveness_scores = []
        qualities = []

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break
            
            if frame_idx % frame_interval == 0:
                # Discard blurry frames
                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                blur = cv2.Laplacian(gray, cv2.CV_64F).var()
                if blur < 80: # Blurry
                    frame_idx += 1
                    continue
                
                faces = face_app.get(frame)
                if faces:
                    # Sort faces by size, pick primary
                    faces = sorted(faces, key=lambda f: (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]), reverse=True)
                    primary_face = faces[0]
                    
                    # Similarity
                    sim = float(np.dot(primary_face.normed_embedding, ref_emb))
                    similarities.append(max(0.0, min(1.0, sim)))

                    # Liveness
                    liveness = check_liveness(frame, primary_face.bbox)
                    liveness_scores.append(liveness)
                    qualities.append(min(1.0, blur / 500.0))

            frame_idx += 1
        cap.release()

        if not similarities:
            save_fail(user_id, "No clear, steady face found in the recorded video.")
            return

        # 5. Compute aggregate score
        best_similarity = max(similarities)
        avg_liveness = sum(liveness_scores) / len(liveness_scores)
        avg_quality = sum(qualities) / len(qualities)

        final_score = (best_similarity * 0.45) + (avg_liveness * 0.40) + (avg_quality * 0.15)
        final_score = min(1.0, max(0.0, final_score))

        # Decide
        if final_score >= AUTO_APPROVE_THRESHOLD:
            decision = "approved"
            reason = ""
        elif final_score >= MANUAL_REVIEW_THRESHOLD:
            decision = "manual_review"
            reason = "Awaiting manual verification check."
        else:
            decision = "rejected"
            if avg_liveness < 0.5:
                reason = "Liveness spoof check failed."
            elif best_similarity < 0.45:
                reason = "Face does not match profile photo."
            else:
                reason = "Verification check failed. Retake video in good lighting."

        # Save result
        update_data = {
            "verificationStatus": decision,
            "verificationScore": round(final_score, 4),
            "verificationDate": firestore.SERVER_TIMESTAMP,
            "verificationReason": reason,
            "verifiedBy": "auto" if decision == "approved" else "auto:review",
            "scoreBreakdown": {
                "raw_best_similarity": round(best_similarity, 4),
                "raw_avg_liveness": round(avg_liveness, 4),
                "raw_avg_quality": round(avg_quality, 4)
            }
        }
        
        if decision == "approved":
            update_data["verifiedBadge"] = "S"
            db.collection("users").document(user_id).update({
                "isVerified": True,
                "verifiedBadge": "S"
            })
            
        db.collection("verifications").document(user_id).set(update_data, merge=True)
        logger.info(f"✓ Verification completed for {user_id}: {decision} (score {final_score:.3f})")

    except Exception as e:
        logger.exception(f"Error processing video for {user_id}")
        save_fail(user_id, f"Processing error: {str(e)}")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)

def check_liveness(frame: np.ndarray, bbox: np.ndarray) -> float:
    try:
        h, w = frame.shape[:2]
        x1, y1, x2, y2 = bbox.astype(int)
        pad_x = int((x2 - x1) * 0.3)
        pad_y = int((y2 - y1) * 0.3)
        x1 = max(0, x1 - pad_x)
        y1 = max(0, y1 - pad_y)
        x2 = min(w, x2 + pad_x)
        y2 = min(h, y2 + pad_y)

        crop = frame[y1:y2, x1:x2]
        if crop.size == 0:
            return 0.5
        
        resized = cv2.resize(crop, (80, 80))
        normalized = (resized.astype(np.float32) - 127.5) / 128.0
        chw = np.transpose(normalized, (2, 0, 1))
        input_tensor = chw[np.newaxis, ...]

        input_name = liveness_session.get_inputs()[0].name
        outputs = liveness_session.run(None, {input_name: input_tensor})
        probs = np.squeeze(outputs[0])
        exp_probs = np.exp(probs - np.max(probs))
        softmax = exp_probs / exp_probs.sum()
        return float(softmax[1]) # Class 1 is real/live
    except Exception:
        return 0.5

def save_fail(user_id: str, reason: str):
    db.collection("verifications").document(user_id).set({
        "verificationStatus": "rejected",
        "verificationScore": 0.0,
        "verificationReason": reason,
        "verificationDate": firestore.SERVER_TIMESTAMP
    }, merge=True)

# ── Main startup ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    from pathlib import Path
    load_models()
    uvicorn.run(app, host="0.0.0.0", port=PORT)
