import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import 'app_state_provider.dart';

/// What the feature gate should show.
enum AccessResult {
  free,         // no gate, allow
  needsCoins,   // show coin deduction sheet
  needsSub,     // show subscription upsell (for subscribed-only features when not subscribed)
  cannotBuy,    // female user — cannot purchase, redirect to earn screen
}

class AccessDecision {
  final AccessResult result;
  final int coinCost;    // only relevant when result == needsCoins
  final String feature;
  const AccessDecision(this.feature, this.result, {this.coinCost = 0});
  bool get isAllowed => result == AccessResult.free;
}

/// Coin costs per feature (for male users without subscription).
const Map<String, int> kFeatureCosts = {
  // Always costs coins (regardless of sub)
  'boost':      25, // cheapest boost tier; actual cost varies
  'spotlight':  50,
  'gift':       30,
  // Subscription-gated features (free with sub)
  'undo_ghost': 20,
  'priority_feed': 10,
  'extra_filters': 5,
  'ar_effects': 10,
  'phone_unlock': 50,
};

const Set<String> _alwaysCostsCoins = {'boost', 'spotlight', 'gift'};
const Set<String> _subGated = {'undo_ghost', 'priority_feed', 'extra_filters', 'ar_effects', 'phone_unlock'};

final featureAccessProvider = Provider.family<AccessDecision, String>((ref, feature) {
  final user = ref.watch(currentUserProvider);
  return _check(feature, user);
});

AccessDecision _check(String feature, UserModel user) {
  final cost = kFeatureCosts[feature] ?? 0;

  // Female users cannot purchase coins — send them to earn screen for coin-gated features
  if (user.isFemale && (_alwaysCostsCoins.contains(feature) || _subGated.contains(feature))) {
    if (user.coins < cost) {
      return AccessDecision(feature, AccessResult.cannotBuy, coinCost: cost);
    }
    // Female can still spend earned coins
    return AccessDecision(feature, AccessResult.needsCoins, coinCost: cost);
  }

  // Always costs coins regardless of subscription
  if (_alwaysCostsCoins.contains(feature)) {
    return AccessDecision(feature, AccessResult.needsCoins, coinCost: cost);
  }

  // Subscription-gated features
  if (_subGated.contains(feature)) {
    if (user.hasActiveSubscription) {
      // Phone unlock: check quota
      if (feature == 'phone_unlock' && user.phoneUnlocksRemaining <= 0) {
        return AccessDecision(feature, AccessResult.needsCoins, coinCost: cost);
      }
      return AccessDecision(feature, AccessResult.free);
    }
    // Not subscribed → show sub upsell or coin gate
    return AccessDecision(feature, AccessResult.needsSub, coinCost: cost);
  }

  return AccessDecision(feature, AccessResult.free);
}
