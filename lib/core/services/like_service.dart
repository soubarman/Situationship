import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/app_state_provider.dart';
import '../providers/firestore_provider.dart';

class MatchResult {
  final bool isMatch;
  final bool isSuperMatch;
  final UserModel user;
  final String chatId;
  final String? note;

  const MatchResult({
    required this.isMatch,
    required this.isSuperMatch,
    required this.user,
    required this.chatId,
    this.note,
  });
}

class LikeService {
  static final FirebaseFirestore _db = firestoreProvider;

  /// Returns a canonical, deterministic chat ID for any pair of user IDs.
  /// This ensures both users always connect to the exact same chat room.
  static String getCanonicalChatId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return 'chat_${sorted[0]}_${sorted[1]}';
  }

  /// Resolves an existing chat document if one already exists under either ID order,
  /// otherwise returns the deterministic canonical chat ID.
  static Future<String> resolveChatId(String uid1, String uid2) async {
    try {
      final id1 = 'chat_${uid1}_${uid2}';
      final doc1 = await _db.collection('chats').doc(id1).get();
      if (doc1.exists) return id1;

      final id2 = 'chat_${uid2}_${uid1}';
      final doc2 = await _db.collection('chats').doc(id2).get();
      if (doc2.exists) return id2;
    } catch (_) {}
    return getCanonicalChatId(uid1, uid2);
  }

  /// Checks if current user has already liked target user.
  static bool hasLiked(UserModel currentUser, String targetUserId) {
    return currentUser.following.contains(targetUserId);
  }

  /// Checks if current user has super-liked target user.
  static bool hasSuperLiked(UserModel currentUser, UserModel targetUser) {
    return targetUser.superLikedBy.contains(currentUser.id);
  }

  /// Checks if target user has liked current user.
  static bool hasLikedMe(UserModel currentUser, String targetUserId) {
    return currentUser.likedBy.contains(targetUserId);
  }

  /// Checks if target user has super-liked current user.
  static bool hasSuperLikedMe(UserModel currentUser, String targetUserId) {
    return currentUser.superLikedBy.contains(targetUserId);
  }

  /// Sends a regular like to [targetUser].
  /// If [targetUser] already liked [currentUser], this immediately becomes a MATCH!
  static Future<MatchResult> sendLike({
    WidgetRef? ref,
    required UserModel currentUser,
    required UserModel targetUser,
  }) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final currentUserId = authUid ?? (currentUser.id.isNotEmpty ? currentUser.id : '');
    if (currentUserId.isEmpty) {
      throw Exception('Authentication required to send like.');
    }
    if (targetUser.id.isEmpty) {
      throw Exception('Target profile ID is missing.');
    }

    final chatId = await resolveChatId(currentUserId, targetUser.id);

    // Mutual check: Has targetUser liked currentUser previously?
    final bool isMutual = targetUser.following.contains(currentUserId) ||
        targetUser.likedBy.contains(currentUserId) ||
        currentUser.likedBy.contains(targetUser.id);

    final batch = _db.batch();
    final targetRef = _db.collection('users').doc(targetUser.id);
    final currentRef = _db.collection('users').doc(currentUserId);
    final chatRef = _db.collection('chats').doc(chatId);

    // 1. Update targetUser: add current user to followers and likedBy (if doc exists)
    final targetDoc = await targetRef.get();
    if (targetDoc.exists) {
      batch.update(targetRef, {
        'followers': FieldValue.arrayUnion([currentUserId]),
        'likedBy': FieldValue.arrayUnion([currentUserId]),
      });
    }

    // 2. Update currentUser: add target to following, remove from disliked
    final currentDoc = await currentRef.get();
    if (currentDoc.exists) {
      batch.update(currentRef, {
        'following': FieldValue.arrayUnion([targetUser.id]),
        'dislikedUsers': FieldValue.arrayRemove([targetUser.id]),
      });
    } else {
      batch.set(currentRef, {
        'id': currentUserId,
        'following': [targetUser.id],
        'dislikedUsers': [],
      }, SetOptions(merge: true));
    }

    // 3. If mutual match -> activate chat immediately!
    if (isMutual) {
      batch.set(chatRef, {
        'id': chatId,
        'participants': [currentUserId, targetUser.id],
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'senderId': currentUserId,
        'senderName': currentUser.name,
        'senderAvatar': currentUser.avatarUrl,
        'receiverId': targetUser.id,
        'receiverName': targetUser.name,
        'receiverAvatar': targetUser.avatarUrl,
        'lastMessage': "🎉 It's a Match! Say hello!",
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': 0,
        'isExpired': false,
        'isConfession': false,
      }, SetOptions(merge: true));

      final msgRef = chatRef.collection('messages').doc();
      batch.set(msgRef, {
        'id': msgRef.id,
        'senderId': currentUserId,
        'text': "🎉 You and ${targetUser.name} matched! Say hello to each other!",
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isRead': false,
        'type': 'system',
      });
    }

    await batch.commit();

    // 4. Update local caches immediately
    if (ref != null) {
      ref.read(likedUsersCacheProvider.notifier).update((m) => {...m, targetUser.id: targetUser});
      ref.read(sessionLikedUserIdsProvider.notifier).update(
            (list) => [targetUser.id, ...list.where((id) => id != targetUser.id)],
          );
    }

    // 5. Send notifications
    try {
      if (isMutual) {
        await sendNotification(
          userId: targetUser.id,
          senderId: currentUserId,
          senderName: currentUser.name,
          senderAvatar: currentUser.avatarUrl,
          type: 'match',
          title: "It's a match! 🎉",
          body: 'You and ${currentUser.name} matched! Start chatting now.',
        );
      } else {
        await sendNotification(
          userId: targetUser.id,
          senderId: currentUserId,
          senderName: currentUser.name,
          senderAvatar: currentUser.avatarUrl,
          type: 'like',
          title: '${currentUser.name} liked you! 💖',
          body: 'Check them out on Situationship!',
        );
      }
    } catch (e) {
      debugPrint('[LikeService] notification error: $e');
    }

    return MatchResult(
      isMatch: isMutual,
      isSuperMatch: false,
      user: targetUser,
      chatId: chatId,
    );
  }

  /// Sends a VIP Super Like with an optional icebreaker [note].
  /// Includes celestial badge, starlight border, and direct chat request creation.
  static Future<MatchResult> sendSuperLike({
    WidgetRef? ref,
    required UserModel currentUser,
    required UserModel targetUser,
    String? note,
  }) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final currentUserId = authUid ?? (currentUser.id.isNotEmpty ? currentUser.id : '');
    if (currentUserId.isEmpty) {
      throw Exception('Authentication required to send Super Like.');
    }
    if (targetUser.id.isEmpty) {
      throw Exception('Target profile ID is missing.');
    }

    // Super like quota / coin validation:
    // If user does not have active subscription, deduct 20 coins
    final bool isSubscribed = currentUser.hasActiveSubscription;
    if (!isSubscribed) {
      final hasEnoughCoins = currentUser.coins >= 20;
      if (!hasEnoughCoins) {
        throw Exception('INSUFFICIENT_COINS');
      }
    }

    final chatId = await resolveChatId(currentUserId, targetUser.id);

    // Mutual check: Has targetUser liked currentUser previously?
    final bool isMutual = targetUser.following.contains(currentUserId) ||
        targetUser.likedBy.contains(currentUserId) ||
        currentUser.likedBy.contains(targetUser.id);

    final cleanNote = (note != null && note.trim().isNotEmpty) ? note.trim() : null;
    final superLikeText = cleanNote ?? '⭐ Super Liked your profile!';

    final batch = _db.batch();
    final targetRef = _db.collection('users').doc(targetUser.id);
    final currentRef = _db.collection('users').doc(currentUserId);
    final chatRef = _db.collection('chats').doc(chatId);

    // 1. Target user updates: followers, likedBy, superLikedBy, superLikeNotes (if doc exists)
    final targetDoc = await targetRef.get();
    if (targetDoc.exists) {
      final Map<String, dynamic> targetUpdates = {
        'followers': FieldValue.arrayUnion([currentUserId]),
        'likedBy': FieldValue.arrayUnion([currentUserId]),
        'superLikedBy': FieldValue.arrayUnion([currentUserId]),
      };
      if (cleanNote != null) {
        if (targetDoc.data()?['superLikeNotes'] != null) {
          targetUpdates['superLikeNotes.$currentUserId'] = cleanNote;
        } else {
          targetUpdates['superLikeNotes'] = {currentUserId: cleanNote};
        }
      }
      batch.update(targetRef, targetUpdates);
    }

    // 2. Current user updates: following, dislikedUsers removal, coins deduction if not subscribed
    final currentDoc = await currentRef.get();
    final Map<String, dynamic> currentUpdates = {
      'following': FieldValue.arrayUnion([targetUser.id]),
      'dislikedUsers': FieldValue.arrayRemove([targetUser.id]),
    };
    if (!isSubscribed) {
      currentUpdates['coins'] = FieldValue.increment(-20);
    }
    if (currentDoc.exists) {
      batch.update(currentRef, currentUpdates);
    } else {
      currentUpdates['id'] = currentUserId;
      currentUpdates['name'] = currentUser.name;
      batch.set(currentRef, currentUpdates, SetOptions(merge: true));
    }

    // 3. Direct chat request / match pipeline
    batch.set(chatRef, {
      'id': chatId,
      'participants': [currentUserId, targetUser.id],
      'status': isMutual ? 'accepted' : 'requested',
      'requestSenderId': currentUserId,
      'senderId': currentUserId,
      'senderName': currentUser.name,
      'senderAvatar': currentUser.avatarUrl,
      'receiverId': targetUser.id,
      'receiverName': targetUser.name,
      'receiverAvatar': targetUser.avatarUrl,
      'otherUserId': targetUser.id,
      'otherUserName': targetUser.name,
      'otherUserAvatar': targetUser.avatarUrl,
      'lastMessage': '⭐ $superLikeText',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': 1,
      'isExpired': false,
      'isConfession': false,
      if (isMutual) 'acceptedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final msgRef = chatRef.collection('messages').doc();
    batch.set(msgRef, {
      'id': msgRef.id,
      'senderId': currentUserId,
      'text': '⭐ Super Like: "$superLikeText"',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'isRead': false,
      'type': 'text',
    });

    await batch.commit();

    // 4. Update local caches immediately
    if (ref != null) {
      ref.read(likedUsersCacheProvider.notifier).update((m) => {...m, targetUser.id: targetUser});
      ref.read(sessionLikedUserIdsProvider.notifier).update(
            (list) => [targetUser.id, ...list.where((id) => id != targetUser.id)],
          );
    }

    // 5. Send push & Firestore notification
    try {
      if (isMutual) {
        await sendNotification(
          userId: targetUser.id,
          senderId: currentUserId,
          senderName: currentUser.name,
          senderAvatar: currentUser.avatarUrl,
          type: 'match',
          title: "⭐ Super Match! 🎉",
          body: 'You and ${currentUser.name} Super Matched! Start chatting now.',
        );
      } else {
        await sendNotification(
          userId: targetUser.id,
          senderId: currentUserId,
          senderName: currentUser.name,
          senderAvatar: currentUser.avatarUrl,
          type: 'superlike',
          title: '⭐ Super Like received!',
          body: cleanNote != null
              ? '${currentUser.name}: "$cleanNote"'
              : '${currentUser.name} Super Liked your profile!',
        );
      }
    } catch (e) {
      debugPrint('[LikeService] notification error: $e');
    }

    return MatchResult(
      isMatch: isMutual,
      isSuperMatch: true,
      user: targetUser,
      chatId: chatId,
      note: cleanNote,
    );
  }

  /// Passes [targetUser] (swipe left or pass button).
  static Future<void> passUser({
    required UserModel currentUser,
    required UserModel targetUser,
  }) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final currentUserId = authUid ?? (currentUser.id.isNotEmpty ? currentUser.id : '');
    if (currentUserId.isEmpty) return;

    try {
      final batch = _db.batch();
      final currentRef = _db.collection('users').doc(currentUserId);
      final targetRef = _db.collection('users').doc(targetUser.id);

      final currentDoc = await currentRef.get();
      if (currentDoc.exists) {
        batch.update(currentRef, {
          'dislikedUsers': FieldValue.arrayUnion([targetUser.id]),
          'following': FieldValue.arrayRemove([targetUser.id]),
        });
      }

      final targetDoc = await targetRef.get();
      if (targetDoc.exists) {
        batch.update(targetRef, {
          'followers': FieldValue.arrayRemove([currentUserId]),
          'likedBy': FieldValue.arrayRemove([currentUserId]),
        });
      }

      await batch.commit();
    } catch (e) {
      debugPrint('[LikeService] passUser error: $e');
    }
  }
}

