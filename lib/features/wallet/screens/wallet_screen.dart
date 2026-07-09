import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/services/coin_service.dart';
import '../../../core/theme/app_theme.dart';

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return user.isMale
        ? _MaleWallet(user: user)
        : _FemaleWallet(user: user);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEMALE WALLET — Earnings dashboard + gift card milestones
// ─────────────────────────────────────────────────────────────────────────────

class _FemaleWallet extends StatelessWidget {
  const _FemaleWallet({required this.user});
  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final milestones = kFemaleMilestones;
    final totalEarned = user.totalEarnedCoins as int;
    final claimed = user.claimedMilestones as List<String>;

    // Find the next unclaimed milestone
    CoinMilestone? nextMilestone;
    for (final m in milestones) {
      if (!claimed.contains(m.id)) { nextMilestone = m; break; }
    }
    final progress = nextMilestone != null
        ? (totalEarned / nextMilestone.threshold).clamp(0.0, 1.0)
        : 1.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            backgroundColor: Colors.transparent,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFAD1457), Color(0xFFE91E63), Color(0xFFFF80AB)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('💎 Earnings', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          '${user.coins} coins',
                          style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${totalEarned} total earned',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Progress to next milestone ────────────────────────────
                if (nextMilestone != null) ...[
                  _sectionTitle('Next Milestone'),
                  const SizedBox(height: 12),
                  _MilestoneProgressCard(
                    milestone: nextMilestone,
                    totalEarned: totalEarned,
                    progress: progress,
                  ),
                  const SizedBox(height: 24),
                ],

                // ── All milestones ────────────────────────────────────────
                _sectionTitle('All Milestones'),
                const SizedBox(height: 12),
                ...milestones.map((m) => _MilestoneRow(
                  milestone: m,
                  claimed: claimed.contains(m.id),
                  unlocked: totalEarned >= m.threshold,
                )),

                const SizedBox(height: 24),

                // ── How to earn ───────────────────────────────────────────
                _sectionTitle('How to Earn Coins'),
                const SizedBox(height: 12),
                _EarnGrid(),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
  );
}

class _MilestoneProgressCard extends StatelessWidget {
  const _MilestoneProgressCard({
    required this.milestone,
    required this.totalEarned,
    required this.progress,
  });
  final CoinMilestone milestone;
  final int totalEarned;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1C1030), Color(0xFF2A1040)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFAD1457).withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(milestone.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(milestone.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('Gift card worth ₹${milestone.giftCardValueInr}',
                        style: const TextStyle(color: Color(0xFFFF80AB), fontSize: 13)),
                  ],
                ),
              ),
              Text(
                '${totalEarned}/${milestone.threshold}',
                style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE91E63)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${((1 - progress) * milestone.threshold).round()} coins to go',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({required this.milestone, required this.claimed, required this.unlocked});
  final CoinMilestone milestone;
  final bool claimed;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: claimed
            ? const Color(0xFF1A2A1A)
            : unlocked
                ? const Color(0xFF1A1030)
                : const Color(0xFF141924),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: claimed
              ? AppTheme.success.withOpacity(0.4)
              : unlocked
                  ? const Color(0xFFAD1457).withOpacity(0.4)
                  : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Text(milestone.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(milestone.name, style: TextStyle(
                  color: claimed || unlocked ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.w700, fontSize: 15,
                )),
                Text('${milestone.threshold} coins → ₹${milestone.giftCardValueInr} gift card',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          if (claimed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: const Text('Claimed', style: TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w700)),
            )
          else if (unlocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFE91E63).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: const Text('Claim!', style: TextStyle(color: Color(0xFFFF80AB), fontSize: 11, fontWeight: FontWeight.w700)),
            )
          else
            Text('${milestone.threshold}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

class _EarnGrid extends StatelessWidget {
  final List<_EarnItem> items = const [
    _EarnItem('💬', 'Deep conversation', '10-60 coins', 'Per chat partner, 3×/day'),
    _EarnItem('🎬', 'Post a Take', '2 coins', 'Up to 5/day'),
    _EarnItem('❤️', 'Felt reaction', '1 coin', 'Up to 20/day'),
    _EarnItem('🔁', 'Content Echoed', '3 coins', 'No cap'),
    _EarnItem('🏘️', 'Vibes post', '2 coins', 'No cap'),
    _EarnItem('🔥', 'Daily login', '1-10 coins', 'Streak bonus at day 7'),
    _EarnItem('✅', 'Complete profile', '15 coins', 'One-time'),
    _EarnItem('👥', 'Referral', '20 coins', 'No cap'),
  ];

  const _EarnGrid();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) => SizedBox(
        width: (MediaQuery.of(context).size.width - 60) / 2,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF141924),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 8),
              Text(item.label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(item.coins, style: const TextStyle(color: Color(0xFFFF80AB), fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(item.cap, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
      )).toList(),
    );
  }
}

class _EarnItem {
  final String emoji, label, coins, cap;
  const _EarnItem(this.emoji, this.label, this.coins, this.cap);
}

// ─────────────────────────────────────────────────────────────────────────────
// MALE WALLET — Coin packs + Subscription
// ─────────────────────────────────────────────────────────────────────────────

class _MaleWallet extends ConsumerStatefulWidget {
  const _MaleWallet({required this.user});
  final dynamic user;

  @override
  ConsumerState<_MaleWallet> createState() => _MaleWalletState();
}

class _MaleWalletState extends ConsumerState<_MaleWallet> {
  bool _purchasing = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            backgroundColor: Colors.transparent,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1565C0), Color(0xFF6ECBF5), Color(0xFFB8A9FF)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('🪙 Your Coins', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          '${user.coins}',
                          style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
                        ),
                        if (user.hasActiveSubscription) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('⭐ Premium Active', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Subscription card ─────────────────────────────────────
                if (!user.hasActiveSubscription) ...[
                  _sectionTitle('Go Premium'),
                  const SizedBox(height: 12),
                  _SubscriptionCard(onSubscribe: _handleSubscribe, isPurchasing: _purchasing),
                  const SizedBox(height: 24),
                ],

                // ── Coin packs ────────────────────────────────────────────
                _sectionTitle('Buy Coins'),
                const SizedBox(height: 12),
                _CoinPackCard(
                  coins: 100, price: 49, label: 'Starter',
                  tag: null, gradient: const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF2563EB)]),
                  onBuy: () => _handleBuy(100, 49, 'starter'),
                  isPurchasing: _purchasing,
                ),
                const SizedBox(height: 12),
                _CoinPackCard(
                  coins: 250, price: 99, label: 'Popular',
                  tag: 'BEST VALUE',
                  gradient: const LinearGradient(colors: [Color(0xFF4527A0), Color(0xFFB8A9FF)]),
                  onBuy: () => _handleBuy(250, 99, 'popular'),
                  isPurchasing: _purchasing,
                ),
                const SizedBox(height: 12),
                _CoinPackCard(
                  coins: 600, price: 199, label: 'Power',
                  tag: 'MOST COINS',
                  gradient: const LinearGradient(colors: [Color(0xFF880E4F), Color(0xFFFF80AB)]),
                  onBuy: () => _handleBuy(600, 199, 'power'),
                  isPurchasing: _purchasing,
                ),

                const SizedBox(height: 24),

                // ── Spend guide ───────────────────────────────────────────
                _sectionTitle('What can I use coins for?'),
                const SizedBox(height: 12),
                _SpendGuide(),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
  );

  Future<void> _handleBuy(int coins, int priceInr, String pack) async {
    if (_purchasing) return;
    setState(() => _purchasing = true);

    // TODO: Integrate Razorpay payment here.
    // On payment success, call CoinService.grantPurchasedCoins(...)
    // For now simulating a successful purchase after a short delay.
    await Future.delayed(const Duration(milliseconds: 800));
    final user = ref.read(currentUserProvider);
    await CoinService.grantPurchasedCoins(userId: user.id, amount: coins);

    if (mounted) {
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ $coins coins added to your wallet!'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _handleSubscribe() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);

    // TODO: Integrate Razorpay subscription here.
    await Future.delayed(const Duration(milliseconds: 800));
    final user = ref.read(currentUserProvider);
    await CoinService.activateSubscription(
      userId: user.id,
      duration: const Duration(days: 30),
      phoneUnlockQuota: 10,
    );

    if (mounted) {
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('⭐ Premium activated! Enjoy all features.'),
        backgroundColor: AppTheme.primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }
}

class _CoinPackCard extends StatelessWidget {
  const _CoinPackCard({
    required this.coins,
    required this.price,
    required this.label,
    required this.tag,
    required this.gradient,
    required this.onBuy,
    required this.isPurchasing,
  });
  final int coins, price;
  final String label;
  final String? tag;
  final Gradient gradient;
  final VoidCallback onBuy;
  final bool isPurchasing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isPurchasing ? null : onBuy,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            const Text('🪙', style: TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('$coins Coins', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                      if (tag != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(20)),
                          child: Text(tag!, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                  Text('$label pack', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(14)),
              child: Text('₹$price', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.onSubscribe, required this.isPurchasing});
  final VoidCallback onSubscribe;
  final bool isPurchasing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D2744), Color(0xFF1565C0)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⭐', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Premium', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    Text('₹199 / month', style: TextStyle(color: Color(0xFF6ECBF5), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _FeatureRow(text: 'Undo ghost views for free'),
          const _FeatureRow(text: 'Priority placement in feed'),
          const _FeatureRow(text: 'All filters & AR effects'),
          const _FeatureRow(text: '10 free phone unlocks/month'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isPurchasing ? null : onSubscribe,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: isPurchasing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Subscribe Now', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBlue, size: 18),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    ),
  );
}

class _SpendGuide extends StatelessWidget {
  final List<List<String>> items = const [
    ['⚡', 'Boost post', 'from 25 coins'],
    ['🎯', 'Spotlight bid', 'from 50 coins'],
    ['🎁', 'Send a gift', 'from 30 coins'],
    ['👻', 'Undo ghost view', '20 coins'],
    ['📞', 'Phone unlock', '50 coins (or free with sub)'],
    ['✨', 'Extra filters', '5 coins (or free with sub)'],
  ];

  const _SpendGuide();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.map((item) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF141924),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Text(item[0], style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(item[1], style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
            Text(item[2], style: const TextStyle(color: AppTheme.primaryBlue, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      )).toList(),
    );
  }
}
