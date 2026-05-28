const admin = require('firebase-admin');
const key = require('./serviceAccountKey.json');
admin.initializeApp({ credential: admin.credential.cert(key) });
const db = admin.firestore();

const names = ['Sourav Barman', 'Priya Das', 'All In One IAS Academy', 'Dimpi Hazarika', 
               'Alex Test', 'Amit Boruah', 'Riya Gupta', 'Sam Iyer', 'Sourav B', 'Chris T'];
const bios = [
  'Chill vibes only 🌊', 'Coffee addict ☕', 'Living life to the fullest ✨',
  'Adventure seeker 🌎', 'Music lover 🎵', 'Foodie 🍕', 'Dog parent 🐶',
  'Gym rat 💪', 'Bookworm 📚', 'Night owl 🦉'
];
const interests = [
  ['music', 'coffee', 'travel'], ['art', 'yoga', 'food'], ['coding', 'gaming', 'chess'],
  ['hiking', 'photography', 'cooking'], ['movies', 'fitness', 'reading'],
  ['dance', 'fashion', 'travel'], ['sports', 'gaming', 'food'],
  ['fitness', 'nutrition', 'running'], ['books', 'writing', 'coffee'],
  ['tech', 'AI', 'startups']
];
const avatars = [
  'https://i.pravatar.cc/400?img=1', 'https://i.pravatar.cc/400?img=2',
  'https://i.pravatar.cc/400?img=3', 'https://i.pravatar.cc/400?img=4',
  'https://i.pravatar.cc/400?img=5', 'https://i.pravatar.cc/400?img=6',
  'https://i.pravatar.cc/400?img=7', 'https://i.pravatar.cc/400?img=8',
  'https://i.pravatar.cc/400?img=9', 'https://i.pravatar.cc/400?img=10',
];

async function seed() {
  const result = await admin.auth().listUsers(25);
  const users = result.users;
  console.log(`Seeding ${users.length} users to Firestore...`);
  
  const batch = db.batch();
  users.forEach((authUser, i) => {
    const displayName = authUser.displayName || names[i] || `User ${i+1}`;
    const ref = db.collection('users').doc(authUser.uid);
    batch.set(ref, {
      id: authUser.uid,
      name: displayName,
      email: authUser.email || '',
      age: 20 + (i % 15),
      avatarUrl: authUser.photoURL || avatars[i % avatars.length],
      bio: bios[i % bios.length],
      interests: interests[i % interests.length],
      isVerified: i < 3,
      isOnline: i % 2 === 0,
      coins: 100 + (i * 50),
      followers: [],
      following: [],
      location: 'Guwahati, India',
      createdAt: Date.now(),
    }, { merge: true });
  });
  
  await batch.commit();
  console.log('✅ Done! Seeded', users.length, 'users.');
  process.exit(0);
}

seed().catch(e => { console.error(e.message); process.exit(1); });
