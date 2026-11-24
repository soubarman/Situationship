import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/user_model.dart';
import '../screens/feed_screen.dart';
import '../../verification/presentation/widgets/s_badge_widget.dart';

/// Modern dating-app style Moments / Stories row.
/// Features lively circular story avatars with animated breathing halos,
/// rotating sunset-coral rings, expanding attention ripples, and glossy lens gleams.
class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storiesStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFollowingOnly = ref.watch(storiesFilterProvider);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final currentUser = ref.watch(currentUserProvider);

    return SizedBox(
      height: 104,
      child: storiesAsync.when(
        data: (stories) {
          final uniqueUsers = <String, Map<String, dynamic>>{};
          for (var s in stories) {
            uniqueUsers[s['userId']] = s;
          }

          // Separate other users stories from current user's
          final otherUsersStories = uniqueUsers.values
              .where((s) {
                if (s['userId'] == currentUserId) return false;
                if (isFollowingOnly && !currentUser.following.contains(s['userId'])) return false;
                return true;
              })
              .toList();

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: otherUsersStories.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final myStory = currentUserId != null
                    ? uniqueUsers[currentUserId]
                    : null;

                if (myStory != null && currentUserId != null) {
                  return _StoryItem(
                    userId: currentUserId,
                    userName: currentUser.name,
                    avatarUrl: currentUser.avatarUrl,
                    storyImageUrl: myStory['imageUrl'],
                    createdAt: myStory['createdAt'] as int?,
                    isDark: isDark,
                    isCurrentUser: true,
                  );
                }

                return _AddStoryItem(
                  isDark: isDark,
                  user: currentUser,
                );
              }

              final story = otherUsersStories[index - 1];
              return _StoryItem(
                userId: story['userId'],
                userName: story['userName'],
                avatarUrl: story['userAvatar'],
                storyImageUrl: story['imageUrl'],
                createdAt: story['createdAt'] as int?,
                isDark: isDark,
                isCurrentUser: false,
              );
            },
          );
        },
        loading: () => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (err, stack) {
          debugPrint('Stories Error: $err');
          return Center(
            child: Icon(
              Icons.error_outline_rounded,
              color: AppTheme.error.withValues(alpha: 0.5),
              size: 20,
            ),
          );
        },
      ),
    );
  }
}

// ── Dating App "Your Story / Add Moment" Avatar ──────────────────────────────
class _AddStoryItem extends StatefulWidget {
  final bool isDark;
  final UserModel user;

  const _AddStoryItem({
    required this.isDark,
    required this.user,
  });

  @override
  State<_AddStoryItem> createState() => _AddStoryItemState();
}

class _AddStoryItemState extends State<_AddStoryItem>
    with TickerProviderStateMixin {
  bool _isPressed = false;
  bool _isHovered = false;

  late final AnimationController _pulseCtrl;
  late final AnimationController _spinCtrl;
  late final Animation<double> _circleScale;
  late final Animation<double> _badgeScale;
  late final Animation<double> _rippleScale;
  late final Animation<double> _rippleOpacity;

  @override
  void initState() {
    super.initState();
    // 1. Slow, subtle rotation for the "Add Moment" border
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    // 2. Gentle inviting breathing pulse
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _circleScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.035).chain(CurveTween(curve: Curves.easeOutSine)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.035, end: 1.0).chain(CurveTween(curve: Curves.easeInSine)),
        weight: 50,
      ),
    ]).animate(_pulseCtrl);

    _badgeScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.15).chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 55,
      ),
    ]).animate(_pulseCtrl);

    _rippleScale = Tween<double>(begin: 1.0, end: 1.7).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOutCubic),
    );

    _rippleOpacity = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = widget.user.avatarUrl != null && widget.user.avatarUrl!.isNotEmpty;
    final bgColor = widget.isDark ? AppTheme.darkBg : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: () {
            HapticFeedback.lightImpact();
            context.push('/take/create');
          },
          child: AnimatedSlide(
            offset: Offset(0, _isHovered ? -0.03 : 0.0),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: _isPressed ? 0.93 : (_isHovered ? 1.03 : 1.0),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                width: 74,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // Animated breathing circle (Increased size: 68x68)
                        AnimatedBuilder(
                          animation: Listenable.merge([_pulseCtrl, _spinCtrl]),
                          builder: (context, _) {
                            return Transform.scale(
                              scale: _circleScale.value,
                              child: Container(
                                width: 68,
                                height: 68,
                                padding: const EdgeInsets.all(2.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(
                                    transform: GradientRotation(_spinCtrl.value * 2 * pi),
                                    colors: [
                                      const Color(0xFFFF385C).withValues(alpha: 0.5),
                                      const Color(0xFFFF7A59).withValues(alpha: 0.3),
                                      widget.isDark ? Colors.white24 : Colors.black12,
                                      const Color(0xFFFF385C).withValues(alpha: 0.5),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF385C).withValues(
                                        alpha: _isHovered ? 0.35 : 0.12,
                                      ),
                                      blurRadius: _isHovered ? 12 : 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: bgColor,
                                  ),
                                  child: ClipOval(
                                    child: hasAvatar
                                        ? CachedNetworkImage(
                                            imageUrl: widget.user.avatarUrl!,
                                            fit: BoxFit.cover,
                                            errorWidget: (_, __, ___) => _avatarFallback(),
                                          )
                                        : _avatarFallback(),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // Animated Dating App '+' Action Pill (bottom-right)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (context, child) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Subtle expanding ripple ring
                                  Transform.scale(
                                    scale: _rippleScale.value,
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFFFF385C).withValues(alpha: _rippleOpacity.value),
                                          width: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Breathing core '+' badge
                                  Transform.scale(
                                    scale: _badgeScale.value,
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFFFF385C), Color(0xFFFF6584)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        border: Border.all(
                                          color: bgColor,
                                          width: 2.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFF385C).withValues(alpha: 0.45),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.add_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Your moment',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.85)
                            : const Color(0xFF222222),
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

  Widget _avatarFallback() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: widget.isDark
              ? [const Color(0xFF25223A), const Color(0xFF1B1926)]
              : [const Color(0xFFECE7FA), const Color(0xFFE0DAF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        size: 28,
        color: widget.isDark ? Colors.white38 : Colors.black38,
      ),
    );
  }
}

// ── Dating App Story Avatar Item ─────────────────────────────────────────────
class _StoryItem extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final String? storyImageUrl;
  final int? createdAt;
  final bool isDark;
  final bool isCurrentUser;

  const _StoryItem({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.storyImageUrl,
    this.createdAt,
    required this.isDark,
    this.isCurrentUser = false,
  });

  @override
  ConsumerState<_StoryItem> createState() => _StoryItemState();
}

class _StoryItemState extends ConsumerState<_StoryItem>
    with TickerProviderStateMixin {
  bool _isPressed = false;
  bool _isHovered = false;

  late final AnimationController _spinCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _rippleCtrl;
  late final AnimationController _gleamCtrl;

  late final Animation<double> _circlePulse;
  late final Animation<double> _haloRippleScale;
  late final Animation<double> _haloRippleOpacity;
  late final Animation<double> _gleamOffset;
  late final Animation<double> _endingPulse;

  @override
  void initState() {
    super.initState();

    // 1. Smooth, continuous rotation of high-contrast sunset gradient (5.5s per loop)
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5500),
    );
    // Stagger phase uniquely per user
    final phase = (widget.userId.hashCode.abs() % 1000) / 1000.0;
    _spinCtrl.value = phase;
    _spinCtrl.repeat();

    // 2. Gentle organic heartbeat pulse on the circle itself (2.2s loop)
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _circlePulse = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );

    _endingPulse = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // 3. Concentric expanding attention ripple wave behind the circle (2.6s loop)
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    // Offset ripple start so they pulse with slight variation
    Future.delayed(Duration(milliseconds: (phase * 1200).toInt()), () {
      if (mounted) _rippleCtrl.repeat();
    });

    _haloRippleScale = Tween<double>(begin: 1.0, end: 1.30).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOutCubic),
    );

    _haloRippleOpacity = Tween<double>(begin: 0.50, end: 0.0).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOutQuad),
    );

    // 4. Subtle glossy sheen reflection passing across the circle lens (3.8s loop)
    _gleamCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat();

    _gleamOffset = Tween<double>(begin: -1.2, end: 2.2).animate(
      CurvedAnimation(
        parent: _gleamCtrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeInOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    _rippleCtrl.dispose();
    _gleamCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Live-watch the story author's profile for up-to-date name/avatar
    final liveAuthor = ref.watch(otherUserProvider(widget.userId));
    final displayName = liveAuthor.asData?.value?.name ?? widget.userName;
    final displayAvatar = liveAuthor.asData?.value?.avatarUrl
        ?? widget.avatarUrl
        ?? 'https://i.pravatar.cc/100?u=${widget.userId}';

    final isVerified = liveAuthor.asData?.value?.isReallyVerified ?? false;

    // First name extraction for warm dating app feel (e.g. "Alex" instead of "@alex_99")
    final firstName = widget.isCurrentUser
        ? 'You'
        : displayName.trim().split(' ').first;

    // Check if moment is expiring soon (within last 2 hours of 24h window)
    bool isEnding = false;
    if (widget.createdAt != null) {
      final createdAtDate = DateTime.fromMillisecondsSinceEpoch(widget.createdAt!);
      final expiresAt = createdAtDate.add(const Duration(hours: 24));
      final remaining = expiresAt.difference(DateTime.now());
      isEnding = remaining.inHours < 2 && remaining.inSeconds > 0;
    }

    final bgColor = widget.isDark ? AppTheme.darkBg : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: () {
            HapticFeedback.lightImpact();
            context.push(
              '/story/view/${widget.userId}',
              extra: {'userName': displayName, 'userAvatar': displayAvatar},
            );
          },
          child: AnimatedSlide(
            offset: Offset(0, _isHovered ? -0.03 : 0.0),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: _isPressed ? 0.93 : (_isHovered ? 1.03 : 1.0),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                width: 74,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // 1. Concentric Attention Ripple Halo behind the circle (Increased to 68px)
                        AnimatedBuilder(
                          animation: _rippleCtrl,
                          builder: (context, _) {
                            return Transform.scale(
                              scale: _haloRippleScale.value,
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFFF385C).withValues(
                                      alpha: _haloRippleOpacity.value,
                                    ),
                                    width: 1.6,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // 2. Animated breathing Story Circle with rotating sunset gradient (68x68)
                        AnimatedBuilder(
                          animation: Listenable.merge([_spinCtrl, _pulseCtrl, _gleamCtrl]),
                          builder: (context, _) {
                            return Transform.scale(
                              scale: _circlePulse.value,
                              child: Container(
                                width: 68,
                                height: 68,
                                padding: const EdgeInsets.all(2.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: SweepGradient(
                                    transform: GradientRotation(_spinCtrl.value * 2 * pi),
                                    colors: const [
                                      Color(0xFFFF385C), // Vibrant Coral
                                      Color(0xFFFF8A00), // Warm Gold
                                      Color(0xFFFF1361), // Hot Pink
                                      Color(0xFFB138FF), // Romantic Violet
                                      Color(0xFFFF385C), // Vibrant Coral
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF385C).withValues(
                                        alpha: _isHovered
                                            ? 0.50
                                            : (0.22 + 0.18 * ((_circlePulse.value - 1.0) / 0.04)),
                                      ),
                                      blurRadius: _isHovered ? 14 : (8 + 6 * ((_circlePulse.value - 1.0) / 0.04)),
                                      spreadRadius: _isHovered ? 1.5 : (0.5 + 1.2 * ((_circlePulse.value - 1.0) / 0.04)),
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(2.2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: bgColor,
                                  ),
                                  child: ClipOval(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        // Story Avatar Image
                                        CachedNetworkImage(
                                          imageUrl: displayAvatar,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 200,
                                          memCacheHeight: 200,
                                          errorWidget: (_, __, ___) => Container(
                                            color: widget.isDark ? const Color(0xFF25223A) : const Color(0xFFECE7FA),
                                            child: const Icon(Icons.person_rounded, size: 28),
                                          ),
                                        ),

                                        // Subtle diagonal glossy light reflection across the circle
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final gleamX = _gleamOffset.value * constraints.maxWidth;
                                                return Transform.translate(
                                                  offset: Offset(gleamX, 0),
                                                  child: Transform.rotate(
                                                    angle: -0.42,
                                                    child: Container(
                                                      width: 22,
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          colors: [
                                                            Colors.white.withValues(alpha: 0.0),
                                                            Colors.white.withValues(alpha: 0.30),
                                                            Colors.white.withValues(alpha: 0.0),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // Refined animated ending badge (subtle pulse)
                        if (isEnding)
                          Positioned(
                            bottom: -3,
                            child: AnimatedBuilder(
                              animation: _pulseCtrl,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _endingPulse.value,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFF3366), Color(0xFFFF5E3A)],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: bgColor,
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFF3366).withValues(alpha: 0.45),
                                          blurRadius: 5,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.local_fire_department_rounded,
                                          size: 9,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 2),
                                        Text(
                                          'Ending',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                        // Subtle Verification Badge anchor
                        if (isVerified && !isEnding)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: bgColor, width: 2),
                              ),
                              child: const SBadgeWidget(size: 13, showTooltip: false),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Clean first name
                    Text(
                      firstName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.9)
                            : const Color(0xFF222222),
                        letterSpacing: -0.1,
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
}
