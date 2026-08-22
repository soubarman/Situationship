import 'package:flutter/material.dart';
import 'package:situationship/core/theme/app_theme.dart';
import '../models/spotlight_model.dart';
import 'dart:math' as math;
import '../../verification/presentation/widgets/s_badge_widget.dart';

class SpotlightCard extends StatelessWidget {
  final SpotlightBid bid;

  const SpotlightCard({super.key, required this.bid});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Determine rank styling
    final bool isTop3 = bid.rank <= 3;
    final Color rankColor;
    final List<Color> gradientColors;
    
    switch (bid.rank) {
      case 1:
        rankColor = const Color(0xFFFFD700); // Gold
        gradientColors = [
          const Color(0xFFFFD700).withOpacity(0.15),
          const Color(0xFFFFA500).withOpacity(0.05)
        ];
        break;
      case 2:
        rankColor = const Color(0xFFE0E0E0); // Silver
        gradientColors = [
          const Color(0xFFE0E0E0).withOpacity(0.1),
          const Color(0xFFBDBDBD).withOpacity(0.05)
        ];
        break;
      case 3:
        rankColor = const Color(0xFFCD7F32); // Bronze
        gradientColors = [
          const Color(0xFFCD7F32).withOpacity(0.15),
          const Color(0xFF8B4513).withOpacity(0.05)
        ];
        break;
      default:
        rankColor = Colors.white54;
        gradientColors = [
          AppTheme.primaryBlue.withOpacity(0.05),
          Colors.transparent
        ];
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.symmetric(
        horizontal: isTop3 ? 6.0 : 16.0,
        vertical: isTop3 ? 0.0 : 6.0,
      ),
      width: isTop3 ? 110 : null,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rankColor.withOpacity(isTop3 ? 0.4 : 0.1),
          width: isTop3 ? 1.5 : 1.0,
        ),
        boxShadow: isTop3 ? [
          BoxShadow(
            color: rankColor.withOpacity(0.15),
            blurRadius: 12,
            spreadRadius: 2,
          )
        ] : null,
      ),
      child: isTop3 ? _buildTop3Card(context, rankColor) : _buildListCard(context, rankColor),
    );
  }

  Widget _buildTop3Card(BuildContext context, Color rankColor) {
    final isPlaceholder = bid.userId.isEmpty;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isPlaceholder ? rankColor.withOpacity(0.3) : rankColor, 
                    width: 2,
                  ),
                  image: isPlaceholder ? null : DecorationImage(
                    image: NetworkImage(bid.profileImageUrl),
                    fit: BoxFit.cover,
                  ),
                  color: isPlaceholder ? rankColor.withOpacity(0.1) : null,
                ),
                child: isPlaceholder 
                    ? Icon(Icons.add_rounded, color: rankColor.withOpacity(0.7), size: 24)
                    : null,
              ),
              if (bid.rank == 1)
                Positioned(
                  top: -16,
                  child: Transform.rotate(
                    angle: math.pi / 12,
                    child: const Text('👑', style: TextStyle(fontSize: 24)),
                  ),
                ),
              Positioned(
                bottom: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPlaceholder ? rankColor.withOpacity(0.4) : rankColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#${bid.rank}',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  isPlaceholder ? 'Empty' : bid.username,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isPlaceholder ? Colors.white38 : Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (bid.isVerified && !isPlaceholder) ...[
                const SizedBox(width: 4),
                const SBadgeWidget(size: 12, showTooltip: false),
              ]
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '₹${bid.amount}',
              style: TextStyle(
                color: isPlaceholder ? rankColor.withOpacity(0.4) : rankColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListCard(BuildContext context, Color rankColor) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Center(
              child: Text(
                '#${bid.rank}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 20,
            backgroundImage: NetworkImage(bid.profileImageUrl),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        bid.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (bid.isVerified) ...[
                      const SizedBox(width: 4),
                      const SBadgeWidget(size: 14, showTooltip: false),
                    ]
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
            ),
            child: Text(
              '₹${bid.amount}',
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
