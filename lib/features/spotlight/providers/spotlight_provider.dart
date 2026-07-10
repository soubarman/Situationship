import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/spotlight_model.dart';
import 'location_provider.dart';
import 'package:situationship/core/providers/app_state_provider.dart';


// ─── Helper: get session ID from location state ───────────────────────────────

/// Returns null if location not yet resolved or denied.
final _sessionIdProvider = Provider<String?>((ref) {
  final locationAsync = ref.watch(locationProvider);
  return locationAsync.when(
    data: (state) => state.sessionId, // null if denied
    loading: () => null,
    error: (_, __) => null,
  );
});

// ─── Session stream ───────────────────────────────────────────────────────────

final spotlightSessionProvider = StreamProvider<SpotlightSession?>((ref) {
  final sessionId = ref.watch(_sessionIdProvider);
  if (sessionId == null) return const Stream.empty();

  return FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
      .collection('spotlight_sessions')
      .doc(sessionId)
      .snapshots()
      .map((snapshot) {
    if (!snapshot.exists) {
      // Auto-create a virtual session for this zone (no write needed — bids create it)
      return SpotlightSession(
        id: sessionId,
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(hours: 1)),
        prizePool: 0,
        isActive: true,
        minStartingBid: 100,
        activeBidders: 0,
      );
    }
    return SpotlightSession.fromMap(snapshot.id, snapshot.data()!);
  });
});

// ─── Bids stream ─────────────────────────────────────────────────────────────

final spotlightBidsProvider =
    StreamProvider.family<List<SpotlightBid>, String>((ref, sessionId) {
  return FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
      .collection('spotlight_sessions')
      .doc(sessionId)
      .collection('bids')
      .orderBy('amount', descending: true)
      .limit(30)
      .snapshots()
      .map((snapshot) {
    final bids = snapshot.docs
        .map((doc) => SpotlightBid.fromMap(doc.id, doc.data()))
        .toList();

    // Sort by amount descending (primary), then timestamp ascending (tie-breaker) in memory
    bids.sort((a, b) {
      final amtCmp = b.amount.compareTo(a.amount);
      if (amtCmp != 0) return amtCmp;
      return a.timestamp.compareTo(b.timestamp);
    });

    // Assign ranks locally based on the sorted order
    for (int i = 0; i < bids.length; i++) {
      bids[i] = SpotlightBid(
        id: bids[i].id,
        sessionId: bids[i].sessionId,
        userId: bids[i].userId,
        username: bids[i].username,
        profileImageUrl: bids[i].profileImageUrl,
        isVerified: bids[i].isVerified,
        amount: bids[i].amount,
        timestamp: bids[i].timestamp,
        rank: i + 1,
      );
    }
    return bids;
  });
});

// ─── Notifier ─────────────────────────────────────────────────────────────────

final spotlightNotifierProvider = Provider((ref) => SpotlightNotifier(ref));

class SpotlightNotifier {
  final Ref _ref;
  SpotlightNotifier(this._ref);

  String? get _sessionId => _ref.read(_sessionIdProvider);

  int getNextValidBid(int currentHighestBid) {
    if (currentHighestBid < 1000) return currentHighestBid + 50;
    if (currentHighestBid < 5000) return currentHighestBid + 100;
    return currentHighestBid + 250;
  }

  Future<void> placeBid({
    required String sessionId,
    required int amount,
  }) async {
    final user = _ref.read(currentUserProvider);
    if (user == null) return;

    final resolvedSessionId = _sessionId ?? sessionId;

    final sessionRef = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
        .collection('spotlight_sessions')
        .doc(resolvedSessionId);

    final bidRef = sessionRef.collection('bids').doc(user.id);
    final userRef = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(user.id);

    await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').runTransaction((transaction) async {
      final userDoc = await transaction.get(userRef);
      if (!userDoc.exists) throw Exception('User not found');
      
      final currentCoins = userDoc.data()?['coins'] as int? ?? 0;
      if (currentCoins < amount) {
        throw Exception('Insufficient balance. You need ₹$amount to place this bid.');
      }

      // Deduct coins from user
      transaction.update(userRef, {
        'coins': FieldValue.increment(-amount),
      });

      transaction.set(bidRef, {
        'sessionId': resolvedSessionId,
        'userId': user.id,
        'username': user.name,
        'profileImageUrl': user.avatarUrl ?? '',
        'isVerified': user.isVerified,
        'amount': amount,
        'timestamp': FieldValue.serverTimestamp(),
        'rank': 999,
      });

      // Ensure the session doc exists with zone metadata
      transaction.set(sessionRef, {
        'isActive': true,
        'prizePool': FieldValue.increment(amount),
        'minStartingBid': 100,
        'sessionId': resolvedSessionId,
      }, SetOptions(merge: true));
    });
  }
}
