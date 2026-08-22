// lib/features/verification/presentation/widgets/s_badge_widget.dart
//
// The custom "S" verification badge.
// Renders inline next to a username or as a standalone icon.
// Usage: SBadgeWidget()  or  SBadgeWidget(size: 18)

import 'package:flutter/material.dart';

class SBadgeWidget extends StatelessWidget {
  final double size;
  final bool showTooltip;

  const SBadgeWidget({
    super.key,
    this.size = 20,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFF6B9D),   // Pink
            Color(0xFFAB47BC),   // Purple
            Color(0xFF7C4DFF),   // Deep purple
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFAB47BC).withOpacity(0.5),
            blurRadius: size * 0.4,
            spreadRadius: size * 0.05,
          ),
        ],
      ),
      child: Center(
        child: Text(
          'S',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.55,
            fontWeight: FontWeight.w900,
            fontFamily: 'SF Pro Display',
            height: 1.0,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );

    if (!showTooltip) return badge;

    return Tooltip(
      message: 'Verified by Situationship',
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontFamily: 'SF Pro Display',
      ),
      child: badge,
    );
  }
}

/// Inline username row with optional S badge.
/// Usage: VerifiedNameRow(name: user.name, isVerified: user.isVerified)
class VerifiedNameRow extends StatelessWidget {
  final String name;
  final bool isVerified;
  final String? verifiedBadge;
  final TextStyle? nameStyle;
  final double badgeSize;
  final double gap;

  const VerifiedNameRow({
    super.key,
    required this.name,
    required this.isVerified,
    this.verifiedBadge,
    this.nameStyle,
    this.badgeSize = 18,
    this.gap = 4,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = isVerified && (verifiedBadge == 'S' || verifiedBadge == null && isVerified);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          name,
          style: nameStyle ??
              const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.white,
              ),
          overflow: TextOverflow.ellipsis,
        ),
        if (showBadge) ...[
          SizedBox(width: gap),
          SBadgeWidget(size: badgeSize),
        ],
      ],
    );
  }
}
