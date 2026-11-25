import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/spotlight_model.dart';
import 'location_provider.dart';
import 'package:situationship/core/providers/app_state_provider.dart';
import 'package:situationship/core/providers/firebase_auth_provider.dart';

// Helper: Current clock-hour slot ID (e.g. '2026-10-30-14')
String getCurrentSlotId([DateTime? dt]) {
  final now = dt ?? DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  final h = now.hour.toString().padLeft(2, '0');
  return '$y-$m-$d-$h';
}

DateTime getCurrentSlotStartTime([DateTime? dt]) {
  final now = dt ?? DateTime.now();
  return DateTime(now.year, now.month, now.day, now.hour, 0, 0);
}

DateTime getCurrentSlotEndTime([DateTime? dt]) {
  final now = dt ?? DateTime.now();
  return DateTime(now.year, now.month, now.day, now.hour + 1, 0, 0);
}

// ??? Helper: get session ID from location state ???????????????????????????????

/// Returns null if location not yet resolved or denied.
final _sessionIdProvider = Provider<String?>((ref) {
  final locationAsync = ref.watch(locationProvider);
  return locationAsync.when(
    data: (state) => state.sessionId, // null if denied
    loading: () => null,
    error: (_, __) => null,
  );
});

// ??? Session stream ???????????????????????????????????????????????????????????

final spotlightSessionProvider = StreamProvider<SpotlightSession?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  final user = authState.asData?.value;
  if (user == null) return const Stream.empty();

  final sessionId = ref.watch(_sessionIdProvider);
  if (sessionId == null) return const Stream.empty();

  final slotStart = getCurrentSlotStartTime();
  final slotEnd = getCurrentSlotEndTime();

  return FirebaseFirestore.instance
      .collection('spotlight_sessions')
      .doc(sessionId)
      .snapshots()
      .handleError((err) {
        debugPrint('[Spotlight] Session stream error: $err');
      })
      .map((snapshot) {
    if (!snapshot.exists) {
      return SpotlightSession(
        id: sessionId,
        startTime: slotStart,
        endTime: slotEnd,
        prizePool: 0,
        isActive: true,
        minStartingBid: 100,
        activeBidders: 0,
      );
    }

    final session = SpotlightSession.fromMap(snapshot.id, snapshot.data()!);
    final now = DateTime.now();
    // If stored endTime has passed or is from a previous hour, present active hour slot
    if (now.isAfter(session.endTime) || session.endTime.isBefore(slotStart)) {
      return SpotlightSession(
        id: session.id,
        startTime: slotStart,
        endTime: slotEnd,
        prizePool: 0, // Reset prize pool for new slot until bids placed
        isActive: true,
        minStartingBid: session.minStartingBid,
        activeBidders: 0,
      );
    }
    return session;
  });
});

// ??? Bids stream ?????????????????????????????????????????????????????????????

final spotlightBidsProvider =
    StreamProvider.family<List<SpotlightBid>, String>((ref, sessionId) {
  final authState = ref.watch(authStateChangesProvider);
  final user = authState.asData?.value;
  if (user == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('spotlight_sessions')
      .doc(sessionId)
      .collection('bids')
      .orderBy('amount', descending: true)
      .limit(60)
      .snapshots()
      .handleError((err) {
        debugPrint('[Spotlight] Bids stream error: $err');
      })
      .map((snapshot) {
    final now = DateTime.now();
    final currentSlotId = getCurrentSlotId(now);
    final slotStart = getCurrentSlotStartTime(now);
    final slotEnd = getCurrentSlotEndTime(now);

    // Filter bids to ONLY those belonging to the current 1-hour slot:
    // 1. If bid has slotId, it MUST match currentSlotId.
    // 2. If legacy bid without slotId, its timestamp must be within [slotStart, slotEnd].
    // Past hour profiles are automatically excluded!
    final activeBids = snapshot.docs
        .map((doc) => SpotlightBid.fromMap(doc.id, doc.data()))
        .where((bid) {
          if (bid.slotId.isNotEmpty) {
            return bid.slotId == currentSlotId;
          }
          return bid.timestamp.isAfter(slotStart.subtract(const Duration(seconds: 10))) &&
                 bid.timestamp.isBefore(slotEnd.add(const Duration(minutes: 1)));
        })
        .toList();

    // Sort by amount descending (primary), then timestamp ascending (tie-breaker)
    activeBids.sort((a, b) {
      final amtCmp = b.amount.compareTo(a.amount);
      if (amtCmp != 0) return amtCmp;
      return a.timestamp.compareTo(b.timestamp);
    });

    final top30 = activeBids.take(30).toList();

    // Assign ranks locally based on the sorted order
    for (int i = 0; i < top30.length; i++) {
      top30[i] = SpotlightBid(
        id: top30[i].id,
        sessionId: top30[i].sessionId,
        userId: top30[i].userId,
        username: top30[i].username,
        profileImageUrl: top30[i].profileImageUrl,
        isVerified: top30[i].isVerified,
        amount: top30[i].amount,
        timestamp: top30[i].timestamp,
        rank: i + 1,
        slotId: top30[i].slotId,
      );
    }
    return top30;
  });
});

// ??? Notifier ?????????????????????????????????????????????????????????????????

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
    if (user.id.isEmpty) {
      throw Exception('Please sign in to place a bid');
    }

    final resolvedSessionId = _sessionId ?? sessionId;

    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) {
        throw Exception('Please sign in to place a spotlight bid.');
      }
      final idToken = await authUser.getIdToken();
      final response = await http.post(
        Uri.parse('https://us-central1-situation-ship.cloudfunctions.net/api/user/spotlight-bid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'bidAmount': amount,
          'sessionId': resolvedSessionId,
          'tier': 'gold',
          'targetGender': 'all',
          'targetCategory': 'dating',
          'durationMinutes': 60,
        }),
      );

      if (response.statusCode == 402 || response.body.contains('Insufficient coins')) {
        throw Exception('Insufficient coins. Please add more coins to your wallet.');
      }

      if (response.statusCode != 200) {
        try {
          final err = jsonDecode(response.body);
          throw Exception(err['detail'] ?? 'Failed to place spotlight bid');
        } catch (_) {
          throw Exception('Failed to place spotlight bid: ${response.body}');
        }
      }
    } catch (e, stack) {
      debugPrint('[Spotlight] placeBid error: $e\n$stack');
      final errorMsg = e.toString();
      if (errorMsg.contains('Insufficient coins')) {
        rethrow;
      } else {
        throw Exception(errorMsg.replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> removeBid({required String sessionId}) async {
    final user = _ref.read(currentUserProvider);
    if (user.id.isEmpty) return;

    final resolvedSessionId = _sessionId ?? sessionId;
    final now = DateTime.now();
    final currentSlotId = getCurrentSlotId(now);
    final slotStart = getCurrentSlotStartTime(now);

    final db = FirebaseFirestore.instance;
    final sessionRef = db.collection('spotlight_sessions').doc(resolvedSessionId);
    final bidRef = sessionRef.collection('bids').doc(user.id);
    final userRef = db.collection('users').doc(user.id);

    try {
      await db.runTransaction((transaction) async {
        final bidDoc = await transaction.get(bidRef);
        if (!bidDoc.exists) return;

        final existingSlotId = bidDoc.data()?['slotId'] as String? ?? '';
        final existingTs = (bidDoc.data()?['timestamp'] as Timestamp?)?.toDate();
        final isCurrentSlot = existingSlotId == currentSlotId || 
            (existingSlotId.isEmpty && existingTs != null && existingTs.isAfter(slotStart));

        final bidAmount = (bidDoc.data()?['amount'] as num?)?.toInt() ?? 0;

        // Delete the bid document from session bids atomically
        transaction.delete(bidRef);

        // Refund coins to user & decrement prize pool & activeBidders only if from current active slot
        if (isCurrentSlot && bidAmount > 0) {
          transaction.update(userRef, {
            'coins': FieldValue.increment(bidAmount),
          });

          transaction.set(sessionRef, {
            'prizePool': FieldValue.increment(-bidAmount),
            'activeBidders': FieldValue.increment(-1),
          }, SetOptions(merge: true));
        }
      });
    } catch (e) {
      debugPrint('[Spotlight] removeBid error: $e');
    }
  }
}
