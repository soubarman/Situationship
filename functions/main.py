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
import logging
import tempfile
import shutil
import urllib.request
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

db = None
def get_db():
    global db
    if db is None:
        try:
            app = firebase_admin.get_app()
            project_id = getattr(app, "project_id", None) or os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCLOUD_PROJECT")
            db = gcp_firestore.Client(project=project_id, database="default")
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
def authenticate_user(request) -> str:
    """Validate Authorization header and return Firebase User UID."""
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise ValueError("Missing or invalid authorization header")
    
    token = auth_header.split(" ")[1]
    try:
        decoded = auth.verify_id_token(token)
        return decoded["uid"]
    except Exception as e:
        raise ValueError(f"Authentication failed: {str(e)}")

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

# ── Single HTTPS Route Wrapper ────────────────────────────────────────────────
@https_fn.on_request(
    memory=options.MemoryOption.GB_4,
    cpu=2,
    timeout_sec=120,
    cors=options.CorsOptions(cors_origins="*", cors_methods=["POST", "GET", "OPTIONS"])
)
def api(request: https_fn.Request) -> https_fn.Response:
    """Wrapper that routes REST HTTP requests securely inside Cloud Functions."""
    if request.method == "OPTIONS":
        return https_fn.Response(status=204)
        
    path = request.path.rstrip("/")
    
    try:
        # Public reset endpoint for staging/debug (helps when user reaches 5/5 attempts)
        if path.endswith("/reset-attempts") and request.method == "GET":
            # Extract user ID from query parameters or default to the test user ID
            target_uid = request.args.get("userId") or "6JKEYKfEoGgewQJ9IwPzvsQRQe42"
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

        # Create dedicated admin account endpoint (staging/developer helper)
        if path.endswith("/create-admin") and request.method == "GET":
            try:
                # 1. Create or get user in Firebase Auth
                email = "admin@situationship.com"
                password = "AdminPassword123!"
                try:
                    user = auth.create_user(
                        email=email,
                        password=password,
                        display_name="Verification Admin"
                    )
                    uid = user.uid
                except auth.EmailAlreadyExistsError:
                    user = auth.get_user_by_email(email)
                    uid = user.uid
                    # Update password in case they want a fresh reset
                    auth.update_user(uid, password=password)
                
                # 2. Grant admin claims
                auth.set_custom_user_claims(uid, {"admin": True})
                
                # 3. Create document in Firestore users collection
                get_db().collection("users").document(uid).set({
                    "id": uid,
                    "name": "Verification Admin",
                    "email": email,
                    "bio": "Situationship Verification Administrator",
                    "avatarUrl": "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150",
                    "isVerified": True,
                    "verifiedBadge": "S",
                    "coins": 9999,
                    "createdAt": firestore.SERVER_TIMESTAMP
                }, merge=True)

                return https_fn.Response(
                    f"Success! Admin account created/updated.<br>Email: <b>{email}</b><br>Password: <b>{password}</b>",
                    status=200,
                    headers={"Access-Control-Allow-Origin": "*", "Content-Type": "text/html"}
                )
            except Exception as ex:
                return https_fn.Response(f"Error creating admin: {ex}", status=500)



        # Validate Firebase ID token
        user_id = authenticate_user(request)

        # ── Admin Stats ──
        if path.endswith("/admin/stats") and request.method == "GET":
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
                        "verifiedBy": f"admin:{user_id}",
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
                        "verifiedBy": f"admin:{user_id}",
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
        
        elif path.endswith("/challenge") and request.method == "POST":
            return handle_challenge(user_id)
            
        elif path.endswith("/verify") and request.method == "POST":
            return handle_verify(user_id, request)
            
        elif "/verify/status/" in path and request.method == "GET":
            job_id = path.split("/verify/status/")[-1]
            return handle_status(user_id, job_id)
            
        else:
            return https_fn.Response("Not Found", status=404)
            
    except ValueError as e:
        return https_fn.Response(json.dumps({"detail": str(e)}), status=401, mimetype="application/json")
    except Exception as e:
        logger.exception("Internal error in api function")
        return https_fn.Response(json.dumps({"detail": str(e)}), status=500, mimetype="application/json")
