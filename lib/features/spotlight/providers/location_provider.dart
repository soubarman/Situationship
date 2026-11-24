import '../../../core/providers/app_state_provider.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator/geolocator.dart';


// ─── Location status ──────────────────────────────────────────────────────────

enum LocationStatus { initial, granted, denied, deniedForever, serviceDisabled }

class LocationState {
  final LocationStatus status;
  final String? sessionId; // geohash-based session ID, null if no permission

  const LocationState({required this.status, this.sessionId});
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final locationProvider = FutureProvider<LocationState>((ref) async {
  // Implementation works for both Web and Mobile
  bool serviceEnabled = true;
  try {
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
  } catch (e) {
    // Ignore
  }
  
  final currentUser = ref.watch(currentUserProvider);
  final profileLocation = currentUser.location?.trim();

  if (!serviceEnabled) {
    if (profileLocation != null && profileLocation.isNotEmpty) {
      final clean = profileLocation.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      return LocationState(status: LocationStatus.granted, sessionId: 'zone_city_$clean');
    }
    return const LocationState(status: LocationStatus.serviceDisabled);
  }

  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    if (profileLocation != null && profileLocation.isNotEmpty) {
      final clean = profileLocation.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      return LocationState(status: LocationStatus.granted, sessionId: 'zone_city_$clean');
    }
    return LocationState(
      status: permission == LocationPermission.deniedForever
          ? LocationStatus.deniedForever
          : LocationStatus.denied,
    );
  }

  try {
    final position = await Geolocator.getCurrentPosition();
    final lat = position.latitude.toStringAsFixed(1);
    final lng = position.longitude.toStringAsFixed(1);

    return LocationState(
      status: LocationStatus.granted,
      sessionId: 'zone_${lat}_$lng',
    );
  } catch (_) {
    if (profileLocation != null && profileLocation.isNotEmpty) {
      final clean = profileLocation.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      return LocationState(status: LocationStatus.granted, sessionId: 'zone_city_$clean');
    }
    return const LocationState(status: LocationStatus.denied);
  }
});
