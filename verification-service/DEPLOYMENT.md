# ⚡ Zero-Server Account Verification (Firebase Cloud Functions)

You can run the entire account verification AI pipeline **directly on your existing Firebase project**. 

There is **no need to rent or configure any other server** (no VPS, no Docker, no Redis, no Celery, and no Nginx)! Everything runs 100% serverless, is fully production-ready, scales automatically, and only bills you when users trigger it.

---

## Step 1: Deploy to your Firebase Project

From your computer's terminal, in the root directory of your project, simply run:

```bash
firebase deploy --only functions
```

### What this does automatically:
*   Firebase packages the code inside the `functions` folder.
*   Installs Python requirements (`insightface`, `onnxruntime`, etc.) in the Cloud Function.
*   Provisions a secure API endpoint with **4GB of RAM** and **2 vCPUs** (fully production-ready for AI inference).
*   Downloads the required liveness model files on first boot to temporary writeable memory.

---

## Step 2: Get the Cloud Function URL

Once the deploy command finishes, the Firebase CLI will print the public URL of your new API function. It looks like:
`https://api-<hash>-<region>.a.run.app` or `https://<region>-<project-id>.cloudfunctions.net/api`

---

## Step 3: Update Flutter App Config

1. Open `lib/features/verification/presentation/providers/verification_provider.dart` in your code editor.
2. Update the `_kApiBase` variable to point to your new Firebase Cloud Function URL:
   ```dart
   const _kApiBase = 'https://us-central1-situation-ship.cloudfunctions.net/api'; // <-- Replace with your URL
   ```
3. Update the `window._API_BASE` in the admin dashboard `admin-dashboard/dashboard/index.html` to point to the same URL.
4. Save and rebuild!
