import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';


// ─── Location status ──────────────────────────────────────────────────────────

enum LocationStatus { initial, granted, denied, deniedForever, serviceDisabled }

class LocationState {
  final LocationStatus status;
  final String? sessionId; // geohash-based session ID, null if no permission

  const LocationState({required this.status, this.sessionId});
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final locationProvider = FutureProvider<LocationState>((ref) async {
  if (kIsWeb) {
    try {
      final completer = Completer<LocationState>();
      final geo = web.window.navigator.geolocation;
      
      geo.getCurrentPosition(
        ((web.GeolocationPosition pos) {
          final lat = pos.coords.latitude.toStringAsFixed(1);
          final lng = pos.coords.longitude.toStringAsFixed(1);
          completer.complete(LocationState(status: LocationStatus.granted, sessionId: 'zone_${lat}_$lng'));
        }).toJS,
        ((web.GeolocationPositionError err) {
          completer.complete(const LocationState(status: LocationStatus.deniedForever));
        }).toJS,
      );
      
      return await completer.future;
    } catch (e) {
      return const LocationState(status: LocationStatus.deniedForever);
    }
  }

  // Mobile Implementation
  bool serviceEnabled = true;
  try {
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
  } catch (e) {
    // Ignore
  }
  
  if (!serviceEnabled) {
    return const LocationState(status: LocationStatus.serviceDisabled);
  }

  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    return const LocationState(status: LocationStatus.denied);
  }

  if (permission == LocationPermission.deniedForever) {
    return const LocationState(status: LocationStatus.deniedForever);
  }

  final position = await Geolocator.getCurrentPosition();
  final lat = position.latitude.toStringAsFixed(1);
  final lng = position.longitude.toStringAsFixed(1);

  return LocationState(
    status: LocationStatus.granted,
    sessionId: 'zone_${lat}_$lng',
  );
});
