import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:situationship/core/theme/app_theme.dart';
import '../models/spotlight_model.dart';
import '../providers/spotlight_provider.dart';

class SpotlightFeedSection extends ConsumerWidget {
  const SpotlightFeedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(spotlightSessionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return sessionAsync.when(
      loading: () => const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => const SizedBox.shrink(),
      data: (session) {
        if (session == null) return const SizedBox.shrink();

        final bidsAsync = ref.watch(spotlightBidsProvider(session.id));

        return bidsAsync.when(
          loading: () => const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => const SizedBox.shrink(),
          data: (bids) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.trending_up_rounded, color: AppTheme.accentPurple, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'SPOTLIGHT HOUR - FEATURED',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () {
                          // Navigate to spotlight screen
                          context.push('/spotlight');
                        },
                        child: Text(
                          'See all 30 →',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                SizedBox(
                  height: 220,
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
      width: 140,
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
