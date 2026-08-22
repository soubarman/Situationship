import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/models/post_model.dart';
import '../../../core/models/user_model.dart';
import '../../verification/presentation/widgets/s_badge_widget.dart';
import '../../../core/providers/firebase_auth_provider.dart';
import '../../feed/widgets/post_card.dart';
import '../../../shared/widgets/background_orbs.dart';
import '../../wallet/widgets/coin_gate_sheet.dart';
import '../../../shared/widgets/profile_choice_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringAnim;

  @override
  void initState() {
    super.initState();
    _ringAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ringAnim.dispose();
    super.dispose();
  }

  void _handleLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkSurface
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout 🚪', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to log out? We\'ll miss you! ✨'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authControllerProvider.notifier).signOut();
              context.go('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingShimmer(bool isDark) {
    return Scaffold(
      body: Shimmer.fromColors(
        baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 100),
              Center(
                child: Container(
                  width: 108,
                  height: 108,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 120,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 80,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userDataAsync = ref.watch(userDataStreamProvider);
    final user = ref.watch(currentUserProvider);

    final streamPosts = ref.watch(postsPaginationProvider).asData?.value ?? [];
    final localPosts = ref.watch(postsProvider);
    final List<PostModel> posts = [];
    final Set<String> seenIds = {};
    for (var p in [...localPosts, ...streamPosts]) {
      if (!seenIds.contains(p.id) && p.userId == user.id) {
        posts.add(p);
        seenIds.add(p.id);
      }
    }
    posts.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (userDataAsync.isLoading) {
      return _buildLoadingShimmer(isDark);
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          const BackgroundOrbs(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header with rotating avatar ring & action buttons
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
                    child: _buildGlassHeader(context, user, isDark),
                  ),
                ),
              ),

              // Animated Glass Stats Row
              SliverToBoxAdapter(
                child: _buildStats(user, posts.length, context, isDark),
              ),

              // Profile Visitors section
              SliverToBoxAdapter(
                child: _buildVisitorsCard(context, user, isDark),
              ),

              // About Me & Traits section
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBio(user, context, isDark),
                    _buildInterests(user, context, isDark),
                    _buildGridHeader(context, isDark, posts.length),
                  ],
                ),
              ),

              _buildPostsGrid(posts, context, isDark),
              SliverPadding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 120)),
            ],
          ),

          // Custom Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.black.withOpacity(0.4) : Colors.white.withOpacity(0.6),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                ),
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: isDark ? Colors.white : Colors.black87),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/feed');
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── GLASS HEADER WITH ROTATING RING ───────────────────────────────────────
  Widget _buildGlassHeader(BuildContext context, UserModel user, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar with animated rotating rainbow gradient ring
        GestureDetector(
          onTap: () => ProfileChoiceSheet.show(context, user, isDark),
          child: AnimatedBuilder(
            animation: _ringAnim,
            builder: (_, __) {
              return SizedBox(
                width: 124,
                height: 124,
                child: CustomPaint(
                  painter: _AvatarRingPainter(
                    angle: _ringAnim.value * 2 * math.pi,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4.5),
                    child: ClipOval(
                      child: Image.network(
                        user.avatarUrl ??
                            'https://ui-avatars.com/api/?name=${Uri.encodeComponent(user.name)}&size=200&background=6ECBF5&color=fff&rounded=true',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 50),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 18),

        // Name, Location, Action Buttons
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      user.name,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (user.isVerified) ...[
                    const SizedBox(width: 6),
                    const SBadgeWidget(size: 22),
                  ],
                ],
              ),
              if (user.location != null && user.location!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFFFF3CAC)),
                      const SizedBox(width: 4),
                      Text(
                        user.location!,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Action Buttons Row
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Edit Profile — icon only
                  _buildIconButton(
                    icon: Icons.edit_rounded,
                    gradientColors: const [Color(0xFFFF3CAC), Color(0xFF7C3AED)],
                    onTap: () => context.push('/profile/edit'),
                  isDark: isDark,
                  ),
                  const SizedBox(width: 8),

                  // View Public Button
                  _buildIconButton(
                    icon: Icons.remove_red_eye_rounded,
                    gradientColors: [const Color(0xFF00C6FF), const Color(0xFF0072FF)],
                    onTap: () => ProfileChoiceSheet.show(context, user, isDark),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),

                  // Settings Button
                  _buildIconButton(
                    icon: Icons.settings_rounded,
                    gradientColors: isDark
                        ? [Colors.white24, Colors.white10]
                        : [Colors.black12, Colors.black26],
                    onTap: () => _showSettingsSheet(context),
                    isDark: isDark,
                  ),

                  if (!user.isVerified) ...[
                    const SizedBox(width: 8),
                    _buildIconButton(
                      icon: Icons.verified_user_rounded,
                      gradientColors: [const Color(0xFFA855F7), const Color(0xFF6366F1)],
                      onTap: () => context.push('/verification'),
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required List<Color> gradientColors,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(colors: gradientColors),
          border: Border.all(
            color: Colors.white.withOpacity(0.25),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SettingsSheet(ref: ref),
    );
  }

  // ─── STATS CARD ─────────────────────────────────────────────────────────────
  Widget _buildStats(UserModel user, int postCount, BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF2A1B40).withOpacity(0.7), const Color(0xFF161026).withOpacity(0.7)]
                    : [Colors.white.withOpacity(0.9), const Color(0xFFF3E8FF).withOpacity(0.8)],
              ),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isDark ? const Color(0xFF9333EA).withOpacity(0.35) : const Color(0xFF9333EA).withOpacity(0.2),
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF9333EA).withOpacity(isDark ? 0.2 : 0.08),
                  blurRadius: 20,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(
                  icon: Icons.people_alt_rounded,
                  label: 'Followers',
                  value: '${user.followers.length}',
                  color: const Color(0xFF00C6FF),
                  isDark: isDark,
                ),
                _Divider(isDark: isDark),
                _StatItem(
                  icon: Icons.favorite_rounded,
                  label: 'Likes',
                  value: '${user.likedBy.length}',
                  color: const Color(0xFFFF3CAC),
                  isDark: isDark,
                ),
                _Divider(isDark: isDark),
                _StatItem(
                  icon: Icons.photo_library_rounded,
                  label: 'Posts',
                  value: '$postCount',
                  color: const Color(0xFFFF8C42),
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── PROFILE VISITORS CARD ──────────────────────────────────────────────────
  Widget _buildVisitorsCard(BuildContext context, UserModel currentUser, bool isDark) {
    final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('profile_views').where('targetId', isEqualTo: currentUser.id).snapshots(),
      builder: (context, snapshot) {
        final allDocs = snapshot.hasData ? snapshot.data!.docs : [];
        final sortedDocs = allDocs.toList()
          ..sort((a, b) {
            final aTime = a.data()['viewedAt'] as int? ?? 0;
            final bTime = b.data()['viewedAt'] as int? ?? 0;
            return bTime.compareTo(aTime);
          });

        final Map<String, dynamic> uniqueVisitors = {};
        for (var doc in sortedDocs) {
          final visitorId = doc.data()['viewerId'] as String? ?? '';
          if (!uniqueVisitors.containsKey(visitorId)) {
            uniqueVisitors[visitorId] = doc;
          }
        }
        final docs = uniqueVisitors.values.toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF231638).withOpacity(0.85), const Color(0xFF140C24).withOpacity(0.85)]
                        : [Colors.white.withOpacity(0.95), const Color(0xFFF3E8FF).withOpacity(0.9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFFA855F7).withOpacity(isDark ? 0.35 : 0.2),
                    width: 1.3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFA855F7).withOpacity(isDark ? 0.18 : 0.08),
                      blurRadius: 20,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFA855F7), Color(0xFF6366F1)],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('👻', style: TextStyle(fontSize: 14)),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Profile Visitors',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (docs.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${docs.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.arrow_forward_ios_rounded, size: 15, color: isDark ? Colors.white60 : Colors.black54),
                          onPressed: () => context.push('/profile/visitors'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    if (docs.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'No profile views yet! 👻\n(Views by other users will appear here)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: docs.length > 3 ? 3 : docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final visitorId = data['viewerId'] as String;
                          final visitorName = data['viewerName'] as String? ?? 'User';
                          final visitorAvatar = data['viewerAvatar'] as String?;

                          final isUnlocked = currentUser.hasActiveSubscription || currentUser.unlockedVisitors.contains(visitorId);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: (isUnlocked && visitorId.isNotEmpty)
                                  ? () => ProfileChoiceSheet.navigateToProfile(context, ref, visitorId)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 19,
                                      backgroundImage: NetworkImage(
                                        isUnlocked
                                            ? (visitorAvatar ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(visitorName)}')
                                            : 'https://ui-avatars.com/api/?name=%3F&background=3B0764&color=fff',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        isUnlocked ? visitorName : 'Ghost Visitor 👻',
                                        style: TextStyle(
                                          color: isDark ? Colors.white : Colors.black87,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (!isUnlocked)
                                      GestureDetector(
                                        onTap: () => _unlockGhostView(context, ref, currentUser, visitorId),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                                            ),
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF00C6FF).withOpacity(0.3),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.lock_open_rounded, size: 13, color: Colors.white),
                                              SizedBox(width: 4),
                                              Text(
                                                'Unlock',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else
                                      Icon(Icons.arrow_forward_ios_rounded, color: isDark ? Colors.white38 : Colors.black38, size: 13),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _unlockGhostView(BuildContext context, WidgetRef ref, UserModel currentUser, String visitorId) async {
    final allowed = await showCoinGate(context, ref, 'undo_ghost');
    if (!allowed) return;

    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

      await db.runTransaction((tx) async {
        final userRef = db.collection('users').doc(currentUser.id);
        final snap = await tx.get(userRef);
        if (!snap.exists) return;

        final unlocked = List<String>.from(snap.data()?['unlockedVisitors'] ?? []);
        if (!unlocked.contains(visitorId)) {
          unlocked.add(visitorId);
        }

        tx.update(userRef, {'unlockedVisitors': unlocked});
      });
    } catch (e) {
      debugPrint('Error unlocking ghost view: $e');
    }
  }

  // ─── ABOUT ME & TRAITS ──────────────────────────────────────────────────────
  Widget _buildBio(UserModel user, BuildContext context, bool isDark) {
    if (user.bio == null || user.bio!.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF3CAC), Color(0xFFFF8C42)],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ABOUT ME',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: isDark ? const Color(0xFFC084FC) : const Color(0xFF7C3AED),
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                user.bio!,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white.withOpacity(0.92) : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInterests(UserModel user, BuildContext context, bool isDark) {
    if (user.interests == null || user.interests!.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 10,
        children: user.interests!.map((interest) {
          final label = interest.toString();
          final icon = _getInterestIcon(label);
          const color = Color(0xFF9333EA);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: color.withOpacity(isDark ? 0.35 : 0.2),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF5B21B6),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getInterestIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('music')) return '🎵';
    if (l.contains('movie')) return '🎬';
    if (l.contains('book')) return '📚';
    if (l.contains('travel')) return '✈️';
    if (l.contains('food')) return '🍔';
    if (l.contains('fitness')) return '🏋️';
    if (l.contains('game') || l.contains('gaming')) return '🎮';
    if (l.contains('pet') || l.contains('cat') || l.contains('dog')) return '🐾';
    if (l.contains('dance')) return '💃';
    if (l.contains('art')) return '🎨';
    return '✨';
  }

  Widget _buildGridHeader(BuildContext context, bool isDark, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF3CAC), Color(0xFFFF8C42)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.photo_library_rounded, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            'Photos & Videos',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF3CAC), Color(0xFFFF8C42)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── POSTS GRID ─────────────────────────────────────────────────────────────
  SliverPadding _buildPostsGrid(List<PostModel> posts, BuildContext context, bool isDark) {
    if (posts.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        sliver: SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
              ),
            ),
            child: Column(
              children: [
                const Icon(Icons.photo_camera_outlined, size: 40, color: Colors.white38),
                const SizedBox(height: 10),
                Text(
                  'No photos uploaded yet 📸',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.82,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = posts[index];
            final mediaUrl = post.imageUrl ?? '';

            return GestureDetector(
              onTap: () => _showPostDetail(context, post, posts),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                      width: 1.2,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (mediaUrl.isNotEmpty)
                        Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: isDark ? Colors.white10 : Colors.black12,
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 28),
                            ),
                          ),
                        )
                      else if (post.mood != null)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [const Color(0xFFFF3CAC).withOpacity(0.3), const Color(0xFF7C3AED).withOpacity(0.3)],
                            ),
                          ),
                          child: Center(
                            child: Text(post.mood!, style: const TextStyle(fontSize: 32)),
                          ),
                        )
                      else
                        Container(
                          color: isDark ? Colors.white10 : Colors.black12,
                          child: const Center(child: Text('✨', style: TextStyle(fontSize: 32))),
                        ),

                      // Bottom gradient scrim with likes
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 50,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.67)],
                              ),
                            ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.favorite_rounded, size: 14, color: Colors.redAccent),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${post.likes.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.chat_bubble_rounded, size: 13, color: Colors.white70),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${post.commentCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: posts.length,
        ),
      ),
    );
  }

  void _showPostDetail(BuildContext context, PostModel post, List<PostModel> posts) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkBg : AppTheme.lightBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Scaffold(
            body: PostCard(
              post: post,
              onLike: () {},
            ),
          ),
        ),
      ),
    );
  }
}

// ─── ROTATING AVATAR RING PAINTER ────────────────────────────────────────────
class _AvatarRingPainter extends CustomPainter {
  final double angle;
  const _AvatarRingPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawOval(rect, bgPaint);

    final gradient = SweepGradient(
      startAngle: angle,
      endAngle: angle + math.pi * 2,
      colors: const [
        Color(0xFFFF3CAC),
        Color(0xFFFF8C42),
        Color(0xFFFFE44D),
        Color(0xFF00C6FF),
        Color(0xFF7C3AED),
        Color(0xFFFF3CAC),
      ],
    );

    final ringPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(rect, ringPaint);
  }

  @override
  bool shouldRepaint(_AvatarRingPainter old) => old.angle != angle;
}

// ─── HELPER STAT ITEM ────────────────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;

  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      width: 1.2,
      color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.1),
    );
  }
}

// ─── SETTINGS SHEET ──────────────────────────────────────────────────────────
class _SettingsSheet extends StatelessWidget {
  final WidgetRef ref;

  const _SettingsSheet({required this.ref});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Settings & Preferences ⚙️',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Appearance Theme',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _themeOption(
                  context,
                  mode: ThemeMode.system,
                  label: 'System',
                  icon: Icons.brightness_auto_rounded,
                  isSelected: themeMode == ThemeMode.system,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _themeOption(
                  context,
                  mode: ThemeMode.light,
                  label: 'Light',
                  icon: Icons.light_mode_rounded,
                  isSelected: themeMode == ThemeMode.light,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _themeOption(
                  context,
                  mode: ThemeMode.dark,
                  label: 'Dark',
                  icon: Icons.dark_mode_rounded,
                  isSelected: themeMode == ThemeMode.dark,
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(authControllerProvider.notifier).signOut();
                context.go('/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Logout 🚪', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _themeOption(
    BuildContext context, {
    required ThemeMode mode,
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
  }) {
    const activeColor = Color(0xFF9333EA);
    return GestureDetector(
      onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withOpacity(0.15)
              : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeColor : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: isSelected ? activeColor : (isDark ? Colors.white60 : Colors.black54)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
