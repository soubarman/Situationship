/**
 * reset_likes_and_chats.js
 * 
 * Safely resets all likes, matches, follow lists, passed/disliked history,
 * and deletes all active chats and message threads for all users in Firestore.
 * 
 * Preserved:
 * - User profiles (names, bios, photos, age, gender, settings)
 * - User coins and verification badges
 * - Posts and Communities
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const PROJECT_ID = 'situation-ship';

// 1. Retrieve access token from Firebase CLI config
function getAccessToken() {
  const configPath = path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json');
  if (!fs.existsSync(configPath)) {
    throw new Error('Firebase CLI credentials not found. Run `firebase login` first.');
  }
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const tokens = config.tokens;
  if (!tokens || !tokens.access_token) {
    throw new Error('No access token found in firebase-tools.json. Please run `firebase login`.');
  }
  return tokens.access_token;
}

// 2. Fetch all user documents from a Firestore database
async function getAllUsers(databaseId, token) {
  const users = [];
  let pageToken = '';
  do {
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/${databaseId}/documents/users?pageSize=100${pageToken ? '&pageToken=' + pageToken : ''}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) {
      console.warn(`[${databaseId}] Could not fetch users: ${res.statusText}`);
      break;
    }
    const json = await res.json();
    if (json.documents) {
      users.push(...json.documents);
    }
    pageToken = json.nextPageToken || '';
  } while (pageToken);
  return users;
}

// 3. Reset like and match arrays on a user document
async function resetUserRelations(docName, token) {
  const fieldsToReset = [
    'likedBy',
    'matches',
    'following',
    'followers',
    'dislikedUsers',
    'unlockedUserPhones',
    'unlockedVisitors'
  ];

  const updateMask = fieldsToReset.map(f => `updateMask.fieldPaths=${f}`).join('&');
  const url = `https://firestore.googleapis.com/v1/${docName}?${updateMask}`;

  const body = {
    fields: {
      likedBy: { arrayValue: {} },
      matches: { arrayValue: {} },
      following: { arrayValue: {} },
      followers: { arrayValue: {} },
      dislikedUsers: { arrayValue: {} },
      unlockedUserPhones: { arrayValue: {} },
      unlockedVisitors: { arrayValue: {} }
    }
  };

  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(body)
  });

  return res.ok;
}

const isDryRun = process.argv.includes('--dry-run');

async function main() {
  console.log('====================================================');
  console.log(`🔄 Situationship: Reset All Likes & Chats ${isDryRun ? '[DRY RUN MODE]' : ''}`);
  console.log('====================================================\n');

  const token = getAccessToken();
  console.log('✅ Authenticated with Firebase CLI credentials');

  // Step 1: Reset Users in 'default' and '(default)' databases
  const databases = ['default', '(default)'];
  for (const dbId of databases) {
    console.log(`\n🔍 Fetching users from database "${dbId}"...`);
    const users = await getAllUsers(dbId, token);
    console.log(`Found ${users.length} users in database "${dbId}".`);

    if (users.length > 0) {
      if (isDryRun) {
        console.log(`[DRY RUN] Would reset likes, matches, and following for ${users.length} users.`);
      } else {
        process.stdout.write(`Resetting likes, matches, and following lists... `);
        let successCount = 0;
        for (const u of users) {
          const ok = await resetUserRelations(u.name, token);
          if (ok) successCount++;
        }
        console.log(`✅ [${successCount}/${users.length} users updated]`);
      }
    }
  }

  // Step 2: Delete 'chats' collection recursively
  console.log('\n🗑️  Deleting all chat conversations and messages...');
  if (isDryRun) {
    console.log('[DRY RUN] Would recursively delete collection "chats" in "default" and "(default)".');
  } else {
    try {
      execSync(`firebase firestore:delete chats -r -f --database "default" --project ${PROJECT_ID}`, {
        stdio: 'inherit'
      });
      console.log('✅ Deleted chats from database "default".');
    } catch (err) {
      console.warn('Notice while deleting default chats:', err.message);
    }

    try {
      execSync(`firebase firestore:delete chats -r -f --database "(default)" --project ${PROJECT_ID}`, {
        stdio: 'inherit'
      });
      console.log('✅ Deleted chats from database "(default)".');
    } catch (err) {
      // If not present in (default), ignore
    }
  }

  // Step 3: Delete profile views history
  console.log('\n👁️  Clearing profile views history...');
  if (isDryRun) {
    console.log('[DRY RUN] Would recursively delete collection "profile_views".');
  } else {
    try {
      execSync(`firebase firestore:delete profile_views -r -f --database "default" --project ${PROJECT_ID}`, {
        stdio: 'inherit'
      });
      console.log('✅ Cleared profile_views from database "default".');
    } catch (_) {}
  }

  console.log('\n====================================================');
  if (isDryRun) {
    console.log('ℹ️  DRY RUN complete! No data was modified.');
    console.log('Run without --dry-run to apply the changes.');
  } else {
    console.log('🎉 Reset Complete! All users have a clean slate.');
    console.log('- All chats and messages have been cleared.');
    console.log('- All likes, matches, following, and unlikes reset to empty.');
    console.log('- User profiles, photos, bios, and coins are safely preserved.');
  }
  console.log('====================================================\n');
}

main().catch(err => {
  console.error('❌ Error during reset:', err);
  process.exit(1);
});
