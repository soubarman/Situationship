import 'dart:ui';
import 'package:flutter/material.dart';

class BackgroundOrbs extends StatelessWidget {
  const BackgroundOrbs({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned.fill(
      child: Stack(
        children: [
          // Orb 1: Neon Cyan/Blue top left
          Positioned(
            top: -100,
            left: -100,
            width: 420,
            height: 420,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6ECBF5).withOpacity(isDark ? 0.16 : 0.45),
              ),
            ),
          ),
          // Orb 2: Accent Purple middle right
          Positioned(
            top: 250,
            right: -80,
            width: 400,
            height: 400,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB8A9FF).withOpacity(isDark ? 0.14 : 0.4),
              ),
            ),
          ),
          // Orb 3: Accent Pink bottom left
          Positioned(
            bottom: -50,
            left: -50,
            width: 380,
            height: 380,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF8EC8).withOpacity(isDark ? 0.16 : 0.4),
              ),
            ),
          ),
          // Full-screen backdrop filter to blend them beautifully!
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(color: Colors.transparent),
            ),
          ),
          // Floating Sparks/Stars
          Positioned(
            top: 120,
            right: 48,
            child: Icon(
              Icons.star_rounded,
              color: Colors.amber.withOpacity(isDark ? 0.25 : 0.35),
              size: 24,
            ),
          ),
          Positioned(
            top: 360,
            left: 36,
            child: Icon(
              Icons.favorite_rounded,
              color: const Color(0xFFFF8EC8).withOpacity(isDark ? 0.2 : 0.3),
              size: 20,
            ),
          ),
          Positioned(
            bottom: 220,
            right: 40,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: const Color(0xFFB8A9FF).withOpacity(isDark ? 0.25 : 0.35),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}
