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
    console.log('--- User:', doc.id);
    console.log(JSON.stringify(doc.data(), null, 2));
  });
}

check().catch(console.error);
