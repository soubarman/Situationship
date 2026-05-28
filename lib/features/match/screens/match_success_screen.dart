import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';

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
  late AnimationController _confettiController;

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
      duration: const Duration(milliseconds: 1200),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _fadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideUp = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );

    _scalePhotos = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.1, 0.7, curve: Curves.elasticOut),
      ),
    );

    _heartPulse = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _heartBeat = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.4, 0.8, curve: Curves.elasticOut),
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
    final matchedName = matchedUser?['name'] as String? ?? 'Julia';
    final matchedAvatar = matchedUser?['avatarUrl'] as String? ??
        'https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?w=400';
    final chatId = matchedUser?['chatId'] as String?;
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFB8EDFF),
              Color(0xFFB8FFE4),
              Color(0xFFD4E4FF),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _mainController,
            builder: (context, child) {
              return Column(
                children: [
                  const SizedBox(height: 40),
                  // Close button
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 20),
                      child: FadeTransition(
                        opacity: _fadeIn,
                        child: GestureDetector(
                          onTap: () => context.go('/match'),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Photos
                  FadeTransition(
                    opacity: _fadeIn,
                    child: ScaleTransition(
                      scale: _scalePhotos,
                      child: _buildPhotoPair(
                        matchedAvatar: matchedAvatar,
                        currentAvatar: currentUser.avatarUrl ??
                            'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=400',
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Match text
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Transform.translate(
                      offset: Offset(0, _slideUp.value),
                      child: Column(
                        children: [
                          const Text(
                            "You matched! 🎉",
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A2A3A),
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'You and $matchedName have 36 Hours\nto make the first move',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: AppTheme.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Start chat button
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Transform.translate(
                      offset: Offset(0, _slideUp.value),
                      child: ScaleTransition(
                        scale: _heartPulse,
                        child: GestureDetector(
                          onTap: () {
                            if (chatId != null) {
                              context.go(
                                '/chats/$chatId',
                                extra: {
                                  'name': matchedName,
                                  'avatarUrl': matchedAvatar,
                                  'isOnline': true,
                                },
                              );
                            } else {
                              context.go('/chats');
                            }
                          },
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryBlue.withOpacity(0.25),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.chat_rounded,
                              size: 30,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Text(
                      'Start Chat',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Keep swiping
                  FadeTransition(
                    opacity: _fadeIn,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: GestureDetector(
                        onTap: () => context.go('/match'),
                        child: Text(
                          'Keep Discovering →',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryBlue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPair({
    required String matchedAvatar,
    required String currentAvatar,
  }) {
    return SizedBox(
      width: 280,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Left photo (matched user)
          Positioned(
            left: 0,
            child: Transform.rotate(
              angle: -0.15,
              child: _PhotoFrame(
                imageUrl: matchedAvatar,
                size: 160,
              ),
            ),
          ),
          // Right photo (current user)
          Positioned(
            right: 0,
            child: Transform.rotate(
              angle: 0.15,
              child: _PhotoFrame(
                imageUrl: currentAvatar,
                size: 155,
              ),
            ),
          ),
          // Heart in center
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
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.favorite_rounded,
                  color: AppTheme.primaryBlue,
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

  const _PhotoFrame({required this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size * 1.3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
