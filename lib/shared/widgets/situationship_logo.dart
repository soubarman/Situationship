import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class _DoodleHeartPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _DoodleHeartPainter({
    required this.color,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(w * 0.5, h * 0.88);
    path.cubicTo(w * 0.15, h * 0.65, w * 0.02, h * 0.40, w * 0.05, h * 0.22);
    path.cubicTo(w * 0.08, h * 0.05, w * 0.32, h * 0.02, w * 0.5, h * 0.25);
    path.cubicTo(w * 0.68, h * 0.02, w * 0.92, h * 0.05, w * 0.95, h * 0.22);
    path.cubicTo(w * 0.98, h * 0.40, w * 0.85, h * 0.65, w * 0.5, h * 0.88);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DoodleHeartPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Official Situationship™ wordmark logo with the iconic doodle heart over the 'i'.
class SituationshipLogo extends StatelessWidget {
  final double fontSize;
  final bool isDark;
  final bool showTrademark;

  const SituationshipLogo({
    super.key,
    this.fontSize = 22,
    this.isDark = true,
    this.showTrademark = true,
  });

  @override
  Widget build(BuildContext context) {
    final scale = fontSize / 42.0;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF131127);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Situa"
        Text(
          'Situa',
          style: GoogleFonts.outfit(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: primaryTextColor,
            letterSpacing: -1.2 * scale,
            height: 1.0,
            shadows: isDark
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 10 * scale,
                      offset: Offset(0, 2 * scale),
                    ),
                  ]
                : null,
          ),
        ),

        // "t" in coral pink
        Text(
          't',
          style: GoogleFonts.outfit(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFFF5277),
            letterSpacing: -1.2 * scale,
            height: 1.0,
            shadows: [
              Shadow(
                color: const Color(0xFFFF5277).withValues(alpha: 0.35),
                blurRadius: 10 * scale,
              ),
            ],
          ),
        ),

        // "i" with small pink doodle heart floating on top of it instead of dot!
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              top: -9.0 * scale,
              child: CustomPaint(
                size: Size(13 * scale, 11 * scale),
                painter: _DoodleHeartPainter(
                  color: const Color(0xFFFF6584),
                  strokeWidth: math.max(1.2, 2.0 * scale),
                ),
              ),
            ),
            Text(
              'i',
              style: GoogleFonts.outfit(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFFF5E7E),
                letterSpacing: -1.2 * scale,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: const Color(0xFFFF5E7E).withValues(alpha: 0.35),
                    blurRadius: 10 * scale,
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
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1.2 * scale,
              height: 1.0,
            ),
          ),
        ),

        // Superscript "™"
        if (showTrademark)
          Padding(
            padding: EdgeInsets.only(top: 1.5 * scale, left: 2.5 * scale),
            child: Text(
              '™',
              style: TextStyle(
                fontSize: math.max(8.0, 11.5 * scale),
                fontWeight: FontWeight.w800,
                color: (isDark ? Colors.white : const Color(0xFF131127)).withValues(alpha: 0.75),
              ),
            ),
          ),
      ],
    );
  }
}
