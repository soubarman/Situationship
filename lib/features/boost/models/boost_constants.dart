class BoostConstants {
  // Distance Radius Tiers (in kilometers)
  static const double localRadius = 5.0;
  static const double regionalRadius = 15.0;
  static const double extendedRadius = 50.0;

  // Coin Costs for standard tier
  static const int localStandardCost = 25;
  static const int localMiniCost = 10;
  
  static const int regionalStandardCost = 50;
  static const int regionalMiniCost = 20;
  
  static const int extendedStandardCost = 100;
  static const int extendedMiniCost = 40;

  // Premium Multiplier for cost
  static const double premiumCostMultiplier = 1.5;

  // Reach Multipliers
  static const double standardReachMultiplier = 2.0;
  static const double premiumReachMultiplier = 3.5;

  // Durations
  static const Duration miniDuration = Duration(minutes: 30);
  static const Duration standardDuration = Duration(hours: 2);
  
  // Cooldown
  static const Duration cooldownDuration = Duration(hours: 24);

  // Gates
  static const int minLikesThreshold = 50;
  static const int minFollowersThreshold = 10;

  // Feed Slot Limits
  static const int maxBoostSlots = 6;
}
