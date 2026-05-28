const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const serviceAccount = require('./serviceAccountKey.json');

initializeApp({
  credential: cert(serviceAccount),
});

async function test() {
  try {
    // Attempt with default behavior which looks for (default)
    const db1 = getFirestore();
    await db1.collection('_test').doc('ping').set({ ok: true });
    console.log("Success with getFirestore()");
  } catch (err) {
    console.error("Failed getFirestore():", err.message);
  }

  try {
    // Attempt with explicit databaseId 'default'
    const db2 = getFirestore(undefined, 'default');
    await db2.collection('_test').doc('ping').set({ ok: true });
    console.log("Success with getFirestore(undefined, 'default')");
  } catch (err) {
    console.error("Failed getFirestore(undefined, 'default'):", err.message);
  }
}

test();
