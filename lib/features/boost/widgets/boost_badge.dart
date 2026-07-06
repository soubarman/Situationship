import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class BoostBadge extends StatelessWidget {
  final bool isPremium;

  const BoostBadge({
    super.key,
    this.isPremium = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPremium 
              ? [Colors.amber.shade700, Colors.orange.shade900]
              : [AppTheme.primaryBlue, Colors.blue.shade800],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (isPremium ? Colors.orange : AppTheme.primaryBlue).withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.bolt,
            color: Colors.white,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            isPremium ? 'Premium Boost' : 'Boosted',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
