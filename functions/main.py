"""
functions/main.py
─────────────────
Production-ready serverless verification engine.
Runs 100% inside Firebase Cloud Functions (v2, Python) as a single API function.
No external servers, VPS, Nginx, Redis, or Celery required.
"""

import os
import json
import uuid
import random
import string
import re
import time
import logging
import tempfile
import shutil
import urllib.request
import urllib.error
import base64
import hashlib
import hmac
from datetime import datetime, timedelta, timezone
from pathlib import Path

from firebase_functions import https_fn, options
import firebase_admin
from firebase_admin import firestore, auth, storage as admin_storage

# Initialize Firebase
firebase_admin.initialize_app(options={
    "storageBucket": "situation-ship.firebasestorage.app"
})

from google.cloud import firestore as gcp_firestore
from google.api_core import exceptions as gcp_exceptions
import grpc

db = None
def get_db():
    global db
    if db is None:
        try:
            app = firebase_admin.get_app()
            project_id = getattr(app, "project_id", None) or os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCLOUD_PROJECT")
            db = gcp_firestore.Client(project=project_id, database="(default)")
        except Exception as e:
            logger.warning(f"Failed to initialize named firestore client: {e}. Falling back to default.")
            db = firestore.client()
    return db

logger = logging.getLogger("FirebaseFunctions")

# ── ML Models Loading ─────────────────────────────────────────────────────────
face_app = None

def download_url(url: str, dest_path: Path):
    """Download a URL to a file path setting a realistic browser User-Agent."""
    logger.info(f"Downloading {url} to {dest_path}...")
    req = urllib.request.Request(
        url,
        headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'}
    )
    with urllib.request.urlopen(req) as response, open(dest_path, 'wb') as out_file:
        out_file.write(response.read())

def ensure_models_loaded():
    """Download and initialize InsightFace models inside /tmp directory on cold start."""
    global face_app
    
    if face_app is not None:
        return  # Already loaded

    logger.info("Initializing ML models inside serverless function...")

    # Pre-download InsightFace (antelopev2) models to prevent timeout/failure
    insightface_root = Path("/tmp/insightface")
    models_root = insightface_root / "models"
    antelope_dir = models_root / "antelopev2"
    
    # Check if the folder exists and is valid (contains the .onnx files directly)
    is_valid = False
    if antelope_dir.exists():
        onnx_files = list(antelope_dir.glob("*.onnx"))
        if len(onnx_files) >= 2:
            is_valid = True
            
    if not is_valid:
        logger.info("InsightFace models not found or invalid. Downloading antelopev2...")
        import shutil
        if insightface_root.exists():
            shutil.rmtree(insightface_root)
            
        models_root.mkdir(parents=True, exist_ok=True)
        zip_path = models_root / "antelopev2.zip"
        
        # Download from official GitHub release
        antelope_url = "https://github.com/deepinsight/insightface/releases/download/v0.7/antelopev2.zip"
        download_url(antelope_url, zip_path)
        
        # Extract files to models_root (the zip itself contains the antelopev2/ directory)
        import zipfile
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(models_root)
            
        # Clean up zip
        if zip_path.exists():
            zip_path.unlink()
            
        logger.info("✓ Antelopev2 models downloaded and unzipped successfully")

    # 4. Initialize InsightFace (ArcFace + SCRFD)
    import insightface
    from insightface.app import FaceAnalysis

    face_app = FaceAnalysis(
        name="antelopev2",
        root="/tmp/insightface",
        allowed_modules=["detection", "recognition"]
    )
    # Prepare model
    face_app.prepare(ctx_id=-1, det_size=(640, 640))
    logger.info("✓ InsightFace models ready")

# ── Security: Token Authenticator ─────────────────────────────────────────────
def authenticate_token(request, check_revoked: bool = False) -> dict:
    """Validate Authorization header and return decoded Firebase token."""
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise ValueError("Missing or invalid authorization header")
    
    parts = auth_header.split(" ", 1)
    if len(parts) < 2 or not parts[1].strip():
        raise ValueError("Missing or invalid authorization header")
    token = parts[1].strip()

    try:
        decoded = auth.verify_id_token(token, check_revoked=check_revoked)
        return decoded
    except auth.RevokedIdTokenError:
        raise ValueError("Authentication failed: Token has been revoked")
    except auth.UserDisabledError:
        raise ValueError("Authentication failed: User account has been disabled")
    except auth.ExpiredIdTokenError:
        raise ValueError("Authentication failed: Token has expired")
    except Exception as e:
        raise ValueError(f"Authentication failed: {str(e)}")

def authenticate_user(request) -> str:
    """Validate Authorization header and return Firebase User UID."""
    decoded = authenticate_token(request)
    return decoded["uid"]

def authenticate_admin(request) -> str:
    """Validate Authorization header, verify admin custom claim with check_revoked=True, and ensure account is active in Firestore."""
    decoded = authenticate_token(request, check_revoked=True)
    uid = decoded.get("uid", "")
    if not uid:
        raise ValueError("Forbidden: Missing UID in authenticated credentials")

    # Production admin authorization strictly requires verified admin custom claim
    is_admin = decoded.get("admin") is True
    if not is_admin:
        raise ValueError("Forbidden: Admin privileges required")

    # Authoritative suspension and existence check from Firestore (fail closed)
    try:
        db = get_db()
        admin_doc = db.collection("users").document(uid).get()
        if not admin_doc.exists:
            raise ValueError("Forbidden: Administrator user document not found")
        admin_data = admin_doc.to_dict() or {}
        if admin_data.get("isSuspended", False) is True:
            raise ValueError("Forbidden: Administrator account is suspended")
    except ValueError:
        raise
    except Exception as e:
        logger.error(f"Failed verifying admin suspension for {uid}: {e}")
        raise ValueError("Forbidden: Administrator authorization verification failed")

    return uid

# ── Request Handlers ──────────────────────────────────────────────────────────

def handle_challenge(user_id: str) -> https_fn.Response:
    # Check attempts
    rec = get_db().collection("verifications").document(user_id).get().to_dict() or {}
    attempts = rec.get("verificationAttempts", 0)
    if attempts >= 5:
        return https_fn.Response(
            json.dumps({"detail": "Maximum verification attempts reached (5/5)."}),
            status=429,
            mimetype="application/json"
        )

    challenge_id = str(uuid.uuid4())
    code = "".join(random.choices(string.digits, k=6))
    action = random.choice(["smile", "blink twice", "raise eyebrows"])
    movement = random.choice(["turn head left", "turn head right", "nod head slowly"])
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
    get_db().collection("challenges").document(challenge_id).set(challenge_data)
    
    return https_fn.Response(
        json.dumps({
            "challengeId": challenge_id,
            "code": code,
            "phrase": challenge_data["phrase"],
            "action": action,
            "movement": movement,
            "expiresAt": expires.isoformat(),
            "ttlSeconds": 900
        }),
        status=201,
        mimetype="application/json"
    )

def handle_verify(user_id: str, request) -> https_fn.Response:
    try:
        body = json.loads(request.data)
    except Exception:
        return https_fn.Response("Invalid JSON body", status=400)

    challenge_id = body.get("challengeId")
    video_storage_path = body.get("videoStoragePath")
    video_download_url = body.get("videoDownloadUrl")

    if not challenge_id or not video_download_url:
        return https_fn.Response("Missing fields", status=400)

    # Validate challenge
    chal_ref = get_db().collection("challenges").document(challenge_id)
    chal = chal_ref.get().to_dict()
    if not chal or chal["userId"] != user_id:
        return https_fn.Response("Invalid challenge", status=400)

    # Check if challenge is expired (based on time, not used flag)
    expires_at = chal.get("expiresAt")
    if expires_at:
        # Firestore Timestamps have a .replace() or can be compared directly
        try:
            if hasattr(expires_at, 'timestamp'):
                exp_dt = datetime.fromtimestamp(expires_at.timestamp(), tz=timezone.utc)
            else:
                exp_dt = expires_at
            if datetime.now(timezone.utc) > exp_dt:
                return https_fn.Response("Challenge has expired", status=400)
        except Exception:
            pass  # If we can't parse time, allow it through

    # Mark as used
    chal_ref.update({"used": True})

    # Increment attempt count
    rec_ref = get_db().collection("verifications").document(user_id)
    rec = rec_ref.get().to_dict() or {}
    attempts_list = rec.get("attemptsList", [])
    attempts = len(attempts_list) + 1

    job_id = str(uuid.uuid4())
    
    # Format current date for the JSON list
    now_str = datetime.now(timezone.utc).isoformat()
    current_attempt = {
        "attemptNumber": attempts,
        "timestamp": now_str,
        "status": "pending",
        "reason": "",
        "challengeId": challenge_id,
        "jobId": job_id
    }
    attempts_list.append(current_attempt)

    rec_ref.set({
        "verificationStatus": "pending",
        "currentJobId": job_id,
        "challengeId": challenge_id,
        "videoStoragePath": video_storage_path,
        "verificationAttempts": attempts,
        "lastAttemptAt": firestore.SERVER_TIMESTAMP,
        "attemptsList": attempts_list
    }, merge=True)

    # Process ML pipeline synchronously inside Cloud Function (lasts ~5-10s)
    tmp_dir = tempfile.mkdtemp()
    try:
        import cv2
        import numpy as np
        ensure_models_loaded()

        # Download reference profile image
        user_doc = get_db().collection("users").document(user_id).get().to_dict() or {}
        profile_url = user_doc.get("profileImage") or user_doc.get("avatarUrl")
        if not profile_url:
            raise ValueError("No profile photo found on account.")

        photo_path = os.path.join(tmp_dir, "ref.jpg")
        video_path = os.path.join(tmp_dir, "video.webm")

        # Download profile photo via urllib (public URL from Firestore)
        urllib.request.urlretrieve(profile_url, photo_path)

        # Download verification video via Admin SDK signed URL
        # video_storage_path = e.g. "verifications/{uid}/{timestamp}.webm"
        logger.info(f"Downloading video from storage path: '{video_storage_path}'")
        try:
            bucket = admin_storage.bucket('situation-ship.firebasestorage.app')
            blob = bucket.blob(video_storage_path)
            if not blob.exists():
                raise ValueError(f"Video not found in storage at path: {video_storage_path}")
            blob.download_to_filename(video_path)
            logger.info(f"Video downloaded successfully to {video_path}")
        except Exception as dl_err:
            logger.error(f"Admin SDK download failed: {dl_err}. Falling back to download URL.")
            # Fallback: use the client download URL directly
            if video_download_url:
                urllib.request.urlretrieve(video_download_url, video_path)
            else:
                raise

        # Get profile embedding
        ref_img = cv2.imread(photo_path)
        rgb_ref_img = cv2.cvtColor(ref_img, cv2.COLOR_BGR2RGB)
        ref_faces = face_app.get(rgb_ref_img)
        if not ref_faces:
            raise ValueError("No face detected in profile photo.")
        
        ref_emb = ref_faces[0].normed_embedding

        # Extract frames using ffmpeg (handles WebM VP8/VP9 which OpenCV cannot decode in Cloud Run)
        frames_dir = os.path.join(tmp_dir, "frames")
        os.makedirs(frames_dir, exist_ok=True)

        # Use ffmpeg to extract 2 frames per second as JPEG images
        ffmpeg_cmd = [
            "ffmpeg", "-y",
            "-i", video_path,
            "-vf", "fps=2,scale=640:-1",       # 2 fps, scale to 640px wide
            "-q:v", "2",                         # High quality JPEG
            os.path.join(frames_dir, "frame_%04d.jpg")
        ]
        import subprocess
        ffmpeg_result = subprocess.run(
            ffmpeg_cmd,
            capture_output=True, text=True, timeout=60
        )
        logger.info(f"ffmpeg exit={ffmpeg_result.returncode} stderr={ffmpeg_result.stderr[-500:]}")

        frame_files = sorted([
            os.path.join(frames_dir, f)
            for f in os.listdir(frames_dir)
            if f.endswith(".jpg")
        ])

        logger.info(f"Extracted {len(frame_files)} frames from video")

        if not frame_files:
            # Fallback: try OpenCV if ffmpeg produced nothing
            logger.warning("ffmpeg produced no frames, falling back to OpenCV")
            cap = cv2.VideoCapture(video_path)
            fps = cap.get(cv2.CAP_PROP_FPS) or 15
            frame_interval = max(1, int(fps) // 2)
            frame_idx = 0
            raw_frames = []
            while cap.isOpened():
                ret, frame = cap.read()
                if not ret:
                    break
                if frame_idx % frame_interval == 0:
                    raw_frames.append(frame)
                frame_idx += 1
            cap.release()
            logger.info(f"OpenCV fallback extracted {len(raw_frames)} frames")
        else:
            raw_frames = None  # Using file-based frames

        frame_idx = 0
        similarities = []
        qualities = []

        def process_frame(frame_bgr):
            """Process a single BGR frame and append similarity/quality if face found."""
            nonlocal frame_idx
            gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
            blur = cv2.Laplacian(gray, cv2.CV_64F).var()

            rgb_frame = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            faces = face_app.get(rgb_frame)
            if not faces:
                logger.info(f"Frame {frame_idx}: no face (blur={blur:.1f})")
                return
            faces = sorted(faces, key=lambda f: (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]), reverse=True)
            primary_face = faces[0]
            similarity = float(np.dot(ref_emb, primary_face.normed_embedding))
            quality = min(1.0, max(0.0, blur / 500.0))
            similarities.append(similarity)
            qualities.append(quality)
            logger.info(f"Frame {frame_idx}: similarity={similarity:.4f} blur={blur:.1f}")

        if frame_files:
            for fpath in frame_files:
                frame_bgr = cv2.imread(fpath)
                if frame_bgr is not None and frame_bgr.size > 0:
                    process_frame(frame_bgr)
                frame_idx += 1
        else:
            for frame_bgr in (raw_frames or []):
                process_frame(frame_bgr)
                frame_idx += 1

        if not similarities:
            raise ValueError("No face detected in video.")

        # Compute final scores (ArcFace similarity is the primary signal)
        best_similarity = float(max(similarities))
        avg_similarity  = float(sum(similarities) / len(similarities))
        avg_quality     = float(sum(qualities) / len(qualities))

        # Score = 85% best similarity + 15% frame quality
        final_score = (best_similarity * 0.85) + (avg_quality * 0.15)
        final_score = float(min(1.0, max(0.0, final_score)))

        logger.info(f"Scores — best_sim={best_similarity:.4f}, avg_sim={avg_similarity:.4f}, quality={avg_quality:.4f}, final={final_score:.4f}")

        # Make decision
        # ArcFace cosine similarity: >0.5 is very confident match
        if best_similarity >= 0.50:
            decision = "approved"
            reason = ""
        elif best_similarity >= 0.35:
            decision = "manual_review"
            reason = "Identity confidence is borderline. A human will review your submission."
        else:
            decision = "rejected"
            reason = "Video does not match profile photo. Please ensure your face is clearly visible."

        # Update the specific attempt in the list
        rec = rec_ref.get().to_dict() or {}
        attempts_list = rec.get("attemptsList", [])
        for att in reversed(attempts_list):
            if att.get("jobId") == job_id:
                att["status"] = decision
                att["reason"] = reason
                break

        # Write result to Firestore
        update_data = {
            "verificationStatus": decision,
            "verificationScore": round(final_score, 4),
            "verificationDate": firestore.SERVER_TIMESTAMP,
            "verificationReason": reason,
            "verifiedBy": "auto" if decision == "approved" else "auto:review",
            "attemptsList": attempts_list,
            "scoreBreakdown": {
                "raw_best_similarity": round(best_similarity, 4),
                "raw_avg_similarity": round(avg_similarity, 4),
                "raw_avg_quality": round(avg_quality, 4)
            }
        }
        
        if decision == "approved":
            update_data["verifiedBadge"] = "S"
            get_db().collection("users").document(user_id).update({
                "isVerified": True,
                "verifiedBadge": "S"
            })
            
        rec_ref.set(update_data, merge=True)

        return https_fn.Response(
            json.dumps({
                "jobId": job_id,
                "status": "completed",
                "decision": decision,
                "score": round(final_score, 4),
                "message": reason
            }),
            status=200,
            mimetype="application/json"
        )

    except Exception as e:
        logger.exception(f"Verification pipeline error for {user_id}")
        
        # Update specific attempt to rejected with error reason
        try:
            rec = rec_ref.get().to_dict() or {}
            attempts_list = rec.get("attemptsList", [])
            for att in reversed(attempts_list):
                if att.get("jobId") == job_id:
                    att["status"] = "rejected"
                    att["reason"] = f"Error: {str(e)}"
                    break
        except Exception:
            attempts_list = []

        rec_ref.set({
            "verificationStatus": "rejected",
            "verificationScore": 0.0,
            "verificationReason": f"Error: {str(e)}",
            "verificationDate": firestore.SERVER_TIMESTAMP,
            "attemptsList": attempts_list
        }, merge=True)
        return https_fn.Response(
            json.dumps({
                "jobId": job_id,
                "status": "completed",
                "decision": "rejected",
                "message": f"Processing error: {str(e)}"
            }),
            status=200,
            mimetype="application/json"
        )
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)

def handle_status(user_id: str, job_id: str) -> https_fn.Response:
    rec = get_db().collection("verifications").document(user_id).get().to_dict() or {}
    
    if rec.get("currentJobId") != job_id:
        return https_fn.Response(
            json.dumps({"jobId": job_id, "status": "pending", "message": "In queue..."}),
            mimetype="application/json"
        )
    
    status_val = rec.get("verificationStatus", "pending")
    return https_fn.Response(
        json.dumps({
            "jobId": job_id,
            "status": "completed" if status_val in ["approved", "rejected", "manual_review"] else "processing",
            "decision": status_val,
            "score": rec.get("verificationScore"),
            "message": rec.get("verificationReason")
        }),
        mimetype="application/json"
    )

def check_liveness(frame, bbox) -> float:
    import cv2
    import numpy as np
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
            return 0.6  # Neutral fallback

        resized = cv2.resize(crop, (80, 80))
        # MiniFASNet expects float32 with ImageNet normalization (BGR channel order)
        img = resized.astype(np.float32) / 255.0
        # BGR mean/std from ImageNet (model was trained with these)
        mean = np.array([0.406, 0.456, 0.485], dtype=np.float32)
        std  = np.array([0.225, 0.224, 0.229], dtype=np.float32)
        img = (img - mean) / std
        # HWC -> CHW -> NCHW
        chw = np.transpose(img, (2, 0, 1))
        input_tensor = chw[np.newaxis, ...]

        input_name = liveness_session.get_inputs()[0].name
        outputs = liveness_session.run(None, {input_name: input_tensor})
        probs = np.squeeze(outputs[0])
        exp_probs = np.exp(probs - np.max(probs))
        softmax = exp_probs / exp_probs.sum()
        # MiniFASNet class mapping: index 1 = real/live, index 0 = spoof
        live_score = float(softmax[1]) if len(softmax) > 1 else float(softmax[0])
        return live_score
    except Exception as e:
        logger.warning(f"Liveness check exception: {e}")
        return 0.6  # Neutral fallback — don't penalise on model error

# ── Core Domain Exceptions & Services ─────────────────────────────────────────

class ApiError(Exception):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.message = message
        self.status_code = status_code

def execute_phone_unlock(db, caller_uid: str, target_uid: str, idempotency_key: str = None) -> dict:
    if not target_uid:
        raise ApiError("Missing targetUserId", 400)
    if caller_uid == target_uid:
        raise ApiError("Cannot unlock your own phone number", 400)

    # SEC-5.2-06: Strict validation of idempotency key before document path construction
    if idempotency_key is not None:
        if type(idempotency_key) is not str:
            raise ApiError("Invalid idempotencyKey: must be a string", 400)
        if len(idempotency_key) < 8 or len(idempotency_key) > 128:
            raise ApiError("Invalid idempotencyKey: length must be between 8 and 128 characters", 400)
        if not re.match(r"^[a-zA-Z0-9_\-]+$", idempotency_key):
            raise ApiError("Invalid idempotencyKey: only ASCII letters, numbers, underscores and hyphens allowed", 400)

    caller_ref = db.collection("users").document(caller_uid)
    target_ref = db.collection("users").document(target_uid)
    contact_ref = db.collection("users").document(target_uid).collection("unlocked_contacts").document(caller_uid)
    target_private_ref = db.collection("users").document(target_uid).collection("private").document("profile")
    
    idempotency_ref = None
    if idempotency_key:
        idempotency_ref = db.collection("users").document(caller_uid).collection("idempotency_records").document(idempotency_key)

    @firestore.transactional
    def unlock_txn(txn):
        # 1. READS (All reads must precede any writes in a Firestore transaction)
        caller_snap = caller_ref.get(transaction=txn)
        target_snap = target_ref.get(transaction=txn)
        contact_snap = contact_ref.get(transaction=txn)
        target_private_snap = target_private_ref.get(transaction=txn)
        idempotency_snap = idempotency_ref.get(transaction=txn) if idempotency_ref else None

        if not caller_snap.exists:
            raise ApiError("Caller account not found", 404)
        if not target_snap.exists:
            raise ApiError("Target account not found", 404)

        caller_data = caller_snap.to_dict() or {}
        target_data = target_snap.to_dict() or {}

        if caller_data.get("isSuspended", False):
            raise ApiError("Caller account is suspended", 403)

        # Check mutual blocks
        caller_blocked = caller_data.get("blockedUsers", [])
        target_blocked = target_data.get("blockedUsers", [])
        if caller_uid in target_blocked or target_uid in caller_blocked:
            raise ApiError("Interaction blocked between users", 403)

        # Check target phone visibility
        if not target_data.get("isPhonePublic", False):
            raise ApiError("Target user phone is strictly private", 403)

        # Fetch private phone number (fallback to public doc if legacy unmigrated)
        target_private_data = target_private_snap.to_dict() if target_private_snap.exists else {}
        target_phone = target_private_data.get("phoneNumber") or target_data.get("phoneNumber")
        if not target_phone:
            raise ApiError("Target user has not registered a phone number", 404)

        version = target_data.get("phoneVisibilityVersion", 0)
        unlock_key = f"{target_uid}_{version}"

        # SEC-5.2-05: Critical Identity Binding & Scope Verification for Idempotency
        if idempotency_snap and idempotency_snap.exists:
            rec = idempotency_snap.to_dict() or {}
            
            # 1. Target Identity Binding: verify key was created for this target
            stored_target = rec.get("targetId")
            if stored_target != target_uid:
                raise ApiError(f"Idempotency conflict: key '{idempotency_key}' was previously used for a different target user", 409)

            # 2. Operation Type Binding: verify operation is phone_unlock
            stored_op = rec.get("operationType", "phone_unlock")
            if stored_op != "phone_unlock":
                raise ApiError(f"Idempotency conflict: key '{idempotency_key}' was previously used for operation '{stored_op}'", 409)

            # 3. Visibility Version Binding: verify version has not changed
            stored_version = rec.get("phoneVisibilityVersion")
            if stored_version != version:
                raise ApiError(f"Idempotency conflict: key '{idempotency_key}' is bound to obsolete visibility version {stored_version} (current: {version})", 409)

            # Legitimate idempotent replay: return original phone number without recharging
            return {
                "success": True,
                "phoneNumber": rec.get("phoneNumber", target_phone),
                "alreadyUnlocked": True,
                "idempotentReplay": True,
                "paymentType": rec.get("paymentType", "none"),
                "phoneVisibilityVersion": version,
            }

        # Check if already unlocked with current version
        contact_data = contact_snap.to_dict() if contact_snap.exists else {}
        is_already_unlocked = (
            (contact_snap.exists and contact_data.get("phoneVisibilityVersion") == version) or
            (unlock_key in caller_data.get("unlockedUserPhones", []))
        )

        caller_updates = {}
        payment_type = "none"

        if not is_already_unlocked:
            is_subscribed = caller_data.get("isSubscribed", False)
            quota = caller_data.get("phoneUnlockQuota", 0)
            used = caller_data.get("phoneUnlocksUsed", 0)
            coins = caller_data.get("coins", 0)

            unlocked_list = list(caller_data.get("unlockedUserPhones", []))
            if unlock_key not in unlocked_list:
                unlocked_list.append(unlock_key)

            if is_subscribed and used < quota:
                caller_updates = {
                    "phoneUnlocksUsed": used + 1,
                    "unlockedUserPhones": unlocked_list,
                }
                payment_type = "subscription_quota"
            elif coins >= 50:
                caller_updates = {
                    "coins": coins - 50,
                    "unlockedUserPhones": unlocked_list,
                }
                payment_type = "coins"
            else:
                raise ApiError("Insufficient coins or quota", 402)

        # 2. WRITES (Atomic update within transaction)
        if caller_updates:
            txn.update(caller_ref, caller_updates)

        now_ts = firestore.SERVER_TIMESTAMP
        txn.set(contact_ref, {
            "phoneNumber": target_phone,
            "viewerId": caller_uid,
            "targetId": target_uid,
            "phoneVisibilityVersion": version,
            "unlockedAt": now_ts,
        }, merge=True)

        if idempotency_ref:
            txn.set(idempotency_ref, {
                "targetId": target_uid,
                "callerId": caller_uid,
                "operationType": "phone_unlock",
                "phoneVisibilityVersion": version,
                "phoneNumber": target_phone,
                "paymentType": payment_type,
                "createdAt": now_ts,
                "status": "completed",
            })

        return {
            "success": True,
            "phoneNumber": target_phone,
            "alreadyUnlocked": is_already_unlocked,
            "paymentType": payment_type,
            "phoneVisibilityVersion": version,
        }

    def _is_transaction_contention(exc: Exception) -> bool:
        """Structured exception classifier: identifies genuine contention vs permanent errors."""
        # Never retry permanent domain or validation errors
        if isinstance(exc, ApiError):
            return False

        # 1. Direct google.api_core.exceptions.Aborted or Conflict
        if isinstance(exc, (gcp_exceptions.Aborted, gcp_exceptions.Conflict)):
            return True

        # 2. Wrapped cause: google.api_core exceptions
        if exc.__cause__ and isinstance(exc.__cause__, (gcp_exceptions.Aborted, gcp_exceptions.Conflict)):
            return True

        # 3. Direct or wrapped gRPC StatusCode.ABORTED
        if isinstance(exc, grpc.RpcError):
            try:
                if exc.code() == grpc.StatusCode.ABORTED:
                    return True
            except Exception:
                pass
        if exc.__cause__ and isinstance(exc.__cause__, grpc.RpcError):
            try:
                if exc.__cause__.code() == grpc.StatusCode.ABORTED:
                    return True
            except Exception:
                pass

        # 4. Documented google.cloud.firestore_v1 commit retry limit (ValueError)
        if isinstance(exc, ValueError) and "Failed to commit transaction" in str(exc):
            return True

        # 5. Emulator & runtime lock contention fallback
        err_lower = str(exc).lower()
        if "transaction lock timeout" in err_lower or "aborted:transaction lock timeout" in err_lower:
            return True

        return False

    max_retries = 5
    for attempt in range(max_retries):
        try:
            transaction = db.transaction()
            return unlock_txn(transaction)
        except Exception as exc:
            if _is_transaction_contention(exc) and attempt < max_retries - 1:
                time.sleep(0.1 * (2 ** attempt) + random.uniform(0.02, 0.08))
                continue
            raise


def execute_pii_migration(db, limit: int = 100, cursor: str = None, batch_size: int = 100, resume: bool = False, dry_run: bool = False) -> dict:
    # SEC-5.2-03: Enforce maximum of 250 users per batch so write ops never exceed 500
    batch_size = min(max(batch_size, 1), 250)
    limit = min(max(limit, 1), 500)

    checkpoint_ref = db.collection("_admin_migrations").document("pii_migration")
    checkpoint_doc = checkpoint_ref.get()
    checkpoint_data = checkpoint_doc.to_dict() if checkpoint_doc.exists else {}

    if resume and not cursor:
        cursor = checkpoint_data.get("lastProcessedId")

    total_scanned = checkpoint_data.get("totalScanned", 0)
    total_migrated = checkpoint_data.get("totalMigrated", 0)
    total_skipped = checkpoint_data.get("totalSkipped", 0)
    total_failed = checkpoint_data.get("totalFailed", 0)
    errors = checkpoint_data.get("errors", [])

    query = db.collection("users").order_by("__name__")
    if cursor:
        cursor_doc = db.collection("users").document(cursor).get()
        if cursor_doc.exists:
            query = query.start_after(cursor_doc)
        else:
            query = query.where("__name__", ">", cursor)

    query = query.limit(limit)
    docs = list(query.stream())

    run_scanned = 0
    run_migrated = 0
    run_skipped = 0
    run_failed = 0
    last_id = cursor

    batch = db.batch()
    batch_ops_count = 0

    for doc in docs:
        doc_id = doc.id
        last_id = doc_id
        run_scanned += 1
        data = doc.to_dict() or {}

        legacy_email = data.get("email")
        legacy_phone = data.get("phoneNumber")
        legacy_unlocked = data.get("unlockedUserPhones")
        legacy_used = data.get("phoneUnlocksUsed")

        has_legacy_pii = (
            legacy_email is not None or 
            legacy_phone is not None or 
            legacy_unlocked is not None or 
            legacy_used is not None
        )

        # Clean document check
        if not has_legacy_pii:
            run_skipped += 1
            continue

        try:
            # Check existing private profile to ensure we never overwrite newer private data
            private_ref = doc.reference.collection("private").document("profile")
            private_doc = private_ref.get()
            private_data = private_doc.to_dict() if private_doc.exists else {}

            private_updates = {}
            if legacy_email is not None and not private_data.get("email"):
                private_updates["email"] = legacy_email

            if legacy_phone is not None and not private_data.get("phoneNumber"):
                private_updates["phoneNumber"] = legacy_phone

            if private_updates:
                private_updates["migratedAt"] = firestore.SERVER_TIMESTAMP

            public_deletes = {}
            if legacy_email is not None:
                public_deletes["email"] = firestore.DELETE_FIELD
            if legacy_phone is not None:
                public_deletes["phoneNumber"] = firestore.DELETE_FIELD
            if legacy_unlocked is not None:
                public_deletes["unlockedUserPhones"] = firestore.DELETE_FIELD
            if legacy_used is not None:
                public_deletes["phoneUnlocksUsed"] = firestore.DELETE_FIELD

            public_deletes["piiMigratedAt"] = firestore.SERVER_TIMESTAMP

            if not dry_run:
                if private_updates:
                    batch.set(private_ref, private_updates, merge=True)
                batch.update(doc.reference, public_deletes)
                batch_ops_count += 2

                if batch_ops_count >= (batch_size * 2):
                    batch.commit()
                    batch = db.batch()
                    batch_ops_count = 0

            run_migrated += 1
        except Exception as doc_err:
            logger.error(f"Failed migrating user doc {doc_id}: {doc_err}")
            run_failed += 1
            errors.append({
                "userId": doc_id,
                "error": str(doc_err),
                "timestamp": datetime.now(timezone.utc).isoformat(),
            })
            if len(errors) > 50:
                errors = errors[-50:]

    if not dry_run and batch_ops_count > 0:
        batch.commit()

    is_complete = len(docs) < limit

    total_scanned += run_scanned
    total_migrated += run_migrated
    total_skipped += run_skipped
    total_failed += run_failed

    updated_checkpoint = {
        "lastProcessedId": last_id,
        "totalScanned": total_scanned,
        "totalMigrated": total_migrated,
        "totalSkipped": total_skipped,
        "totalFailed": total_failed,
        "lastRunAt": firestore.SERVER_TIMESTAMP,
        "status": "completed" if is_complete else "in_progress",
        "errors": errors,
    }

    if not dry_run:
        checkpoint_ref.set(updated_checkpoint, merge=True)

    return {
        "success": True,
        "cursor": cursor,
        "lastProcessedId": last_id,
        "batchScanned": run_scanned,
        "batchMigrated": run_migrated,
        "batchSkipped": run_skipped,
        "batchFailed": run_failed,
        "isComplete": is_complete,
        "checkpoint": {
            "totalScanned": total_scanned,
            "totalMigrated": total_migrated,
            "totalSkipped": total_skipped,
            "totalFailed": total_failed,
            "status": "completed" if is_complete else "in_progress",
            "lastProcessedId": last_id,
            "errorCount": len(errors),
        }
    }

# ── Razorpay Payment Integration ──────────────────────────────────────────────
RAZORPAY_KEY_ID = os.environ.get("RAZORPAY_KEY_ID")
RAZORPAY_KEY_SECRET = os.environ.get("RAZORPAY_KEY_SECRET")
RAZORPAY_WEBHOOK_SECRET = os.environ.get("RAZORPAY_WEBHOOK_SECRET")

COIN_PACKS = {
    "pack_100": {"coins": 100, "amount_paise": 9900, "currency": "INR", "name": "Handful of Coins"},
    "pack_500": {"coins": 500, "amount_paise": 44900, "currency": "INR", "name": "Bag of Coins"},
    "pack_1200": {"coins": 1200, "amount_paise": 99900, "currency": "INR", "name": "Chest of Coins"},
    "pack_2500": {"coins": 2500, "amount_paise": 199900, "currency": "INR", "name": "Vault of Coins"},
}

def create_payment_order(db, user_id: str, pack_id: str) -> dict:
    key_id = os.environ.get("RAZORPAY_KEY_ID") or RAZORPAY_KEY_ID
    key_secret = os.environ.get("RAZORPAY_KEY_SECRET") or RAZORPAY_KEY_SECRET
    if not key_id or not key_secret:
        raise ApiError(
            "Payment gateway configuration required: RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET are not configured on the backend.",
            503
        )
    if not pack_id or pack_id not in COIN_PACKS:
        raise ApiError(f"Invalid coin pack '{pack_id}'. Available: {list(COIN_PACKS.keys())}", 400)

    pack = COIN_PACKS[pack_id]
    order_id = f"order_{uuid.uuid4().hex[:16]}"

    order_doc = {
        "orderId": order_id,
        "userId": user_id,
        "packId": pack_id,
        "coins": pack["coins"],
        "amount": pack["amount_paise"],
        "currency": pack["currency"],
        "status": "created",
        "createdAt": firestore.SERVER_TIMESTAMP,
    }
    db.collection("orders").document(order_id).set(order_doc)

    return {
        "success": True,
        "orderId": order_id,
        "amount": pack["amount_paise"],
        "currency": pack["currency"],
        "keyId": key_id,
        "coins": pack["coins"],
        "name": pack["name"],
    }

def fetch_razorpay_payment(payment_id: str, key_id: str, key_secret: str) -> dict:
    """Fetch payment entity directly from Razorpay REST API using HTTP Basic Auth."""
    url = f"https://api.razorpay.com/v1/payments/{payment_id}"
    credentials = f"{key_id}:{key_secret}"
    encoded_auth = base64.b64encode(credentials.encode("utf-8")).decode("ascii")

    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Basic {encoded_auth}",
            "User-Agent": "Situationship-Backend/1.0",
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8")
        logger.error(f"Razorpay API error ({e.code}) for {payment_id}: {error_body}")
        raise ApiError(f"Payment gateway verification failed: {error_body}", 400)
    except Exception as e:
        logger.error(f"Razorpay connection error for {payment_id}: {e}")
        raise ApiError(f"Payment gateway communication error: {str(e)}", 502)

def verify_payment_signature(db, user_id: str, order_id: str, payment_id: str, signature: str) -> dict:
    key_id = os.environ.get("RAZORPAY_KEY_ID") or RAZORPAY_KEY_ID
    key_secret = os.environ.get("RAZORPAY_KEY_SECRET") or RAZORPAY_KEY_SECRET
    if not key_id or not key_secret:
        raise ApiError("Payment gateway configuration required: RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET are not configured", 503)

    if not order_id or not payment_id or not signature:
        raise ApiError("Missing required payment verification parameters (orderId, paymentId, signature)", 400)

    # 1. Cryptographic HMAC signature check
    message = f"{order_id}|{payment_id}".encode("utf-8")
    expected_signature = hmac.new(
        key_secret.encode("utf-8"),
        message,
        hashlib.sha256
    ).hexdigest()

    if not hmac.compare_digest(expected_signature, signature):
        raise ApiError("Invalid payment signature: verification failed", 400)

    # 2. Check Order existence & ownership before contacting gateway
    order_ref = db.collection("orders").document(order_id)
    order_doc = order_ref.get()
    if not order_doc.exists:
        raise ApiError(f"Order '{order_id}' not found", 404)

    order_data = order_doc.to_dict() or {}
    if order_data.get("userId") != user_id:
        raise ApiError("Order ownership mismatch: order does not belong to authenticated user", 403)

    # Fast-path idempotency: if already paid with matching paymentId
    if order_data.get("status") == "paid":
        return {
            "success": True,
            "alreadyProcessed": True,
            "orderId": order_id,
            "coins": order_data.get("coins", 0),
            "message": "Payment already verified and credited",
        }

    # 3. Server-side Gateway Settlement Verification
    # Call Razorpay API to confirm that the payment genuinely reached 'captured' status
    payment_record = fetch_razorpay_payment(payment_id, key_id, key_secret)

    # Verify payment binding to order
    pay_order_id = payment_record.get("order_id")
    if pay_order_id != order_id:
        raise ApiError(f"Payment order mismatch: payment is bound to order '{pay_order_id}', not '{order_id}'", 400)

    # Verify settlement state
    pay_status = payment_record.get("status")
    if pay_status not in ["captured", "settled"]:
        raise ApiError(f"Payment has not reached settled state (current status: '{pay_status}')", 400)

    # Verify amount matching server order
    expected_amount = order_data.get("amount")
    actual_amount = payment_record.get("amount")
    if actual_amount != expected_amount:
        raise ApiError(f"Payment amount mismatch: expected {expected_amount} paise, received {actual_amount} paise", 400)

    # Verify currency matching server order
    expected_currency = order_data.get("currency", "INR")
    actual_currency = payment_record.get("currency", "INR")
    if actual_currency != expected_currency:
        raise ApiError(f"Payment currency mismatch: expected '{expected_currency}', received '{actual_currency}'", 400)

    # 4. Atomic Transactional Fulfillment
    @firestore.transactional
    def _fulfill_txn(txn):
        order_snap = order_ref.get(transaction=txn)
        if not order_snap.exists:
            raise ApiError(f"Order '{order_id}' not found", 404)

        current_order = order_snap.to_dict() or {}
        if current_order.get("status") == "paid":
            return {
                "success": True,
                "alreadyProcessed": True,
                "orderId": order_id,
                "coins": current_order.get("coins", 0),
                "message": "Payment already verified and credited",
            }

        # Check payment audit log to prevent replay of paymentId across orders
        audit_ref = db.collection("payment_audit_logs").document(payment_id)
        audit_snap = audit_ref.get(transaction=txn)
        if audit_snap.exists:
            existing_audit = audit_snap.to_dict() or {}
            if existing_audit.get("orderId") != order_id or existing_audit.get("status") == "captured":
                return {
                    "success": True,
                    "alreadyProcessed": True,
                    "orderId": order_id,
                    "coins": current_order.get("coins", 0),
                    "message": "Payment already processed",
                }

        coins_to_add = current_order.get("coins", 0)
        user_ref = db.collection("users").document(user_id)
        user_snap = user_ref.get(transaction=txn)
        current_coins = user_snap.to_dict().get("coins", 0) if user_snap.exists else 0
        new_balance = current_coins + coins_to_add

        now_ts = firestore.SERVER_TIMESTAMP

        txn.update(order_ref, {
            "status": "paid",
            "paymentId": payment_id,
            "signature": signature,
            "paidAt": now_ts,
            "settledAt": now_ts,
            "gatewayStatus": pay_status,
        })

        txn.set(user_ref, {"coins": new_balance}, merge=True)

        txn.set(audit_ref, {
            "paymentId": payment_id,
            "orderId": order_id,
            "userId": user_id,
            "coins": coins_to_add,
            "amount": expected_amount,
            "currency": expected_currency,
            "status": "captured",
            "verifiedAt": now_ts,
            "settlementMethod": "api_verification",
        })

        tx_ref = db.collection("coin_transactions").document(f"tx_{payment_id}")
        txn.set(tx_ref, {
            "userId": user_id,
            "amount": coins_to_add,
            "type": "coin_purchase",
            "orderId": order_id,
            "paymentId": payment_id,
            "timestamp": now_ts,
        })

        return {
            "success": True,
            "alreadyProcessed": False,
            "orderId": order_id,
            "coinsAwarded": coins_to_add,
            "newBalance": new_balance,
        }

    txn = db.transaction()
    return _fulfill_txn(txn)

def handle_payment_webhook(db, raw_body: bytes, signature_header: str) -> dict:
    webhook_secret = os.environ.get("RAZORPAY_WEBHOOK_SECRET") or RAZORPAY_WEBHOOK_SECRET
    if not webhook_secret:
        raise ApiError("Webhook secret not configured", 503)

    if not signature_header:
        raise ApiError("Missing X-Razorpay-Signature header", 400)

    expected_sig = hmac.new(
        webhook_secret.encode("utf-8"),
        raw_body,
        hashlib.sha256
    ).hexdigest()

    if not hmac.compare_digest(expected_sig, signature_header):
        raise ApiError("Invalid webhook signature", 400)

    try:
        payload = json.loads(raw_body.decode("utf-8"))
    except Exception:
        raise ApiError("Invalid JSON webhook body", 400)

    event = payload.get("event")
    now_ts = firestore.SERVER_TIMESTAMP

    # 1. Captured & Paid Events
    if event in ["payment.captured", "order.paid"]:
        payment_entity = payload.get("payload", {}).get("payment", {}).get("entity", {})
        payment_id = payment_entity.get("id")
        order_id = payment_entity.get("order_id")
        amount = payment_entity.get("amount")
        currency = payment_entity.get("currency", "INR")
        pay_status = payment_entity.get("status")

        if payment_id and order_id:
            # Idempotency check via payment_audit_logs
            audit_ref = db.collection("payment_audit_logs").document(payment_id)
            if audit_ref.get().exists:
                audit_data = audit_ref.get().to_dict() or {}
                if audit_data.get("status") == "captured":
                    return {"status": "ok", "message": "Already processed and settled"}

            order_ref = db.collection("orders").document(order_id)
            order_doc = order_ref.get()
            if order_doc.exists:
                order_data = order_doc.to_dict() or {}
                # Verify amount and currency
                if order_data.get("amount") == amount and order_data.get("currency", "INR") == currency:
                    if order_data.get("status") != "paid":
                        user_id = order_data.get("userId")
                        coins = order_data.get("coins", 0)

                        @firestore.transactional
                        def _webhook_txn(txn):
                            user_ref = db.collection("users").document(user_id)
                            user_snap = user_ref.get(transaction=txn)
                            curr = user_snap.to_dict().get("coins", 0) if user_snap.exists else 0

                            txn.update(order_ref, {
                                "status": "paid",
                                "paymentId": payment_id,
                                "paidAt": now_ts,
                                "settledAt": now_ts,
                                "gatewayStatus": pay_status,
                            })
                            txn.set(user_ref, {"coins": curr + coins}, merge=True)
                            txn.set(audit_ref, {
                                "paymentId": payment_id,
                                "orderId": order_id,
                                "userId": user_id,
                                "coins": coins,
                                "amount": amount,
                                "currency": currency,
                                "status": "captured",
                                "timestamp": now_ts,
                                "settlementMethod": "webhook",
                            })
                            tx_ref = db.collection("coin_transactions").document(f"tx_wh_{payment_id}")
                            txn.set(tx_ref, {
                                "userId": user_id,
                                "amount": coins,
                                "type": "coin_purchase",
                                "orderId": order_id,
                                "paymentId": payment_id,
                                "timestamp": now_ts,
                            })

                        _webhook_txn(db.transaction())

    # 2. Failed Payment Events
    elif event == "payment.failed":
        payment_entity = payload.get("payload", {}).get("payment", {}).get("entity", {})
        payment_id = payment_entity.get("id")
        order_id = payment_entity.get("order_id")
        error_code = payment_entity.get("error_code")
        error_desc = payment_entity.get("error_description")

        if payment_id:
            audit_ref = db.collection("payment_audit_logs").document(payment_id)
            audit_ref.set({
                "paymentId": payment_id,
                "orderId": order_id,
                "status": "failed",
                "errorCode": error_code,
                "errorDescription": error_desc,
                "timestamp": now_ts,
                "settlementMethod": "webhook",
            }, merge=True)

            if order_id:
                order_ref = db.collection("orders").document(order_id)
                order_doc = order_ref.get()
                if order_doc.exists and order_doc.to_dict().get("status") != "paid":
                    order_ref.update({
                        "status": "failed",
                        "errorCode": error_code,
                        "failedAt": now_ts,
                    })

    # 3. Refund Events
    elif event in ["refund.processed", "payment.refunded"]:
        refund_entity = payload.get("payload", {}).get("refund", {}).get("entity", {})
        refund_id = refund_entity.get("id")
        payment_id = refund_entity.get("payment_id")
        amount = refund_entity.get("amount")

        if refund_id or payment_id:
            ref_id = refund_id or f"refund_{payment_id}"
            audit_ref = db.collection("payment_audit_logs").document(ref_id)
            audit_ref.set({
                "refundId": refund_id,
                "paymentId": payment_id,
                "amount": amount,
                "status": "refunded",
                "timestamp": now_ts,
                "settlementMethod": "webhook",
            }, merge=True)

    return {"status": "ok"}

# ── Spotlight Bidding ────────────────────────────────────────────────────────
def execute_spotlight_bid(db, user_id: str, bid_amount: int, tier: str = "gold", target_gender: str = "all", target_category: str = "dating", duration_minutes: int = 60, session_id: str = "global") -> dict:
    if type(bid_amount) is bool or not isinstance(bid_amount, int) or bid_amount < 10:
        raise ApiError("Invalid bidAmount: must be an integer >= 10", 400)

    if not session_id or not isinstance(session_id, str):
        session_id = "global"

    @firestore.transactional
    def _bid_txn(txn):
        user_ref = db.collection("users").document(user_id)
        user_snap = user_ref.get(transaction=txn)
        if not user_snap.exists:
            raise ApiError("User document not found", 404)

        user_data = user_snap.to_dict() or {}
        coins = user_data.get("coins", 0)

        # Check existing bid in this session
        session_ref = db.collection("spotlight_sessions").document(session_id)
        bid_ref = session_ref.collection("bids").document(user_id)
        existing_bid_snap = bid_ref.get(transaction=txn)
        prev_amount = 0
        if existing_bid_snap.exists:
            prev_amount = (existing_bid_snap.to_dict() or {}).get("amount", 0)

        delta = bid_amount - prev_amount
        if delta > 0 and coins < delta:
            raise ApiError("Insufficient coins for spotlight bid", 402)

        new_balance = coins - delta if delta > 0 else coins
        txn.update(user_ref, {"coins": new_balance})

        now_ts = firestore.SERVER_TIMESTAMP
        username = user_data.get("displayName") or user_data.get("name") or "Anonymous"
        avatar_url = user_data.get("photoUrl") or user_data.get("avatarUrl") or ""
        is_verified = bool(user_data.get("isVerified", False))

        # Update session bid document
        txn.set(bid_ref, {
            "sessionId": session_id,
            "userId": user_id,
            "username": username,
            "profileImageUrl": avatar_url,
            "isVerified": is_verified,
            "amount": bid_amount,
            "tier": tier,
            "targetGender": target_gender,
            "targetCategory": target_category,
            "timestamp": now_ts,
            "rank": 999,
        }, merge=True)

        # Update session prizePool
        txn.set(session_ref, {
            "isActive": True,
            "sessionId": session_id,
            "minStartingBid": 100,
            "prizePool": firestore.Increment(delta if delta > 0 else 0),
            "activeBidders": firestore.Increment(1 if prev_amount == 0 else 0),
        }, merge=True)

        # Record audit log in spotlight_bids
        bid_id = f"bid_{uuid.uuid4().hex[:16]}"
        global_bid_ref = db.collection("spotlight_bids").document(bid_id)
        txn.set(global_bid_ref, {
            "bidId": bid_id,
            "sessionId": session_id,
            "userId": user_id,
            "bidAmount": bid_amount,
            "delta": delta,
            "tier": tier,
            "targetGender": target_gender,
            "targetCategory": target_category,
            "durationMinutes": duration_minutes,
            "status": "active",
            "createdAt": now_ts,
        })

        if delta > 0:
            tx_ref = db.collection("coin_transactions").document(f"tx_{uuid.uuid4().hex[:16]}")
            txn.set(tx_ref, {
                "userId": user_id,
                "amount": -delta,
                "type": "spotlight_bid",
                "bidId": bid_id,
                "sessionId": session_id,
                "timestamp": now_ts,
            })

        return {
            "success": True,
            "bidId": bid_id,
            "bidAmount": bid_amount,
            "remainingCoins": new_balance,
            "sessionId": session_id,
            "status": "active",
        }

    txn = db.transaction()
    return _bid_txn(txn)

# ── Daily Login & Milestones ──────────────────────────────────────────────────
def execute_daily_login(db, user_id: str) -> dict:
    today_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    @firestore.transactional
    def _login_txn(txn):
        user_ref = db.collection("users").document(user_id)
        user_snap = user_ref.get(transaction=txn)
        if not user_snap.exists:
            raise ApiError("User document not found", 404)

        user_data = user_snap.to_dict() or {}
        last_login_date = user_data.get("lastLoginRewardDate")
        current_streak = user_data.get("loginStreak", 0)
        current_coins = user_data.get("coins", 0)

        if last_login_date == today_str:
            return {
                "success": True,
                "alreadyClaimed": True,
                "streak": current_streak,
                "rewardCoins": 0,
                "coins": current_coins,
            }

        yesterday_str = (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")
        if last_login_date == yesterday_str:
            new_streak = current_streak + 1
        else:
            new_streak = 1

        reward_coins = min(5 + (new_streak % 7) * 2, 25)
        new_balance = current_coins + reward_coins
        now_ts = firestore.SERVER_TIMESTAMP

        txn.update(user_ref, {
            "coins": new_balance,
            "lastLoginRewardDate": today_str,
            "loginStreak": new_streak,
        })

        tx_ref = db.collection("coin_transactions").document(f"tx_{uuid.uuid4().hex[:16]}")
        txn.set(tx_ref, {
            "userId": user_id,
            "amount": reward_coins,
            "type": "daily_login_reward",
            "streak": new_streak,
            "timestamp": now_ts,
        })

        return {
            "success": True,
            "alreadyClaimed": False,
            "streak": new_streak,
            "rewardCoins": reward_coins,
            "coins": new_balance,
        }

    txn = db.transaction()
    return _login_txn(txn)

MILESTONE_REWARDS = {
    "profile_complete": {"coins": 20, "description": "Complete your profile"},
    "first_match": {"coins": 15, "description": "Get your first match"},
    "first_chat": {"coins": 10, "description": "Send your first chat message"},
    "photo_verified": {"coins": 50, "description": "Verify your profile photo"},
}

def execute_claim_milestone(db, user_id: str, milestone_id: str) -> dict:
    if milestone_id not in MILESTONE_REWARDS:
        raise ApiError(f"Invalid milestoneId '{milestone_id}'. Valid: {list(MILESTONE_REWARDS.keys())}", 400)

    reward_info = MILESTONE_REWARDS[milestone_id]
    reward_coins = reward_info["coins"]

    @firestore.transactional
    def _milestone_txn(txn):
        user_ref = db.collection("users").document(user_id)
        user_snap = user_ref.get(transaction=txn)
        if not user_snap.exists:
            raise ApiError("User document not found", 404)

        user_data = user_snap.to_dict() or {}
        claimed = list(user_data.get("claimedMilestones", []))
        if milestone_id in claimed:
            raise ApiError(f"Milestone '{milestone_id}' has already been claimed", 409)

        if milestone_id == "photo_verified":
            if not user_data.get("isVerified", False):
                raise ApiError("Photo verification required to claim this milestone", 400)
        elif milestone_id == "profile_complete":
            has_name = bool(user_data.get("displayName") or user_data.get("name"))
            has_photos = bool(user_data.get("photos") or user_data.get("profileImages"))
            if not (has_name and has_photos):
                raise ApiError("Profile must have name and photos to claim milestone", 400)

        claimed.append(milestone_id)
        current_coins = user_data.get("coins", 0)
        new_balance = current_coins + reward_coins
        now_ts = firestore.SERVER_TIMESTAMP

        txn.update(user_ref, {
            "coins": new_balance,
            "claimedMilestones": claimed,
        })

        tx_ref = db.collection("coin_transactions").document(f"tx_{uuid.uuid4().hex[:16]}")
        txn.set(tx_ref, {
            "userId": user_id,
            "amount": reward_coins,
            "type": "milestone_reward",
            "milestoneId": milestone_id,
            "timestamp": now_ts,
        })

        return {
            "success": True,
            "milestoneId": milestone_id,
            "rewardCoins": reward_coins,
            "coins": new_balance,
        }

    txn = db.transaction()
    return _milestone_txn(txn)

# ── Single HTTPS Route Wrapper ────────────────────────────────────────────────
@https_fn.on_request(
    memory=options.MemoryOption.GB_4,
    cpu=2,
    timeout_sec=120,
    cors=options.CorsOptions(cors_origins="*", cors_methods=["POST", "GET", "OPTIONS"]),
)
def api(request: https_fn.Request) -> https_fn.Response:
    """Wrapper that routes REST HTTP requests securely inside Cloud Functions."""
    if request.method == "OPTIONS":
        return https_fn.Response(status=204)
        
    path = request.path.rstrip("/")
    
    try:
        # Protected reset endpoint (admin-only)
        if path.endswith("/reset-attempts") and request.method == "GET":
            admin_uid = authenticate_admin(request)
            target_uid = request.args.get("userId")
            if not target_uid:
                return https_fn.Response("Missing userId parameter", status=400)
            get_db().collection("verifications").document(target_uid).set({
                "verificationAttempts": 0,
                "verificationStatus": "not_started",
                "attemptsList": [] # Also clean up history so they start fresh
            }, merge=True)
            return https_fn.Response(
                f"Verification attempts reset successfully for user: {target_uid}",
                status=200,
                headers={"Access-Control-Allow-Origin": "*"}
            )

        # Admin account creation is restricted to verified admins only
        if path.endswith("/create-admin") and request.method == "GET":
            authenticate_admin(request)
            return https_fn.Response(
                "Admin self-provisioning endpoint is disabled in production.",
                status=403,
                headers={"Access-Control-Allow-Origin": "*"}
            )

        # ── Admin Stats ──
        if path.endswith("/admin/stats") and request.method == "GET":
            admin_uid = authenticate_admin(request)
            db = get_db()
            col = db.collection("verifications")
            
            pending_review = len(list(col.where("verificationStatus", "==", "manual_review").stream()))
            approved = len(list(col.where("verificationStatus", "==", "approved").stream()))
            rejected = len(list(col.where("verificationStatus", "==", "rejected").stream()))
            total = len(list(col.stream()))
            
            res_data = {
                "pending_review": pending_review,
                "approved": approved,
                "rejected": rejected,
                "total": total
            }
            return https_fn.Response(
                json.dumps(res_data),
                status=200,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"}
            )

        # ── Admin Verification Actions ──
        elif "/admin/verifications/" in path and request.method == "POST":
            admin_uid = authenticate_admin(request)
            # Extract target user ID and action from path (e.g., /admin/verifications/{userId}/{action})
            parts = [p for p in path.split("/") if p]
            if len(parts) >= 4:
                target_uid = parts[2]
                action = parts[3]
                
                db = get_db()
                req_json = request.get_json(silent=True) or {}
                reason = req_json.get("reason", "Action taken by admin")

                if action == "approve":
                    db.collection("verifications").document(target_uid).set({
                        "verificationStatus": "approved",
                        "verifiedBy": f"admin:{admin_uid}",
                        "verificationReason": reason,
                        "verifiedBadge": "S",
                        "adminReviewedAt": firestore.SERVER_TIMESTAMP
                    }, merge=True)
                    db.collection("users").document(target_uid).update({
                        "isVerified": True,
                        "verifiedBadge": "S"
                    })
                    return https_fn.Response(json.dumps({"success": True}), status=200, mimetype="application/json", headers={"Access-Control-Allow-Origin": "*"})

                elif action == "reject":
                    db.collection("verifications").document(target_uid).set({
                        "verificationStatus": "rejected",
                        "verifiedBy": f"admin:{admin_uid}",
                        "verificationReason": reason,
                        "adminReviewedAt": firestore.SERVER_TIMESTAMP
                    }, merge=True)
                    db.collection("users").document(target_uid).update({
                        "isVerified": False,
                        "verifiedBadge": None
                    })
                    return https_fn.Response(json.dumps({"success": True}), status=200, mimetype="application/json", headers={"Access-Control-Allow-Origin": "*"})

                elif action == "request-new":
                    db.collection("verifications").document(target_uid).set({
                        "verificationAttempts": 0,
                        "verificationStatus": "not_started",
                        "attemptsList": [],
                        "verificationReason": reason,
                        "adminReviewedAt": firestore.SERVER_TIMESTAMP
                    }, merge=True)
                    return https_fn.Response(json.dumps({"success": True}), status=200, mimetype="application/json", headers={"Access-Control-Allow-Origin": "*"})
            
            return https_fn.Response("Bad Admin Request", status=400)
        
        # ── Phone Unlock Action ──
        elif path.endswith("/user/unlock-phone") and request.method == "POST":
            caller_uid = authenticate_user(request)
            req_json = request.get_json(silent=True) or {}
            target_uid = req_json.get("targetUserId")
            idempotency_key = req_json.get("idempotencyKey")

            db = get_db()
            result = execute_phone_unlock(db, caller_uid, target_uid, idempotency_key)
            return https_fn.Response(
                json.dumps(result),
                status=200,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"}
            )

        # ── Admin PII Migration Action ──
        elif path.endswith("/admin/migrate-pii") and request.method == "POST":
            admin_uid = authenticate_admin(request)
            req_json = request.get_json(silent=True) or {}

            raw_batch_size = req_json.get("batchSize", 100)
            if type(raw_batch_size) is bool or not isinstance(raw_batch_size, int):
                return https_fn.Response(json.dumps({"detail": "Invalid batchSize: must be an integer"}), status=400, mimetype="application/json")
            if raw_batch_size < 1 or raw_batch_size > 250:
                return https_fn.Response(json.dumps({"detail": "Invalid batchSize: must be between 1 and 250"}), status=400, mimetype="application/json")
            batch_size = raw_batch_size

            raw_limit = req_json.get("limit", 100)
            if type(raw_limit) is bool or not isinstance(raw_limit, int):
                return https_fn.Response(json.dumps({"detail": "Invalid limit: must be an integer"}), status=400, mimetype="application/json")
            if raw_limit < 1 or raw_limit > 500:
                return https_fn.Response(json.dumps({"detail": "Invalid limit: must be between 1 and 500"}), status=400, mimetype="application/json")
            limit = raw_limit

            cursor = req_json.get("cursor")
            if cursor is not None and (type(cursor) is not str or not cursor.strip()):
                return https_fn.Response(json.dumps({"detail": "Invalid cursor: must be a non-empty string"}), status=400, mimetype="application/json")

            resume = bool(req_json.get("resume", False))
            dry_run = bool(req_json.get("dryRun", False))

            db = get_db()
            result = execute_pii_migration(db, limit=limit, cursor=cursor, batch_size=batch_size, resume=resume, dry_run=dry_run)
            return https_fn.Response(
                json.dumps(result),
                status=200,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"}
            )

        # ── Razorpay Payment Endpoints ──
        elif path.endswith("/payments/create-order") and request.method == "POST":
            user_id = authenticate_user(request)
            req_json = request.get_json(silent=True) or {}
            pack_id = req_json.get("packId") or req_json.get("tier")
            db = get_db()
            result = create_payment_order(db, user_id, pack_id)
            return https_fn.Response(
                json.dumps(result),
                status=200,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"}
            )

        elif path.endswith("/payments/verify") and request.method == "POST":
            user_id = authenticate_user(request)
            req_json = request.get_json(silent=True) or {}
            order_id = req_json.get("orderId")
            payment_id = req_json.get("paymentId")
            signature = req_json.get("signature")
            db = get_db()
            result = verify_payment_signature(db, user_id, order_id, payment_id, signature)
            return https_fn.Response(
                json.dumps(result),
                status=200,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"}
            )

        elif path.endswith("/payments/webhook") and request.method == "POST":
            signature_header = request.headers.get("X-Razorpay-Signature", "")
            raw_body = request.get_data()
            db = get_db()
            result = handle_payment_webhook(db, raw_body, signature_header)
            return https_fn.Response(
                json.dumps(result),
                status=200,
                mimetype="application/json"
            )

        # ── Spotlight Bidding Endpoint ──
        elif path.endswith("/user/spotlight-bid") and request.method == "POST":
            user_id = authenticate_user(request)
            req_json = request.get_json(silent=True) or {}
            bid_amount = req_json.get("bidAmount")
            tier = req_json.get("tier", "gold")
            target_gender = req_json.get("targetGender", "all")
            target_category = req_json.get("targetCategory", "dating")
            duration_minutes = req_json.get("durationMinutes", 60)
            session_id = req_json.get("sessionId", "global")
            db = get_db()
            result = execute_spotlight_bid(
                db, user_id, bid_amount=bid_amount, tier=tier,
                target_gender=target_gender, target_category=target_category,
                duration_minutes=duration_minutes, session_id=session_id
            )
            return https_fn.Response(
                json.dumps(result),
                status=200,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"}
            )

        # ── Daily Login & Milestones ──
        elif path.endswith("/user/daily-login") and request.method == "POST":
            user_id = authenticate_user(request)
            db = get_db()
            result = execute_daily_login(db, user_id)
            return https_fn.Response(
                json.dumps(result),
                status=200,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"}
            )

        elif path.endswith("/user/claim-milestone") and request.method == "POST":
            user_id = authenticate_user(request)
            req_json = request.get_json(silent=True) or {}
            milestone_id = req_json.get("milestoneId")
            db = get_db()
            result = execute_claim_milestone(db, user_id, milestone_id)
            return https_fn.Response(
                json.dumps(result),
                status=200,
                mimetype="application/json",
                headers={"Access-Control-Allow-Origin": "*"}
            )

        elif path.endswith("/challenge") and request.method == "POST":
            user_id = authenticate_user(request)
            return handle_challenge(user_id)
            
        elif path.endswith("/verify") and request.method == "POST":
            user_id = authenticate_user(request)
            return handle_verify(user_id, request)
            
        elif "/verify/status/" in path and request.method == "GET":
            user_id = authenticate_user(request)
            job_id = path.split("/verify/status/")[-1]
            return handle_status(user_id, job_id)
            
        else:
            return https_fn.Response("Not Found", status=404)
            
    except ApiError as e:
        return https_fn.Response(json.dumps({"detail": e.message}), status=e.status_code, mimetype="application/json")
    except ValueError as e:
        err_msg = str(e)
        status = 401 if ("authentication failed" in err_msg.lower() or "authorization" in err_msg.lower()) else 400
        if "forbidden" in err_msg.lower():
            status = 403
        return https_fn.Response(json.dumps({"detail": err_msg}), status=status, mimetype="application/json")
    except Exception as e:
        logger.exception("Internal error in api function")
        return https_fn.Response(json.dumps({"detail": str(e)}), status=500, mimetype="application/json")
