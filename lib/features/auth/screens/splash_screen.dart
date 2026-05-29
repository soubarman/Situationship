import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import 'dart:math' as math;

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    _controller.forward();

    // Replay floating effect after entrance is finished
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.repeat(reverse: true);
      }
    });

    // The router's `redirect` watches the Firebase auth stream.
    // Once Firebase resolves the auth state it will automatically
    // navigate to /feed (if logged in) or /login (if not).
    Future.delayed(const Duration(milliseconds: 4500), () {
      if (mounted) {
        context.go('/login');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF1F5F9), // Soft slate white
              Color(0xFFFDF4FF), // Very soft lavender/pink
              Color(0xFFFAE8FF), // Pastel violet
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Entrance animation combines scale + translation (for float)
                final translationY = _controller.status == AnimationStatus.forward
                    ? (1.0 - _fadeAnimation.value) * 60.0
                    : math.sin(_controller.value * math.pi * 2) * 8.0;

                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, translationY),
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: _buildLogoCard(isDark),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoCard(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Neumorphic/Popping Container for logo
        Container(
          width: 320,
          height: 320,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(56),
            boxShadow: [
              // Soft Ambient Dark Glow (Pastel Purple)
              BoxShadow(
                color: const Color(0xFFE8BBFF).withOpacity(0.55),
                blurRadius: 50,
                spreadRadius: 6,
                offset: const Offset(10, 16),
              ),
              // Soft Ambient Light Glow (Pure White)
              BoxShadow(
                color: Colors.white.withOpacity(0.85),
                blurRadius: 40,
                spreadRadius: 4,
                offset: const Offset(-10, -10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(56),
            child: kIsWeb
                ? Image.network(
                    'icons/logo.jpeg',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Image.asset(
                        'assets/images/logo.jpeg',
                        fit: BoxFit.cover,
                      );
                    },
                  )
                : Image.asset(
                    'assets/images/logo.jpeg',
                    fit: BoxFit.cover,
                  ),
          ),
        ),
        const SizedBox(height: 48),
        // Minimalist Premium Spinner
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              AppTheme.primaryBlue.withOpacity(0.4),
            ),
          ),
        ),
      ],
    );
  }
}
