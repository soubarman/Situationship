import 'package:flutter/material.dart';

class BoostBadge extends StatelessWidget {
  final bool isPremium;
  final VoidCallback? onTap;

  const BoostBadge({
    super.key,
    this.isPremium = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPremium
              ? const [Color(0xFFFFB800), Color(0xFFFF3366)]
              : const [Color(0xFF3B82F6), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPremium ? const Color(0xFFFF8A00) : const Color(0xFF6366F1)).withValues(alpha: 0.4),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: const Icon(
        Icons.bolt_rounded,
        color: Colors.white,
        size: 13,
      ),
    );

    return Tooltip(
      message: isPremium ? 'Premium Boosted' : 'Boosted',
      child: onTap != null
          ? MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: badge,
              ),
            )
          : badge,
    );
  }
}
