const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./serviceAccountKey.json');

initializeApp({
  credential: cert(serviceAccount),
});

async function check() {
  const db = getFirestore(undefined, 'default');
  const snapshot = await db.collection('users').get();
  snapshot.docs.forEach(doc => {
    const data = doc.data();
    console.log(doc.id, 'lastSeen:', data.lastSeen, typeof data.lastSeen, data.lastSeen?.constructor?.name);
  });
}

check().catch(console.error);
