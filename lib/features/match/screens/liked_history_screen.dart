import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';

// ─── Provider to track locally revealed users (per session + Firestore) ───────
final _revealedUsersProvider = StateProvider<Set<String>>((ref) => {});

class LikedHistoryScreen extends ConsumerStatefulWidget {
  const LikedHistoryScreen({super.key});

  @override
  ConsumerState<LikedHistoryScreen> createState() => _LikedHistoryScreenState();
}

class _LikedHistoryScreenState extends ConsumerState<LikedHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 2, vsync: this);
    _loadRevealedFromFirestore();
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  Future<void> _loadRevealedFromFirestore() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser.id.isEmpty) return;
    try {
      final doc = await firestoreProvider
          .collection('users')
          .doc(currentUser.id)
          .get();
      final data = doc.data();
      if (data != null && data['revealedLikers'] != null) {
        final revealed = Set<String>.from(data['revealedLikers'] as List);
        ref.read(_revealedUsersProvider.notifier).state = revealed;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Sub-tab bar
        _buildSubTabBar(isDark),
        // Sub-tab content
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              _MyLikesTab(),
              _LikedMeTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubTabBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.white.withOpacity(0.40),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.10)
                    : Colors.white.withOpacity(0.70),
                width: 1.0,
              ),
            ),
            child: TabBar(
              controller: _subTabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFFF8E53)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B9D).withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_rounded, size: 15),
                      SizedBox(width: 5),
                      Text('My Likes'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border_rounded, size: 15),
                      SizedBox(width: 5),
                      Text('Liked Me'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Tab 1: My Likes ──────────────────────────────────────────────────────────

class _MyLikesTab extends ConsumerWidget {
  const _MyLikesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final followingIds = currentUser.following;

    if (followingIds.isEmpty) {
      return _buildEmptyState(
        isDark,
        icon: Icons.favorite_border_rounded,
        title: 'No likes yet 💘',
        subtitle: 'Start swiping to find your\nperfect match!',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: followingIds.length,
      itemBuilder: (context, index) {
        return _LikedUserCard(
          userId: followingIds[index],
          currentUserId: currentUser.id,
        );
      },
    );
  }
}

// ─── Tab 2: Liked Me ──────────────────────────────────────────────────────────

class _LikedMeTab extends ConsumerWidget {
  const _LikedMeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final likedByIds = currentUser.likedBy;

    if (likedByIds.isEmpty) {
      return _buildEmptyState(
        isDark,
        icon: Icons.auto_awesome_rounded,
        title: 'No admirers yet ✨',
        subtitle: 'Keep using the app — someone\nwill like you soon!',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: likedByIds.length,
      itemBuilder: (context, index) {
        return _LikedMeCard(
          userId: likedByIds[index],
          currentUser: currentUser,
        );
      },
    );
  }
}

// ─── Blurred "Liked Me" Card ──────────────────────────────────────────────────

class _LikedMeCard extends ConsumerStatefulWidget {
  final String userId;
  final UserModel currentUser;

  const _LikedMeCard({required this.userId, required this.currentUser});

  @override
  ConsumerState<_LikedMeCard> createState() => _LikedMeCardState();
}

class _LikedMeCardState extends ConsumerState<_LikedMeCard> {
  bool _isRevealing = false;

  bool get _isRevealedBySwipe =>
      widget.currentUser.following.contains(widget.userId);

  bool get _isRevealedByCoins =>
      ref.watch(_revealedUsersProvider).contains(widget.userId);

  bool get _isRevealed => _isRevealedBySwipe || _isRevealedByCoins;

  Future<void> _revealWithCoins() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentCoins = widget.currentUser.coins;

    if (currentCoins < 10) {
      // Not enough coins
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Text('🪙', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text(
                'Not enough coins! Need 10 coins to reveal.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // Confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDark ? const Color(0xFF1A1035) : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Text('🪙', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text(
              'Reveal Profile',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'Spend 10 coins to reveal who liked you?\n\nYou currently have ${widget.currentUser.coins} coins.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
            ),
          ),
          ElevatedButton(
            onPressed: () => ctx.pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B9D),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Reveal for 10 🪙',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isRevealing = true);

    try {
      final success = await ref.read(socialProvider.notifier).spendCoins(
            userId: widget.currentUser.id,
            amount: 10,
          );

      if (!mounted) return;

      if (success) {
        // Save reveal to Firestore so it persists
        await firestoreProvider
            .collection('users')
            .doc(widget.currentUser.id)
            .update({
          'revealedLikers': FieldValue.arrayUnion([widget.userId]),
        });

        // Update local state
        final current = ref.read(_revealedUsersProvider);
        ref.read(_revealedUsersProvider.notifier).state = {
          ...current,
          widget.userId
        };

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Text('✨', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'Profile revealed! Go say hi 💘',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFFF6B9D),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Not enough coins! 🪙'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isRevealing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userAsync = ref.watch(otherUserProvider(widget.userId));

    return userAsync.when(
      loading: () => _buildShimmer(isDark),
      error: (_, __) => const SizedBox.shrink(),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return _isRevealed
            ? _buildRevealedCard(context, user, isDark)
            : _buildBlurredCard(context, user, isDark);
      },
    );
  }

  Widget _buildBlurredCard(
      BuildContext context, UserModel user, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(isDark ? 0.16 : 0.60),
            Colors.white.withOpacity(isDark ? 0.04 : 0.20),
          ],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A1035).withOpacity(0.55)
                    : Colors.white.withOpacity(0.50),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFFFF6B9D).withOpacity(0.20)
                      : const Color(0xFFFF6B9D).withOpacity(0.30),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  // Blurred avatar
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: ImageFiltered(
                          imageFilter:
                              ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                          child: user.avatarUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: user.avatarUrl!,
                                  width: 62,
                                  height: 62,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 186,
                                  errorWidget: (_, __, ___) =>
                                      _blurFallback(isDark),
                                )
                              : _blurFallback(isDark),
                        ),
                      ),
                      // Heart overlay on avatar
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B9D).withOpacity(0.25),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Blurred info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Blurred name
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ImageFiltered(
                            imageFilter:
                                ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Text(
                              '${user.name}, ${user.age}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1035),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Blurred location
                        if (user.location != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: ImageFiltered(
                              imageFilter:
                                  ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                              child: Text(
                                user.location ?? '',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        // Reveal buttons
                        Row(
                          children: [
                            // Coin reveal button
                            Expanded(
                              child: GestureDetector(
                                onTap: _isRevealing ? null : _revealWithCoins,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 10),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFF6B9D),
                                        Color(0xFFFF8E53),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFFF6B9D)
                                            .withOpacity(0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: _isRevealing
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text('🪙',
                                                style:
                                                    TextStyle(fontSize: 13)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Reveal (10)',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Hint text
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 11,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.black38,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Or swipe right on them by luck to reveal free!',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildRevealedCard(
      BuildContext context, UserModel user, bool isDark) {
    return GestureDetector(
      onTap: () => context.push('/profile/view/${user.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(isDark ? 0.18 : 0.65),
              Colors.white.withOpacity(isDark ? 0.04 : 0.20),
            ],
          ),
        ),
        child: Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6B9D).withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1A1035).withOpacity(0.55)
                      : Colors.white.withOpacity(0.50),
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(
                    color: const Color(0xFFFF6B9D).withOpacity(0.30),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFFF6B9D).withOpacity(0.6),
                              width: 2.0,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: user.avatarUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: user.avatarUrl!,
                                    width: 62,
                                    height: 62,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 186,
                                    errorWidget: (_, __, ___) =>
                                        _blurFallback(isDark),
                                  )
                                : _blurFallback(isDark),
                          ),
                        ),
                        if (user.isOnline)
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGreen,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF1A1035)
                                      : Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${user.name}, ${user.age}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1A1035),
                                    letterSpacing: -0.3,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // "Liked You" badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFF6B9D),
                                      Color(0xFFFF8E53),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.favorite_rounded,
                                        size: 10, color: Colors.white),
                                    SizedBox(width: 3),
                                    Text(
                                      'LIKED YOU',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (user.location != null &&
                              user.location!.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.location_on_rounded,
                                    size: 13,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    user.location!,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black54,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          if (user.bio != null && user.bio!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              user.bio!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.black45,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (user.interests.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: user.interests
                                  .take(3)
                                  .map((interest) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6B9D)
                                              .withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: const Color(0xFFFF6B9D)
                                                .withOpacity(0.30),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          interest,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Color(0xFFFF6B9D),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // View Profile arrow
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B9D).withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFF6B9D).withOpacity(0.30),
                          width: 1.0,
                        ),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Color(0xFFFF6B9D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _blurFallback(bool isDark) {
    return Container(
      width: 62,
      height: 62,
      color: isDark ? Colors.white10 : Colors.black12,
      child: const Icon(Icons.person_rounded,
          size: 28, color: Colors.white54),
    );
  }

  Widget _buildShimmer(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7),
      height: 90,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(23),
      ),
    );
  }
}

// ─── My Likes Card ────────────────────────────────────────────────────────────

class _LikedUserCard extends ConsumerWidget {
  final String userId;
  final String currentUserId;

  const _LikedUserCard({required this.userId, required this.currentUserId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userAsync = ref.watch(otherUserProvider(userId));

    return userAsync.when(
      loading: () => Container(
        margin: const EdgeInsets.symmetric(vertical: 7),
        height: 90,
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(23),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        final isMatch = user.following.contains(currentUserId);

        return GestureDetector(
          onTap: () => context.push('/profile/view/${user.id}'),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(isDark ? 0.16 : 0.60),
                  Colors.white.withOpacity(isDark ? 0.04 : 0.20),
                ],
              ),
            ),
            child: Container(
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                boxShadow: [
                  BoxShadow(
                    color: (isMatch
                            ? const Color(0xFFFF6B9D)
                            : AppTheme.primaryBlue)
                        .withOpacity(0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(23),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A1035).withOpacity(0.55)
                          : Colors.white.withOpacity(0.50),
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.10)
                            : Colors.white.withOpacity(0.75),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isMatch
                                      ? const Color(0xFFFF6B9D)
                                          .withOpacity(0.7)
                                      : AppTheme.primaryBlue.withOpacity(0.4),
                                  width: 2.0,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: user.avatarUrl != null
                                    ? Image.network(
                                        user.avatarUrl!,
                                        width: 62,
                                        height: 62,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _avatarFallback(user, isDark),
                                      )
                                    : _avatarFallback(user, isDark),
                              ),
                            ),
                            if (user.isOnline)
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF1A1035)
                                          : Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${user.name}, ${user.age}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF1A1035),
                                        letterSpacing: -0.3,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isMatch)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFFFF6B9D),
                                            Color(0xFFFF8E53),
                                          ],
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.favorite_rounded,
                                              size: 10, color: Colors.white),
                                          SizedBox(width: 3),
                                          Text(
                                            'MATCH',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (user.location != null &&
                                  user.location!.isNotEmpty)
                                Row(
                                  children: [
                                    Icon(Icons.location_on_rounded,
                                        size: 13,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45),
                                    const SizedBox(width: 3),
                                    Expanded(
                                      child: Text(
                                        user.location!,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.black54,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              if (user.bio != null &&
                                  user.bio!.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  user.bio!,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (user.interests.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 5,
                                  runSpacing: 4,
                                  children: user.interests
                                      .take(3)
                                      .map(
                                        (interest) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryBlue
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: AppTheme.primaryBlue
                                                  .withOpacity(0.25),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            interest,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: AppTheme.primaryBlue,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Unlike button
                        GestureDetector(
                          onTap: () async {
                            HapticFeedback.lightImpact();
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: isDark
                                    ? const Color(0xFF1A1035)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                                title: Text(
                                  'Unlike ${user.name}?',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87),
                                ),
                                content: Text(
                                  'They will be removed from your liked list.',
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.black54),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => ctx.pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => ctx.pop(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                    child: const Text('Unlike',
                                        style:
                                            TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ref
                                  .read(socialProvider.notifier)
                                  .toggleFollow(
                                    currentUserId: currentUserId,
                                    targetUserId: user.id,
                                    isCurrentlyFollowing: true,
                                  );
                            }
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.10),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.redAccent.withOpacity(0.25),
                                width: 1.0,
                              ),
                            ),
                            child: const Icon(
                              Icons.heart_broken_rounded,
                              size: 20,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _avatarFallback(UserModel user, bool isDark) {
    return Container(
      width: 62,
      height: 62,
      color: isDark ? Colors.white10 : Colors.black12,
      child: Center(
        child: Text(
          user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
          style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white),
        ),
      ),
    );
  }
}

// ─── Shared empty state helper ────────────────────────────────────────────────

Widget _buildEmptyState(
  bool isDark, {
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                const Color(0xFFFF6B9D).withOpacity(0.15),
                AppTheme.primaryBlue.withOpacity(0.15),
              ],
            ),
          ),
          child: Icon(icon, size: 44, color: const Color(0xFFFF6B9D)),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white60 : Colors.black54,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}
