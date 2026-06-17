import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:situationship/core/theme/app_theme.dart';
import 'package:situationship/core/providers/app_state_provider.dart';
import '../models/spotlight_model.dart';
import '../providers/spotlight_provider.dart';
import '../providers/location_provider.dart';
import '../widgets/spotlight_card.dart';
import '../widgets/bid_bottom_sheet.dart';

class SpotlightScreen extends ConsumerStatefulWidget {
  const SpotlightScreen({super.key});

  @override
  ConsumerState<SpotlightScreen> createState() => _SpotlightScreenState();
}

class _SpotlightScreenState extends ConsumerState<SpotlightScreen> {
  void _openBiddingSheet(BuildContext context, SpotlightSession session, List<SpotlightBid> currentBids) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => BidBottomSheet(
          session: session,
          currentBids: currentBids,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);

    return locationAsync.when(
      loading: () => Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0B14) : const Color(0xFFF8FAFC),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (locState) {
        if (locState.status != LocationStatus.granted) {
          return _SpotlightLocationGate(isDark: isDark, locState: locState);
        }

        final sessionAsync = ref.watch(spotlightSessionProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0B14) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black),
          onPressed: () => context.pop(),
        ),
        title: Column(
          children: [
            Text(
              'SPOTLIGHT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Top 30 · This Hour',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, size: 14, color: AppTheme.accentPurple),
                const SizedBox(width: 4),
                Text(
                  '₹${currentUser.coins}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          )
        ],
      ),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (session) {
          if (session == null) {
            return const Center(child: Text('No active spotlight session.'));
          }

          final bidsAsync = ref.watch(spotlightBidsProvider(session.id));

          return bidsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (bids) {
              final top3 = List<SpotlightBid>.from(bids.where((b) => b.rank <= 3));
              while (top3.length < 3) {
                top3.add(_createPlaceholder(session.id, top3.length + 1, session.minStartingBid));
              }
              final remaining = bids.where((b) => b.rank > 3).toList();
              final existingRanks = remaining.map((b) => b.rank).toSet();
              for (int i = 4; i <= 30; i++) {
                if (!existingRanks.contains(i)) {
                  remaining.add(_createPlaceholder(session.id, i, session.minStartingBid));
                }
              }
              remaining.sort((a, b) => a.rank.compareTo(b.rank));

              // Check user's bid
              final userBid = bids.where((b) => b.userId == currentUser.id).firstOrNull;

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      // Live Slot Card
                      _buildLiveSlotCard(session),
                      
                      const SizedBox(height: 16),
                      
                      // Your Bid Card
                      _buildYourBidCard(context, session, bids, userBid, isDark),
                      
                      const SizedBox(height: 32),
                      
                      // Podium
                      Row(
                        children: [
                          const Text('👑', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Text(
                            'SPOTLIGHT HOUR',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 240,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Rank 2
                            Expanded(child: _SpotlightPodiumCard(bid: top3[1])),
                            const SizedBox(width: 8),
                            // Rank 1
                            Expanded(child: _SpotlightPodiumCard(bid: top3[0])),
                            const SizedBox(width: 8),
                            // Rank 3
                            Expanded(child: _SpotlightPodiumCard(bid: top3[2])),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Featured List
                      if (remaining.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text('✨', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Text(
                              'FEATURED TONIGHT',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: remaining.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            return _SpotlightListItem(bid: remaining[index], isDark: isDark);
                          },
                        ),
                        SizedBox(height: MediaQuery.of(context).padding.bottom + 100),
                      ]
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
      }, // end data
    ); // end locationAsync.when
  }

  Widget _buildLiveSlotCard(SpotlightSession session) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF9E8FFF), Color(0xFFC7AFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LIVE SLOT',
                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Text('🌙', style: TextStyle(fontSize: 10)),
                    SizedBox(width: 4),
                    Text('Off-peak', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '12:00 AM – 1:00 AM',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MIN BID', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('₹${session.minStartingBid}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.access_time, color: Colors.white70, size: 12),
                      SizedBox(width: 4),
                      Text('NEXT SLOT IN', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _CountdownText(endTime: session.endTime),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildYourBidCard(BuildContext context, SpotlightSession session, List<SpotlightBid> bids, SpotlightBid? userBid, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B2E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Text('✨', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your bid this hour', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  userBid != null ? 'Rank #${userBid.rank} (₹${userBid.amount})' : 'Not bidding yet',
                  style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _openBiddingSheet(context, session, bids),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9E8FFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              elevation: 0,
            ),
            child: Text(userBid != null ? 'Update bid' : 'Place bid', style: const TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  SpotlightBid _createPlaceholder(String sessionId, int rank, int minBid) {
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

class _CountdownText extends StatefulWidget {
  final DateTime endTime;
  const _CountdownText({required this.endTime});

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<_CountdownText> {
  late DateTime _endTime;

  @override
  void initState() {
    super.initState();
    _endTime = widget.endTime;
    _update();
  }

  void _update() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {});
        _update();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final diff = _endTime.difference(DateTime.now());
    if (diff.isNegative) return const Text('00:00', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900));
    final mm = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return Text('$mm:$ss', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, fontFeatures: [FontFeature.tabularFigures()]));
  }
}

class _SpotlightPodiumCard extends StatelessWidget {
  final SpotlightBid bid;
  const _SpotlightPodiumCard({required this.bid});

  @override
  Widget build(BuildContext context) {
    final isRank1 = bid.rank == 1;
    final isPlaceholder = bid.userId.isEmpty;

    Color rankColor;
    if (bid.rank == 1) rankColor = const Color(0xFFFFD700);
    else if (bid.rank == 2) rankColor = const Color(0xFFE0E0E0);
    else rankColor = const Color(0xFFCD7F32);

    return GestureDetector(
      onTap: () {
        if (!isPlaceholder && bid.userId.isNotEmpty) {
          context.push('/profile/view/${bid.userId}');
        }
      },
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: isRank1 ? 240 : 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: rankColor, width: 2),
        boxShadow: isRank1 ? [BoxShadow(color: rankColor.withOpacity(0.2), blurRadius: 20, spreadRadius: 2)] : [],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!isPlaceholder)
              Image.network(bid.profileImageUrl, fit: BoxFit.cover)
            else
              Container(color: Colors.black26),
              
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),

            if (isRank1)
              const Positioned(
                top: 12, left: 0, right: 0,
                child: Center(child: Text('👑', style: TextStyle(fontSize: 24))),
              ),

            Positioned(
              top: 16, right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: rankColor, borderRadius: BorderRadius.circular(8)),
                child: Text('#${bid.rank}', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ),

            Positioned(
              bottom: 16, left: 12, right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPlaceholder ? 'Empty' : bid.username,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isPlaceholder ? '' : '@${bid.username.toLowerCase().replaceAll(' ', '')}',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, color: Color(0xFFFF4B4B), size: 10),
                        const SizedBox(width: 4),
                        Text('${bid.amount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
      ),
    );
  }
}

class _SpotlightListItem extends StatelessWidget {
  final SpotlightBid bid;
  final bool isDark;
  const _SpotlightListItem({required this.bid, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (bid.userId.isNotEmpty) {
          context.push('/profile/view/${bid.userId}');
        }
      },
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1B2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${bid.rank}',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                backgroundImage: bid.userId.isNotEmpty ? NetworkImage(bid.profileImageUrl) : null,
                child: bid.userId.isEmpty ? Icon(Icons.person, color: isDark ? Colors.white38 : Colors.black38) : null,
              ),
              const Positioned(
                top: -4, right: -4,
                child: Icon(Icons.star_rounded, color: AppTheme.accentPurple, size: 16),
              )
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bid.username, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('@${bid.username.toLowerCase().replaceAll(' ', '')}', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFF4B4B), Color(0xFFFF9068)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('Glowing', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.favorite, color: Color(0xFFFF4B4B), size: 12),
                  const SizedBox(width: 4),
                  Text('${bid.amount}', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              )
            ],
          )
        ],
      ),
      ),
    );
  }
}

// ─── Full-screen location gate for SpotlightScreen ────────────────────────────

class _SpotlightLocationGate extends StatelessWidget {
  final bool isDark;
  final LocationState locState;

  const _SpotlightLocationGate({
    required this.isDark,
    required this.locState,
  });

  @override
  Widget build(BuildContext context) {
    final isPermanent = locState.status == LocationStatus.deniedForever;
    final isService   = locState.status == LocationStatus.serviceDisabled;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0B14) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'SPOTLIGHT',
          style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.5,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.4), blurRadius: 30, spreadRadius: 4),
                  ],
                ),
                child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 42),
              ),
              const SizedBox(height: 28),

              // Title
              ShaderMask(
                shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
                child: Text(
                  isService ? 'Location Services Off' : 'Location Required',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),

              // Body
              Text(
                isService
                    ? 'Turn on your device\'s location services to see Spotlight in your area.'
                    : isPermanent
                        ? 'You\'ve permanently blocked location access. Open Settings to enable it and join your local Spotlight.'
                        : 'Spotlight shows the most popular people near you.\nEnable location to see who\'s trending in your area!',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: isDark ? Colors.white54 : AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // CTA button
              GestureDetector(
                onTap: () async {
                  if (isService) {
                    await Geolocator.openLocationSettings();
                  } else if (isPermanent) {
                    await Geolocator.openAppSettings();
                  } else {
                    await Geolocator.requestPermission();
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Text(
                    isService ? 'Open Location Settings' : isPermanent ? 'Open App Settings' : 'Enable Location',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
