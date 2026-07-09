import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/access_provider.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/services/coin_service.dart';
import '../../../core/theme/app_theme.dart';

/// Shows the correct gate bottom sheet for [feature].
/// Returns true if the action was allowed/confirmed, false if cancelled.
Future<bool> showCoinGate(
  BuildContext context,
  WidgetRef ref,
  String feature,
) async {
  final decision = ref.read(featureAccessProvider(feature));
  if (decision.isAllowed) return true;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: _CoinGateSheet(decision: decision),
    ),
  );
  return result ?? false;
}

class _CoinGateSheet extends ConsumerStatefulWidget {
  const _CoinGateSheet({required this.decision});
  final AccessDecision decision;

  @override
  ConsumerState<_CoinGateSheet> createState() => _CoinGateSheetState();
}

class _CoinGateSheetState extends ConsumerState<_CoinGateSheet> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final d = widget.decision;
    final hasEnough = user.coins >= d.coinCost;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141924),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: _gradientColors(d.result)),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(_icon(d.result), style: const TextStyle(fontSize: 32))),
          ),
          const SizedBox(height: 16),

          // Title
          Text(_title(d), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(_subtitle(d, user.coins), style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.5), textAlign: TextAlign.center),

          const SizedBox(height: 24),

          if (d.result == AccessResult.needsCoins) ...[
            // Coin balance display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Your balance', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  Text('🪙 ${user.coins} coins', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cost', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  Text('🪙 ${d.coinCost} coins', style: TextStyle(
                    color: hasEnough ? Colors.white : AppTheme.error,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  )),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (hasEnough)
              _bigButton(
                label: 'Use ${d.coinCost} coins',
                icon: '🪙',
                color: AppTheme.primaryBlue,
                onTap: _spendCoins,
              )
            else
              _bigButton(
                label: 'Get more coins',
                icon: '🛍️',
                color: AppTheme.accentPurple,
                onTap: () { context.pop(); context.push('/wallet'); },
              ),
          ] else if (d.result == AccessResult.needsSub) ...[
            _bigButton(
              label: 'View Premium Plans',
              icon: '⭐',
              color: AppTheme.primaryBlue,
              onTap: () { context.pop(); context.push('/wallet'); },
            ),
            const SizedBox(height: 12),
            _bigButton(
              label: 'Pay ${d.coinCost} coins instead',
              icon: '🪙',
              color: Colors.white12,
              onTap: _spendCoins,
            ),
          ] else if (d.result == AccessResult.cannotBuy) ...[
            _bigButton(
              label: 'Go earn coins',
              icon: '💬',
              color: const Color(0xFFAD1457),
              onTap: () { context.pop(); context.push('/wallet'); },
            ),
          ],

          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Future<void> _spendCoins() async {
    setState(() => _isLoading = true);
    final user = ref.read(currentUserProvider);
    final success = await CoinService.spend(
      userId: user.id,
      amount: widget.decision.coinCost,
      reason: widget.decision.feature,
    );
    if (mounted) {
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Not enough coins'),
          backgroundColor: AppTheme.error,
        ));
      }
    }
  }

  Widget _bigButton({required String label, required String icon, required Color color, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text('$icon  $label', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }

  List<Color> _gradientColors(AccessResult r) {
    switch (r) {
      case AccessResult.needsCoins:   return [const Color(0xFF1565C0), AppTheme.primaryBlue];
      case AccessResult.needsSub:     return [const Color(0xFF4527A0), AppTheme.accentPurple];
      case AccessResult.cannotBuy:    return [const Color(0xFFAD1457), const Color(0xFFE91E63)];
      default:                        return [AppTheme.primaryBlue, AppTheme.accentPurple];
    }
  }

  String _icon(AccessResult r) {
    switch (r) {
      case AccessResult.needsCoins:  return '🪙';
      case AccessResult.needsSub:    return '⭐';
      case AccessResult.cannotBuy:   return '💎';
      default:                       return '✨';
    }
  }

  String _title(AccessDecision d) {
    switch (d.result) {
      case AccessResult.needsCoins:  return '${d.coinCost} Coins Required';
      case AccessResult.needsSub:    return 'Premium Feature';
      case AccessResult.cannotBuy:   return 'Earn More Coins';
      default:                       return 'Feature Locked';
    }
  }

  String _subtitle(AccessDecision d, int balance) {
    switch (d.result) {
      case AccessResult.needsCoins:
        if (balance >= d.coinCost) {
          return 'You have $balance coins. This will cost ${d.coinCost} coins.';
        }
        return 'You need ${d.coinCost} coins but only have $balance.\nGet more coins to continue.';
      case AccessResult.needsSub:
        return 'This feature is free with Premium (₹199/mo)\nor you can pay ${d.coinCost} coins one-time.';
      case AccessResult.cannotBuy:
        return 'Women earn coins through genuine conversations and activity — you can\'t purchase them.\nEarn more to unlock this.';
      default:
        return 'This feature requires a subscription.';
    }
  }
}
