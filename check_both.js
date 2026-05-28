const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./serviceAccountKey.json');

initializeApp({
  credential: cert(serviceAccount),
});

async function check() {
  const db1 = getFirestore(undefined, '(default)');
  const db2 = getFirestore(undefined, 'default');
  
  const posts1 = await db1.collection('posts').get();
  console.log('(default) length:', posts1.docs.length);
  
  const posts2 = await db2.collection('posts').get();
  console.log('default length:', posts2.docs.length);
}

check().catch(console.error);
