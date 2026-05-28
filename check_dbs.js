const admin = require('firebase-admin');
const key = require('./serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(key) });

async function checkDbs() {
  const db1 = admin.firestore(); // (default)
  const db2 = admin.firestore(admin.app(), 'default'); // 'default'
  
  const posts1 = await db1.collection('posts').get();
  console.log('(default) Total posts:', posts1.docs.length);

  try {
    const posts2 = await db2.collection('posts').get();
    console.log("'default' Total posts:", posts2.docs.length);
  } catch (e) {
    console.log("'default' Error:", e.message);
  }
  process.exit(0);
}
checkDbs();
