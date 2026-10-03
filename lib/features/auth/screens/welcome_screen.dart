import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
    );

    _slideAnim = Tween<double>(begin: 24, end: 0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: Curves.easeOutCubic,
      ),
    );

    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0B12),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. Full-Bleed Atmospheric Couple Background ───────────────────
          Positioned.fill(
            child: kIsWeb
                ? Image.asset(
                    'assets/images/welcome_bg.jpg',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.4),
                    errorBuilder: (_, __, ___) => Image.network(
                      'welcome_bg.jpg',
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.4),
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF161520),
                      ),
                    ),
                  )
                : Image.asset(
                    'assets/images/welcome_bg.jpg',
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -0.4),
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF161520),
                    ),
                  ),
          ),

          // ── 2. Atmospheric Dark Vignette & Gradient Overlays ──────────────
          // Top subtle gradient for status bar & skip button readability
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Middle-to-bottom dark gradient to create seamless background for UI
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: size.height * 0.68,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      const Color(0xFF0C0B12).withValues(alpha: 0.45),
                      const Color(0xFF0C0B12).withValues(alpha: 0.88),
                      const Color(0xFF0C0B12),
                    ],
                    stops: const [0.0, 0.28, 0.58, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── 3. Hand-Drawn Doodle Accents ─────────────────────────────────
          // Top-Left Floating Doodle Heart (near the woman)
          Positioned(
            top: size.height * 0.13,
            left: 36,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: -0.22,
                child: CustomPaint(
                  size: const Size(34, 34),
                  painter: _DoodleHeartPainter(color: const Color(0xFFFF5E8A)),
                ),
              ),
            ),
          ),

          // Top-Right Floating Sparkle/Burst Lines (near the man)
          Positioned(
            top: size.height * 0.21,
            right: 32,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(30, 36),
                painter: _DoodleBurstPainter(color: const Color(0xFFFF5E8A)),
              ),
            ),
          ),

          // ── 4. Main Foreground Content (SafeArea) ─────────────────────────
          SafeArea(
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnim.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnim.value),
                    child: child,
                  ),
                );
              },
              child: Column(
                children: [
                  const Spacer(),

                  // ── Center Branding & Tagline ─────────────────────────────
                  _buildBranding(context),

                  const SizedBox(height: 28),

                  // ── 4 Feature Highlights Grid ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: _buildFeaturePills(),
                  ),

                  const SizedBox(height: 32),

                  // ── Action Buttons ────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      children: [
                        // Primary: "Create Account" Pill
                        _buildCreateAccountButton(context),

                        const SizedBox(height: 14),

                        // Secondary: "I Already Have an Account" Outline Pill
                        _buildLoginButton(context),
                      ],
                    ),
                  ),

                  const SizedBox(height: 26),

                  // ── Bottom Decorative Flourish & Muted Tagline ───────────
                  _buildBottomFlourish(),

                  SizedBox(height: bottomPadding > 0 ? bottomPadding + 6 : 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Branding Widget: "Situationship™" + "Define the undefined" ───────────────
  Widget _buildBranding(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Situationship™" Title
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "Situa" in Bold White
            Text(
              'Situa',
              style: GoogleFonts.outfit(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1.2,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 16,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),

            // "t"
            Text(
              't',
              style: GoogleFonts.outfit(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFFF5277),
                letterSpacing: -1.2,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: const Color(0xFFFF5277).withValues(alpha: 0.4),
                    blurRadius: 16,
                  ),
                ],
              ),
            ),

            // "i" with small pink heart floating on top of it instead of dot!
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: -9,
                  child: CustomPaint(
                    size: const Size(13, 11),
                    painter: _DoodleHeartPainter(
                      color: const Color(0xFFFF6584),
                      strokeWidth: 2.0,
                    ),
                  ),
                ),
                Text(
                  'i',
                  style: GoogleFonts.outfit(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFFF5E7E),
                    letterSpacing: -1.2,
                    height: 1.0,
                    shadows: [
                      Shadow(
                        color: const Color(0xFFFF5E7E).withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // "onship" with Warm Gradient
            ShaderMask(
              shaderCallback: (bounds) {
                return const LinearGradient(
                  colors: [
                    Color(0xFFFF6584),
                    Color(0xFFFF7E7E),
                    Color(0xFFFFA573),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(bounds);
              },
              child: Text(
                'onship',
                style: GoogleFonts.outfit(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.2,
                  height: 1.0,
                ),
              ),
            ),

            // Superscript "™"
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 3),
              child: Text(
                '™',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        // "Define the undefined" with brush underline under "undefined"
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Define the ',
              style: GoogleFonts.caveat(
                fontSize: 27,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.95),
                letterSpacing: 0.5,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'undefined',
                  style: GoogleFonts.caveat(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                CustomPaint(
                  size: const Size(96, 5),
                  painter: _BrushUnderlinePainter(
                    color: const Color(0xFFFF5E8A),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ── 4 Feature Highlights Grid ─────────────────────────────────────────────
  Widget _buildFeaturePills() {
    final items = [
      _FeatureData(
        icon: Icons.favorite_border_rounded,
        color: const Color(0xFFFF4E78),
        title: 'Real',
        subtitle: 'People',
      ),
      _FeatureData(
        icon: Icons.chat_bubble_outline_rounded,
        color: const Color(0xFFA855F7),
        title: 'Real',
        subtitle: 'Vibes',
      ),
      _FeatureData(
        icon: Icons.people_outline_rounded,
        color: const Color(0xFFFBBF24),
        title: 'Your',
        subtitle: 'Way',
      ),
      _FeatureData(
        icon: Icons.auto_awesome_outlined,
        color: const Color(0xFF34D399),
        title: 'No',
        subtitle: 'Pressure',
      ),
    ];

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Glassmorphic rounded square icon container
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      height: 58,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1A26).withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.09),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          item.icon,
                          size: 26,
                          color: item.color,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                // 2-line clean muted label
                Text(
                  '${item.title}\n${item.subtitle}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.8),
                    height: 1.22,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Primary Button: "Create Account" Pill with Arrow ──────────────────────
  Widget _buildCreateAccountButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF3366),
            Color(0xFFFF5252),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3366).withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/login/signup'),
          borderRadius: BorderRadius.circular(28),
          splashColor: Colors.white.withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left dummy placeholder to perfectly center text
                const SizedBox(width: 24),

                // Center Text
                Text(
                  'Create Account',
                  style: GoogleFonts.outfit(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),

                // Right Arrow
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Secondary Button: "I Already Have an Account" Outline Pill ─────────────
  Widget _buildLoginButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF13121C).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.28),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/login'),
          borderRadius: BorderRadius.circular(28),
          splashColor: Colors.white.withValues(alpha: 0.1),
          child: Center(
            child: Text(
              'I Already Have an Account',
              style: GoogleFonts.outfit(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom Flourish: Curved Line with Heart + Muted Letterspaced Slogan ───
  Widget _buildBottomFlourish() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(220, 16),
          painter: _BottomFlourishPainter(
            color: const Color(0xFF7E7998).withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'PEOPLE   •   VIBES   •   CONNECTIONS',
          style: GoogleFonts.outfit(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.38),
            letterSpacing: 2.8,
          ),
        ),
      ],
    );
  }
}

// ── Helpers & Custom Painters ────────────────────────────────────────────────

class _FeatureData {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  _FeatureData({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
}

/// Custom painter for a hand-drawn tilted doodle heart outline
class _DoodleHeartPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _DoodleHeartPainter({required this.color, this.strokeWidth = 2.4});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(w * 0.5, h * 0.88);
    path.cubicTo(w * 0.1, h * 0.58, w * 0.02, h * 0.22, w * 0.28, h * 0.08);
    path.cubicTo(w * 0.45, -0.01, w * 0.5, h * 0.2, w * 0.5, h * 0.25);
    path.cubicTo(w * 0.5, h * 0.2, w * 0.55, -0.01, w * 0.72, h * 0.08);
    path.cubicTo(w * 0.98, h * 0.22, w * 0.9, h * 0.58, w * 0.5, h * 0.88);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for a 3-line hand-drawn radiant burst doodle
class _DoodleBurstPainter extends CustomPainter {
  final Color color;

  _DoodleBurstPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top ray
    canvas.drawLine(
      const Offset(22, 2),
      const Offset(10, 10),
      paint,
    );
    // Middle ray
    canvas.drawLine(
      const Offset(28, 16),
      const Offset(14, 18),
      paint,
    );
    // Bottom ray
    canvas.drawLine(
      const Offset(24, 30),
      const Offset(12, 26),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for the hand-drawn brush underline below "undefined"
class _BrushUnderlinePainter extends CustomPainter {
  final Color color;

  _BrushUnderlinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height * 0.5);
    path.quadraticBezierTo(
      size.width * 0.5,
      size.height * 1.35,
      size.width,
      size.height * 0.2,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for the bottom flourish: wavy curved line with center heart
class _BottomFlourishPainter extends CustomPainter {
  final Color color;

  _BottomFlourishPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final cy = h * 0.55;

    // Left curved stroke
    final leftPath = Path();
    leftPath.moveTo(0, cy + 3);
    leftPath.cubicTo(w * 0.18, cy - 6, w * 0.32, cy + 6, w * 0.44, cy);
    canvas.drawPath(leftPath, paint);

    // Right curved stroke
    final rightPath = Path();
    rightPath.moveTo(w * 0.56, cy);
    rightPath.cubicTo(w * 0.68, cy + 6, w * 0.82, cy - 6, w, cy + 3);
    canvas.drawPath(rightPath, paint);

    // Center mini heart
    final heartPath = Path();
    final hx = w * 0.5;
    final hy = cy - 4.5;
    heartPath.moveTo(hx, hy + 7.5);
    heartPath.cubicTo(hx - 5.5, hy + 2.5, hx - 7.5, hy - 4.5, hx - 3.5, hy - 6.5);
    heartPath.cubicTo(hx - 0.5, hy - 7.5, hx, hy - 3.5, hx, hy - 2);
    heartPath.cubicTo(hx, hy - 3.5, hx + 0.5, hy - 7.5, hx + 3.5, hy - 6.5);
    heartPath.cubicTo(hx + 7.5, hy - 4.5, hx + 5.5, hy + 2.5, hx, hy + 7.5);

    canvas.drawPath(heartPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
