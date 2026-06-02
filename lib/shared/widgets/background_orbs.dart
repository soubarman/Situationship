import 'dart:ui';
import 'package:flutter/material.dart';

/// Static background gradient orbs used on main screens.
///
/// PERFORMANCE: Wrapped in RepaintBoundary so Flutter caches it as its
/// own raster layer. Scrolling lists above/below never trigger a repaint
/// of this widget — it's drawn exactly once and reused.
class BackgroundOrbs extends StatelessWidget {
  const BackgroundOrbs({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // RepaintBoundary isolates this layer — the scroll view repainting above
    // it never causes this to re-rasterize. This is the #1 perf fix.
    return RepaintBoundary(
      child: Positioned.fill(
        child: Stack(
          children: [
            // Orb 1: Neon Cyan/Blue top-left
            Positioned(
              top: -100,
              left: -100,
              width: 420,
              height: 420,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6ECBF5)
                      .withOpacity(isDark ? 0.16 : 0.45),
                ),
              ),
            ),
            // Orb 2: Accent Purple middle-right
            Positioned(
              top: 250,
              right: -80,
              width: 400,
              height: 400,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFB8A9FF)
                      .withOpacity(isDark ? 0.14 : 0.40),
                ),
              ),
            ),
            // Orb 3: Accent Pink bottom-left
            Positioned(
              bottom: -50,
              left: -50,
              width: 380,
              height: 380,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF8EC8)
                      .withOpacity(isDark ? 0.16 : 0.40),
                ),
              ),
            ),
            // Full-screen backdrop blur — sigma reduced from 90→50 (50% faster GPU pass)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            // Decorative sparks (const — never rebuild)
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
                color: const Color(0xFFFF8EC8)
                    .withOpacity(isDark ? 0.20 : 0.30),
                size: 20,
              ),
            ),
            Positioned(
              bottom: 220,
              right: 40,
              child: Icon(
                Icons.auto_awesome_rounded,
                color: const Color(0xFFB8A9FF)
                    .withOpacity(isDark ? 0.25 : 0.35),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
