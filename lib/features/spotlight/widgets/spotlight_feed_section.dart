import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';

import 'package:situationship/core/theme/app_theme.dart';
import '../models/spotlight_model.dart';
import '../providers/spotlight_provider.dart';
import '../providers/location_provider.dart';

class SpotlightFeedSection extends ConsumerWidget {
  const SpotlightFeedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationAsync = ref.watch(locationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return locationAsync.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => _LocationPrompt(isDark: isDark, isPermanentlyDenied: true, errorMessage: e.toString(), ref: ref),
      data: (locState) {
        if (locState.status != LocationStatus.granted) {
          return _LocationPrompt(
            isDark: isDark,
            isPermanentlyDenied: locState.status == LocationStatus.deniedForever,
            ref: ref,
          );
        }

        final sessionAsync = ref.watch(spotlightSessionProvider);
        return sessionAsync.when(
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Container(padding: const EdgeInsets.all(16), child: Text("Session Error: $e", style: const TextStyle(color: Colors.red))),
          data: (session) {
            if (session == null) return const Center(child: Text("Session is null"));

            final bidsAsync = ref.watch(spotlightBidsProvider(session.id));
            return bidsAsync.when(
              loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Container(padding: const EdgeInsets.all(16), child: Text("Bids Error: $e", style: const TextStyle(color: Colors.red))),
              data: (bids) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.bolt_rounded, color: Color(0xFFFFD700), size: 16),
                                const SizedBox(width: 6),
                                const Flexible(
                                  child: Text(
                                    'SPOTLIGHT',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.withOpacity(0.4), width: 1),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.location_on_rounded, color: Colors.green, size: 10),
                                      SizedBox(width: 2),
                                      Text('Your Area', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => context.push('/spotlight'),
                            child: ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFF9E8FFF), Color(0xFFFF4B4B)],
                              ).createShader(bounds),
                              child: const Text(
                                'See all 30 →',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: bids.length < 5 ? 5 : bids.length,
                        itemBuilder: (context, index) {
                          SpotlightBid? bid;
                          if (index < bids.length) {
                            bid = bids[index];
                          } else {
                            bid = _createPlaceholderBid(session.id, index + 1, session.minStartingBid);
                          }
                          return SpotlightFeedCard(bid: bid);
                        },
                      ),
                    ),
                  ],
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
      username: 'Empty',
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
  final String? errorMessage;
  final WidgetRef ref;

  const _LocationPrompt({
    required this.isDark,
    required this.isPermanentlyDenied,
    this.errorMessage,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1628) : const Color(0xFFF3F0FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.accentPurple.withOpacity(0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
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
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.3),
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

  const SpotlightFeedCard({super.key, required this.bid});

  @override
  Widget build(BuildContext context) {
    final isTop3 = bid.rank <= 3;
    Color rankColor;
    
    switch (bid.rank) {
      case 1: rankColor = const Color(0xFFFFD700); break;
      case 2: rankColor = const Color(0xFFE0E0E0); break;
      case 3: rankColor = const Color(0xFFCD7F32); break;
      default: rankColor = Colors.white24;
    }

    final isPlaceholder = bid.userId.isEmpty;

    return GestureDetector(
      onTap: () {
        if (!isPlaceholder && bid.userId.isNotEmpty) {
          context.push('/profile/view/${bid.userId}');
        }
      },
      child: Container(
      width: 80,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTop3 ? rankColor : rankColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: isTop3 ? [
          BoxShadow(
            color: rankColor.withOpacity(0.15),
            blurRadius: 12,
            spreadRadius: 2,
          )
        ] : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Image
            if (!isPlaceholder)
              Image.network(
                bid.profileImageUrl,
                fit: BoxFit.cover,
              )
            else
              Container(color: Colors.black26),

            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.8),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),

            // Rank Badge
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isTop3 ? rankColor : Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bid.rank == 1) const Text('👑 ', style: TextStyle(fontSize: 10)),
                    Text(
                      '#${bid.rank}',
                      style: TextStyle(
                        color: isTop3 ? Colors.black87 : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Info
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${bid.username.toLowerCase().replaceAll(' ', '')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, color: Color(0xFFFF4B4B), size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${bid.amount}', // Mocking likes using amount as discussed
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
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
}
