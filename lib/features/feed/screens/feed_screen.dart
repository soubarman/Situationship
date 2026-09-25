import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/widgets/empty_state_widget.dart';
import '../widgets/post_card.dart';
import '../widgets/stories_row.dart';
import '../widgets/quick_post_box.dart';
import '../../spotlight/widgets/spotlight_feed_section.dart';
import '../../../core/models/user_model.dart';
import '../../../core/models/notification_model.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../shared/widgets/background_orbs.dart';

// false = All Stories, true = Following Only
final storiesFilterProvider = StateProvider<bool>((ref) => false);

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _genderPromptShown = false;

  void _showGenderPrompt(BuildContext context, UserModel user) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String selectedGender = 'other';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Complete Your Profile 💫'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Please select your gender to continue. This helps us tailor your experience!'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedGender,
                    items: const [
                      DropdownMenuItem(value: 'male', child: Text('Male 🙋‍♂️')),
                      DropdownMenuItem(value: 'female', child: Text('Female 🙋‍♀️')),
                      DropdownMenuItem(value: 'other', child: Text('Other ✨')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedGender = val);
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    if (selectedGender == 'other') return; // Enforce selecting male or female if possible, but other is allowed. Wait, we can just save it.
                    final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
                    await db.collection('users').doc(user.id).update({'gender': selectedGender});
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final postsStream = ref.watch(postsPaginationProvider);
    final isLoading   = postsStream.isLoading;
    final posts       = ref.watch(filteredPostsProvider);
    final activeFilter= ref.watch(feedFilterProvider);
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);
    final palette     = ref.watch(appPaletteProvider);

    ref.listen(currentUserProvider, (prev, next) {
      if (!_genderPromptShown && next.id.isNotEmpty && (next.gender.isEmpty || next.gender == 'other')) {
        _genderPromptShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showGenderPrompt(context, next);
        });
      }
    });

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF5F5F7),
      body: Stack(
        children: [
          const BackgroundOrbs(),
          RefreshIndicator(
            onRefresh: () async {
              await ref.read(postsPaginationProvider.notifier).refresh();
            },
            color: palette.primary,
            child: CustomScrollView(
              cacheExtent: 2000,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                _buildAppBar(context, isDark, currentUser, ref, palette),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                const SliverToBoxAdapter(child: StoriesRow()),

                // ── Feed filter chips (ABOVE spotlight) ───────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Row(
                      children: [
                        Expanded(child: _TabChip(label: 'All',         isSelected: activeFilter == 'all',         palette: palette, onTap: () => ref.read(feedFilterProvider.notifier).state = 'all')),
                        const SizedBox(width: 6),
                        Expanded(child: _TabChip(label: 'Following',   isSelected: activeFilter == 'following',   palette: palette, onTap: () => ref.read(feedFilterProvider.notifier).state = 'following')),
                        const SizedBox(width: 6),
                        Expanded(child: _TabChip(label: 'Trending',    isSelected: activeFilter == 'trending',    palette: palette, onTap: () => ref.read(feedFilterProvider.notifier).state = 'trending')),
                        const SizedBox(width: 6),
                        Expanded(child: _TabChip(label: 'Communities', isSelected: activeFilter == 'communities', palette: palette, onTap: () => ref.read(feedFilterProvider.notifier).state = 'communities')),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SpotlightFeedSection(),
                ),

                // spacing so spotlight and posts don't look merged
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
    
                // ── Firestore error banner ─────────────────────────────────────
                if (postsStream.hasError)
                  SliverToBoxAdapter(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.error.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text('Feed load error:', style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.bold))),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            postsStream.error.toString(),
                            style: TextStyle(color: AppTheme.error.withOpacity(0.8), fontSize: 11, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ),
    
                // ── Posts ──────────────────────────────────────────────────────
                if (isLoading)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _PostShimmer(isDark: isDark),
                      childCount: 3,
                    ),
                  )
                else ...[
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final post = posts[index];
                        return PostCard(
                          key: ValueKey(post.id),
                          post: post,
                          onLike: () {
                            ref.read(postsProvider.notifier).toggleLike(post.id, currentUser.id);
                          },
                        );
                      },
                      childCount: posts.length,
                      addRepaintBoundaries: false,
                    ),
                  ),
                  if (posts.isEmpty && !postsStream.hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyStateWidget(
                        emoji: '✨',
                        title: 'Nothing here yet!',
                        message: 'The vibe is just getting started. Pull down to refresh or create the first post! 🚀',
                        onAction: () => context.push('/create-post'),
                        actionLabel: 'Start the Vibe 🔥',
                      ),
                    ),
                ],
    
                SliverPadding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 120)),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80.0),
        child: FloatingActionButton(
          shape: const CircleBorder(),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: const SafeArea(
                  child: QuickPostBox(),
                ),
              ),
            );
          },
          backgroundColor: palette.primary,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  // ─── Glassmorphic App Bar ──────────────────────────────────────────────────

  SliverAppBar _buildAppBar(BuildContext context, bool isDark, UserModel currentUser, WidgetRef ref, AppPalette palette) {
    return SliverAppBar(
      floating: true,
      snap: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      backgroundColor: isDark ? palette.backgroundTint : const Color(0xFFF5F5F7),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          thickness: 0.5,
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => palette.logoGradient.createShader(bounds),
              child: const Text(
                'situationship',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: palette.verifiedBadgeBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: palette.verifiedBadgeBg.withValues(alpha: 0.35),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  palette.verifiedIcon,
                  color: palette.verifiedIconColor,
                  size: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        _buildCoinBadge(currentUser.coins, isDark, palette),
        const SizedBox(width: 6),
        // Bell with notification badge
        Consumer(
          builder: (context, ref, child) {
            final notificationsAsync = ref.watch(notificationsStreamProvider);
            final notifications = notificationsAsync.asData?.value ?? [];
            final unreadCount = notifications.where((n) => !n.isRead).length;
            final hasUnread = unreadCount > 0;
            final displayCount = unreadCount >= 10 ? '9+' : '$unreadCount';

            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () => _showNotificationsSheet(context, currentUser, ref),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF161026) : Colors.black.withValues(alpha: 0.04),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.08),
                        width: 1.0,
                      ),
                    ),
                    child: Icon(
                      hasUnread ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                      size: 16,
                      color: isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87,
                    ),
                  ),
                ),
                if (hasUnread)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: palette.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? const Color(0xFF0B0715) : Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primary.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          displayCount,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(width: 6),
        // Search icon button
        GestureDetector(
          onTap: () => context.push('/search'),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF161026) : Colors.black.withValues(alpha: 0.04),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.08),
                width: 1.0,
              ),
            ),
            child: Icon(
              Icons.search_rounded,
              size: 16,
              color: isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 6),
        // My Profile button on the far right
        _buildProfileAvatar(currentUser, isDark, palette),
        const SizedBox(width: 12),
      ],
    );
  }

  // ─── Profile Avatar Button ─────────────────────────────────────────────────

  Widget _buildProfileAvatar(UserModel currentUser, bool isDark, AppPalette palette) {
    final avatarUrl = currentUser.avatarUrl;
    return GestureDetector(
      onTap: () => context.push('/profile'),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: palette.primaryGradient,
          boxShadow: [
            BoxShadow(
              color: palette.primary.withValues(alpha: 0.35),
              blurRadius: 6,
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.5),
        child: ClipOval(
          child: Container(
            color: isDark ? const Color(0xFF161026) : Colors.white,
            child: avatarUrl != null && avatarUrl.isNotEmpty
                ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    width: 29,
                    height: 29,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person_rounded,
                      size: 16,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  )
                : Icon(
                    Icons.person_rounded,
                    size: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
          ),
        ),
      ),
    );
  }

  // ─── Flame Streak / Coin Badge ─────────────────────────────────────────────

  Widget _buildCoinBadge(int coins, bool isDark, AppPalette palette) {
    final displayStreak = coins > 0 ? coins : 3;
    return GestureDetector(
      onTap: () => context.push('/wallet'),
      child: Center(
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: palette.streakBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: palette.streakBorder,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: palette.streakBorder.withValues(alpha: 0.18),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: palette.streakContentColor,
                size: 15,
              ),
              const SizedBox(width: 4),
              Text(
                '$displayStreak',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: palette.streakContentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // ─── Notifications Sheet ───────────────────────────────────────────────────

  void _showNotificationsSheet(BuildContext context, UserModel currentUser, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Consumer(
          builder: (context, ref, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final notificationsAsync = ref.watch(notificationsStreamProvider);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              markAllNotificationsAsRead(currentUser.id);
            });

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white.withOpacity(0.88),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.9),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 14),
                      Container(
                        width: 40, height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Notifications 🔔',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                color: isDark ? Colors.white : AppTheme.textPrimary,
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Close',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
                      Expanded(
                        child: notificationsAsync.when(
                          data: (list) {
                            if (list.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text('✨', style: TextStyle(fontSize: 48)),
                                    const SizedBox(height: 12),
                                    Text('All caught up!',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? Colors.white60 : AppTheme.textSecondary,
                                        )),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Reactions and chat requests will appear here.',
                                      style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = list[index];
                                IconData icon;
                                Color iconColor;

                                if (item.type == 'reaction') {
                                  icon = Icons.favorite_rounded;
                                  iconColor = Colors.pinkAccent;
                                } else if (item.type == 'gift') {
                                  icon = Icons.card_giftcard_rounded;
                                  iconColor = Colors.amber;
                                } else {
                                  icon = Icons.chat_bubble_rounded;
                                  iconColor = AppTheme.primaryBlue;
                                }

                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.05)
                                        : Colors.white.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: isDark ? Colors.white.withOpacity(0.07) : Colors.black.withOpacity(0.04),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: iconColor.withOpacity(0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(icon, color: iconColor, size: 20),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.title,
                                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                                            const SizedBox(height: 4),
                                            Text(item.body,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark ? Colors.white70 : AppTheme.textSecondary,
                                                )),
                                            const SizedBox(height: 6),
                                            Text(
                                              _formatTime(item.createdAt),
                                              style: const TextStyle(fontSize: 10.5, color: AppTheme.textTertiary, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Shimmer placeholder ───────────────────────────────────────────────────────

class _PostShimmer extends StatelessWidget {
  final bool isDark;
  const _PostShimmer({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final c = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 120, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 6),
                Container(width: 80,  height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5))),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          Container(width: double.infinity, height: 220, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20))),
          const SizedBox(height: 12),
          Container(width: 200, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
        ],
      ),
    );
  }
}

// ─── Filter tab chip ──────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final AppPalette palette;

  const _TabChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? palette.primaryGradient : null,
          color: isSelected
              ? null
              : (isDark ? Colors.white.withOpacity(0.08) : Colors.white),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: isSelected
                ? Colors.white.withOpacity(0.4)
                : (isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08)),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: palette.primary.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Glass icon widget ────────────────────────────────────────────────────────

class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isDark;
  const _GlassIcon({required this.icon, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.9),
              width: 1.0,
            ),
            boxShadow: isDark ? [] : [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
