import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';

import 'package:situationship/core/theme/app_theme.dart';
import 'package:situationship/core/theme/app_palette.dart';
import '../models/spotlight_model.dart';
import '../providers/spotlight_provider.dart';
import '../providers/location_provider.dart';

class SpotlightFeedSection extends ConsumerWidget {
  const SpotlightFeedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(locationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = ref.watch(appPaletteProvider);

    return locationAsync.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => _LocationPrompt(isDark: isDark, palette: palette, isPermanentlyDenied: true, errorMessage: e.toString(), ref: ref),
      data: (locState) {
        if (locState.status != LocationStatus.granted) {
          return _LocationPrompt(
            isDark: isDark,
            palette: palette,
            isPermanentlyDenied: locState.status == LocationStatus.deniedForever,
            ref: ref,
          );
        }

        final sessionAsync = ref.watch(spotlightSessionProvider);
        return sessionAsync.when(
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => const SizedBox.shrink(),
          data: (session) {
            if (session == null) return const SizedBox.shrink();

            final bidsAsync = ref.watch(spotlightBidsProvider(session.id));
            return bidsAsync.when(
              loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => const SizedBox.shrink(),
              data: (bids) {
                // Filter real bids from Firestore
                final realBids = bids.where((b) => b.userId.isNotEmpty).toList();

                final List<SpotlightBid> displayBids = [];
                // Take up to 10 booked bids
                final bookedBids = realBids.take(10).toList();
                displayBids.addAll(bookedBids);

                // If slots are booked, the single open slot shifts up until the 10th position.
                // Once 10 slots are booked, the open slot disappears.
                // If any slot is deleted (bookedBids.length < 10), the open slot appears again!
                if (bookedBids.length < 10) {
                  displayBids.add(_createPlaceholderBid(
                    session.id,
                    bookedBids.length + 1,
                    session.minStartingBid,
                  ));
                }

                return SizedBox(
                  height: 185,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: displayBids.length,
                    itemBuilder: (context, index) {
                      return SpotlightFeedCard(bid: displayBids[index], palette: palette);
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  SpotlightBid _createPlaceholderBid(String sessionId, int rank, int minBid) {
    return SpotlightBid(
      id: 'placeholder_$rank',
      sessionId: sessionId,
      userId: '',
      username: 'Spot Open',
      profileImageUrl: '',
      isVerified: false,
      amount: minBid,
      timestamp: DateTime.now(),
      rank: rank,
    );
  }
}

// ─── Location Permission Prompt ───────────────────────────────────────────────

class _LocationPrompt extends StatelessWidget {
  final bool isDark;
  final bool isPermanentlyDenied;
  final AppPalette palette;
  final String? errorMessage;
  final WidgetRef ref;

  const _LocationPrompt({
    required this.isDark,
    required this.isPermanentlyDenied,
    required this.palette,
    this.errorMessage,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A0D20) : const Color(0xFFFDE8F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: palette.primary.withOpacity(0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: palette.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⚡ Spotlight is location-based',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isPermanentlyDenied
                      ? 'Enable location in Settings to see your area\'s Spotlight.'
                      : 'Allow location access to see & join your local Spotlight.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Error: $errorMessage',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () async {
              // Geolocator handles Web permissions natively

              if (isPermanentlyDenied) {
                await Geolocator.openAppSettings();
              } else {
                final perm = await Geolocator.requestPermission();
                if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
                  ref.invalidate(locationProvider);
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: palette.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                isPermanentlyDenied ? 'Settings' : 'Enable',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class SpotlightFeedCard extends StatelessWidget {
  final SpotlightBid bid;
  final AppPalette palette;

  const SpotlightFeedCard({super.key, required this.bid, required this.palette});

  @override
  Widget build(BuildContext context) {
    final rank = bid.rank;
    final isReal = bid.userId.isNotEmpty;

    // Border color and rank styling
    final Color borderColor;
    final Widget rankBadge;

    switch (rank) {
      case 1:
        borderColor = const Color(0xFFFFB800);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFFFB800),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('👑', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text(
                '#1',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
        break;
      case 2:
        borderColor = const Color(0xFF38BDF8);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('👑', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text(
                '#2',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
        break;
      case 3:
        borderColor = const Color(0xFFEC4899);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFDB2777),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('👑', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text(
                '#3',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
        break;
      case 4:
        borderColor = const Color(0xFFA855F7);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF7E22CE),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('⚡', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text('#4', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
            ],
          ),
        );
        break;
      case 5:
        borderColor = const Color(0xFF10B981);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF059669),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('⚡', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text('#5', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
            ],
          ),
        );
        break;
      case 6:
        borderColor = const Color(0xFFF59E0B);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFD97706),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('⚡', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text('#6', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
            ],
          ),
        );
        break;
      case 7:
        borderColor = const Color(0xFF6366F1);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('⚡', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text('#7', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
            ],
          ),
        );
        break;
      case 8:
        borderColor = const Color(0xFF14B8A6);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF0D9488),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('⚡', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text('#8', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
            ],
          ),
        );
        break;
      case 9:
        borderColor = const Color(0xFF06B6D4);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF0891B2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('⚡', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text('#9', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
            ],
          ),
        );
        break;
      case 10:
        borderColor = const Color(0xFFF43F5E);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFE11D48),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('🔥', style: TextStyle(fontSize: 10)),
              SizedBox(width: 3),
              Text('#10', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
            ],
          ),
        );
        break;
      default:
        borderColor = const Color(0xFFA855F7);
        rankBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF7E22CE),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '#$rank',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
        );
    }

    if (!isReal) {
      // Clean, premium Open Slot card without any fake user data
      return GestureDetector(
        onTap: () => context.push('/spotlight'),
        child: Container(
          width: 124,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                borderColor.withValues(alpha: 0.16),
                const Color(0xFF140F22),
                Colors.black.withValues(alpha: 0.88),
              ],
            ),
            border: Border.all(
              color: borderColor.withValues(alpha: 0.65),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: borderColor.withValues(alpha: 0.20),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Rank badge at top-left
              Positioned(
                top: 10,
                left: 10,
                child: rankBadge,
              ),

              // Center: Action icon and "Spot Open"
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: borderColor.withValues(alpha: 0.15),
                        border: Border.all(
                          color: borderColor.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.add_rounded,
                        color: borderColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Spot Open',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Info: Min bid & Claim CTA
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Min 🪙 ${bid.amount}',
                        style: TextStyle(
                          color: borderColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Tap to claim',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Real user bid card
    final displayUsername = bid.username;
    final displayLikes = '🪙 ${bid.amount}';
    final hasPhoto = bid.profileImageUrl.isNotEmpty;

    return GestureDetector(
      onTap: () => context.push('/profile/view/${bid.userId}'),
      child: Container(
        width: 124,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor.withValues(alpha: 0.85),
            width: 1.8,
          ),
          boxShadow: [
            BoxShadow(
              color: borderColor.withValues(alpha: 0.35),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo background or initials fallback
              if (hasPhoto)
                Image.network(
                  bid.profileImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildFallbackAvatar(displayUsername, borderColor),
                )
              else
                _buildFallbackAvatar(displayUsername, borderColor),

              // Gradient Overlay for readability
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.90),
                    ],
                    stops: const [0.35, 0.65, 1.0],
                  ),
                ),
              ),

              // Top-left: Rank Badge
              Positioned(
                top: 10,
                left: 10,
                child: rankBadge,
              ),

              // Top-right: Glassmorphic Add (+) button
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () {
                    context.push('/spotlight');
                  },
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.45),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.add_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ),

              // Bottom Info: Username, Bid Amount
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayUsername,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.flash_on_rounded,
                          size: 12,
                          color: Color(0xFFFFB800),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          displayLikes,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackAvatar(String name, Color accentColor) {
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
    return Container(
      color: const Color(0xFF1E1B2E),
      child: Center(
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentColor.withValues(alpha: 0.2),
            border: Border.all(color: accentColor.withValues(alpha: 0.5)),
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                color: accentColor,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
