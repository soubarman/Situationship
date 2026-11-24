import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/like_service.dart';

/// Full-screen overlay that celebrates a mutual match with
/// floating hearts/stars, photo rings, and direct messaging actions.
class MatchOverlay extends StatefulWidget {
  final UserModel currentUser;
  final UserModel matchedUser;
  final bool isSuperMatch;
  final VoidCallback onSendMessage;
  final VoidCallback onDismiss;

  const MatchOverlay({
    super.key,
    required this.currentUser,
    required this.matchedUser,
    this.isSuperMatch = false,
    required this.onSendMessage,
    required this.onDismiss,
  });

  /// Static helper to trigger the match celebration dialog from anywhere in the app.
  static Future<void> show({
    required BuildContext context,
    required UserModel currentUser,
    required UserModel matchedUser,
    bool isSuperMatch = false,
    VoidCallback? onSendMessage,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Match',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogCtx, anim1, anim2) {
        return Material(
          color: Colors.transparent,
          child: MatchOverlay(
            currentUser: currentUser,
            matchedUser: matchedUser,
            isSuperMatch: isSuperMatch,
            onSendMessage: onSendMessage ??
                () {
                  Navigator.of(dialogCtx).pop();
                  final chatId = LikeService.getCanonicalChatId(
                      currentUser.id, matchedUser.id);
                  context.push('/chats/$chatId', extra: {
                    'otherUserId': matchedUser.id,
                    'name': matchedUser.name,
                    'avatarUrl': matchedUser.avatarUrl,
                    'isOnline': matchedUser.isOnline,
                  });
                },
            onDismiss: () => Navigator.of(dialogCtx).pop(),
          ),
        );
      },
    );
  }

  @override
  State<MatchOverlay> createState() => _MatchOverlayState();
}

class _MatchOverlayState extends State<MatchOverlay>
    with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _photoController;
  late AnimationController _textController;
  late AnimationController _heartController;
  late AnimationController _pulseController;

  late Animation<double> _bgFade;
  late Animation<double> _photoScale;
  late Animation<double> _photoFade;
  late Animation<double> _textSlide;
  late Animation<double> _textFade;
  late Animation<double> _heartPulse;

  final List<_FloatingHeart> _hearts = [];
  final Random _rng = Random();

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();

    _bgController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _photoController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _textController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _heartController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    _bgFade = CurvedAnimation(parent: _bgController, curve: Curves.easeOut);
    _photoScale = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _photoController, curve: Curves.elasticOut));
    _photoFade =
        CurvedAnimation(parent: _photoController, curve: Curves.easeOut);
    _textSlide = Tween<double>(begin: 40, end: 0).animate(
        CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic));
    _textFade =
        CurvedAnimation(parent: _textController, curve: Curves.easeOut);
    _heartPulse = Tween<double>(begin: 0.9, end: 1.15).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

    // Stagger animations
    _bgController.forward();
    Future.delayed(const Duration(milliseconds: 200),
        () => _photoController.forward());
    Future.delayed(const Duration(milliseconds: 600),
        () => _textController.forward());

    // Spawn floating celebration particles (stars if super match, hearts if standard)
    for (int i = 0; i < 20; i++) {
      Future.delayed(Duration(milliseconds: i * 130), _spawnHeart);
    }
  }

  void _spawnHeart() {
    if (!mounted) return;
    final List<String> emojis = widget.isSuperMatch
        ? const ['⭐', '🌟', '💫', '✨', '💖']
        : const ['❤️', '💕', '💖', '✨', '🔥'];

    setState(() {
      _hearts.add(_FloatingHeart(
        x: _rng.nextDouble(),
        size: 14 + _rng.nextDouble() * 22,
        duration: Duration(milliseconds: 2000 + _rng.nextInt(1500)),
        emoji: emojis[_rng.nextInt(emojis.length)],
        delay: Duration.zero,
      ));
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _photoController.dispose();
    _textController.dispose();
    _heartController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSuper = widget.isSuperMatch;

    return AnimatedBuilder(
      animation: _bgFade,
      builder: (context, _) => Opacity(
        opacity: _bgFade.value,
        child: Stack(
          children: [
            // ── Blurred gradient background ─────────────────────────────
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onDismiss,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isSuper
                          ? const [
                              Color(0xFF001529),
                              Color(0xFF0B2046),
                              Color(0xFF021024),
                            ]
                          : const [
                              Color(0xFF0D0D2B),
                              Color(0xFF1A0B2E),
                              Color(0xFF0B1A2B),
                            ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Floating celebration particles ──────────────────────────
            ..._hearts.map((h) => _FloatingHeartWidget(
                  heart: h,
                  screenWidth: size.width,
                  screenHeight: size.height,
                )),

            // ── Content ─────────────────────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  // Close button
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: GestureDetector(
                        onTap: widget.onDismiss,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // ── Match text ────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, _) => Transform.translate(
                      offset: Offset(0, _textSlide.value - 20),
                      child: Opacity(
                        opacity: _textFade.value,
                        child: Column(
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) => isSuper
                                  ? const LinearGradient(
                                      colors: [Color(0xFF00C9FF), Color(0xFF92FE9D), Color(0xFFFFD700)],
                                    ).createShader(bounds)
                                  : AppTheme.primaryGradient.createShader(bounds),
                              child: Text(
                                isSuper ? "It's a Super Match! ⭐" : "It's a Match! 💫",
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isSuper
                                  ? 'You and ${widget.matchedUser.name} super vibed!\nPriority celestial connection unlocked ✨'
                                  : 'You and ${widget.matchedUser.name} vibed!\nYou have 36 hours to say hello.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withValues(alpha: 0.75),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Photo pair ────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _photoController,
                    builder: (context, _) => ScaleTransition(
                      scale: _photoScale,
                      child: FadeTransition(
                        opacity: _photoFade,
                        child: _buildPhotoPair(),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // ── Buttons ───────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (context, _) => Opacity(
                      opacity: _textFade.value,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                        child: Column(
                          children: [
                            // Send message button
                            GestureDetector(
                              onTap: widget.onSendMessage,
                              child: AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) => Transform.scale(
                                  scale: _heartPulse.value,
                                  child: child,
                                ),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  decoration: BoxDecoration(
                                    gradient: isSuper
                                        ? const LinearGradient(
                                            colors: [Color(0xFF00C9FF), Color(0xFF0072FF)],
                                          )
                                        : AppTheme.primaryGradient,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (isSuper ? const Color(0xFF00C9FF) : AppTheme.primaryBlue)
                                            .withValues(alpha: 0.45),
                                        blurRadius: 20,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isSuper ? Icons.star_rounded : Icons.chat_bubble_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isSuper ? 'Send a Message ⭐' : 'Send a Message 💌',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Keep swiping button
                            GestureDetector(
                              onTap: widget.onDismiss,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Keep Swiping ✨',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPair() {
    final isSuper = widget.isSuperMatch;

    return SizedBox(
      width: 300,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left — matched user (tilted left)
          Positioned(
            left: 0,
            child: Transform.rotate(
              angle: -0.12,
              child: _PhotoRing(
                imageUrl: widget.matchedUser.avatarUrl ??
                    'https://i.pravatar.cc/300?u=${widget.matchedUser.id}',
                size: 155,
                isSuper: isSuper,
              ),
            ),
          ),
          // Right — current user (tilted right)
          Positioned(
            right: 0,
            child: Transform.rotate(
              angle: 0.12,
              child: _PhotoRing(
                imageUrl: widget.currentUser.avatarUrl ??
                    'https://i.pravatar.cc/300?u=${widget.currentUser.id}',
                size: 150,
                isSuper: isSuper,
              ),
            ),
          ),
          // Pulsing center badge
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Transform.scale(
              scale: _heartPulse.value,
              child: child,
            ),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: isSuper
                    ? const LinearGradient(
                        colors: [Color(0xFF00C9FF), Color(0xFF0072FF)],
                      )
                    : AppTheme.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isSuper ? const Color(0xFF00C9FF) : AppTheme.primaryBlue)
                        .withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                isSuper ? Icons.star_rounded : Icons.favorite_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Photo Ring ───────────────────────────────────────────────────────────────

class _PhotoRing extends StatelessWidget {
  final String imageUrl;
  final double size;
  final bool isSuper;

  const _PhotoRing({
    required this.imageUrl,
    required this.size,
    this.isSuper = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size * 1.3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSuper ? const Color(0xFF00C9FF) : Colors.white,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: isSuper
                ? const Color(0xFF00C9FF).withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.35),
            blurRadius: isSuper ? 28 : 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: const Color(0xFF1A1A2E),
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: const Color(0xFF1A1A2E),
            child: const Icon(Icons.person_rounded,
                size: 48, color: Colors.white30),
          ),
        ),
      ),
    );
  }
}

// ─── Floating Heart Particle ──────────────────────────────────────────────────

class _FloatingHeart {
  final double x;
  final double size;
  final Duration duration;
  final String emoji;
  final Duration delay;

  _FloatingHeart({
    required this.x,
    required this.size,
    required this.duration,
    required this.emoji,
    required this.delay,
  });
}

class _FloatingHeartWidget extends StatefulWidget {
  final _FloatingHeart heart;
  final double screenWidth;
  final double screenHeight;

  const _FloatingHeartWidget({
    required this.heart,
    required this.screenWidth,
    required this.screenHeight,
  });

  @override
  State<_FloatingHeartWidget> createState() => _FloatingHeartWidgetState();
}

class _FloatingHeartWidgetState extends State<_FloatingHeartWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _yAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _wiggleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.heart.duration);

    _yAnim = Tween<double>(
      begin: widget.screenHeight * 0.85,
      end: widget.screenHeight * 0.1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _fadeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_ctrl);

    _wiggleAnim = Tween<double>(begin: -15, end: 15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );

    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final xPos = widget.heart.x * widget.screenWidth + _wiggleAnim.value;
        return Positioned(
          left: xPos.clamp(0.0, widget.screenWidth - widget.heart.size),
          top: _yAnim.value,
          child: Opacity(
            opacity: _fadeAnim.value,
            child: Text(
              widget.heart.emoji,
              style: TextStyle(fontSize: widget.heart.size),
            ),
          ),
        );
      },
    );
  }
}
