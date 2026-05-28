const admin = require('firebase-admin');
const key = require('./serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(key) });
const db = admin.firestore();

async function checkPosts() {
  const posts = await db.collection('posts').get();
  console.log('Total posts:', posts.docs.length);
  process.exit(0);
}
checkPosts();
