import 'dart:math' as math;
import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// 3D Minted Gold Coin Icon
/// ─────────────────────────────────────────────────────────────────────────────
class Coin3dIcon extends StatelessWidget {
  final double size;
  final bool showShadow;

  const Coin3dIcon({
    super.key,
    this.size = 14,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final s = size;
    return RepaintBoundary(
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: const Color(0xFFE68A00).withValues(alpha: 0.40),
                    blurRadius: s * 0.35,
                    offset: Offset(0, s * 0.12),
                  ),
                  BoxShadow(
                    color: const Color(0xFFFFE082).withValues(alpha: 0.25),
                    blurRadius: s * 0.15,
                    offset: Offset(0, -s * 0.05),
                  ),
                ]
              : null,
        ),
        child: CustomPaint(
          size: Size(s, s),
          painter: _Coin3dPainter(),
        ),
      ),
    );
  }
}

class _Coin3dPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Outer beveled rim gradient (top-left bright, bottom-right deep metallic amber)
    final outerRimPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFF3A0), // Bright gold shine
          Color(0xFFFFB800), // Rich gold
          Color(0xFFC97A00), // Darker bronze edge
          Color(0xFF8F4E00), // Shadow bevel
        ],
        stops: [0.0, 0.45, 0.85, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, outerRimPaint);

    // 2. Beveled inner groove (depth illusion)
    final innerGrooveRadius = radius * 0.84;
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, size.width * 0.06)
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF8B4700),
          Color(0xFFE59900),
          Color(0xFFFFF099),
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: innerGrooveRadius));

    canvas.drawCircle(center, innerGrooveRadius, groovePaint);

    // 3. Inner Face with warm radial gradient
    final faceRadius = innerGrooveRadius - (groovePaint.strokeWidth * 0.5);
    if (faceRadius > 1) {
      final facePaint = Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.3),
          radius: 0.85,
          colors: [
            Color(0xFFFFEC80), // Sunburst highlight
            Color(0xFFFFB300), // Main coin gold
            Color(0xFFE08500), // Warm amber base
          ],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: faceRadius));

      canvas.drawCircle(center, faceRadius, facePaint);
    }

    // 4. Minted Center Emblem (Stylized "S" / diamond spark mark)
    final emblemSize = size.width * 0.44;
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'S',
        style: TextStyle(
          color: const Color(0xFF7A3E00),
          fontSize: emblemSize,
          fontWeight: FontWeight.w900,
          fontFamily: 'sans-serif',
          height: 1.0,
          shadows: [
            Shadow(
              color: const Color(0xFFFFF8BD).withValues(alpha: 0.85),
              offset: const Offset(0, 0.8),
              blurRadius: 0.5,
            ),
            Shadow(
              color: const Color(0xFF542900).withValues(alpha: 0.5),
              offset: const Offset(0, -0.5),
              blurRadius: 0.5,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      ),
    );

    // 5. Specular Gloss Arc Highlight across the top-left rim
    final glossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, size.width * 0.08)
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: math.pi * 0.9,
        endAngle: math.pi * 1.8,
        colors: [
          Colors.transparent,
          Color(0xDFFFFFFF),
          Colors.transparent,
        ],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.92));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.90),
      math.pi * 0.95,
      math.pi * 0.8,
      false,
      glossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// ─────────────────────────────────────────────────────────────────────────────
/// Crisp Vector Crown Icon
/// ─────────────────────────────────────────────────────────────────────────────
class CrownVector extends StatelessWidget {
  final double size;
  final Color? color;
  final bool is3dGold;

  const CrownVector({
    super.key,
    this.size = 12,
    this.color,
    this.is3dGold = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = size;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(s, s * 0.82),
        painter: _CrownPainter(
          color: color ?? (is3dGold ? const Color(0xFFFFB800) : Colors.white),
          is3dGold: is3dGold,
        ),
      ),
    );
  }
}

class _CrownPainter extends CustomPainter {
  final Color color;
  final bool is3dGold;

  _CrownPainter({required this.color, required this.is3dGold});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final crownPath = Path();

    // 3 Peaks Crown Silhouette
    final leftX = w * 0.08;
    final rightX = w * 0.92;
    final bottomY = h * 0.92;
    final baseY = h * 0.72;

    // Start at bottom-left band
    crownPath.moveTo(leftX, bottomY);
    crownPath.lineTo(leftX, baseY);
    // Peak 1: Left peak
    crownPath.lineTo(w * 0.04, h * 0.28);
    // Valley 1
    crownPath.lineTo(w * 0.32, h * 0.52);
    // Peak 2: Center peak (highest)
    crownPath.lineTo(w * 0.50, h * 0.06);
    // Valley 2
    crownPath.lineTo(w * 0.68, h * 0.52);
    // Peak 3: Right peak
    crownPath.lineTo(w * 0.96, h * 0.28);
    // Right side down to base
    crownPath.lineTo(rightX, baseY);
    crownPath.lineTo(rightX, bottomY);
    crownPath.close();

    final crownPaint = Paint()..style = PaintingStyle.fill;

    if (is3dGold) {
      crownPaint.shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFF099),
          Color(0xFFFFB800),
          Color(0xFFE68A00),
          Color(0xFFFFC72C),
        ],
        stops: [0.0, 0.4, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    } else {
      crownPaint.color = color;
    }

    // Shadow for depth if 3D gold
    if (is3dGold) {
      canvas.drawShadow(
        crownPath,
        const Color(0xFFFFB800).withValues(alpha: 0.6),
        3.0,
        false,
      );
    }

    canvas.drawPath(crownPath, crownPaint);

    // Jewels at each peak
    final orbPaint = Paint()..style = PaintingStyle.fill;
    if (is3dGold) {
      orbPaint.color = const Color(0xFFFFF8BD);
    } else {
      orbPaint.color = color;
    }

    final orbRadius = math.max(0.9, w * 0.075);
    canvas.drawCircle(Offset(w * 0.04, h * 0.26), orbRadius, orbPaint);
    canvas.drawCircle(Offset(w * 0.50, h * 0.05), orbRadius * 1.15, orbPaint);
    canvas.drawCircle(Offset(w * 0.96, h * 0.26), orbRadius, orbPaint);

    // Decorative crown band line
    final bandPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, h * 0.09);

    if (is3dGold) {
      bandPaint.color = const Color(0xFF8F4E00).withValues(alpha: 0.5);
    } else {
      bandPaint.color = (color == Colors.black ? Colors.white : Colors.black).withValues(alpha: 0.35);
    }

    canvas.drawLine(
      Offset(leftX + (w * 0.04), h * 0.82),
      Offset(rightX - (w * 0.04), h * 0.82),
      bandPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.is3dGold != is3dGold;
}

/// ─────────────────────────────────────────────────────────────────────────────
/// 3D Glowing Fire Icon
/// ─────────────────────────────────────────────────────────────────────────────
class Fire3dIcon extends StatelessWidget {
  final double size;

  const Fire3dIcon({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback: (bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF59D), // Yellow flame tip
              Color(0xFFFF9800), // Bright Orange
              Color(0xFFFF3D00), // Hot Vermilion base
              Color(0xFFD50000), // Deep Ember
            ],
            stops: [0.0, 0.35, 0.75, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.srcIn,
        child: Icon(
          Icons.local_fire_department_rounded,
          size: size,
          color: Colors.white,
          shadows: [
            Shadow(
              color: const Color(0xFFFF5722).withValues(alpha: 0.5),
              blurRadius: size * 0.4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
/// 3D Glowing Electric Bolt Icon
/// ─────────────────────────────────────────────────────────────────────────────
class Bolt3dIcon extends StatelessWidget {
  final double size;
  final bool isCyan;

  const Bolt3dIcon({super.key, this.size = 14, this.isCyan = false});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback: (bounds) {
          if (isCyan) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFE0F7FA),
                Color(0xFF00E5FF),
                Color(0xFF00B0FF),
              ],
              stops: [0.0, 0.5, 1.0],
            ).createShader(bounds);
          }
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFDE7), // Electric highlight
              Color(0xFFFFEA00), // Bright neon yellow
              Color(0xFFFF9100), // Vibrant amber edge
            ],
            stops: [0.0, 0.45, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.srcIn,
        child: Icon(
          Icons.bolt_rounded,
          size: size,
          color: Colors.white,
          shadows: [
            Shadow(
              color: (isCyan ? const Color(0xFF00E5FF) : const Color(0xFFFFAB00))
                  .withValues(alpha: 0.6),
              blurRadius: size * 0.35,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}
