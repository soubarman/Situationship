const { initializeApp } = require('firebase/app');
const { getFirestore, collection, getDocs, doc, getDoc } = require('firebase/firestore');

const firebaseConfig = {
  apiKey: 'AIzaSyBo21crFp9ui4bXzqHxFJnGoMmOH8uDoVg',
  appId: '1:990817672883:web:b9d16252fcd56fee4c9ac6',
  messagingSenderId: '990817672883',
  projectId: 'situation-ship',
  authDomain: 'situation-ship.firebaseapp.com',
  storageBucket: 'situation-ship.firebasestorage.app',
};

const app = initializeApp(firebaseConfig);

async function run() {
  console.log("Checking DB: default");
  try {
    const dbDefault = getFirestore(app, 'default');
    const snap = await getDocs(collection(dbDefault, 'users'));
    console.log(`Found ${snap.docs.length} users in 'default':`);
    snap.docs.forEach(d => {
      const data = d.data();
      console.log(`- ${d.id} (${data.name}): avatarUrl=${data.avatarUrl}, photos=${JSON.stringify(data.photos)}`);
    });
  } catch (e) {
    console.error("Error with 'default':", e.message);
  }

  console.log("\nChecking DB: (default)");
  try {
    const dbParen = getFirestore(app, '(default)');
    const snap2 = await getDocs(collection(dbParen, 'users'));
    console.log(`Found ${snap2.docs.length} users in '(default)':`);
    snap2.docs.forEach(d => {
      const data = d.data();
      console.log(`- ${d.id} (${data.name}): avatarUrl=${data.avatarUrl}, photos=${JSON.stringify(data.photos)}`);
    });
  } catch (e) {
    console.error("Error with '(default)':", e.message);
  }
}

run();
