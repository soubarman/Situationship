import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/models/post_model.dart';
import '../../../core/models/user_model.dart';
import '../../verification/presentation/widgets/s_badge_widget.dart';
import '../../../core/providers/firebase_auth_provider.dart';
import '../../feed/widgets/post_card.dart';
import '../../../shared/widgets/background_orbs.dart';
import '../../wallet/widgets/coin_gate_sheet.dart';
import '../../../core/utils/image_url_helper.dart';
import '../../../shared/widgets/profile_choice_sheet.dart';
import '../../../shared/widgets/situationship_logo.dart';

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
    final palette = ref.watch(appPaletteProvider);

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
              // Sticky Frosted Glass AppBar
              _buildTopAppBar(context, isDark),

              // Profile Identity Hero Card
              SliverToBoxAdapter(
                child: _buildProfileHero(context, user, isDark, palette),
              ),

              // 3D Glass Stats Row
              SliverToBoxAdapter(
                child: _buildStats(user, posts.length, context, isDark, palette),
              ),

              // Profile Visitors section
              SliverToBoxAdapter(
                child: _buildVisitorsCard(context, user, isDark, palette),
              ),

              // About Me & Traits section
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBio(user, context, isDark, palette),
                    _buildInterests(user, context, isDark, palette),
                    _buildGridHeader(context, isDark, posts.length, palette),
                  ],
                ),
              ),

              _buildPostsGrid(posts, context, isDark),
              SliverPadding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 120)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── STICKY TOP APP BAR ─────────────────────────────────────────────────────
  Widget _buildTopAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: (isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC)).withOpacity(0.85),
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Center(
          child: _buildGlassCircleBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/feed');
              }
            },
            isDark: isDark,
          ),
        ),
      ),
      centerTitle: true,
      title: SituationshipLogo(
        fontSize: 20,
        isDark: isDark,
        showTrademark: true,
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Center(
            child: _buildGlassCircleBtn(
              icon: Icons.settings_rounded,
              onTap: () => _showSettingsSheet(context),
              isDark: isDark,
            ),
          ),
        ),
      ],
    );
  }

  // ─── LUXURY PROFILE HERO CARD ───────────────────────────────────────────────
  Widget _buildProfileHero(BuildContext context, UserModel user, bool isDark, AppPalette palette) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161226).withOpacity(0.88) : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark ? const Color(0xFF9B5DE5).withOpacity(0.28) : const Color(0xFFD4C1FF).withOpacity(0.85),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9B5DE5).withOpacity(isDark ? 0.22 : 0.08),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar + Outer Ambient Glow + Rotating Ring
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ambient halo
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: palette.primary.withOpacity(isDark ? 0.45 : 0.25),
                        blurRadius: 26,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                // Rotating neon gradient ring
                AnimatedBuilder(
                  animation: _ringAnim,
                  builder: (_, __) {
                    return SizedBox(
                      width: 106,
                      height: 106,
                      child: CustomPaint(
                        painter: _AvatarRingPainter(
                          angle: _ringAnim.value * 2 * math.pi,
                          palette: palette,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: GestureDetector(
                            onTap: () => ProfileChoiceSheet.show(context, user, isDark),
                            child: ClipOval(
                              child: Image.network(
                                ImageUrlHelper.proxy(user.avatarUrl ??
                                    'https://ui-avatars.com/api/?name=${Uri.encodeComponent(user.name)}&size=200&background=6ECBF5&color=fff&rounded=true'),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 44),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Verified S-Badge overlay on avatar
                if (user.isReallyVerified)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const SBadgeWidget(size: 24),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // User Name
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  user.name,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF1E1B2E),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              if (user.isReallyVerified) ...[
                const SizedBox(width: 6),
                const SBadgeWidget(size: 22),
              ],
            ],
          ),

          // Location badge
          if (user.location != null && user.location!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: palette.primary.withOpacity(isDark ? 0.16 : 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: palette.primary.withOpacity(isDark ? 0.3 : 0.18),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_rounded, size: 13, color: palette.primary),
                  const SizedBox(width: 5),
                  Text(
                    user.location!,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF4A4458),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          // Action Buttons: Edit Profile (Primary) & View as Visitor (Secondary)
          Row(
            children: [
              Expanded(
                child: _BouncingButton(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.push('/profile/edit');
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [palette.primary, palette.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: palette.primary.withOpacity(0.45),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_rounded, color: Colors.white, size: 17),
                        SizedBox(width: 8),
                        Text(
                          'Edit Profile',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BouncingButton(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ProfileChoiceSheet.show(context, user, isDark);
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFD4C1FF),
                        width: 1.3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.visibility_rounded,
                          size: 17,
                          color: isDark ? Colors.white : palette.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Visitor View',
                          style: TextStyle(
                            color: isDark ? Colors.white : palette.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // If not verified, add a subtle VIP banner to get verified
          if (!user.isReallyVerified) ...[
            const SizedBox(height: 12),
            _BouncingButton(
              onTap: () {
                HapticFeedback.lightImpact();
                context.push('/verification');
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6C63FF).withOpacity(0.15),
                      const Color(0xFFFF6584).withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF6C63FF).withOpacity(0.35),
                    width: 1.2,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('🛡️', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 8),
                    Text(
                      'Get Verified Profile Badge',
                      style: TextStyle(
                        color: Color(0xFFB06EF5),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(width: 5),
                    Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFFB06EF5)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── GLASS CIRCLE BUTTON ───────────────────────────────────────────────────
  Widget _buildGlassCircleBtn({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return _BouncingButton(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08),
                width: 1.2,
              ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: isDark ? Colors.white : const Color(0xFF1E1B2E),
            ),
          ),
        ),
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

  // ─── 3D GLASS STATS ROW ─────────────────────────────────────────────────────
  Widget _buildStats(UserModel user, int postCount, BuildContext context, bool isDark, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _buildStatCard(
            value: '${user.followers.length}',
            label: 'Followers',
            icon: Icons.people_alt_rounded,
            gradientColors: const [Color(0xFF9B5DE5), Color(0xFF6C63FF)],
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          _buildStatCard(
            value: '${user.likedBy.length}',
            label: 'Likes',
            icon: Icons.favorite_rounded,
            gradientColors: const [Color(0xFFFF416C), Color(0xFFFF4B2B)],
            isDark: isDark,
          ),
          const SizedBox(width: 10),
          _buildStatCard(
            value: '$postCount',
            label: 'Posts',
            icon: Icons.photo_library_rounded,
            gradientColors: const [Color(0xFF36D1DC), Color(0xFF5B86E5)],
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String value,
    required String label,
    required IconData icon,
    required List<Color> gradientColors,
    required bool isDark,
  }) {
    return Expanded(
      child: _BouncingButton(
        onTap: () => HapticFeedback.lightImpact(),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors.map((c) => c.withOpacity(isDark ? 0.22 : 0.12)).toList(),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: gradientColors.first.withOpacity(isDark ? 0.35 : 0.25),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withOpacity(isDark ? 0.15 : 0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: gradientColors.first),
              const SizedBox(height: 6),
              ShaderMask(
                shaderCallback: (b) => LinearGradient(
                  colors: gradientColors,
                ).createShader(b),
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white60 : Colors.black54,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── PROFILE VISITORS CARD ──────────────────────────────────────────────────
  Widget _buildVisitorsCard(BuildContext context, UserModel currentUser, bool isDark, AppPalette palette) {
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E1433).withOpacity(0.92), const Color(0xFF120B20).withOpacity(0.92)]
                    : [Colors.white.withOpacity(0.95), const Color(0xFFF6F0FF).withOpacity(0.95)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark ? const Color(0xFF9B5DE5).withOpacity(0.3) : const Color(0xFFD4C1FF).withOpacity(0.7),
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF9B5DE5).withOpacity(isDark ? 0.16 : 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF9B5DE5), Color(0xFFFF5069)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF9B5DE5).withOpacity(0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Text('👻', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Profile Visitors',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                if (docs.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF9B5DE5), Color(0xFFFF5069)],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
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
                            const SizedBox(height: 2),
                            Text(
                              docs.isEmpty ? 'No recent visits' : 'Who checked out your vibe',
                              style: TextStyle(
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    _BouncingButton(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.push('/profile/visitors');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.06),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'See all',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (docs.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                              shape: BoxShape.circle,
                            ),
                            child: const Text('✨', style: TextStyle(fontSize: 26)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No profile views yet',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'When someone views your profile, they will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? Colors.white38 : Colors.black45,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: docs.length > 3 ? 3 : docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final visitorId = data['viewerId'] as String;
                      final visitorName = data['viewerName'] as String? ?? 'User';
                      final visitorAvatar = data['viewerAvatar'] as String?;

                      final isUnlocked = currentUser.hasActiveSubscription || currentUser.unlockedVisitors.contains(visitorId);

                      return _BouncingButton(
                        onTap: (isUnlocked && visitorId.isNotEmpty)
                            ? () {
                                HapticFeedback.lightImpact();
                                ProfileChoiceSheet.navigateToProfile(context, ref, visitorId);
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF160F26).withOpacity(0.65) : Colors.white.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark ? const Color(0xFF9B5DE5).withOpacity(0.18) : const Color(0xFFE9D5FF).withOpacity(0.6),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              if (isUnlocked)
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF9B5DE5).withOpacity(0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: Image.network(
                                      ImageUrlHelper.proxy(visitorAvatar ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(visitorName)}'),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white60, size: 22),
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const RadialGradient(
                                      colors: [Color(0xFF7928CA), Color(0xFF3B0764)],
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFFF5069).withOpacity(0.4),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF7928CA).withOpacity(0.35),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Text('👻', style: TextStyle(fontSize: 20)),
                                  ),
                                ),
                              const SizedBox(width: 12),
                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isUnlocked ? visitorName : 'Ghost Visitor 👻',
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black87,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isUnlocked ? 'View profile' : 'Secret admirer • Tap to reveal',
                                      style: TextStyle(
                                        color: isUnlocked
                                            ? (isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED))
                                            : (isDark ? Colors.white54 : Colors.black45),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Action button
                              if (!isUnlocked)
                                _BouncingButton(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _unlockGhostView(context, ref, currentUser, visitorId);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFF5069), Color(0xFF9B5DE5)],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFF5069).withOpacity(0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.lock_open_rounded, size: 12, color: Colors.white),
                                        SizedBox(width: 5),
                                        Text(
                                          'Unlock',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 12,
                                    color: isDark ? Colors.white60 : Colors.black45,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
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
  Widget _buildBio(UserModel user, BuildContext context, bool isDark, AppPalette palette) {
    if (user.bio == null || user.bio!.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161026).withOpacity(0.85) : Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: isDark ? const Color(0xFF9B5DE5).withOpacity(0.24) : const Color(0xFFD4C1FF).withOpacity(0.7),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9B5DE5).withOpacity(isDark ? 0.12 : 0.05),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9B5DE5), Color(0xFFFF5069)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ABOUT ME',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text('✨', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              user.bio!,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white.withOpacity(0.92) : const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInterests(UserModel user, BuildContext context, bool isDark, AppPalette palette) {
    if (user.interests == null || user.interests!.isEmpty) return const SizedBox.shrink();

    // Vibrant curated color palettes for individual interest chips
    final chipGradients = [
      const [Color(0xFF9B5DE5), Color(0xFF7928CA)], // Purple
      const [Color(0xFFFF5069), Color(0xFFFF8E53)], // Coral
      const [Color(0xFF36D1DC), Color(0xFF5B86E5)], // Cyan-Blue
      const [Color(0xFF00F260), Color(0xFF0575E6)], // Green-Teal
      const [Color(0xFFFF007F), Color(0xFF7928CA)], // Neon Pink
      const [Color(0xFFF7971E), Color(0xFFFFD200)], // Gold-Orange
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 10,
        children: user.interests!.asMap().entries.map((entry) {
          final idx = entry.key;
          final label = entry.value.toString();
          final icon = _getInterestIcon(label);
          final grad = chipGradients[idx % chipGradients.length];

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? grad[0].withOpacity(0.14) : grad[0].withOpacity(0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: grad[0].withOpacity(isDark ? 0.38 : 0.25),
                width: 1.3,
              ),
              boxShadow: [
                BoxShadow(
                  color: grad[0].withOpacity(isDark ? 0.12 : 0.04),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Text(icon, style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : grad[0],
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
    if (l.contains('movie') || l.contains('film')) return '🎬';
    if (l.contains('book') || l.contains('read')) return '📚';
    if (l.contains('travel')) return '✈️';
    if (l.contains('food') || l.contains('cook')) return '🍔';
    if (l.contains('fitness') || l.contains('gym')) return '🏋️';
    if (l.contains('game') || l.contains('gaming')) return '🎮';
    if (l.contains('pet') || l.contains('cat') || l.contains('dog')) return '🐾';
    if (l.contains('dance')) return '💃';
    if (l.contains('art') || l.contains('draw')) return '🎨';
    if (l.contains('photo')) return '📷';
    if (l.contains('tech') || l.contains('code')) return '💻';
    return '✨';
  }

  Widget _buildGridHeader(BuildContext context, bool isDark, int count, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF36D1DC), Color(0xFF5B86E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF36D1DC).withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.photo_library_rounded, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                'Photos & Videos',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF36D1DC), Color(0xFF5B86E5)],
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
        ],
      ),
    );
  }

  // ─── POSTS GRID ─────────────────────────────────────────────────────────────
  SliverPadding _buildPostsGrid(List<PostModel> posts, BuildContext context, bool isDark) {
    if (posts.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        sliver: SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161026).withOpacity(0.6) : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_camera_outlined, size: 36, color: Colors.white54),
                ),
                const SizedBox(height: 12),
                Text(
                  'No moments shared yet 📸',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your posted photos and videos will appear in this showcase grid.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
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

            return _BouncingButton(
              onTap: () {
                HapticFeedback.lightImpact();
                _showPostDetail(context, post, posts);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
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
                              colors: [AppTheme.primaryBlue.withOpacity(0.3), AppTheme.accentPurple.withOpacity(0.3)],
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
                        height: 54,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.favorite_rounded, size: 14, color: Color(0xFFFF416C)),
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
  final AppPalette palette;
  const _AvatarRingPainter({required this.angle, required this.palette});

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
      colors: [
        palette.primary,
        palette.secondary,
        palette.accent,
        palette.primary,
        palette.secondary,
        palette.primary,
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
    final currentVibe = ref.watch(themeVibeProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
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
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Settings & Preferences ⚙️',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Theme Accent (Dark Mode)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _vibeOption(
                  context,
                  vibe: ThemeVibe.male,
                  label: 'Boy (Blue)',
                  icon: Icons.bolt_rounded,
                  isSelected: currentVibe == ThemeVibe.male,
                  accentColor: const Color(0xFF2D6FD4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _vibeOption(
                  context,
                  vibe: ThemeVibe.female,
                  label: 'Girl (Pink)',
                  icon: Icons.favorite_rounded,
                  isSelected: currentVibe == ThemeVibe.female,
                  accentColor: const Color(0xFFFF5277),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _vibeOption(
                  context,
                  vibe: ThemeVibe.auto,
                  label: 'Auto (Gender)',
                  icon: Icons.auto_awesome_rounded,
                  isSelected: currentVibe == ThemeVibe.auto,
                  accentColor: AppTheme.primaryPink,
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

  Widget _vibeOption(
    BuildContext context, {
    required ThemeVibe vibe,
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color accentColor,
  }) {
    return GestureDetector(
      onTap: () => ref.read(themeVibeProvider.notifier).setVibe(vibe),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withOpacity(0.18)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accentColor : Colors.white12,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: isSelected ? accentColor : Colors.white60),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? accentColor : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── BOUNCING BUTTON ─────────────────────────────────────────────────────────
class _BouncingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _BouncingButton({required this.child, this.onTap});

  @override
  State<_BouncingButton> createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<_BouncingButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.94).animate(
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
    if (widget.onTap == null) {
      return widget.child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
