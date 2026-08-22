import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../core/providers/firebase_auth_provider.dart';
import '../../../shared/widgets/background_orbs.dart';
import '../../../core/utils/location_helper.dart';
import '../../../core/utils/heart_queue_engine.dart';
import '../widgets/discover_tab.dart';
import '../widgets/soul_mode_tab.dart';
import '../widgets/nearly_souls_tab.dart';
import '../widgets/match_overlay.dart';
import 'liked_history_screen.dart';

class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({super.key});

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<SoulModeTabState> _soulModeKey = GlobalKey<SoulModeTabState>();

  double? _deviceLat;
  double? _deviceLon;

  // ── HeartQueue™ Engine ──────────────────────────────────────────────────────────
  final HeartQueueEngine _engine = HeartQueueEngine();

  // ── HeartQueue™ Algorithm State ────────────────────────────────────────────
  // Tier 1: Explicitly skipped ("Show me others") — permanent, not undoable
  final Set<String> _permanentSkippedIds = {};
  // Tier 2: Likes confirmed (undo window closed) — permanent
  final Set<String> _confirmedLikedIds = {};
  // Tier 3: Pending like transaction — undoable within 3s window
  _LikeTx? _pendingTx;
  // Tier 4: Paired profiles waiting to be shuffled back into queue
  // Maps userId → how many more "swipe events" to wait before re-showing
  final Map<String, int> _shuffleBackPool = {};
  // Counts every like/skip action so we can decrement shuffle counters
  int _swipeCount = 0;
  // Session exclusion set: persists liked+skipped IDs across widget rebuilds
  // so the engine can never re-rank a processed profile back to the top.
  final Set<String> _sessionExcludedIds = {};

  // Derived: all IDs currently hidden from the queue
  Set<String> get _effectiveExcludedIds {
    final ids = <String>{
      ..._permanentSkippedIds,
      ..._confirmedLikedIds,
      ..._sessionExcludedIds,
    };
    if (_pendingTx != null) {
      ids.add(_pendingTx!.liked.id);
      if (_pendingTx!.pairedWith != null) ids.add(_pendingTx!.pairedWith!.id);
    }
    // Also hide profiles still waiting in the shuffle-back pool
    ids.addAll(_shuffleBackPool.keys);
    return ids;
  }

  /// Increments swipe counter and releases any shuffle-back profiles whose
  /// countdown has reached zero, making them visible in the queue again.
  void _tickSwipeCounter() {
    _swipeCount++;
    final toRelease = <String>[];
    _shuffleBackPool.forEach((id, remaining) {
      if (_swipeCount >= remaining) toRelease.add(id);
    });
    if (toRelease.isNotEmpty && mounted) {
      setState(() {
        for (final id in toRelease) _shuffleBackPool.remove(id);
      });
    }
  }

  // Match overlay state
  bool _showMatchOverlay = false;
  UserModel? _matchedUser;

  // ── Undo animation state ────────────────────────────────────────────────────
  UserModel? _undoUser;
  bool _showUndo = false;
  late AnimationController _undoSlideController;
  late Animation<Offset> _undoSlideAnim;
  late AnimationController _undoCountdownController;
  late Animation<double> _undoCountdownAnim;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _fetchDeviceLocation();

    _undoSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _undoSlideAnim = Tween<Offset>(
      begin: const Offset(0, 1.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _undoSlideController,
      curve: Curves.easeOutBack,
    ));

    _undoCountdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _undoCountdownAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _undoCountdownController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _undoSlideController.dispose();
    _undoCountdownController.dispose();
    super.dispose();
  }

  Future<void> _fetchDeviceLocation() async {
    if (!mounted) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
      );

      if (mounted) {
        setState(() {
          _deviceLat = position.latitude;
          _deviceLon = position.longitude;
        });
      }
    } catch (e) {
      debugPrint('Failed to get location: $e');
    }
  }

  List<UserModel> _filteredUsers(
    List<UserModel> all,
    UserModel currentUser,
    double minAge,
    double maxAge,
    double maxDistance,
    bool matchIrrespective,
  ) {
    final excluded = _effectiveExcludedIds;
    // Also pull session-unliked IDs from provider so undoes are respected
    final unlikedIds = ref.read(unlikedUserIdsProvider);
    // dislikedUsers is persisted in Firestore — permanent across sessions
    final dislikedUsers = currentUser.dislikedUsers.toSet();
    return all.where((user) {
      // Already followed / liked — never show again
      if (currentUser.following.contains(user.id)) return false;
      // Excluded by algorithm state (skipped, liked, pending, shuffle-pool)
      if (excluded.contains(user.id)) return false;
      // Excluded by session exclusion set (persists across builds)
      if (_sessionExcludedIds.contains(user.id)) return false;
      // Explicitly unliked this session
      if (unlikedIds.contains(user.id)) return false;
      // Permanently disliked (persisted in Firestore)
      if (dislikedUsers.contains(user.id)) return false;
      if (user.age < minAge || user.age > maxAge) return false;

      final distance = LocationHelper.getDistanceKm(
        lat1: _deviceLat,
        lon1: _deviceLon,
        loc1: currentUser.location,
        loc2: user.location,
        id1: currentUser.id,
        id2: user.id,
      );

      if (matchIrrespective) return true;
      return distance <= maxDistance;
    }).toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HeartQueue™ Core: Like / Undo / Confirm / Skip
  // ──────────────────────────────────────────────────────────────────────────

  /// Called when user taps a profile card.
  /// [pairedWith] is the OTHER card shown in the same pair — it will be
  /// temporarily hidden during the 3-second undo window, then permanently
  /// skipped when the window closes. On undo, BOTH are restored.
  Future<void> _onLike(UserModel targetUser, {UserModel? pairedWith}) async {
    final currentUser = ref.read(currentUserProvider);
    final authUid = ref.read(authStateChangesProvider).asData?.value?.uid;
    final currentUserId =
        currentUser.id.isNotEmpty ? currentUser.id : (authUid ?? '');
    if (currentUserId.isEmpty) return;

    final alreadyConfirmed = _confirmedLikedIds.contains(targetUser.id) ||
        currentUser.following.contains(targetUser.id) ||
        currentUser.dislikedUsers.contains(targetUser.id); // permanently disliked
    if (alreadyConfirmed) return;

    // ── Step 1: Commit any prior pending tx (its undo window just closed) ──
    _commitPendingTransaction(animated: false);

    // Tick swipe counter (releases shuffle-back profiles as needed)
    _tickSwipeCounter();

    // ── Step 2: Register new pending transaction ────────────────────────────
    final tx = _LikeTx(
      liked: targetUser,
      pairedWith: pairedWith,
      at: DateTime.now(),
    );

    // ── Step 3: Show undo bar instantly (optimistic UI) ────────────────────
    // Cache profile for Likes history screen immediately
    ref.read(likedUsersCacheProvider.notifier).update((map) => {...map, targetUser.id: targetUser});
    ref.read(sessionLikedUserIdsProvider.notifier).update(
          (list) => [targetUser.id, ...list.where((id) => id != targetUser.id)],
        );

    _undoSlideController.reset();
    _undoCountdownController.reset();
    if (mounted) {
      setState(() {
        _pendingTx = tx;
        _undoUser = targetUser;
        _showUndo = true;
      });
    }
    _undoSlideController.forward();
    _undoCountdownController.forward().then((_) {
      // Timer expired → commit the transaction
      if (mounted && _pendingTx?.liked.id == targetUser.id) {
        _commitPendingTransaction();
      }
    });

    // ── Step 4: Write to Firestore in background ───────────────────────────
    _writeLikeToFirestore(targetUser, currentUserId, currentUser);
  }

  /// Finalises a pending transaction after the undo window closes:
  /// • moves liked user → _confirmedLikedIds (permanent)
  /// • moves paired user → _shuffleBackPool (re-shown after 3–8 swipes)
  void _commitPendingTransaction({bool animated = true}) {
    if (_pendingTx == null) return;
    final tx = _pendingTx!;
    if (mounted) {
      setState(() {
        _confirmedLikedIds.add(tx.liked.id);
        _sessionExcludedIds.add(tx.liked.id); // persist across rebuilds
        if (tx.pairedWith != null) {
          // Schedule the paired profile to reappear after 3–8 more swipes
          final int delay = 3 + Random().nextInt(6);
          _shuffleBackPool[tx.pairedWith!.id] = _swipeCount + delay;
        }
        _pendingTx = null;
        if (!animated) _showUndo = false;
      });
    }
    if (animated) _dismissUndo();
  }

  /// Undo the pending like:
  /// • clears the pending tx → both liked AND paired users return to queue
  /// • reverses Firestore writes
  Future<void> _onUndo() async {
    if (_pendingTx == null) return;
    final tx = _pendingTx!;

    _undoCountdownController.stop();

    // Revert from optimistic session likes
    ref.read(sessionLikedUserIdsProvider.notifier).update(
          (list) => list.where((id) => id != tx.liked.id).toList(),
        );
    ref.read(unlikedUserIdsProvider.notifier).update(
          (set) => {...set, tx.liked.id},
        );

    // If on Soul Mode tab, step card back to the undone profile
    _soulModeKey.currentState?.stepBack();

    // Clear pending → queue filter recalculates, both cards reappear
    if (mounted) setState(() => _pendingTx = null);
    _dismissUndo();

    // Reverse Firestore write
    final currentUser = ref.read(currentUserProvider);
    final authUid = ref.read(authStateChangesProvider).asData?.value?.uid;
    final currentUserId =
        currentUser.id.isNotEmpty ? currentUser.id : (authUid ?? '');
    if (currentUserId.isEmpty) return;

    try {
      final db = firestoreProvider;
      final batch = db.batch();
      batch.update(db.collection('users').doc(currentUserId), {
        'following': FieldValue.arrayRemove([tx.liked.id]),
      });
      batch.update(db.collection('users').doc(tx.liked.id), {
        'followers': FieldValue.arrayRemove([currentUserId]),
        'likedBy': FieldValue.arrayRemove([currentUserId]),
      });
      await batch.commit();
      debugPrint('[HeartQueue] Undo: restored ${tx.liked.name}'
          '${tx.pairedWith != null ? ' + ${tx.pairedWith!.name}' : ''}');
    } catch (e) {
      debugPrint('[HeartQueue] Undo error: $e');
    }
  }

  /// Permanent skip — used by "Show me others" (not undoable).
  void _onSkip(UserModel user) {
    // Commit pending if user skips either card in the active pair
    if (_pendingTx?.pairedWith?.id == user.id ||
        _pendingTx?.liked.id == user.id) {
      _commitPendingTransaction(animated: false);
    }
    // Notify engine (enables quick-skip velocity detection)
    _engine.onSkip(user);
    // Tick swipe counter (releases shuffle-back profiles as needed)
    _tickSwipeCounter();
    setState(() {
      _permanentSkippedIds.add(user.id);
      _sessionExcludedIds.add(user.id); // persist across rebuilds
    });
  }

  /// Async Firestore write (separated for clarity).
  Future<void> _writeLikeToFirestore(
    UserModel targetUser,
    String currentUserId,
    UserModel currentUser,
  ) async {
    // Notify engine about the like (behavioral learning)
    _engine.onLike(targetUser);
    try {
      final db = firestoreProvider;
      final batch = db.batch();
      batch.set(
        db.collection('users').doc(currentUserId),
        {'following': FieldValue.arrayUnion([targetUser.id])},
        SetOptions(merge: true),
      );
      batch.set(
        db.collection('users').doc(targetUser.id),
        {
          'followers': FieldValue.arrayUnion([currentUserId]),
          'likedBy': FieldValue.arrayUnion([currentUserId]),
        },
        SetOptions(merge: true),
      );
      await batch.commit();

      await sendNotification(
        userId: targetUser.id,
        senderId: currentUser.id,
        senderName: currentUser.name,
        senderAvatar: currentUser.avatarUrl,
        type: 'like',
        title: '${currentUser.name} liked you! 💖',
        body: 'Check them out before someone else does!',
      );

      final isMutual = targetUser.following.contains(currentUser.id) ||
          targetUser.likedBy.contains(currentUser.id) ||
          currentUser.likedBy.contains(targetUser.id);

      if (isMutual && mounted) {
        await sendNotification(
          userId: targetUser.id,
          senderId: currentUser.id,
          senderName: currentUser.name,
          senderAvatar: currentUser.avatarUrl,
          type: 'match',
          title: "It's a match! 🎉",
          body: 'You and ${currentUser.name} have matched! Say hello!',
        );
        if (mounted) {
          setState(() {
            _showMatchOverlay = true;
            _matchedUser = targetUser;
          });
        }
      }
    } catch (e) {
      debugPrint('[HeartQueue] Firestore write error: $e');
    }
  }

  void _dismissUndo() {
    _undoSlideController.reverse().then((_) {
      if (mounted) setState(() => _showUndo = false);
    });
  }

  void _dismissMatchOverlay() {
    setState(() {
      _showMatchOverlay = false;
      _matchedUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(matchQueueProvider);
    final currentUser = ref.watch(currentUserProvider);

    final minAge           = ref.watch(filterMinAgeProvider);
    final maxAge           = ref.watch(filterMaxAgeProvider);
    final maxDistance      = ref.watch(filterMaxDistanceProvider);
    final matchIrrespective = ref.watch(filterMatchIrrespectiveProvider);

    // ── Step 1: Basic eligibility filter ───────────────────────────────────────
    final filtered = _filteredUsers(
        users, currentUser, minAge, maxAge, maxDistance, matchIrrespective);

    // ── Step 2: HeartQueue™ smart ranking ────────────────────────────────────
    // Engine scores by: mutual attraction, interests, proximity, age,
    // profile completeness, vibe affinity (learned), online/verified bonuses.
    final ranked = _engine.rankedUsers(
      currentUser: currentUser,
      candidates: filtered,
      deviceLat: _deviceLat,
      deviceLon: _deviceLon,
    );

    // ── Step 3: Curate Discover pair (top-scored + contrasting vibe) ───────
    final curatedPair = _engine.curateDiscoverPair(ranked);
    final discoverList = [
      ...curatedPair,
      ...ranked.where((u) => !curatedPair.any((c) => c.id == u.id)),
    ];

    final likesCount = currentUser.likedBy.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Stack(
        children: [
          const BackgroundOrbs(),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 74),
                  child: Column(
                    children: [
                      _buildHeader(currentUser, isDark),
                      _buildTabBar(likesCount, isDark),
                      const SizedBox(height: 6),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      DiscoverTab(
                        users: discoverList,  // curated pair at top
                        deviceLat: _deviceLat,
                        deviceLon: _deviceLon,
                        onLike: _onLike,
                        onSkip: _onSkip,
                      ),
                      SoulModeTab(
                        key: _soulModeKey,
                        users: ranked,        // engine-ranked
                        onLike: _onLike,
                        onSkip: _onSkip,
                      ),
                      const LikedHistoryScreen(),
                      NearlySoulsTab(
                        users: ranked,        // engine-ranked
                        onLike: _onLike,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),

          // ── Match celebration overlay ─────────────────────────────────
          if (_showMatchOverlay && _matchedUser != null)
            MatchOverlay(
              currentUser: currentUser,
              matchedUser: _matchedUser!,
              onSendMessage: () {
                _dismissMatchOverlay();
                final chatId =
                    'chat_${currentUser.id}_${_matchedUser!.id}';
                context.push('/chats/$chatId', extra: {
                  'name': _matchedUser!.name,
                  'avatarUrl': _matchedUser!.avatarUrl,
                  'isOnline': _matchedUser!.isOnline,
                });
              },
              onDismiss: _dismissMatchOverlay,
            ),

          // ── Undo Like button (3-second animated toast) ────────────────
          if (_showUndo && _undoUser != null)
            Positioned(
              bottom: 90,
              left: 20,
              right: 20,
              child: SlideTransition(
                position: _undoSlideAnim,
                child: _UndoLikeBar(
                  userName: _undoUser!.name,
                  countdownAnim: _undoCountdownAnim,
                  isDark: isDark,
                  onUndo: _onUndo,
                  onDismiss: _dismissUndo,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(UserModel currentUser, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Hearts',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppTheme.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          GestureDetector(
            onTap: _showFilters,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              child: Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: isDark ? Colors.white70 : AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 4-Tab Pill Bar ─────────────────────────────────────────────────────────

  Widget _buildTabBar(int likesCount, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildTabPill(0, 'Discover', isDark),
            const SizedBox(width: 6),
            _buildTabPill(1, 'Soul Mode', isDark),
            const SizedBox(width: 6),
            _buildLikesPill(likesCount, isDark),
            const SizedBox(width: 6),
            _buildTabPill(3, 'Nearly Souls', isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill(int index, String label, bool isDark) {
    final active = _tabController.index == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _tabController.index = index;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
                )
              : null,
          color: active
              ? null
              : (isDark ? const Color(0xFF161228) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? Colors.transparent
                : (isDark
                    ? Colors.white.withValues(alpha: 0.09)
                    : Colors.black.withValues(alpha: 0.08)),
            width: 0.8,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF4F75FF).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  )
                ]
              : [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active
                ? Colors.white
                : (isDark
                    ? Colors.white.withValues(alpha: 0.65)
                    : AppTheme.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildLikesPill(int count, bool isDark) {
    final active = _tabController.index == 2;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _tabController.index = 2;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
                )
              : null,
          color: active
              ? null
              : (isDark ? const Color(0xFF161228) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? Colors.transparent
                : (isDark
                    ? Colors.white.withValues(alpha: 0.09)
                    : Colors.black.withValues(alpha: 0.08)),
            width: 0.8,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: const Color(0xFF4F75FF).withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  )
                ]
              : [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Likes',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active
                    ? Colors.white
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.65)
                        : AppTheme.textSecondary),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.25)
                      : (isDark
                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.30)
                          : const Color(0xFF8B5CF6).withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: active
                        ? Colors.white
                        : (isDark ? const Color(0xFFB8A9FF) : const Color(0xFF6D28D9)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMatchModeToggle() {
    final matchIrrespective = ref.watch(filterMatchIrrespectiveProvider);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(filterMatchIrrespectiveProvider.notifier).state =
            !matchIrrespective;
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              matchIrrespective
                  ? Icons.public_rounded
                  : Icons.location_on_rounded,
              size: 13,
              color: matchIrrespective
                  ? AppTheme.primaryGreen
                  : AppTheme.primaryBlue,
            ),
            const SizedBox(width: 4),
            Text(
              matchIrrespective ? 'Global' : 'Nearby',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filters Sheet ──────────────────────────────────────────────────────────

  void _showFilters() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentMinAge = ref.read(filterMinAgeProvider);
    final currentMaxAge = ref.read(filterMaxAgeProvider);
    final currentMaxDistance = ref.read(filterMaxDistanceProvider);

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        double minAge = currentMinAge;
        double maxAge = currentMaxAge;
        double maxDistance = currentMaxDistance;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Match Filters 🎛️',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Age Range',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : AppTheme.textSecondary)),
                      Text('${minAge.toInt()} - ${maxAge.toInt()}',
                          style: const TextStyle(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  RangeSlider(
                    values: RangeValues(minAge, maxAge),
                    min: 18,
                    max: 65,
                    divisions: 47,
                    activeColor: AppTheme.primaryBlue,
                    inactiveColor:
                        AppTheme.primaryBlue.withValues(alpha: 0.2),
                    onChanged: (values) {
                      setModalState(() {
                        minAge = values.start;
                        maxAge = values.end;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Max Distance',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : AppTheme.textSecondary)),
                      Text('${maxDistance.toInt()} km',
                          style: const TextStyle(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Slider(
                    value: maxDistance,
                    min: 5,
                    max: 100,
                    divisions: 19,
                    activeColor: AppTheme.primaryGreen,
                    inactiveColor:
                        AppTheme.primaryGreen.withValues(alpha: 0.2),
                    onChanged: (value) {
                      setModalState(() => maxDistance = value);
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            ref.read(filterMinAgeProvider.notifier).state =
                                18;
                            ref.read(filterMaxAgeProvider.notifier).state =
                                35;
                            ref
                                .read(filterMaxDistanceProvider.notifier)
                                .state = 50;
                            ref
                                .read(matchQueueProvider.notifier)
                                .applyFilters(
                                  maxDistance: 50,
                                  minAge: 18,
                                  maxAge: 35,
                                );
                            context.pop();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? Colors.white70 : AppTheme.textSecondary,
                            side: BorderSide(
                                color: isDark ? Colors.white24 : Colors.black12, width: 1),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            ref.read(filterMinAgeProvider.notifier).state =
                                minAge;
                            ref.read(filterMaxAgeProvider.notifier).state =
                                maxAge;
                            ref
                                .read(filterMaxDistanceProvider.notifier)
                                .state = maxDistance;
                            ref
                                .read(matchQueueProvider.notifier)
                                .applyFilters(
                                  maxDistance: maxDistance,
                                  minAge: minAge,
                                  maxAge: maxAge,
                                );
                            context.pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Apply Filters',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 16
                          : 0),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Animated Undo Like Bar ───────────────────────────────────────────────────

class _UndoLikeBar extends StatelessWidget {
  final String userName;
  final Animation<double> countdownAnim;
  final bool isDark;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  const _UndoLikeBar({
    required this.userName,
    required this.countdownAnim,
    required this.isDark,
    required this.onUndo,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF181528) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark
                ? const Color(0xFF332B52)
                : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Pulsing heart icon
            _PulsingHeart(),

            const SizedBox(width: 10),

            // Label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Liked!',
                    style: TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Undo button with countdown arc
            GestureDetector(
              onTap: onUndo,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Countdown arc
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: AnimatedBuilder(
                      animation: countdownAnim,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _CountdownArcPainter(
                            progress: countdownAnim.value,
                          ),
                        );
                      },
                    ),
                  ),
                  // Undo label inside arc
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'Undo',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 9.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // Dismiss X button
            GestureDetector(
              onTap: onDismiss,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pulsing Heart ────────────────────────────────────────────────────────────

class _PulsingHeart extends StatefulWidget {
  @override
  State<_PulsingHeart> createState() => _PulsingHeartState();
}

class _PulsingHeartState extends State<_PulsingHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.12).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B9D).withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(
            Icons.favorite_rounded,
            color: Color(0xFFFF6B9D),
            size: 18,
          ),
        ),
      ),
    );
  }
}

// ─── Countdown Arc Painter ────────────────────────────────────────────────────

class _CountdownArcPainter extends CustomPainter {
  final double progress; // 1.0 → full, 0.0 → empty

  _CountdownArcPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Background track
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.white.withValues(alpha: 0.1);
    canvas.drawCircle(center, radius, trackPaint);

    // Countdown arc
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    final sweepAngle = 2 * 3.14159265 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159265 / 2, // start from top
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_CountdownArcPainter old) => old.progress != progress;
}

// ─── HeartQueue™ Transaction Model ───────────────────────────────────────────
//
// Represents a single "like" action that is currently in the 3-second undo
// window. Stores:
//   • [liked]      — the profile that was tapped / liked
//   • [pairedWith] — the other profile shown in the same pair card
//                    (temporarily hidden; permanently skipped on commit,
//                     restored to queue on undo)
//   • [at]         — timestamp, useful for debugging or future expiry logic

class _LikeTx {
  final UserModel liked;
  final UserModel? pairedWith;
  final DateTime at;

  const _LikeTx({
    required this.liked,
    this.pairedWith,
    required this.at,
  });

  @override
  String toString() =>
      '_LikeTx(liked: ${liked.name}, paired: ${pairedWith?.name}, at: $at)';
}
