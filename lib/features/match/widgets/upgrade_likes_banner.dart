import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/providers/app_state_provider.dart';

/// Exactly matches the dark, premium "Upgrade to see who likes you" banner
/// with golden crown badge, sky-blue title, and glowing "Go Premium >" pill button.
class UpgradeLikesBanner extends ConsumerWidget {
  const UpgradeLikesBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _showPremiumUpgradeSheet(context, ref);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1322),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF1E2D4A).withOpacity(0.75),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.55),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: const Color(0xFF1E3A8A).withOpacity(0.18),
              blurRadius: 28,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Crown Icon Box ──────────────────────────────────────────
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF291E18),
                    Color(0xFF15100E),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFFE58E26).withOpacity(0.55),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD97706).withOpacity(0.35),
                    blurRadius: 14,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: const Center(
                child: CustomPaint(
                  size: Size(26, 20),
                  painter: _CrownPainter(),
                ),
              ),
            ),

            const SizedBox(width: 14),

            // ── Middle Text Column ──────────────────────────────────────
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Upgrade to see who likes you',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6BA6FF),
                      letterSpacing: -0.2,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3.5),
                  Text(
                    'Get unlimited faceoffs and more!',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFFA0ABBA),
                      letterSpacing: 0.0,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ── Right "Go Premium >" Button ─────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF4CA5FF),
                    Color(0xFF1D68F5),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.55),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: const Color(0xFF38BDF8).withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Go Premium',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  SizedBox(width: 3),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPremiumUpgradeSheet(BuildContext context, WidgetRef ref) {
    final palette = ref.read(appPaletteProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (ctx) => _PremiumUpgradeSheet(palette: palette, isDark: isDark),
    );
  }
}

/// Exact vector painter for the 3-pointed lustrous gold crown icon
class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Gradient fill for crown body
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFE599), // bright warm pale gold at top tips
          Color(0xFFFBBF24), // radiant amber-gold body
          Color(0xFFD97706), // warm amber base
        ],
        stops: [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path();
    // Bottom-left with slight bevel
    path.moveTo(w * 0.08, h * 0.88);
    // Base line to bottom-right
    path.lineTo(w * 0.92, h * 0.88);
    // Right side up to right peak
    path.lineTo(w * 0.96, h * 0.28);
    // Valley curve between right peak and center peak
    path.quadraticBezierTo(w * 0.73, h * 0.62, w * 0.50, h * 0.06);
    // Valley curve between center peak and left peak
    path.quadraticBezierTo(w * 0.27, h * 0.62, w * 0.04, h * 0.28);
    // Left side down to bottom-left
    path.lineTo(w * 0.08, h * 0.88);
    path.close();

    // Soft subtle ambient glow under the crown
    final glowPaint = Paint()
      ..color = const Color(0xFFF59E0B).withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawPath(path, glowPaint);

    // Draw main solid gradient crown
    canvas.drawPath(path, fillPaint);

    // Subtle horizontal highlight band along the base
    final highlightPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Colors.transparent,
          Color(0xFFFFF7D6),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(w * 0.15, h * 0.82, w * 0.70, 2))
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(w * 0.18, h * 0.84),
      Offset(w * 0.82, h * 0.84),
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Interactive sheet shown when user taps the banner or "Go Premium" button
class _PremiumUpgradeSheet extends StatelessWidget {
  final AppPalette palette;
  final bool isDark;

  const _PremiumUpgradeSheet({required this.palette, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0C1322) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 42,
              height: 4.5,
              margin: const EdgeInsets.only(bottom: 22),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),

            // Crown Header Badge
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF291E18),
                    Color(0xFF15100E),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFFE58E26).withOpacity(0.55),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD97706).withOpacity(0.35),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: const Center(
                child: CustomPaint(
                  size: Size(32, 24),
                  painter: _CrownPainter(),
                ),
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              'Situationship Gold',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF6BA6FF),
                letterSpacing: -0.3,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Upgrade to unlock the ultimate dating & social experience',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFA0ABBA),
              ),
            ),

            const SizedBox(height: 22),

            // Feature perks
            _buildFeatureTile(
              icon: Icons.visibility_rounded,
              iconColor: const Color(0xFF6BA6FF),
              title: 'See Who Likes You',
              subtitle: 'Instantly reveal everyone who swiped or liked you without coins',
            ),
            const SizedBox(height: 10),
            _buildFeatureTile(
              icon: Icons.flash_on_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'Unlimited Faceoffs',
              subtitle: 'Never hit daily limits; keep matching and discovering without pause',
            ),
            const SizedBox(height: 10),
            _buildFeatureTile(
              icon: Icons.replay_rounded,
              iconColor: const Color(0xFF10B981),
              title: 'Unlimited Rewinds & Undos',
              subtitle: 'Accidentally passed on a profile? Take it back anytime effortlessly',
            ),
            const SizedBox(height: 10),
            _buildFeatureTile(
              icon: Icons.rocket_launch_rounded,
              iconColor: const Color(0xFFEC4899),
              title: 'Free Weekly Spotlight',
              subtitle: 'Get placed on campus top-rank cards and double your interaction aura',
            ),

            const SizedBox(height: 24),

            // Get Premium Action Button
            GestureDetector(
              onTap: () {
                HapticFeedback.heavyImpact();
                Navigator.of(context, rootNavigator: true).pop();
                context.push('/wallet');
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF4CA5FF),
                      Color(0xFF1D68F5),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.55),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'Get Premium in Wallet',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121B2E) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E2D4A).withOpacity(0.5) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withOpacity(0.15),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? const Color(0xFFA0ABBA) : Colors.black54,
                    height: 1.25,
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
