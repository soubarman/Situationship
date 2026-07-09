import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../providers/firestore_provider.dart';

/// Coin milestones for female users (totalEarnedCoins thresholds).
/// Adjust values once confirmed with Xoxoday.
class CoinMilestone {
  final String id;
  final String name;
  final int threshold;
  final int giftCardValueInr;
  final String emoji;
  const CoinMilestone({
    required this.id,
    required this.name,
    required this.threshold,
    required this.giftCardValueInr,
    required this.emoji,
  });
}

const List<CoinMilestone> kFemaleMilestones = [
  CoinMilestone(id: 'spark',  name: 'Spark',  threshold: 500,  giftCardValueInr: 50,  emoji: '✨'),
  CoinMilestone(id: 'glow',   name: 'Glow',   threshold: 1500, giftCardValueInr: 150, emoji: '🌟'),
  CoinMilestone(id: 'icon',   name: 'Icon',   threshold: 3000, giftCardValueInr: 300, emoji: '💎'),
  CoinMilestone(id: 'legend', name: 'Legend', threshold: 6000, giftCardValueInr: 600, emoji: '👑'),
];

class CoinService {
  static final FirebaseFirestore _db = firestoreProvider;

  // ── Award coins (female earning track) ─────────────────────────────────────

  /// Awards [amount] coins to [userId].
  /// Also increments [totalEarnedCoins] and checks milestones.
  /// [reason] is for analytics only (not stored).
  static Future<void> award({
    required String userId,
    required int amount,
    required String reason,
  }) async {
    if (amount <= 0) return;
    try {
      final userRef = _db.collection('users').doc(userId);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        if (!snap.exists) return;
        final data = snap.data()!;
        final newCoins = (data['coins'] ?? 0) + amount;
        final newTotal = (data['totalEarnedCoins'] ?? 0) + amount;
        tx.update(userRef, {
          'coins': newCoins,
          'totalEarnedCoins': newTotal,
        });
      });
      // Check milestones after award (fire-and-forget)
      _checkMilestones(userId).catchError((_) {});
    } catch (e) {
      debugPrint('[CoinService.award] error: $e');
    }
  }

  // ── Spend coins (male purchase track) ────────────────────────────────────

  /// Deducts [amount] coins from [userId].
  /// Returns true if success, false if insufficient coins.
  static Future<bool> spend({
    required String userId,
    required int amount,
    required String reason,
  }) async {
    if (amount <= 0) return true;
    bool success = false;
    try {
      final userRef = _db.collection('users').doc(userId);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        if (!snap.exists) return;
        final current = (snap.data()!['coins'] ?? 0) as int;
        if (current < amount) return; // insufficient
        tx.update(userRef, {'coins': current - amount});
        success = true;
      });
    } catch (e) {
      debugPrint('[CoinService.spend] error: $e');
    }
    return success;
  }

  // ── Grant coins for pack purchase (male) ──────────────────────────────────

  /// Called after a successful payment to add coins to a male user.
  static Future<void> grantPurchasedCoins({
    required String userId,
    required int amount,
  }) async {
    try {
      await _db.collection('users').doc(userId).update({
        'coins': FieldValue.increment(amount),
      });
    } catch (e) {
      debugPrint('[CoinService.grantPurchasedCoins] error: $e');
    }
  }

  // ── Subscription management ───────────────────────────────────────────────

  static Future<void> activateSubscription({
    required String userId,
    required Duration duration,
    required int phoneUnlockQuota,
  }) async {
    final expiry = DateTime.now().add(duration);
    await _db.collection('users').doc(userId).update({
      'isSubscribed': true,
      'subscriptionExpiry': expiry.millisecondsSinceEpoch,
      'phoneUnlockQuota': phoneUnlockQuota,
      'phoneUnlocksUsed': 0,
    });
  }

  // ── Daily login reward ────────────────────────────────────────────────────

  static Future<void> processDailyLogin({
    required String userId,
    required bool isFemale,
    required String? lastLoginDate,
    required int currentStreak,
  }) async {
    final today = _dateKey(DateTime.now());
    if (lastLoginDate == today) return; // already claimed today

    final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final newStreak = lastLoginDate == yesterday ? currentStreak + 1 : 1;
    final coins = (newStreak == 7 || newStreak % 7 == 0) ? 10 : 1; // +10 bonus every 7 days

    final userRef = _db.collection('users').doc(userId);
    await userRef.update({
      'lastLoginDate': today,
      'dailyLoginStreak': newStreak,
      'conversationRewardsToday': 0, // reset daily conv reward counter
    });

    // Only award coins to female users (male users get coins from purchases)
    if (isFemale) {
      await award(userId: userId, amount: coins, reason: 'daily_login');
    }
  }

  // ── Conversation depth reward ─────────────────────────────────────────────

  /// Called after each message send to check if a depth tier was just crossed.
  /// [myCount] = messages sent by this user in this thread today.
  /// [otherCount] = messages sent by the other party today.
  /// [rewardsUsedToday] = how many conv rewards this user already got today.
  static Future<int> checkConversationDepth({
    required String userId,
    required String chatId,
    required int myCount,
    required int otherCount,
    required int rewardsUsedToday,
  }) async {
    if (rewardsUsedToday >= 3) return 0; // daily cap

    final minCount = myCount < otherCount ? myCount : otherCount;
    int reward = 0;
    String tier = '';

    // Check tiers (highest unlocked wins — tiers don't stack)
    if (minCount >= 20) {
      tier = '20+';
      reward = 60;
    } else if (minCount >= 10) {
      tier = '10+';
      reward = 25;
    } else if (minCount >= 4) {
      tier = '4+';
      reward = 10;
    }

    if (tier.isEmpty) return 0;

    // Check if this tier was already rewarded for this chat today
    final key = 'conv_${chatId}_${_dateKey(DateTime.now())}_$tier';
    final rewardDoc = await _db.collection('coin_rewards').doc('${userId}_$key').get();
    if (rewardDoc.exists) return 0; // already rewarded

    // Mark as rewarded & award
    await _db.collection('coin_rewards').doc('${userId}_$key').set({'at': FieldValue.serverTimestamp()});
    await _db.collection('users').doc(userId).update({
      'conversationRewardsToday': FieldValue.increment(1),
    });
    await award(userId: userId, amount: reward, reason: 'conversation_depth_$tier');
    return reward;
  }

  // ── Milestone checking ────────────────────────────────────────────────────

  static Future<void> _checkMilestones(String userId) async {
    final snap = await _db.collection('users').doc(userId).get();
    if (!snap.exists) return;
    final data = snap.data()!;
    final totalEarned = (data['totalEarnedCoins'] ?? 0) as int;
    final claimed = List<String>.from(data['claimedMilestones'] ?? []);

    for (final milestone in kFemaleMilestones) {
      if (claimed.contains(milestone.id)) continue;
      if (totalEarned >= milestone.threshold) {
        // Create unclaimed reward document
        final rewardRef = _db.collection('coin_milestones').doc('${userId}_${milestone.id}');
        await rewardRef.set({
          'userId': userId,
          'milestoneId': milestone.id,
          'milestoneName': milestone.name,
          'giftCardValueInr': milestone.giftCardValueInr,
          'status': 'pending', // → 'issued' once Xoxoday responds
          'giftCode': null,    // filled by Cloud Function
          'createdAt': FieldValue.serverTimestamp(),
        });
        // Mark milestone as claimed so it doesn't fire again
        await _db.collection('users').doc(userId).update({
          'claimedMilestones': FieldValue.arrayUnion([milestone.id]),
        });
        debugPrint('[CoinService] Milestone ${milestone.name} triggered for $userId');
      }
    }
  }

  // ── Utils ─────────────────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
