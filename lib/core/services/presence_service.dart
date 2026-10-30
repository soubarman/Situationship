import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

/// Real-time presence management service.
/// Tracks app foreground/background state via WidgetsBindingObserver and
/// sends a periodic 2-minute heartbeat to keep user presence completely accurate.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  Timer? _heartbeatTimer;
  StreamSubscription<User?>? _authSubscription;
  bool _isInitialized = false;

  /// Starts listening to auth state and app lifecycle
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    WidgetsBinding.instance.addObserver(this);

    // If a session is already restored synchronously, mark online immediately
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      _setOnline(true);
      _startHeartbeat();
    }

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _setOnline(true);
        _startHeartbeat();
      } else {
        _stopHeartbeat();
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // Heartbeat every 2 minutes while active
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _sendHeartbeat();
    });
    // Send immediate heartbeat
    _sendHeartbeat();
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _setOnline(bool online) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = {
      'isOnline': online,
      'lastSeen': now,
    };

    // Update 'default' and '(default)' databases safely
    for (final dbId in const ['default', '(default)']) {
      try {
        final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: dbId);
        await db.collection('users').doc(user.uid).update(updates);
      } catch (_) {
        // Silently ignore if database doesn't exist or doc missing
      }
    }
  }

  Future<void> _sendHeartbeat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final updates = {
      'isOnline': true,
      'lastSeen': now,
    };

    for (final dbId in const ['default', '(default)']) {
      try {
        final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: dbId);
        await db.collection('users').doc(user.uid).update(updates);
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
      _startHeartbeat();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached ||
               state == AppLifecycleState.hidden) {
      _setOnline(false);
      _stopHeartbeat();
    }
  }

  /// Explicitly mark user offline (e.g. on manual logout)
  Future<void> markOffline() async {
    _stopHeartbeat();
    await _setOnline(false);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _stopHeartbeat();
    _isInitialized = false;
  }
}

