# Super Simple One-Click Deployment Guide (No Server Setup Required)

If managing a VPS (Hetzner, DigitalOcean), Docker, and SSL certificates is too complicated, you can deploy the verification service for **free or very cheap** using **Render** or **Railway**. 

These services connect directly to your GitHub repository and handle building, deploying, scaling, and SSL certificates (HTTPS link) **automatically** with zero command-line work!

---

## Option A: Deploying on Render (Recommended)

Render is extremely user-friendly and handles everything through a visual web interface.

### Step 1: Push your code to GitHub
If you haven't already, push your Situationship repository to a private GitHub repository.

### Step 2: Create a Redis Database (Message Broker)
1. Go to [Render.com](https://render.com) and sign up/log in.
2. In the Render Dashboard, click **New +** (top right) and select **Redis**.
3. Name it `verification-redis`.
4. Click **Create Redis**.
5. Once created, copy the **Internal Redis URL** (looks like `redis://red-xxxxxxxxxx:6379`).

### Step 3: Create the FastAPI Web Service (API)
1. In the Render Dashboard, click **New +** and select **Web Service**.
2. Connect your GitHub repository.
3. Configure the following fields:
   * **Name:** `situationship-verify-api`
   * **Region:** Choose the one closest to your users.
   * **Root Directory:** `verification-service` (Important!)
   * **Runtime:** `Python`
   * **Build Command:** `pip install -r requirements.txt && python scripts/download_models.py`
   * **Start Command:** `uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1`
4. Scroll down, click **Advanced**, and click **Add Environment Variable**. Add these values:
   * `REDIS_URL`: Paste the **Internal Redis URL** you copied in Step 2.
   * `FIREBASE_PROJECT_ID`: `situation-ship`
   * `FIREBASE_STORAGE_BUCKET`: `situation-ship.appspot.com`
   * `SECRET_KEY`: (Enter any long random text)
   * `ALLOWED_ORIGINS`: `["https://situatioship.netlify.app"]`
   * `FIREBASE_SERVICE_ACCOUNT_JSON`: `/opt/render/project/src/verification-service/firebase-service-account.json`
5. Click **Create Web Service**. Render will automatically build the service, download the AI models, and give you a secure URL like `https://situationship-verify-api.onrender.com`.

### Step 4: Create the Celery Worker (AI Processor)
1. In the Render Dashboard, click **New +** and select **Background Worker**.
2. Connect the same GitHub repository.
3. Configure the fields:
   * **Name:** `situationship-verify-worker`
   * **Root Directory:** `verification-service`
   * **Runtime:** `Python`
   * **Build Command:** `pip install -r requirements.txt && python scripts/download_models.py`
   * **Start Command:** `celery -A app.workers.celery_app.celery_app worker --loglevel=info --concurrency=1`
4. Click **Advanced**, and add the exact same environment variables as Step 3.
5. Click **Create Background Worker**.

### Step 5: Add your Firebase Secret Key
To let Render read/write to your Firestore database:
1. In the **FastAPI Web Service** settings in Render, go to **Environment** tab.
2. Scroll to **Secret Files**.
3. Click **Add Secret File**.
4. Set the Filename to `firebase-service-account.json`.
5. Open your Firebase Service Account JSON file on your computer, copy all of its content, and paste it into the value field.
6. Repeat this for the **Celery Worker** service.

**🎉 Done! Your service is live and secure.**

---

## Option B: Deploying on Railway (Even Simpler)

Railway is another great alternative that lets you deploy everything in a single visual canvas.

1. Go to [Railway.app](https://railway.app) and create an account.
2. Click **New Project** -> **Provision Redis** (this sets up your database).
3. Click **New** -> **GitHub Repo** and connect your repository.
4. Set the **Root Directory** to `verification-service`.
5. Under variables, add all variables from `.env.example` (including pasting your Firebase JSON string directly into a variable named `FIREBASE_SERVICE_ACCOUNT_JSON_STRING` if preferred, which we can support).
6. Railway will automatically give you a public `https://...` domain.

---

## Update Flutter App Base URL

Once you have your `https://xxxx.onrender.com` or `https://xxxx.railway.app` URL:
1. Open `lib/features/verification/presentation/providers/verification_provider.dart` on your computer.
2. Change `_kApiBase` (around line 21) to point to your new URL:
   ```dart
   const _kApiBase = 'https://situationship-verify-api.onrender.com/api/v1';
   ```
3. Save, rebuild the app, and redeploy to Netlify!
