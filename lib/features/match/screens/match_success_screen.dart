import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/like_service.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../shared/widgets/background_orbs.dart';
import '../../../shared/widgets/gradient_button.dart';

class MatchSuccessScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> matchData;

  const MatchSuccessScreen({super.key, required this.matchData});

  @override
  ConsumerState<MatchSuccessScreen> createState() => _MatchSuccessScreenState();
}

class _MatchSuccessScreenState extends ConsumerState<MatchSuccessScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _pulseController;

  late Animation<double> _fadeIn;
  late Animation<double> _slideUp;
  late Animation<double> _scalePhotos;
  late Animation<double> _heartPulse;
  late Animation<double> _heartBeat;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _slideUp = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _scalePhotos = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.1, 0.75, curve: Curves.easeOutBack),
      ),
    );

    _heartPulse = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _heartBeat = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.4, 0.85, curve: Curves.elasticOut),
      ),
    );

    _mainController.forward();
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchedUser = widget.matchData['matchedUser'] as Map<String, dynamic>?;
    final matchedName = matchedUser?['name'] as String? ?? 'Someone';
    final matchedAvatar = matchedUser?['avatarUrl'] as String? ??
        'https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?w=400';
    final chatId = matchedUser?['chatId'] as String?;
    final currentUser = ref.watch(currentUserProvider);
    final palette = ref.watch(appPaletteProvider);

    return Scaffold(
      backgroundColor: DesignTokens.obsidianBase,
      body: Stack(
        children: [
          const BackgroundOrbs(),
          SafeArea(
            child: AnimatedBuilder(
              animation: _mainController,
              builder: (context, child) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacing24),
                  child: Column(
                    children: [
                      const SizedBox(height: DesignTokens.spacing16),
                      // Top close button
                      Align(
                        alignment: Alignment.topRight,
                        child: FadeTransition(
                          opacity: _fadeIn,
                          child: GestureDetector(
                            onTap: () => context.go('/match'),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: DesignTokens.obsidianElevated,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: DesignTokens.hairline,
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: DesignTokens.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),

                      // Glowing Photos Connection
                      FadeTransition(
                        opacity: _fadeIn,
                        child: ScaleTransition(
                          scale: _scalePhotos,
                          child: _buildPhotoPair(
                            matchedAvatar: matchedAvatar,
                            currentAvatar: currentUser.avatarUrl ??
                                'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=400',
                            palette: palette,
                          ),
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spacing32),

                      // Match Title & Copy
                      FadeTransition(
                        opacity: _fadeIn,
                        child: Transform.translate(
                          offset: Offset(0, _slideUp.value),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: DesignTokens.spacing12,
                                  vertical: DesignTokens.spacing4,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                                  border: Border.all(
                                    color: palette.primary.withValues(alpha: 0.35),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'MUTUAL CONNECTION',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: palette.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacing12),
                              Text(
                                "It's a Match",
                                style: DesignTokens.fontDisplay(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: DesignTokens.textPrimary,
                                  letterSpacing: -0.8,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacing8),
                              Text(
                                'You and $matchedName liked each other.\nBreak the ice before the spark fades.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: DesignTokens.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),

                      // Action Buttons
                      FadeTransition(
                        opacity: _fadeIn,
                        child: Transform.translate(
                          offset: Offset(0, _slideUp.value),
                          child: Column(
                            children: [
                              ScaleTransition(
                                scale: _heartPulse,
                                child: GradientButton(
                                  text: 'Send a Message',
                                  icon: Icons.chat_bubble_outline_rounded,
                                  onPressed: () {
                                    final matchedId = (matchedUser?['id'] ?? '').toString();
                                    final realChatId = (chatId != null && !chatId.startsWith('chat_match_'))
                                        ? chatId
                                        : (currentUser.id.isNotEmpty && matchedId.isNotEmpty
                                            ? LikeService.getCanonicalChatId(currentUser.id, matchedId)
                                            : chatId);
                                    if (realChatId != null) {
                                      context.go(
                                        '/chats/$realChatId',
                                        extra: {
                                          'otherUserId': matchedId,
                                          'name': matchedName,
                                          'avatarUrl': matchedAvatar,
                                          'isOnline': true,
                                          'isConfession': false,
                                        },
                                      );
                                    } else {
                                      context.go('/chats');
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacing12),
                              GestureDetector(
                                onTap: () => context.go('/match'),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Keep Exploring',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: DesignTokens.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spacing24),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoPair({
    required String matchedAvatar,
    required String currentAvatar,
    required AppPalette palette,
  }) {
    return SizedBox(
      width: 290,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left photo (matched user)
          Positioned(
            left: 10,
            child: Transform.rotate(
              angle: -0.12,
              child: _PhotoFrame(
                imageUrl: matchedAvatar,
                size: 148,
                glowColor: palette.primary,
              ),
            ),
          ),
          // Right photo (current user)
          Positioned(
            right: 10,
            child: Transform.rotate(
              angle: 0.12,
              child: _PhotoFrame(
                imageUrl: currentAvatar,
                size: 148,
                glowColor: palette.secondary,
              ),
            ),
          ),
          // Heart badge in center
          AnimatedBuilder(
            animation: _heartBeat,
            builder: (context, child) => Transform.scale(
              scale: _heartBeat.value,
              child: child,
            ),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: DesignTokens.obsidianElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.favorite_rounded,
                  color: palette.primary,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoFrame extends StatelessWidget {
  final String imageUrl;
  final double size;
  final Color glowColor;

  const _PhotoFrame({
    required this.imageUrl,
    required this.size,
    required this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size * 1.35,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radius24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radius24 - 2.5),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: DesignTokens.obsidianCard),
          errorWidget: (_, __, ___) => Container(
            color: DesignTokens.obsidianCard,
            child: const Icon(Icons.person, color: DesignTokens.textTertiary),
          ),
        ),
      ),
    );
  }
}
