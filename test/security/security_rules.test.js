/**
 * test/security/security_rules.test.js
 * ─────────────────────────────────────────────────────────────────────────────
 * Phase 4A: Comprehensive Automated Security Rules Test Suite for Situationship.
 * Uses official @firebase/rules-unit-testing to verify all access control
 * and data integrity invariants against real Firestore and Storage emulators.
 * ─────────────────────────────────────────────────────────────────────────────
 */

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'situation-ship';

describe('Situationship Phase 4A Security Rules Automated Test Suite', () => {
  let testEnv;

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: fs.readFileSync(path.resolve(__dirname, '../../firestore.rules'), 'utf8'),
        host: '127.0.0.1',
        port: 8080,
      },
      storage: {
        rules: fs.readFileSync(path.resolve(__dirname, '../../storage.rules'), 'utf8'),
        host: '127.0.0.1',
        port: 9199,
      },
    });
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.clearStorage();

    // Seed baseline user profiles and collections via admin context
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();

      // Alice (userA): Verified, subscribed, member of comm1
      await db.collection('users').doc('userA').set({
        id: 'userA',
        name: 'Alice',
        coins: 100,
        totalEarnedCoins: 600,
        isVerified: true,
        isSubscribed: true,
        isSuspended: false,
        followers: [],
        likedBy: [],
        superLikedBy: [],
        blockedUsers: [],
        joinedCommunities: ['comm1'],
      });

      // Bob (userB): Active user, member of comm1, already liked Alice (enables match)
      await db.collection('users').doc('userB').set({
        id: 'userB',
        name: 'Bob',
        coins: 50,
        totalEarnedCoins: 200,
        isVerified: false,
        isSubscribed: false,
        isSuspended: false,
        followers: ['userA'],
        likedBy: ['userA'],
        superLikedBy: [],
        blockedUsers: [],
        joinedCommunities: ['comm1'],
      });

      // Charlie (userC): Unconnected stranger
      await db.collection('users').doc('userC').set({
        id: 'userC',
        name: 'Charlie',
        coins: 10,
        totalEarnedCoins: 0,
        isVerified: false,
        isSubscribed: false,
        isSuspended: false,
        followers: [],
        likedBy: [],
        superLikedBy: [],
        blockedUsers: [],
        joinedCommunities: [],
      });

      // userBlocked: Blocked Alice
      await db.collection('users').doc('userBlocked').set({
        id: 'userBlocked',
        name: 'Dave (Blocked Alice)',
        isSuspended: false,
        blockedUsers: ['userA'],
      });

      // userSuspended: Suspended user
      await db.collection('users').doc('userSuspended').set({
        id: 'userSuspended',
        name: 'Eve (Suspended)',
        isSuspended: true,
      });

      // Private data subcollection (Bob)
      await db.collection('users').doc('userB').collection('private').doc('settings').set({
        phoneNumber: '+19998887777',
        email: 'bob@example.com',
      });

      // Active chat between Alice and Bob
      await db.collection('chats').doc('chat_alice_bob').set({
        id: 'chat_alice_bob',
        participants: ['userA', 'userB'],
        lastMessage: 'Hello Bob',
        unreadCount: 0,
        status: 'accepted',
      });
      await db.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').set({
        id: 'msg1',
        senderId: 'userA',
        text: 'Hello Bob',
        type: 'text',
        isRead: false,
        createdAt: Date.now(),
      });

      // Community comm1 (Admin: Alice, Members: Alice, Bob)
      await db.collection('communities').doc('comm1').set({
        id: 'comm1',
        name: 'Assam Vibes',
        adminId: 'userA',
        createdBy: 'userA',
        memberCount: 2,
        memberAvatars: ['userA', 'userB'],
        pendingApprovals: [],
      });
      await db.collection('communities').doc('comm1').collection('rooms').doc('room1').set({
        id: 'room1',
        name: 'General Chat',
      });
      await db.collection('communities').doc('comm1').collection('messages').doc('cmsg1').set({
        id: 'cmsg1',
        senderId: 'userA',
        text: 'Welcome to the community!',
      });

      // Posts & Comments
      await db.collection('posts').doc('post_bob_1').set({
        id: 'post_bob_1',
        userId: 'userB',
        caption: 'Bobs thought',
        likes: [],
        commentCount: 0,
        reactions: {},
      });
      await db.collection('posts').doc('post_bob_1').collection('comments').doc('c1').set({
        id: 'c1',
        userId: 'userB',
        text: 'First comment',
        likes: [],
      });

      // Stories
      await db.collection('stories').doc('story_bob_1').set({
        id: 'story_bob_1',
        userId: 'userB',
        caption: 'Bobs story',
        viewers: [],
      });

      // Boosts
      await db.collection('boosts').doc('boost_1').set({
        id: 'boost_1',
        ownerUserId: 'userA',
        status: 'active',
      });
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 1. USER DOCUMENT SECURITY & PRIVILEGE ESCALATION
  // ═════════════════════════════════════════════════════════════════════════════

  it('TEST 1 [DENIED]: User A cannot modify User B coins balance', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('users').doc('userB').update({ coins: 999999 }));
  });

  it('TEST 2 [DENIED]: Owner User B cannot self-grant coins via owner allowlist', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('users').doc('userB').update({ coins: 999999 }));
  });

  it('TEST 3 [DENIED]: Owner User B cannot self-grant verification status', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('users').doc('userB').update({ isVerified: true, verifiedBadge: 'S' }));
  });

  it('TEST 4 [DENIED]: Owner User B cannot self-grant subscription', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('users').doc('userB').update({ isSubscribed: true }));
  });

  it('TEST 5 [DENIED]: User A cannot read User B private settings subcollection', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('users').doc('userB').collection('private').doc('settings').get());
  });

  it('TEST 1.1 [DENIED]: User cannot self-grant coins or role during user creation', async () => {
    const newUserDb = testEnv.authenticatedContext('newUser1').firestore();
    await assertFails(newUserDb.collection('users').doc('newUser1').set({
      id: 'newUser1',
      name: 'Hacker',
      email: 'hacker@example.com',
      coins: 500,
      role: 'admin',
    }));
  });

  it('TEST 1.2 [DENIED]: User cannot self-grant isVerified: true during user creation', async () => {
    const newUserDb = testEnv.authenticatedContext('newUser2').firestore();
    await assertFails(newUserDb.collection('users').doc('newUser2').set({
      id: 'newUser2',
      name: 'Pretender',
      email: 'pretender@example.com',
      isVerified: true,
    }));
  });

  it('TEST 1.3 [DENIED]: User cannot inject unlockedUserPhones during user creation', async () => {
    const newUserDb = testEnv.authenticatedContext('newUser3').firestore();
    await assertFails(newUserDb.collection('users').doc('newUser3').set({
      id: 'newUser3',
      name: 'Snooper',
      email: 'snoop@example.com',
      unlockedUserPhones: ['userB'],
    }));
  });

  it('TEST 1.4 [DENIED]: Owner User B cannot modify unlockedUserPhones or unlockedVisitors on update', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('users').doc('userB').update({
      unlockedUserPhones: ['userA'],
      unlockedVisitors: ['userA'],
    }));
  });

  it('TEST 1.5 [DENIED]: Owner User B cannot modify dailyLoginStreak or conversationRewardsToday on update', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('users').doc('userB').update({
      dailyLoginStreak: 50,
      conversationRewardsToday: 10,
    }));
  });

  it('TEST 1.6 [DENIED]: Non-owner User C cannot remove existing users from Bob likedBy array', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    // Bob currently has likedBy: ['userA']. Charlie tries to replace with ['userC']
    await assertFails(charlieDb.collection('users').doc('userB').update({
      likedBy: ['userC'],
    }));
  });

  it('TEST 1.7 [DENIED]: Non-owner User C cannot inject third-party User D into Bob likedBy array', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    // Bob currently has likedBy: ['userA']. Charlie tries to append userD
    await assertFails(charlieDb.collection('users').doc('userB').update({
      likedBy: ['userA', 'userD'],
    }));
  });

  it('TEST 1.8 [PERMITTED]: New user can create legitimate profile with zeroed privileged defaults (PII excluded)', async () => {
    const freshDb = testEnv.authenticatedContext('userFresh').firestore();
    await assertSucceeds(freshDb.collection('users').doc('userFresh').set({
      id: 'userFresh',
      name: 'Fresh User',
      bio: 'Ready to connect',
      age: 22,
      gender: 'other',
      interests: ['coding'],
      photos: [],
      followers: [],
      following: [],
      likedBy: [],
      superLikedBy: [],
      matches: [],
      postCount: 0,
      isOnline: true,
      isVerified: false,
      isSubscribed: false,
      isSuspended: false,
      coins: 0,
      totalEarnedCoins: 0,
      claimedMilestones: [],
      role: 'user',
      unlockedUserPhones: [],
      unlockedVisitors: [],
      dailyLoginStreak: 0,
      conversationRewardsToday: 0,
    }));
  });

  it('TEST 1.9 [PERMITTED]: Bob can update his own bio, location, and isPhonePublic (PII excluded from public doc)', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertSucceeds(bobDb.collection('users').doc('userB').update({
      bio: 'Updated developer bio',
      location: 'Guwahati, Assam',
      isPhonePublic: true,
    }));
  });

  it('TEST 1.9b [DENIED]: Bob cannot update phoneNumber on public user document', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('users').doc('userB').update({
      phoneNumber: '+91 98765 43210',
    }));
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 2. CHAT & MESSAGE SECURITY
  // ═════════════════════════════════════════════════════════════════════════════

  it('TEST 6 [DENIED]: Non-participant User C cannot read Alice and Bob chat messages', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    await assertFails(charlieDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').get());
  });

  it('TEST 7 [DENIED]: Non-participant User C cannot send messages to Alice and Bob chat', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    await assertFails(charlieDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg_hacked').set({
      id: 'msg_hacked',
      senderId: 'userC',
      text: 'I hacked into your chat!',
      type: 'text',
      createdAt: Date.now(),
    }));
  });

  it('TEST 8 [DENIED]: User C cannot add themselves to Alice and Bob chat participants', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    await assertFails(charlieDb.collection('chats').doc('chat_alice_bob').update({
      participants: ['userA', 'userB', 'userC'],
    }));
  });

  it('TEST 9 [DENIED]: User C cannot create chat with Bob without mutual like/match', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    await assertFails(charlieDb.collection('chats').doc('chat_charlie_bob').set({
      id: 'chat_charlie_bob',
      participants: ['userC', 'userB'],
    }));
  });

  it('TEST 10 [DENIED]: User A cannot create self-chat with duplicate participants', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('chats').doc('chat_alice_alice').set({
      id: 'chat_alice_alice',
      participants: ['userA', 'userA'],
    }));
  });

  it('TEST 11 [DENIED]: User A cannot send message to userBlocked who blocked User A', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('chats').doc('chat_alice_blocked').set({
        id: 'chat_alice_blocked',
        participants: ['userA', 'userBlocked'],
      });
    });

    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('chats').doc('chat_alice_blocked').collection('messages').doc('m_block').set({
      id: 'm_block',
      senderId: 'userA',
      text: 'Are you ignoring me?',
      type: 'text',
    }));
  });

  it('TEST 12 [DENIED]: User A cannot modify senderId of an existing message', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').update({
      senderId: 'userB',
    }));
  });

  it('TEST 13 [DENIED]: User A cannot modify message type to system', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').update({
      type: 'system',
    }));
  });

  it('TEST 2.1 [DENIED]: Sender User A cannot mark their own message as read', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').update({
      isRead: true,
      readAt: Date.now(),
    }));
  });

  it('TEST 2.2 [DENIED]: Recipient User B cannot alter text of User A message', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').update({
      text: 'Altered by recipient Bob',
    }));
  });

  it('TEST 2.3 [PERMITTED]: Recipient Bob can mark Alice message as read', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertSucceeds(bobDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').update({
      isRead: true,
      readAt: Date.now(),
    }));
  });

  it('TEST 2.4 [PERMITTED]: Sender Alice can edit text of her own message', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').update({
      text: 'Hello Bob! (edited)',
    }));
  });

  it('TEST 2.5 [PERMITTED]: Sender Alice can delete her own message', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').delete());
  });

  it('TEST 2.6 [DENIED]: Blocked user cannot read existing chat', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('chats').doc('chat_blocked_test').set({
        id: 'chat_blocked_test',
        participants: ['userA', 'userBlocked'],
      });
    });
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('chats').doc('chat_blocked_test').get());
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 3. COMMUNITY SECURITY
  // ═════════════════════════════════════════════════════════════════════════════

  it('TEST 3.1 [DENIED]: Non-member User C cannot read community rooms', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    await assertFails(charlieDb.collection('communities').doc('comm1').collection('rooms').doc('room1').get());
  });

  it('TEST 3.2 [DENIED]: Non-member User C cannot read community messages', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    await assertFails(charlieDb.collection('communities').doc('comm1').collection('messages').doc('cmsg1').get());
  });

  it('TEST 3.3 [DENIED]: Non-member User C cannot post messages in community', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    await assertFails(charlieDb.collection('communities').doc('comm1').collection('messages').doc('cmsg_hack').set({
      id: 'cmsg_hack',
      senderId: 'userC',
      text: 'Spamming the community',
    }));
  });

  it('TEST 3.4 [DENIED]: Non-admin Bob cannot arbitrarily manipulate memberCount to 999999', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('communities').doc('comm1').update({
      memberCount: 999999,
    }));
  });

  it('TEST 3.5 [PERMITTED]: Member Bob can post a message in comm1', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertSucceeds(bobDb.collection('communities').doc('comm1').collection('messages').doc('cmsg_bob').set({
      id: 'cmsg_bob',
      senderId: 'userB',
      text: 'Hey everyone in Assam Vibes!',
    }));
  });

  it('TEST 3.6 [PERMITTED]: Member Bob can edit text of his own community message', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('communities').doc('comm1').collection('messages').doc('cmsg_bob').set({
        id: 'cmsg_bob',
        senderId: 'userB',
        text: 'Initial message',
      });
    });
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertSucceeds(bobDb.collection('communities').doc('comm1').collection('messages').doc('cmsg_bob').update({
      text: 'Edited message by Bob',
    }));
  });

  it('TEST 3.7 [DENIED]: Member Bob cannot edit Alice community message', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('communities').doc('comm1').collection('messages').doc('cmsg1').update({
      text: 'Tampered by Bob',
    }));
  });

  it('TEST 3.8 [PERMITTED]: Community admin Alice can delete community messages', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('communities').doc('comm1').collection('messages').doc('cmsg1').delete());
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 4. POSTS, STORIES & NOTIFICATIONS SECURITY
  // ═════════════════════════════════════════════════════════════════════════════

  it('TEST 14 [DENIED]: User A cannot delete User B posts', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('posts').doc('post_bob_1').delete());
  });

  it('TEST 19 [DENIED]: Suspended user cannot create posts', async () => {
    const suspendedDb = testEnv.authenticatedContext('userSuspended').firestore();
    await assertFails(suspendedDb.collection('posts').doc('post_suspended').set({
      id: 'post_suspended',
      userId: 'userSuspended',
      caption: 'Trying to post while suspended',
    }));
  });

  it('TEST 4.1 [DENIED]: User A cannot arbitrarily jump commentCount by 50 on Bob post', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('posts').doc('post_bob_1').update({
      commentCount: 50,
    }));
  });

  it('TEST 4.2 [PERMITTED]: User A can increment commentCount by 1 when commenting', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('posts').doc('post_bob_1').update({
      commentCount: 1,
    }));
  });

  it('TEST 4.3 [PERMITTED]: User A can like Bob post (append own UID to likes)', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('posts').doc('post_bob_1').update({
      likes: ['userA'],
    }));
  });

  it('TEST 4.4 [DENIED]: User A cannot edit Bob comment text', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('posts').doc('post_bob_1').collection('comments').doc('c1').update({
      text: 'Tampered comment text',
    }));
  });

  it('TEST 4.5 [PERMITTED]: Bob can edit text of his own comment', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertSucceeds(bobDb.collection('posts').doc('post_bob_1').collection('comments').doc('c1').update({
      text: 'Bob revised comment',
    }));
  });

  it('TEST 4.6 [DENIED]: Viewer User C cannot inject third-party User A into story viewers', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    await assertFails(charlieDb.collection('stories').doc('story_bob_1').update({
      viewers: ['userA', 'userC'],
    }));
  });

  it('TEST 4.7 [PERMITTED]: Viewer Charlie can append self to story viewers', async () => {
    const charlieDb = testEnv.authenticatedContext('userC').firestore();
    await assertSucceeds(charlieDb.collection('stories').doc('story_bob_1').update({
      viewers: ['userC'],
    }));
  });

  it('TEST 4.8 [DENIED]: User A cannot forge type: system notification for User B', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('notifications').doc('notif_fake_sys').set({
      id: 'notif_fake_sys',
      userId: 'userB',
      senderId: 'userA',
      type: 'system',
      title: 'Fake System Warning',
      body: 'Your account is banned.',
    }));
  });

  it('TEST 4.9 [DENIED]: User A cannot forge type: match notification for User B', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('notifications').doc('notif_fake_match').set({
      id: 'notif_fake_match',
      userId: 'userB',
      senderId: 'userA',
      type: 'match',
      title: "It's a Match!",
      body: 'You and Alice matched!',
    }));
  });

  it('TEST 4.10 [PERMITTED]: User A can send legitimate like notification to Bob', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('notifications').doc('notif_like_1').set({
      id: 'notif_like_1',
      userId: 'userB',
      senderId: 'userA',
      senderName: 'Alice',
      type: 'like',
      title: 'Alice liked your profile!',
      body: 'Check them out on Situationship.',
      createdAt: Date.now(),
      isRead: false,
    }));
  });

  it('TEST 4.11 [PERMITTED]: Recipient Bob can mark notification as read', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('notifications').doc('notif_read_test').set({
        id: 'notif_read_test',
        userId: 'userB',
        senderId: 'userA',
        isRead: false,
      });
    });
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertSucceeds(bobDb.collection('notifications').doc('notif_read_test').update({
      isRead: true,
    }));
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 5. BOOSTS, REWARDS & PROFILE VIEWS SECURITY
  // ═════════════════════════════════════════════════════════════════════════════

  it('TEST 17 [DENIED]: User A cannot self-award coins in coin_rewards', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('coin_rewards').doc('userA_reward_fake').set({
      userId: 'userA',
      amount: 10000,
      at: new Date(),
    }));
  });

  it('TEST 18 [DENIED]: User A cannot overwrite Spotlight session or place client bids', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('spotlight_sessions').doc('session_active').set({
      prizePool: 999999,
      currentWinnerId: 'userA',
    }));
    await assertFails(aliceDb.collection('spotlight_sessions').doc('session_active').collection('bids').doc('userA').set({
      amount: 100,
    }));
  });

  it('TEST 5.1 [DENIED]: Client User A cannot create paid boost in boosts collection', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('boosts').doc('boost_fake').set({
      id: 'boost_fake',
      ownerUserId: 'userA',
      status: 'active',
    }));
  });

  it('TEST 5.2 [DENIED]: User A cannot forge boost analytics event with mismatched userId', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('boosts').doc('boost_1').collection('boost_analytics').doc('evt_fake').set({
      id: 'evt_fake',
      userId: 'userB',
      boostId: 'boost_1',
    }));
  });

  it('TEST 5.3 [PERMITTED]: User A can log own boost view analytics event', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('boosts').doc('boost_1').collection('boost_analytics').doc('evt_valid').set({
      id: 'evt_valid',
      userId: 'userA',
      boostId: 'boost_1',
      type: 'impression',
      timestamp: Date.now(),
    }));
  });

  it('TEST 5.4 [DENIED]: User B cannot claim milestone with injected giftCode or approved status', async () => {
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('coin_milestones').doc('userB_spark').set({
      userId: 'userB',
      milestoneId: 'spark',
      status: 'approved',
      giftCode: 'FREE-MONEY-CODE',
    }));
  });

  it('TEST 5.5 [DENIED]: User B cannot claim milestone if totalEarnedCoins < threshold', async () => {
    // Bob has totalEarnedCoins: 200, Spark requires 500
    const bobDb = testEnv.authenticatedContext('userB').firestore();
    await assertFails(bobDb.collection('coin_milestones').doc('userB_spark').set({
      userId: 'userB',
      milestoneId: 'spark',
      milestoneName: 'Spark',
      giftCardValueInr: 50,
      status: 'pending',
      giftCode: null,
    }));
  });

  it('TEST 5.6 [PERMITTED]: Alice can claim earned milestone Spark (totalEarnedCoins: 600 >= 500)', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('coin_milestones').doc('userA_spark').set({
      userId: 'userA',
      milestoneId: 'spark',
      milestoneName: 'Spark',
      giftCardValueInr: 50,
      status: 'pending',
      giftCode: null,
    }));
  });

  it('TEST 5.7 [DENIED]: User A cannot forge profile view record of themselves', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('profile_views').doc('userA_userA').set({
      id: 'userA_userA',
      viewerId: 'userA',
      targetId: 'userA',
    }));
  });

  it('TEST 5.8 [DENIED]: Client cannot update existing profile view record (immutable)', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('profile_views').doc('userA_userB').set({
        id: 'userA_userB',
        viewerId: 'userA',
        targetId: 'userB',
        viewedAt: Date.now(),
      });
    });
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertFails(aliceDb.collection('profile_views').doc('userA_userB').update({
      viewedAt: 0,
    }));
  });

  it('TEST 5.9 [PERMITTED]: User A can create valid profile view of User B', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('profile_views').doc('userA_userB').set({
      id: 'userA_userB',
      viewerId: 'userA',
      viewerName: 'Alice',
      targetId: 'userB',
      viewedAt: Date.now(),
    }));
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 6. FIREBASE STORAGE SECURITY
  // ═════════════════════════════════════════════════════════════════════════════

  it('TEST 15 [DENIED]: User A cannot overwrite User B avatar file in Storage', async () => {
    const aliceStorage = testEnv.authenticatedContext('userA').storage();
    await assertFails(aliceStorage.ref('avatars/userB_photo_1.jpg').putString('fake', 'raw', { contentType: 'image/jpeg' }));
  });

  it('TEST 16 [DENIED]: Intruder User C cannot read private chat attachments in Storage', async () => {
    const charlieStorage = testEnv.authenticatedContext('userC').storage();
    await assertFails(charlieStorage.ref('chats/chat_alice_bob/img_secret.jpg').getDownloadURL());
  });

  it('TEST 6.1 [PERMITTED]: User A can upload own avatar with matching UID prefix', async () => {
    const aliceStorage = testEnv.authenticatedContext('userA').storage();
    await assertSucceeds(aliceStorage.ref('avatars/userA_photo_profile.jpg').putString('avatar_bytes', 'raw', { contentType: 'image/jpeg' }));
  });

  it('TEST 6.2 [DENIED]: User A cannot upload non-image as avatar (e.g. text/plain)', async () => {
    const aliceStorage = testEnv.authenticatedContext('userA').storage();
    await assertFails(aliceStorage.ref('avatars/userA_script.sh').putString('#!/bin/bash', 'raw', { contentType: 'text/plain' }));
  });

  it('TEST 6.3 [PERMITTED]: Participant User A can upload chat attachment in chat_alice_bob', async () => {
    const aliceStorage = testEnv.authenticatedContext('userA').storage();
    await assertSucceeds(aliceStorage.ref('chats/chat_alice_bob/img_photo.jpg').putString('photo_bytes', 'raw', { contentType: 'image/jpeg' }));
  });

  it('TEST 6.4 [PERMITTED]: Participant User B can read chat attachment in chat_alice_bob', async () => {
    // Seed attachment via admin
    const aliceStorage = testEnv.authenticatedContext('userA').storage();
    await aliceStorage.ref('chats/chat_alice_bob/img_photo2.jpg').putString('photo_bytes', 'raw', { contentType: 'image/jpeg' });

    const bobStorage = testEnv.authenticatedContext('userB').storage();
    await assertSucceeds(bobStorage.ref('chats/chat_alice_bob/img_photo2.jpg').getDownloadURL());
  });

  it('TEST 6.5 [DENIED]: Blocked user cannot read chat attachments in Storage', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('chats').doc('chat_alice_blocked').set({
        id: 'chat_alice_blocked',
        participants: ['userA', 'userBlocked'],
        status: 'blocked',
        blockedUsers: ['userA'],
      });
    });
    const aliceStorage = testEnv.authenticatedContext('userA').storage();
    await assertFails(aliceStorage.ref('chats/chat_alice_blocked/img_secret.jpg').getDownloadURL());
  });

  it('TEST 6.6 [PERMITTED]: User A can upload and delete own media in UID-based posts path', async () => {
    const aliceStorage = testEnv.authenticatedContext('userA').storage();
    await assertSucceeds(aliceStorage.ref('posts/userA/post1.jpg').putString('bytes', 'raw', { contentType: 'image/jpeg' }));
    await assertSucceeds(aliceStorage.ref('posts/userA/post1.jpg').delete());
  });

  it('TEST 6.7 [DENIED]: User A cannot delete User B media in UID-based posts path', async () => {
    // Bob uploads his post photo
    const bobStorage = testEnv.authenticatedContext('userB').storage();
    await bobStorage.ref('posts/userB/post_bob.jpg').putString('bob_bytes', 'raw', { contentType: 'image/jpeg' });

    // Alice attempts to delete Bob's post photo
    const aliceStorage = testEnv.authenticatedContext('userA').storage();
    await assertFails(aliceStorage.ref('posts/userB/post_bob.jpg').delete());
  });

  it('TEST 6.8 [DENIED]: Non-member User C cannot upload media to comm1 in Storage', async () => {
    const charlieStorage = testEnv.authenticatedContext('userC').storage();
    await assertFails(charlieStorage.ref('communities/comm1/cover.jpg').putString('bytes', 'raw', { contentType: 'image/jpeg' }));
  });

  it('TEST 6.9 [DENIED]: Non-owner User A cannot read User B private verification video', async () => {
    const bobStorage = testEnv.authenticatedContext('userB').storage();
    await bobStorage.ref('verifications/userB/video.webm').putString('video_bytes', 'raw', { contentType: 'video/webm' });

    const aliceStorage = testEnv.authenticatedContext('userA').storage();
    await assertFails(aliceStorage.ref('verifications/userB/video.webm').getDownloadURL());
  });

  it('TEST 6.10 [PERMITTED]: User B can upload and read own private verification video', async () => {
    const bobStorage = testEnv.authenticatedContext('userB').storage();
    await assertSucceeds(bobStorage.ref('verifications/userB/video_pass.webm').putString('video_bytes', 'raw', { contentType: 'video/webm' }));
    await assertSucceeds(bobStorage.ref('verifications/userB/video_pass.webm').getDownloadURL());
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 7. BASELINE LEGITIMATE OPERATIONS
  // ═════════════════════════════════════════════════════════════════════════════

  it('LEGITIMATE 1 [PERMITTED]: Alice can update her own bio and interests', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('users').doc('userA').update({
      bio: 'New verified bio',
      interests: ['music', 'travel'],
    }));
  });

  it('LEGITIMATE 2 [PERMITTED]: Alice can swipe right and like Bob (append self to likedBy)', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('users').doc('userB').update({
      likedBy: ['userA'],
      followers: ['userA'],
    }));
  });

  it('LEGITIMATE 3 [PERMITTED]: Alice and Bob can chat in their mutual chat', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg_valid').set({
      id: 'msg_valid',
      senderId: 'userA',
      text: 'Hey Bob, how are you?',
      createdAt: Date.now(),
      type: 'text',
    }));
  });

  it('LEGITIMATE 4 [PERMITTED]: Alice can create chat with Bob because Bob already liked Alice', async () => {
    const aliceDb = testEnv.authenticatedContext('userA').firestore();
    await assertSucceeds(aliceDb.collection('chats').doc('chat_alice_bob_2').set({
      id: 'chat_alice_bob_2',
      participants: ['userA', 'userB'],
    }));
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 8. PHASE 4B: ADDITIONAL SECURITY GAPS REMEDIATION TESTS
  // ═════════════════════════════════════════════════════════════════════════════

  describe('Phase 4B Specific Security Assertions', () => {

    it('TEST 4B.1 [DENIED]: Storage upload via old flat /posts/{fileName} is denied', async () => {
      const aliceStorage = testEnv.authenticatedContext('userA').storage();
      await assertFails(aliceStorage.ref('posts/flat_post_123.jpg').putString('data', 'raw', { contentType: 'image/jpeg' }));
    });

    it('TEST 4B.2 [DENIED]: Storage upload via old flat /stories/{fileName} is denied', async () => {
      const aliceStorage = testEnv.authenticatedContext('userA').storage();
      await assertFails(aliceStorage.ref('stories/flat_story_123.jpg').putString('data', 'raw', { contentType: 'image/jpeg' }));
    });

    it('TEST 4B.3 [DENIED]: Storage upload via old flat /voice_notes/{fileName} is denied', async () => {
      const aliceStorage = testEnv.authenticatedContext('userA').storage();
      await assertFails(aliceStorage.ref('voice_notes/flat_voice_123.m4a').putString('data', 'raw', { contentType: 'audio/mp4' }));
    });

    it('TEST 4B.4 [DENIED]: Storage upload via old flat /communities/{fileName} is denied', async () => {
      const aliceStorage = testEnv.authenticatedContext('userA').storage();
      await assertFails(aliceStorage.ref('communities/flat_comm_123.jpg').putString('data', 'raw', { contentType: 'image/jpeg' }));
    });

    it('TEST 4B.5 [DENIED]: User cannot upload to another user UID-based posts path', async () => {
      const aliceStorage = testEnv.authenticatedContext('userA').storage();
      await assertFails(aliceStorage.ref('posts/userB/malicious_post.jpg').putString('data', 'raw', { contentType: 'image/jpeg' }));
    });

    it('TEST 4B.6 [DENIED]: User cannot upload to another user UID-based stories path', async () => {
      const aliceStorage = testEnv.authenticatedContext('userA').storage();
      await assertFails(aliceStorage.ref('stories/userB/malicious_story.jpg').putString('data', 'raw', { contentType: 'image/jpeg' }));
    });

    it('TEST 4B.7 [DENIED]: User cannot upload to another user UID-based voice_notes path', async () => {
      const aliceStorage = testEnv.authenticatedContext('userA').storage();
      await assertFails(aliceStorage.ref('voice_notes/userB/malicious_voice.m4a').putString('data', 'raw', { contentType: 'audio/mp4' }));
    });

    it('TEST 4B.8 [DENIED]: Non-member cannot upload cover or media to community', async () => {
      const charlieStorage = testEnv.authenticatedContext('userC').storage();
      await assertFails(charlieStorage.ref('communities/comm1/cover.jpg').putString('data', 'raw', { contentType: 'image/jpeg' }));
    });

    it('TEST 4B.9 [DENIED]: User cannot self-grant community membership by editing memberAvatars without count or rules', async () => {
      const charlieDb = testEnv.authenticatedContext('userC').firestore();
      // Charlie tries to add himself to memberAvatars without updating memberCount properly or altering other fields
      await assertFails(charlieDb.collection('communities').doc('comm1').update({
        memberAvatars: ['userA', 'userB', 'userC'],
      }));
    });

    it('TEST 4B.10 [DENIED]: User cannot self-grant community admin rights or alter adminId', async () => {
      const charlieDb = testEnv.authenticatedContext('userC').firestore();
      await assertFails(charlieDb.collection('communities').doc('comm1').update({
        adminId: 'userC',
      }));
    });

    it('TEST 4B.11 [DENIED]: Blocked user cannot read target user profile document', async () => {
      // userBlocked has blocked userA. userA cannot read userBlocked
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userBlocked').get());
    });

    it('TEST 4B.12 [DENIED]: Non-owner cannot read private settings/documents in users/{userId}/private/{doc}', async () => {
      // Seed private doc for userB
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('userB').collection('private').doc('settings').set({
          stripeCustomerId: 'cus_12345',
          secretToken: 'secret_abc',
        });
      });

      // Charlie attempts to read userB private document
      const charlieDb = testEnv.authenticatedContext('userC').firestore();
      await assertFails(charlieDb.collection('users').doc('userB').collection('private').doc('settings').get());
    });

    it('TEST 4B.13 [PERMITTED]: Owner can read own private document in users/{userId}/private/{doc}', async () => {
      const bobDb = testEnv.authenticatedContext('userB').firestore();
      await assertSucceeds(bobDb.collection('users').doc('userB').collection('private').doc('settings').get());
    });

    it('TEST 4B.14 [DENIED]: Arbitrary commentCount increment (e.g. +5) on post is rejected', async () => {
      const charlieDb = testEnv.authenticatedContext('userC').firestore();
      await assertFails(charlieDb.collection('posts').doc('post_bob_1').update({
        commentCount: 5,
      }));
    });

    it('TEST 4B.15 [PERMITTED]: Legitimate commentCount increment (+1) on post is permitted', async () => {
      const charlieDb = testEnv.authenticatedContext('userC').firestore();
      await assertSucceeds(charlieDb.collection('posts').doc('post_bob_1').update({
        commentCount: 1,
      }));
    });

    it('TEST 4B.16 [DENIED]: Message reaction update spoofing another user identity is rejected', async () => {
      // Bob (recipient) attempts to add reaction on behalf of userC
      const bobDb = testEnv.authenticatedContext('userB').firestore();
      await assertFails(bobDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').update({
        reactions: { userC: '❤️' },
      }));
    });

    it('TEST 4B.17 [PERMITTED]: Message reaction update with caller own UID is permitted', async () => {
      const bobDb = testEnv.authenticatedContext('userB').firestore();
      await assertSucceeds(bobDb.collection('chats').doc('chat_alice_bob').collection('messages').doc('msg1').update({
        reactions: { userB: '❤️' },
      }));
    });

    it('TEST 4B.18 [DENIED]: Client cannot grant itself purchased coins or alter coin balances', async () => {
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userA').update({
        coins: 5000,
      }));
    });

    it('TEST 4B.19 [DENIED]: Client cannot self-activate subscription or alter subscriptionExpiry', async () => {
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userA').update({
        isSubscribed: true,
        subscriptionExpiry: Date.now() + 10000000,
      }));
    });

    it('TEST 4B.20 [DENIED]: Ineligible user claiming milestone reward without required totalEarnedCoins is rejected', async () => {
      // Charlie has 0 totalEarnedCoins, attempts to claim spark milestone (needs 500)
      const charlieDb = testEnv.authenticatedContext('userC').firestore();
      await assertFails(charlieDb.collection('coin_milestones').doc('claim_charlie_spark').set({
        userId: 'userC',
        milestoneId: 'spark',
        milestoneName: 'Spark Level',
        giftCardValueInr: 100,
        status: 'pending',
        createdAt: Date.now(),
      }));
    });

    it('TEST 4B.21 [PERMITTED]: Eligible user claiming milestone with sufficient totalEarnedCoins succeeds', async () => {
      // Alice has 600 totalEarnedCoins, eligible for spark (500)
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertSucceeds(aliceDb.collection('coin_milestones').doc('claim_alice_spark').set({
        userId: 'userA',
        milestoneId: 'spark',
        milestoneName: 'Spark Level',
        giftCardValueInr: 100,
        status: 'pending',
        createdAt: Date.now(),
      }));
    });

    it('TEST 4B.22 [DENIED]: Blocked user cannot access chat attachments in Storage', async () => {
      // Seed blocked chat
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('chats').doc('chat_blocked_4b').set({
          id: 'chat_blocked_4b',
          participants: ['userA', 'userBlocked'],
          status: 'blocked',
        });
      });

      const aliceStorage = testEnv.authenticatedContext('userA').storage();
      await assertFails(aliceStorage.ref('chats/chat_blocked_4b/photo.jpg').putString('data', 'raw', { contentType: 'image/jpeg' }));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 9. PHASE 5: USER PRIVACY & PII REMEDIATION ASSERTIONS
  // ═════════════════════════════════════════════════════════════════════════════

  describe('Phase 5: User Privacy & PII Remediation Assertions', () => {

    it('TEST 5.P1 [DENIED]: Another user cannot read private profile documents', async () => {
      // Alice attempts to read Bob's private profile document
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userB').collection('private').doc('profile').get());
    });

    it('TEST 5.P2 [DENIED]: Another user cannot write to Bob private profile document', async () => {
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userB').collection('private').doc('profile').set({
        email: 'alice_tamper@example.com',
        phoneNumber: '+19999999999',
      }));
    });

    it('TEST 5.P3 [PERMITTED]: Account owner can read and write own private profile document', async () => {
      const bobDb = testEnv.authenticatedContext('userB').firestore();
      await assertSucceeds(bobDb.collection('users').doc('userB').collection('private').doc('profile').set({
        email: 'bob_private@example.com',
        phoneNumber: '+91 98765 43210',
        updatedAt: Date.now(),
      }));
      await assertSucceeds(bobDb.collection('users').doc('userB').collection('private').doc('profile').get());
    });

    it('TEST 5.P4 [DENIED]: User cannot create public profile containing email', async () => {
      const hackerDb = testEnv.authenticatedContext('userEmailHacker').firestore();
      await assertFails(hackerDb.collection('users').doc('userEmailHacker').set({
        id: 'userEmailHacker',
        name: 'Email Hacker',
        email: 'hacker@example.com',
        bio: 'Bio',
        age: 25,
        gender: 'other',
        isVerified: false,
        isSubscribed: false,
        isSuspended: false,
        coins: 0,
        totalEarnedCoins: 0,
        claimedMilestones: [],
        role: 'user',
        unlockedUserPhones: [],
        unlockedVisitors: [],
        dailyLoginStreak: 0,
        conversationRewardsToday: 0,
        phoneUnlocksUsed: 0,
        phoneUnlockQuota: 0,
      }));
    });

    it('TEST 5.P5 [DENIED]: User cannot create public profile containing phoneNumber', async () => {
      const hackerDb = testEnv.authenticatedContext('userPhoneHacker').firestore();
      await assertFails(hackerDb.collection('users').doc('userPhoneHacker').set({
        id: 'userPhoneHacker',
        name: 'Phone Hacker',
        phoneNumber: '+91 99999 88888',
        bio: 'Bio',
        age: 25,
        gender: 'other',
        isVerified: false,
        isSubscribed: false,
        isSuspended: false,
        coins: 0,
        totalEarnedCoins: 0,
        claimedMilestones: [],
        role: 'user',
        unlockedUserPhones: [],
        unlockedVisitors: [],
        dailyLoginStreak: 0,
        conversationRewardsToday: 0,
        phoneUnlocksUsed: 0,
        phoneUnlockQuota: 0,
      }));
    });

    it('TEST 5.P6 [DENIED]: User cannot update public profile with phoneNumber', async () => {
      const bobDb = testEnv.authenticatedContext('userB').firestore();
      await assertFails(bobDb.collection('users').doc('userB').update({
        phoneNumber: '+91 88888 77777',
      }));
    });

    it('TEST 5.P7 [DENIED]: User cannot modify their own unlockedUserPhones array directly', async () => {
      const bobDb = testEnv.authenticatedContext('userB').firestore();
      await assertFails(bobDb.collection('users').doc('userB').update({
        unlockedUserPhones: ['target_unlocked_fake'],
      }));
    });

    it('TEST 5.P8 [DENIED]: User cannot modify their own phoneUnlocksUsed directly', async () => {
      const bobDb = testEnv.authenticatedContext('userB').firestore();
      await assertFails(bobDb.collection('users').doc('userB').update({
        phoneUnlocksUsed: 1,
      }));
    });

    it('TEST 5.P9 [DENIED]: User cannot modify their own coin balance directly', async () => {
      const bobDb = testEnv.authenticatedContext('userB').firestore();
      await assertFails(bobDb.collection('users').doc('userB').update({
        coins: 9999,
      }));
    });

    it('TEST 5.P10 [PERMITTED]: Authorized viewer can read unlocked contact document in unlocked_contacts', async () => {
      // Seed authorized unlock document written by backend/admin
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('userB').update({
          isPhonePublic: true,
          phoneVisibilityVersion: 1,
        });
        await context.firestore().collection('users').doc('userB').collection('unlocked_contacts').doc('userA').set({
          phoneNumber: '+91 98765 43210',
          viewerId: 'userA',
          targetId: 'userB',
          phoneVisibilityVersion: 1,
          unlockedAt: Date.now(),
        });
      });

      // Alice (authorized viewer) reads the unlocked contact document
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertSucceeds(aliceDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userA').get());
    });

    it('TEST 5.P11 [DENIED]: Unauthorized viewer cannot read another users unlocked contact document', async () => {
      // Charlie (unauthorized) attempts to read Alice's unlocked contact for Bob
      const charlieDb = testEnv.authenticatedContext('userC').firestore();
      await assertFails(charlieDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userA').get());
    });

    it('TEST 5.P12 [DENIED]: Client cannot write or forge own unlocked contact document directly', async () => {
      // Charlie tries to write an unlock record for himself under Bob's profile
      const charlieDb = testEnv.authenticatedContext('userC').firestore();
      await assertFails(charlieDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userC').set({
        phoneNumber: '+91 98765 43210',
        viewerId: 'userC',
        targetId: 'userB',
      }));
    });

    it('TEST 5.P13 [DENIED]: Blocked user cannot read target user profile document', async () => {
      // userBlocked blocked userA. userA cannot read userBlocked profile
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userBlocked').get());
    });

    it('TEST 5.P14 [DENIED]: Blocked viewer cannot read unlocked contact (viewer blocked target)', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('userB').update({
          isPhonePublic: true,
          phoneVisibilityVersion: 1,
        });
        await context.firestore().collection('users').doc('userA').update({
          blockedUsers: ['userB'],
        });
        await context.firestore().collection('users').doc('userB').collection('unlocked_contacts').doc('userA').set({
          phoneNumber: '+91 98765 43210',
          viewerId: 'userA',
          targetId: 'userB',
          phoneVisibilityVersion: 1,
          unlockedAt: Date.now(),
        });
      });

      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userA').get());
    });

    it('TEST 5.P15 [DENIED]: Blocked viewer cannot read unlocked contact (target blocked viewer)', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('userB').update({
          isPhonePublic: true,
          phoneVisibilityVersion: 1,
          blockedUsers: ['userA'],
        });
        await context.firestore().collection('users').doc('userB').collection('unlocked_contacts').doc('userA').set({
          phoneNumber: '+91 98765 43210',
          viewerId: 'userA',
          targetId: 'userB',
          phoneVisibilityVersion: 1,
          unlockedAt: Date.now(),
        });
      });

      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userA').get());
    });

    it('TEST 5.P16 [DENIED]: Viewer cannot read contact after target disables phone visibility (isPhonePublic = false)', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('userB').update({
          isPhonePublic: false,
          phoneVisibilityVersion: 1,
        });
        await context.firestore().collection('users').doc('userB').collection('unlocked_contacts').doc('userA').set({
          phoneNumber: '+91 98765 43210',
          viewerId: 'userA',
          targetId: 'userB',
          phoneVisibilityVersion: 1,
          unlockedAt: Date.now(),
        });
      });

      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userA').get());
    });

    it('TEST 5.P17 [DENIED]: Stale phoneVisibilityVersion cannot authorize contact read', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('userB').update({
          isPhonePublic: true,
          phoneVisibilityVersion: 2, // Version bumped to 2
        });
        await context.firestore().collection('users').doc('userB').collection('unlocked_contacts').doc('userA').set({
          phoneNumber: '+91 98765 43210',
          viewerId: 'userA',
          targetId: 'userB',
          phoneVisibilityVersion: 1, // Stored record has stale version 1
          unlockedAt: Date.now(),
        });
      });

      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userA').get());
    });

    it('TEST 5.P18 [DENIED]: Unauthorized user cannot create an unlocked contact record', async () => {
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userA').set({
        phoneNumber: '+91 98765 43210',
        viewerId: 'userA',
        targetId: 'userB',
        phoneVisibilityVersion: 1,
        unlockedAt: Date.now(),
      }));
    });

    it('TEST 5.P19 [DENIED]: Unauthorized user cannot update an unlocked contact record', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('userB').collection('unlocked_contacts').doc('userA').set({
          phoneNumber: '+91 98765 43210',
          viewerId: 'userA',
          targetId: 'userB',
          phoneVisibilityVersion: 1,
          unlockedAt: Date.now(),
        });
      });

      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertFails(aliceDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userA').update({
        phoneNumber: '+91 11111 22222',
      }));
    });

    it('TEST 5.P20 [PERMITTED]: Target owner can read their own unlocked contacts list', async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection('users').doc('userB').collection('unlocked_contacts').doc('userA').set({
          phoneNumber: '+91 98765 43210',
          viewerId: 'userA',
          targetId: 'userB',
          phoneVisibilityVersion: 1,
          unlockedAt: Date.now(),
        });
      });

      const bobDb = testEnv.authenticatedContext('userB').firestore();
      await assertSucceeds(bobDb.collection('users').doc('userB').collection('unlocked_contacts').doc('userA').get());
    });

    it('TEST 5.P21 [PERMITTED]: Account owner can read and update their own private/profile', async () => {
      const aliceDb = testEnv.authenticatedContext('userA').firestore();
      await assertSucceeds(aliceDb.collection('users').doc('userA').collection('private').doc('profile').set({
        email: 'alice@test.com',
        phoneNumber: '+91 98765 43210',
      }, { merge: true }));

      await assertSucceeds(aliceDb.collection('users').doc('userA').collection('private').doc('profile').get());
    });
  });
});
