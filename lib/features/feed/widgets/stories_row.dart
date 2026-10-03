import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/user_model.dart';
import '../screens/feed_screen.dart';
import '../../verification/presentation/widgets/s_badge_widget.dart';
import 'package:flutter/foundation.dart';
import '../utils/ui_web_shim.dart' as ui_web;
import '../../../core/utils/web_stub.dart' if (dart.library.html) 'package:web/web.dart' as web;
import 'dart:math';

class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storiesStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 140,
      child: storiesAsync.when(
        data: (stories) {
          final uniqueUsers = <String, Map<String, dynamic>>{};
          for (var s in stories) {
            uniqueUsers[s['userId']] = s;
          }
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          final currentUser = ref.watch(currentUserProvider);
          final isFollowingOnly = ref.watch(storiesFilterProvider);
          
          // Separate other users stories from current user's
          final otherUsersStories = uniqueUsers.values
              .where((s) {
                if (s['userId'] == currentUserId) return false;
                if (isFollowingOnly && !currentUser.following.contains(s['userId'])) return false;
                return true;
              })
              .toList();

          return Stack(
            children: [
              ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16, right: 80),
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
                      );
                    }

                    return _buildAddStory(context, isDark, currentUser);
                  }

                  final story = otherUsersStories[index - 1];
                  return _StoryItem(
                    userId: story['userId'],
                    userName: story['userName'],
                    avatarUrl: story['userAvatar'],
                    storyImageUrl: story['imageUrl'],
                    createdAt: story['createdAt'] as int?,
                    isDark: isDark,
                  );
                },
              ),
              Positioned(
                right: 16,
                top: 20,
                child: GestureDetector(
                  onTap: () => ref.read(storiesFilterProvider.notifier).state = !isFollowingOnly,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isFollowingOnly ? Icons.group_rounded : Icons.public_rounded,
                              size: 16,
                              color: isFollowingOnly ? AppTheme.primaryBlue : (isDark ? Colors.white70 : Colors.black54),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isFollowingOnly ? 'Following' : 'All',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isFollowingOnly ? AppTheme.primaryBlue : (isDark ? Colors.white70 : Colors.black54),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) {
          debugPrint('Stories Error: $err');
          return Center(
            child: Icon(
              Icons.error_outline_rounded,
              color: AppTheme.error.withOpacity(0.5),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddStory(BuildContext context, bool isDark, UserModel user) {
    return _AddStoryCard(isDark: isDark, user: user);
  }
}

// ── Modern Animated "Drop a Moment" card ─────────────────────────────────────
class _AddStoryCard extends ConsumerStatefulWidget {
  final bool isDark;
  final UserModel user;
  const _AddStoryCard({
    required this.isDark,
    required this.user,
  });

  @override
  ConsumerState<_AddStoryCard> createState() => _AddStoryCardState();
}

class _AddStoryCardState extends ConsumerState<_AddStoryCard>
    with TickerProviderStateMixin {
  bool _isPressed = false;
  bool _isHovered = false;

  // 1. Gentle breathing glow & button pulse controller
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;
  late final Animation<double> _glowPulse;

  // 2. Concentric expanding ripple behind '+' button
  late final AnimationController _rippleCtrl;
  late final Animation<double> _rippleScale;
  late final Animation<double> _rippleOpacity;

  // 3. Rotating neon aura around the card border
  late final AnimationController _rotateCtrl;

  // 4. Glossy diagonal light shimmer sweep
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerOffset;

  @override
  void initState() {
    super.initState();

    // Pulse animation (2.2s loop, reverse)
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.96, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );

    _glowPulse = Tween<double>(begin: 0.35, end: 0.95).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );

    // Ripple wave animation (1.8s loop)
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _rippleScale = Tween<double>(begin: 1.0, end: 1.65).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOutCubic),
    );

    _rippleOpacity = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOutQuad),
    );

    // Continuous rotating border gradient (4.5s loop)
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    )..repeat();

    // Periodic diagonal shimmer sweep across the card (3.2s loop)
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _shimmerOffset = Tween<double>(begin: -1.3, end: 2.3).animate(
      CurvedAnimation(
        parent: _shimmerCtrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeInOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _rippleCtrl.dispose();
    _rotateCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(appPaletteProvider);
    final hasAvatar = widget.user.avatarUrl != null && widget.user.avatarUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          MouseRegion(
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
                offset: Offset(0, _isHovered ? -0.04 : 0.0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: _isPressed ? 0.92 : (_isHovered ? 1.04 : 1.0),
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pulseCtrl, _rippleCtrl, _rotateCtrl, _shimmerCtrl]),
                    builder: (context, _) {
                      return Container(
                        width: 78,
                        height: 98,
                        padding: const EdgeInsets.all(2.2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          // Rotating iridescent aura around border
                          gradient: SweepGradient(
                            transform: GradientRotation(_rotateCtrl.value * 2 * pi),
                            colors: [
                              palette.primary,
                              palette.accent,
                              AppTheme.accentPurple,
                              palette.primary,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: palette.primary.withValues(
                                alpha: _isHovered ? 0.55 : (0.22 + 0.22 * _glowPulse.value),
                              ),
                              blurRadius: _isHovered ? 18 : (10 + 6 * _glowPulse.value),
                              spreadRadius: _isHovered ? 2.5 : (0.5 + 1.2 * _glowPulse.value),
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            color: widget.isDark ? const Color(0xFF141022) : Colors.white,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Video background or User Avatar
                              if (hasAvatar)
                                CachedNetworkImage(
                                  imageUrl: widget.user.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    color: widget.isDark ? const Color(0xFF1E1933) : const Color(0xFFECE7FA),
                                    child: Icon(
                                      Icons.person_rounded,
                                      color: palette.primary.withValues(alpha: 0.5),
                                      size: 32,
                                    ),
                                  ),
                                )
                              else
                                const _LoopingVideoBackground(),

                              // Ambient dark gradient scrim for contrast
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.22),
                                      Colors.black.withValues(alpha: 0.60),
                                    ],
                                  ),
                                ),
                              ),

                              // Periodic diagonal glass shimmer gleam
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final shimmerX = _shimmerOffset.value * constraints.maxWidth;
                                      return Transform.translate(
                                        offset: Offset(shimmerX, 0),
                                        child: Transform.rotate(
                                          angle: -0.38,
                                          child: Container(
                                            width: 34,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.white.withValues(alpha: 0.0),
                                                  Colors.white.withValues(alpha: 0.35),
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

                              // Floating Animated Center '+' Button with Ripple Aura
                              Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Concentric expanding ripple ring
                                    Transform.scale(
                                      scale: _rippleScale.value,
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: _rippleOpacity.value),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Breathing Core '+' Button
                                    Transform.scale(
                                      scale: _pulseScale.value,
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: palette.primaryGradient,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.8,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: palette.primary.withValues(
                                                alpha: 0.45 + 0.25 * _glowPulse.value,
                                              ),
                                              blurRadius: 8 + 4 * _glowPulse.value,
                                              spreadRadius: 1 * _glowPulse.value,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.add_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Chic top-right camera pill with live pulsing indicator
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.25),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Blinking beacon dot
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color.lerp(
                                            const Color(0xFFFF2D55),
                                            palette.accent,
                                            _glowPulse.value,
                                          )!.withValues(alpha: 0.5 + 0.5 * _glowPulse.value),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFF2D55).withValues(alpha: 0.7 * _glowPulse.value),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(
                                        Icons.videocam_rounded,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Animated Label with Twinkle Sparkle
          SizedBox(
            width: 82,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (context, _) => Transform.scale(
                    scale: 0.85 + 0.25 * _glowPulse.value,
                    child: Icon(
                      Icons.auto_awesome,
                      size: 10.5,
                      color: Color.lerp(palette.primary, palette.accent, _glowPulse.value),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    'Drop Moment',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.92)
                          : const Color(0xFF161226),
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryItem extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final String? storyImageUrl;
  final int? createdAt;
  final bool isDark;

  const _StoryItem({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.storyImageUrl,
    this.createdAt,
    required this.isDark,
  });

  @override
  ConsumerState<_StoryItem> createState() => _StoryItemState();
}

class _StoryItemState extends ConsumerState<_StoryItem> {

  @override
  Widget build(BuildContext context) {
    // Live-watch the story author's profile for up-to-date name/avatar.
    final liveAuthor = ref.watch(otherUserProvider(widget.userId));
    final displayName = liveAuthor.asData?.value?.name ?? widget.userName;
    final displayAvatar = liveAuthor.asData?.value?.avatarUrl
        ?? widget.avatarUrl
        ?? 'https://i.pravatar.cc/100?u=${widget.userId}';

    bool isEnding = false;
    if (widget.createdAt != null) {
      final createdAtDate = DateTime.fromMillisecondsSinceEpoch(widget.createdAt!);
      final expiresAt = createdAtDate.add(const Duration(hours: 24));
      final remaining = expiresAt.difference(DateTime.now());
      isEnding = remaining.inHours < 2 && remaining.inSeconds > 0;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => context.push(
              '/story/view/${widget.userId}',
              extra: {'userName': displayName, 'userAvatar': displayAvatar},
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 78,
                  height: 98,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      colors: widget.userId.hashCode % 2 == 0 
                          ? [const Color(0xFFE84855), const Color(0xFFF9A03F)]
                          : [const Color(0xFFB138FF), const Color(0xFFFD297B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      color: widget.isDark ? AppTheme.darkBg : Colors.white,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: displayAvatar,
                          fit: BoxFit.cover,
                        ),
                          
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // ENDING badge
                if (isEnding)
                  Positioned(
                    bottom: -6, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF2D55),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Text('ENDING', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      )
                    )
                  ),
                
                // Emoji badge
                Positioned(
                  top: -6, right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: Text(
                      widget.userId.hashCode % 3 == 0 ? '🔥' : (widget.userId.hashCode % 2 == 0 ? '✨' : '💯'),
                      style: const TextStyle(fontSize: 10),
                    )
                  )
                ),

                // Verification Badge
                if (liveAuthor.asData?.value?.isVerified ?? false)
                  const Positioned(
                    bottom: -4,
                    right: -4,
                    child: SBadgeWidget(size: 14, showTooltip: false),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 78,
            child: Text(
              '@${displayName.toLowerCase().replaceAll(' ', '')}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.isDark ? Colors.white70 : AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoopingVideoBackground extends StatefulWidget {
  const _LoopingVideoBackground();

  @override
  State<_LoopingVideoBackground> createState() => _LoopingVideoBackgroundState();
}

class _LoopingVideoBackgroundState extends State<_LoopingVideoBackground> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  String? _webElementId;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webElementId = 'take_video_bg_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
      ui_web.platformViewRegistry.registerViewFactory(_webElementId!, (int viewId) {
        final video = web.HTMLVideoElement()
          ..autoplay = true
          ..loop = true
          ..muted = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.pointerEvents = 'none';
          
        video.setAttribute('playsinline', 'true');
        video.setAttribute('muted', 'true');
        video.setAttribute('autoplay', 'true');
        video.setAttribute('loop', 'true');
        
        video.src = 'assets/assets/take video/take_icon_video.mp4';
        
        return video;
      });
      _ready = true;
    } else {
      _ctrl = VideoPlayerController.asset('assets/take video/take_icon_video.mp4');
      _ctrl!.initialize().then((_) async {
        await _ctrl!.setVolume(0.0);
        await _ctrl!.setLooping(true);
        await _ctrl!.play();
        
        _ctrl!.addListener(() {
          if (_ctrl!.value.isInitialized && !_ctrl!.value.isPlaying) {
            final position = _ctrl!.value.position;
            final duration = _ctrl!.value.duration;
            if (position >= duration || (duration.inMilliseconds - position.inMilliseconds) < 50) {
              _ctrl!.seekTo(Duration.zero);
              _ctrl!.play();
            }
          }
        });
        
        if (mounted) setState(() => _ready = true);
      });
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    
    if (kIsWeb) {
      return SizedBox.expand(
        child: IgnorePointer(
          child: HtmlElementView(viewType: _webElementId!),
        ),
      );
    }
    
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _ctrl!.value.size.width,
          height: _ctrl!.value.size.height,
          child: VideoPlayer(_ctrl!),
        ),
      ),
    );
  }
}
