import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:situationship/core/theme/app_theme.dart';
import '../models/spotlight_model.dart';
import '../providers/spotlight_provider.dart';
import 'spotlight_card.dart';
import 'bid_bottom_sheet.dart';

class SpotlightSection extends ConsumerStatefulWidget {
  const SpotlightSection({super.key});

  @override
  ConsumerState<SpotlightSection> createState() => _SpotlightSectionState();
}

class _SpotlightSectionState extends ConsumerState<SpotlightSection> {
  bool _isExpanded = false;

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
    final sessionAsync = ref.watch(spotlightSessionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return sessionAsync.when(
      loading: () => _buildShimmerLoader(isDark),
      error: (err, stack) => _buildErrorState(err.toString(), isDark),
      data: (session) {
        if (session == null) {
          return _buildNoActiveSessionCard(isDark);
        }

        final bidsAsync = ref.watch(spotlightBidsProvider(session.id));

        return bidsAsync.when(
          loading: () => _buildShimmerLoader(isDark),
          error: (err, stack) => _buildErrorState(err.toString(), isDark),
          data: (bids) {
            // Build placeholders if we have less than 3 bids
            final List<SpotlightBid> top3Bids = List.from(bids.where((b) => b.rank <= 3));
            
            // Generate placeholder bids for missing top 3 slots
            if (top3Bids.isEmpty) {
              top3Bids.add(_createPlaceholderBid(session.id, 1, session.minStartingBid));
              top3Bids.add(_createPlaceholderBid(session.id, 2, session.minStartingBid));
              top3Bids.add(_createPlaceholderBid(session.id, 3, session.minStartingBid));
            } else if (top3Bids.length == 1) {
              top3Bids.add(_createPlaceholderBid(session.id, 2, session.minStartingBid));
              top3Bids.add(_createPlaceholderBid(session.id, 3, session.minStartingBid));
            } else if (top3Bids.length == 2) {
              top3Bids.add(_createPlaceholderBid(session.id, 3, session.minStartingBid));
            }

            final remainingBids = bids.where((b) => b.rank > 3).toList();

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.01),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Spotlight Header
                    _buildHeader(context, session, bids, isDark),
                    
                    const SizedBox(height: 16),

                    // Top 3 Row (Rank 2, Rank 1, Rank 3 is standard podium style, or Rank 1, 2, 3)
                    // Let's do standard Podium order: Rank 2 on left, Rank 1 in middle (taller/gold), Rank 3 on right
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Rank #2
                          Expanded(
                            child: SpotlightCard(bid: top3Bids[1]),
                          ),
                          // Rank #1 (Taller/Elevated)
                          Expanded(
                            child: SpotlightCard(bid: top3Bids[0]),
                          ),
                          // Rank #3
                          Expanded(
                            child: SpotlightCard(bid: top3Bids[2]),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Ranks #4 to #20
                    if (remainingBids.isNotEmpty) ...[
                      // Expander Toggle Header
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isExpanded = !_isExpanded;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'View Leaderboard (#4 - #20)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                              Icon(
                                _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                color: isDark ? Colors.white70 : Colors.black54,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Animated List
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: remainingBids.length,
                          itemBuilder: (context, index) {
                            return SpotlightCard(bid: remainingBids[index]);
                          },
                        ),
                        crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 300),
                      ),
                    ],

                    // CTA Button at the bottom
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton(
                        onPressed: () => _openBiddingSheet(context, session, bids),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryBlue.withOpacity(0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Container(
                            height: 50,
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.flash_on_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Bid & Join Spotlight Hour',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, SpotlightSession session, List<SpotlightBid> bids, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Live status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4B4B).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFF4B4B).withOpacity(0.3), width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PulseDotWidget(),
                SizedBox(width: 8),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: Color(0xFFFF4B4B),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          
          // Countdown Timer
          CountdownTimerWidget(endTime: session.endTime),

          // Total prize pool / stats
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.2)),
            ),
            child: Text(
              'Prize Pool: ₹${session.prizePool}',
              style: const TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoActiveSessionCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.01),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.electric_bolt_outlined,
            color: Colors.amber,
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            'Spotlight Hour is Off-air',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'The active bidding window has closed. Check back later to bid for profile spotlight visibility!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              ref.read(spotlightNotifierProvider).createMockSession();
            },
            icon: const Icon(Icons.play_arrow_rounded, color: Colors.black87),
            label: const Text(
              'Start Mock Spotlight Session',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerLoader(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      height: 200,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.01),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryBlue),
      ),
    );
  }

  Widget _buildErrorState(String error, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      child: Text(
        'Error: $error',
        style: const TextStyle(color: AppTheme.error),
      ),
    );
  }

  SpotlightBid _createPlaceholderBid(String sessionId, int rank, int minBid) {
    return SpotlightBid(
      id: 'placeholder_$rank',
      sessionId: sessionId,
      userId: '', // Denotes placeholder
      username: 'Empty Slot',
      profileImageUrl: 'https://i.pravatar.cc/150?img=${30 + rank}',
      isVerified: false,
      amount: minBid,
      timestamp: DateTime.now(),
      rank: rank,
    );
  }
}

// ─── Countdown Timer Widget ───────────────────────────────────────────────
class CountdownTimerWidget extends StatefulWidget {
  final DateTime endTime;
  const CountdownTimerWidget({super.key, required this.endTime});

  @override
  State<CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<CountdownTimerWidget> {
  late Timer _timer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateDuration();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateDuration());
  }

  void _updateDuration() {
    final now = DateTime.now();
    if (now.isAfter(widget.endTime)) {
      setState(() {
        _duration = Duration.zero;
      });
      _timer.cancel();
    } else {
      setState(() {
        _duration = widget.endTime.difference(now);
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = _duration.inHours.toString().padLeft(2, '0');
    final minutes = (_duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_duration.inSeconds % 60).toString().padLeft(2, '0');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.timer_outlined, color: AppTheme.accentPink, size: 14),
        const SizedBox(width: 4),
        Text(
          '$hours:$minutes:$seconds',
          style: const TextStyle(
            color: AppTheme.accentPink,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─── Pulse Dot Widget ──────────────────────────────────────────────────────
class PulseDotWidget extends StatefulWidget {
  const PulseDotWidget({super.key});

  @override
  State<PulseDotWidget> createState() => _PulseDotWidgetState();
}

class _PulseDotWidgetState extends State<PulseDotWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF4B4B),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF4B4B).withOpacity(0.5 * _controller.value),
                blurRadius: 6 * _controller.value,
                spreadRadius: 2 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
