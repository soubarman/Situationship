import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../core/models/notification_model.dart';
import '../models/boost_model.dart';
import '../models/boost_constants.dart';
import '../models/boost_analytics_event.dart';

final activeBoostsProvider = StreamProvider<List<BoostModel>>((ref) {
  final now = DateTime.now();
  final db = firestoreProvider;
  return db
      .collection('boosts')
      .where('endTime', isGreaterThan: Timestamp.fromDate(now))
      .snapshots()
      .map((snapshot) {
        return snapshot.docs
            .map((doc) => BoostModel.fromMap(doc.data(), doc.id))
            .toList();
      });
});

final gpsCoordinatesProvider = FutureProvider<Position?>((ref) async {
  try {
    bool serviceEnabled = true;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (_) {}
    if (!serviceEnabled) return null;

    LocationPermission permission = LocationPermission.denied;
    try {
      permission = await Geolocator.checkPermission();
    } catch (_) {}

    if (permission == LocationPermission.denied) {
      try {
        permission = await Geolocator.requestPermission();
      } catch (_) {}
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
    ).timeout(const Duration(seconds: 4), onTimeout: () {
      debugPrint('gpsCoordinatesProvider timed out');
      return Position(
        latitude: 0.0,
        longitude: 0.0,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
    });
  } catch (e) {
    debugPrint('Error getting GPS coordinates: $e');
    return null;
  }
});

final boostedPostIdsProvider = Provider<Set<String>>((ref) {
  final boostsAsync = ref.watch(activeBoostsProvider);
  final userPosAsync = ref.watch(gpsCoordinatesProvider);
  final currentUser = ref.watch(currentUserProvider);

  final boosts = boostsAsync.asData?.value ?? [];
  final userPos = userPosAsync.asData?.value;

  final inRangeIds = <String>{};
  for (var b in boosts) {
    // If the viewer is the owner of the boost, it is always considered "in-range"
    if (b.ownerUserId == currentUser.id) {
      inRangeIds.add(b.contentId);
      continue;
    }

    // If boost has no coordinates (0.0, 0.0) due to location failure, treat as global boost!
    if (b.ownerLatitude == 0.0 && b.ownerLongitude == 0.0) {
      inRangeIds.add(b.contentId);
      continue;
    }

    if (userPos == null) continue;

    final distanceInMeters = Geolocator.distanceBetween(
      userPos.latitude,
      userPos.longitude,
      b.ownerLatitude,
      b.ownerLongitude,
    );
    final distanceInKm = distanceInMeters / 1000.0;
    if (distanceInKm <= b.radiusKm) {
      inRangeIds.add(b.contentId);
    }
  }
  return inRangeIds;
});

final contentBoostStatusProvider = Provider.family<BoostModel?, String>((ref, contentId) {
  final boostsAsync = ref.watch(activeBoostsProvider);
  final userPosAsync = ref.watch(gpsCoordinatesProvider);
  final currentUser = ref.watch(currentUserProvider);

  final boosts = boostsAsync.asData?.value ?? [];
  final userPos = userPosAsync.asData?.value;

  try {
    final activeBoost = boosts.firstWhere((b) => b.contentId == contentId);

    // If the viewer is the owner of the boost, show the badge immediately
    if (activeBoost.ownerUserId == currentUser.id) {
      return activeBoost;
    }

    // Global boost fallback
    if (activeBoost.ownerLatitude == 0.0 && activeBoost.ownerLongitude == 0.0) {
      return activeBoost;
    }

    if (userPos == null) return null;

    final distanceInMeters = Geolocator.distanceBetween(
      userPos.latitude,
      userPos.longitude,
      activeBoost.ownerLatitude,
      activeBoost.ownerLongitude,
    );
    final distanceInKm = distanceInMeters / 1000.0;
    if (distanceInKm <= activeBoost.radiusKm) {
      return activeBoost;
    }
  } catch (e) {
    // No active boost found
  }
  return null;
});

final boostPurchaseProvider = StateNotifierProvider<BoostPurchaseNotifier, bool>((ref) {
  return BoostPurchaseNotifier(ref);
});

class BoostPurchaseNotifier extends StateNotifier<bool> {
  final Ref ref;
  BoostPurchaseNotifier(this.ref) : super(false);

  /// Returns null if success, or error message string if failed
  Future<String?> purchaseBoost({
    required String contentId,
    required String contentType,
    required String boostScope,
    required String boostTier,
    required Duration duration,
    required int coinCost,
    required double reachMultiplier,
  }) async {
    state = true;
    try {
      final user = ref.read(currentUserProvider);
      final db = firestoreProvider;

      if (user.coins < coinCost) {
        throw Exception('Insufficient coins');
      }

      if (contentType == 'plan') {
        throw Exception('Plans cannot be boosted');
      }

      // Fetch current GPS position safely with a fallback to (0.0, 0.0) to prevent browser interop crashes
      double latitude = 0.0;
      double longitude = 0.0;

      try {
        bool serviceEnabled = true;
        try {
          serviceEnabled = await Geolocator.isLocationServiceEnabled();
        } catch (_) {}
        
        if (serviceEnabled) {
          LocationPermission permission = LocationPermission.denied;
          try {
            permission = await Geolocator.checkPermission();
          } catch (_) {}

          if (permission == LocationPermission.denied) {
            try {
              permission = await Geolocator.requestPermission();
            } catch (_) {}
          }

          if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
            final position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
            ).timeout(const Duration(seconds: 4));
            latitude = position.latitude;
            longitude = position.longitude;
          }
        }
      } catch (e) {
        // Safe fallback — log but do not crash the transaction
        debugPrint('Location fetching bypassed with fallback: $e');
      }

      // Determine radius based on boostScope
      double radiusKm = BoostConstants.localRadius;
      if (boostScope == 'regional') {
        radiusKm = BoostConstants.regionalRadius;
      } else if (boostScope == 'extended') {
        radiusKm = BoostConstants.extendedRadius;
      }

      // 1. Transaction to deduct coins safely without throwing inside JS interop callback
      bool transactionSuccess = false;
      String transactionError = '';

      try {
        await db.runTransaction((transaction) async {
          final userRef = db.collection('users').doc(user.id);
          final userDoc = await transaction.get(userRef);
          final currentCoins = userDoc.data()?['coins'] ?? 0;
          
          if (currentCoins < coinCost) {
            transactionSuccess = false;
            transactionError = 'Insufficient coins';
            return; // Exit callback cleanly
          }
          
          transaction.update(userRef, {'coins': currentCoins - coinCost});
          transactionSuccess = true;
        });
      } catch (e) {
        transactionSuccess = false;
        transactionError = e.toString();
      }

      if (!transactionSuccess) {
        throw Exception(transactionError.isNotEmpty ? transactionError : 'Insufficient coins');
      }

      // 2. Create Boost Doc
      final now = DateTime.now();
      final boostDoc = db.collection('boosts').doc();
      final boost = BoostModel(
        id: boostDoc.id,
        contentId: contentId,
        contentType: contentType,
        boostScope: boostScope,
        boostTier: boostTier,
        startTime: now,
        endTime: now.add(duration),
        coinCost: coinCost,
        reachMultiplier: reachMultiplier,
        ownerUserId: user.id,
        ownerLatitude: latitude,
        ownerLongitude: longitude,
        radiusKm: radiusKm,
        cooldownUntil: now.add(duration).add(BoostConstants.cooldownDuration),
        eligibilityCheckPassed: true,
      );

      await boostDoc.set(boost.toMap());

      // Create "Boost Active" notification in notification panel
      final notifId = db.collection('notifications').doc().id;
      final formattedDuration = duration.inHours > 0
          ? '${duration.inHours} hours'
          : '${duration.inMinutes} minutes';
      final activeNotif = NotificationModel(
        id: notifId,
        userId: user.id,
        senderId: 'system',
        senderName: 'Situationship',
        senderAvatar: '',
        type: 'boost_active',
        title: '⚡ Post Boosted!',
        body: 'Your post is now boosted for the next $formattedDuration.',
        createdAt: now,
        isRead: false,
      );
      await db.collection('notifications').doc(notifId).set(activeNotif.toMap());

      // 3. Log Analytics — fire-and-forget
      db
          .collection('boosts')
          .doc(boostDoc.id)
          .collection('boost_analytics')
          .add(BoostAnalyticsEvent(
            type: 'boost_purchased',
            timestamp: now,
            metadata: {'cost': coinCost, 'tier': boostTier, 'scope': boostScope, 'radiusKm': radiusKm},
          ).toMap())
          .catchError((_) {});

      state = false;
      return null; // success
    } catch (e) {
      state = false;
      debugPrint('Boost purchase failure detail: $e');
      
      // Safe dynamic error conversion to avoid JS interop type failures
      String errMsg = 'Transaction failed. Check network connection.';
      try {
        errMsg = e.toString().replaceAll('Exception: ', '');
      } catch (_) {}
      return errMsg;
    }
  }
}

final userBoostsStreamProvider = StreamProvider<List<BoostModel>>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  final db = firestoreProvider;
  return db
      .collection('boosts')
      .where('ownerUserId', isEqualTo: currentUser.id)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => BoostModel.fromMap(doc.data(), doc.id))
          .toList());
});

final boostNotificationListenerProvider = Provider<void>((ref) {
  final userBoostsAsync = ref.watch(userBoostsStreamProvider);
  final db = firestoreProvider;

  userBoostsAsync.whenData((boosts) async {
    final now = DateTime.now();
    for (var b in boosts) {
      if (b.endTime.isBefore(now) && !b.expiredNotificationSent) {
        // Send notification
        final notifId = db.collection('notifications').doc().id;
        final expiredNotif = NotificationModel(
          id: notifId,
          userId: b.ownerUserId,
          senderId: 'system',
          senderName: 'Situationship',
          senderAvatar: '',
          type: 'boost_expired',
          title: '⚡ Boost Expired',
          body: 'Your post boost has expired. Boost it again to keep maximum reach!',
          createdAt: now,
          isRead: false,
        );

        // Update document first to prevent race condition/multiple writes
        await db.collection('boosts').doc(b.id).update({'expiredNotificationSent': true});
        await db.collection('notifications').doc(notifId).set(expiredNotif.toMap());
      }
    }
  });
});
