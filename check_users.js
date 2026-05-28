const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./serviceAccountKey.json');

initializeApp({
  credential: cert(serviceAccount),
});

async function check() {
  const db1 = getFirestore(undefined, '(default)');
  const db2 = getFirestore(undefined, 'default');
  
  const users1 = await db1.collection('users').get();
  console.log('(default) users:', users1.docs.length);
  
  const users2 = await db2.collection('users').get();
  console.log('default users:', users2.docs.length);
}

check().catch(console.error);
