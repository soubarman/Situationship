import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/spotlight_model.dart';
import 'package:situationship/core/providers/app_state_provider.dart';

final spotlightSessionProvider = StreamProvider<SpotlightSession?>((ref) {
  return FirebaseFirestore.instance
      .collection('spotlight_sessions')
      .doc('live_session')
      .snapshots()
      .map((snapshot) {
    if (!snapshot.exists) {
      return SpotlightSession(
        id: 'live_session',
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

final spotlightBidsProvider = StreamProvider.family<List<SpotlightBid>, String>((ref, sessionId) {
  return FirebaseFirestore.instance
      .collection('spotlight_sessions')
      .doc('live_session')
      .collection('bids')
      .orderBy('amount', descending: true)
      .orderBy('timestamp', descending: false)
      .limit(20)
      .snapshots()
      .map((snapshot) {
    final bids = snapshot.docs
        .map((doc) => SpotlightBid.fromMap(doc.id, doc.data()))
        .toList();
    
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

final spotlightNotifierProvider = Provider((ref) => SpotlightNotifier(ref));

class SpotlightNotifier {
  final Ref _ref;
  SpotlightNotifier(this._ref);

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

    final sessionRef = FirebaseFirestore.instance
        .collection('spotlight_sessions')
        .doc('live_session');
    
    final bidRef = sessionRef.collection('bids').doc(user.id);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      // Simulate real transaction logic
      transaction.set(bidRef, {
        'sessionId': sessionId,
        'userId': user.id,
        'username': user.name,
        'profileImageUrl': user.avatarUrl ?? '',
        'isVerified': user.isVerified,
        'amount': amount,
        'timestamp': FieldValue.serverTimestamp(),
        'rank': 999, // Will be computed on read
      });

      // Ensure the session doc exists
      transaction.set(sessionRef, {
        'isActive': true,
        'prizePool': FieldValue.increment(amount),
        'minStartingBid': 100,
      }, SetOptions(merge: true));
    });
  }

  // Removed createMockSession
}
