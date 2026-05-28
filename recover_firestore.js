/**
 * recover_firestore.js  (firebase-admin v12+ compatible)
 * ─────────────────────────────────────────────────────────────────────────────
 * Scans Firebase Storage for existing post images and rebuilds the missing
 * Firestore `users` and `posts` documents.
 *
 * HOW TO RUN:
 *   node recover_firestore.js
 * ─────────────────────────────────────────────────────────────────────────────
 */

// ── firebase-admin v12+ uses named exports ────────────────────────────────────
const { initializeApp, cert }  = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getStorage }           = require('firebase-admin/storage');
const { getAuth }              = require('firebase-admin/auth');
const path                     = require('path');

const serviceAccount = require('./serviceAccountKey.json');

// ── Init ──────────────────────────────────────────────────────────────────────
initializeApp({
  credential:    cert(serviceAccount),
  storageBucket: 'situation-ship.firebasestorage.app',
});

const db     = getFirestore(undefined, 'default');
const bucket = getStorage().bucket();
const auth   = getAuth();

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Build a Firebase Storage download URL from the file's metadata token.
 * Does NOT need getSignedUrl() or IAM signBlob permission.
 */
async function getDownloadUrl(file) {
  const [meta] = await file.getMetadata();

  const token = meta.metadata?.firebaseStorageDownloadTokens;
  if (token) {
    const encoded = encodeURIComponent(file.name);
    return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;
  }

  // Fallback: make the object publicly readable
  console.log(`    ⚠  No download token — making file public…`);
  await file.makePublic();
  return `https://storage.googleapis.com/${bucket.name}/${file.name}`;
}

async function getAuthUser(uid) {
  try {
    return await auth.getUser(uid);
  } catch {
    return null;
  }
}

// ── Smoke-test Firestore before doing real work ────────────────────────────────
async function testFirestore() {
  try {
    const testRef = db.collection('_recovery_test').doc('ping');
    await testRef.set({ ok: true });
    await testRef.delete();
    console.log('  ✅  Firestore connection OK\n');
    return true;
  } catch (e) {
    console.error(`  ❌  Firestore connection FAILED: ${e.message}`);
    console.error('\n  Possible causes:');
    console.error('  • Firestore database has not been created in the Firebase Console.');
    console.error('    Go to → https://console.firebase.google.com/project/situation-ship/firestore');
    console.error('    and click "Create database" if you haven\'t already.\n');
    return false;
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function recover() {
  console.log('\n🔧  Testing Firestore connection...');
  const ok = await testFirestore();
  if (!ok) process.exit(1);

  console.log('🔍  Scanning Storage bucket for post images...\n');

  const [files]    = await bucket.getFiles({ prefix: 'posts/' });
  const imageFiles = files.filter(f => !f.name.endsWith('/'));

  if (imageFiles.length === 0) {
    console.log('⚠️  No image files found under posts/. Nothing to recover.');
    return;
  }

  console.log(`📦  Found ${imageFiles.length} image file(s). Rebuilding Firestore...\n`);

  const processedUids = new Set();

  for (const file of imageFiles) {
    const fileName = path.basename(file.name);
    const parts    = fileName.split('_');

    if (parts.length < 2) {
      console.log(`  ⏭  Skipping: ${fileName}`);
      continue;
    }

    const uid       = parts[0];
    const tsStr     = parts.slice(1).join('_').split('.')[0];
    const timestamp = parseInt(tsStr, 10);
    const createdAt = isNaN(timestamp) ? Date.now() : timestamp;
    const postId    = `recovered_${uid}_${tsStr}`;

    console.log(`\n  📂  ${fileName}`);

    // ── 1. User doc ───────────────────────────────────────────────────────────
    if (!processedUids.has(uid)) {
      try {
        const userRef  = db.collection('users').doc(uid);
        const userSnap = await userRef.get();

        if (!userSnap.exists) {
          const authUser = await getAuthUser(uid);
          const name     = authUser?.displayName
                           || authUser?.email?.split('@')[0]
                           || `User_${uid.slice(0, 6)}`;
          const email    = authUser?.email    || '';
          const avatar   = authUser?.photoURL || null;

          await userRef.set({
            id: uid, name, email, age: 18,
            bio: '', location: '', avatarUrl: avatar,
            interests: [], photos: [],
            isVerified: false, isOnline: false,
            followers: [], following: [], likedBy: [], matches: [],
            postCount: 0,
          });
          console.log(`  ✅  Created user doc → ${name}`);
        } else {
          console.log(`  👤  User doc already exists`);
        }

        processedUids.add(uid);
      } catch (e) {
        console.error(`  ❌  User doc failed: ${e.message}`);
        continue;
      }
    }

    // ── 2. Post doc ───────────────────────────────────────────────────────────
    try {
      const postRef  = db.collection('posts').doc(postId);
      const postSnap = await postRef.get();

      if (postSnap.exists) {
        console.log(`  📄  Post already exists`);
        continue;
      }

      let imageUrl;
      try {
        imageUrl = await getDownloadUrl(file);
      } catch (e) {
        console.error(`  ❌  URL failed: ${e.message}`);
        continue;
      }

      const userSnap = await db.collection('users').doc(uid).get();
      const u        = userSnap.data() || {};

      await postRef.set({
        id: postId, userId: uid,
        userName:       u.name       || 'User',
        userAvatar:     u.avatarUrl  || null,
        isUserVerified: u.isVerified || false,
        imageUrl,
        caption: '', likes: [], commentCount: 0, shareCount: 0,
        createdAt: Timestamp.fromMillis(createdAt),
        tags: [],
      });

      console.log(`  🖼  Post created → ${postId}`);
    } catch (e) {
      console.error(`  ❌  Post failed: ${e.message}`);
    }
  }

  // ── 3. Update postCount ───────────────────────────────────────────────────
  console.log('\n📊  Updating post counts...');
  for (const uid of processedUids) {
    try {
      const snap = await db.collection('posts').where('userId', '==', uid).get();
      await db.collection('users').doc(uid).update({ postCount: snap.size });
      console.log(`  ✅  ${uid.slice(0, 12)}… → ${snap.size} post(s)`);
    } catch (e) {
      console.error(`  ❌  postCount update failed: ${e.message}`);
    }
  }

  console.log('\n✨  Recovery complete! Reload your app.\n');
}

recover().catch(err => {
  console.error('\n❌  Unhandled error:', err.message);
  console.error(err.stack);
  process.exit(1);
});
