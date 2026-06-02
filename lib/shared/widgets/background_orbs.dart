import 'dart:ui';
import 'package:flutter/material.dart';

/// Soft background orbs rendered using RadialGradient.
///
/// PERFORMANCE: No BackdropFilter — RadialGradient is equivalent to
/// sigma-90 blur on a solid circle (same falloff, zero GPU compositing).
/// RepaintBoundary is placed INSIDE Positioned.fill so the parent Stack
/// positions correctly while still caching the orb layer as a GPU texture.
class BackgroundOrbs extends StatelessWidget {
  const BackgroundOrbs({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Positioned.fill MUST be the outermost widget so the parent Stack
    // can read the positioning directive. RepaintBoundary is inside it.
    return Positioned.fill(
      child: RepaintBoundary(
        child: Stack(
          children: [
            // ── Orb 1: Neon Cyan/Blue — top left ─────────────────────────
            Positioned(
              top: -120,
              left: -120,
              width: 480,
              height: 480,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF6ECBF5)
                          .withOpacity(isDark ? 0.45 : 0.75),
                      const Color(0xFF6ECBF5).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),

            // ── Orb 2: Accent Purple — middle right ──────────────────────
            Positioned(
              top: 220,
              right: -100,
              width: 460,
              height: 460,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFB8A9FF)
                          .withOpacity(isDark ? 0.42 : 0.70),
                      const Color(0xFFB8A9FF).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),

            // ── Orb 3: Accent Pink — bottom left ─────────────────────────
            Positioned(
              bottom: -80,
              left: -80,
              width: 440,
              height: 440,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFF8EC8)
                          .withOpacity(isDark ? 0.42 : 0.70),
                      const Color(0xFFFF8EC8).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),

            // ── Decorative sparks ─────────────────────────────────────────
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
