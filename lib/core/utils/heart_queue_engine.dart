import 'dart:math' as math;
import '../models/user_model.dart';
import 'location_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  HeartQueue™ Engine  v3.0 — Personalized, Raw & Reciprocal Compatibility
// ─────────────────────────────────────────────────────────────────────────────
//
//  TWO-STAGE RECOMMENDATION ARCHITECTURE:
//
//  STAGE 1: HARD ELIGIBILITY FILTER (Strict, Non-Negotiable, Never Overridden)
//  Candidate
//      ↓
//  Is account valid & active?
//      ↓
//  Is candidate discoverable?
//      ↓
//  Is candidate suspended/banned?
//      ↓
//  Is candidate blocked by user / has candidate blocked user?
//      ↓
//  Already matched?
//      ↓
//  Already liked/passed/unliked in session?
//      ↓
//  Age preference compatible?
//      ↓
//  GENDER & DATING PREFERENCE COMPATIBLE? (Mutual Reciprocal Filtering)
//      ↓
//  Dealbreakers satisfied?
//      ↓
//  Distance / location constraints?
//      ↓
//  ONLY THEN → STAGE 2: RAW COMPATIBILITY SCORING & RANKING
//
//  STAGE 2: MULTI-SIGNAL RAW COMPATIBILITY SCORING:
//  • Intent Compatibility (0–25 pts)
//  • Categorized Interests & Rare-Interest Bonus (0–20 pts)
//  • Personality Synergy: Similarity + Complementarity (0–20 pts)
//  • Conversation Potential: Shared hooks & talking points (0–15 pts)
//  • Geographic Proximity: Distance decay (0–10 pts)
//  • Age Harmony: Preference proximity (0–5 pts)
//  • Profile Quality & Completeness (0–5 pts)
//  • Mutual Attraction Bonus (+15 pts if they liked you first)
//  • Multipliers: Learned Behavioral Vibe Affinity, Online, Verified, Recency
//
//  STAGE 3: ANTI-BUBBLE DIVERSIFICATION:
//  • 75% Top Compatibility
//  • 15% Vibe Contrast / Discovery
//  • 10% Wildcard (high conversation / unexpected shared rare interest)
// ─────────────────────────────────────────────────────────────────────────────

/// Internal match classification badge.
enum MatchCategory {
  highCompatibility,
  sharedVibe,
  conversationMatch,
  nearbyMatch,
  wildcard,
}

extension MatchCategoryExtension on MatchCategory {
  String get label {
    switch (this) {
      case MatchCategory.highCompatibility:
        return 'Soul Match';
      case MatchCategory.sharedVibe:
        return 'Shared Vibe';
      case MatchCategory.conversationMatch:
        return 'High Spark';
      case MatchCategory.nearbyMatch:
        return 'Nearby Connection';
      case MatchCategory.wildcard:
        return 'Wildcard';
    }
  }

  String get emoji {
    switch (this) {
      case MatchCategory.highCompatibility:
        return '🔥';
      case MatchCategory.sharedVibe:
        return '✨';
      case MatchCategory.conversationMatch:
        return '💬';
      case MatchCategory.nearbyMatch:
        return '📍';
      case MatchCategory.wildcard:
        return '🎲';
    }
  }
}

/// Centralized, configurable weights for the Stage 2 scoring engine.
class MatchingWeights {
  final double intentWeight;
  final double personalityWeight;
  final double interestWeight;
  final double conversationWeight;
  final double proximityWeight;
  final double ageHarmonyWeight;
  final double profileQualityWeight;
  final double mutualAttractionBonus;

  const MatchingWeights({
    this.intentWeight = 25.0,
    this.personalityWeight = 20.0,
    this.interestWeight = 20.0,
    this.conversationWeight = 15.0,
    this.proximityWeight = 10.0,
    this.ageHarmonyWeight = 5.0,
    this.profileQualityWeight = 5.0,
    this.mutualAttractionBonus = 15.0,
  });

  MatchingWeights copyWith({
    double? intentWeight,
    double? personalityWeight,
    double? interestWeight,
    double? conversationWeight,
    double? proximityWeight,
    double? ageHarmonyWeight,
    double? profileQualityWeight,
    double? mutualAttractionBonus,
  }) {
    return MatchingWeights(
      intentWeight: intentWeight ?? this.intentWeight,
      personalityWeight: personalityWeight ?? this.personalityWeight,
      interestWeight: interestWeight ?? this.interestWeight,
      conversationWeight: conversationWeight ?? this.conversationWeight,
      proximityWeight: proximityWeight ?? this.proximityWeight,
      ageHarmonyWeight: ageHarmonyWeight ?? this.ageHarmonyWeight,
      profileQualityWeight: profileQualityWeight ?? this.profileQualityWeight,
      mutualAttractionBonus: mutualAttractionBonus ?? this.mutualAttractionBonus,
    );
  }
}

/// Immutable result of scoring a single profile.
class ScoredProfile {
  final UserModel user;
  final double score;              // Raw weighted engine score
  final int displayScore;          // Realistic 0–99 "match %" shown to user
  final MatchCategory category;    // Internal classification
  final String matchExplanation;   // Grounded human-readable match reason
  final double conversationScore;  // 0.0–1.0 conversation potential
  final String debugInfo;          // Developer breakdown

  const ScoredProfile({
    required this.user,
    required this.score,
    required this.displayScore,
    this.category = MatchCategory.highCompatibility,
    this.matchExplanation = 'Compatible vibe and shared interests',
    this.conversationScore = 0.5,
    required this.debugInfo,
  });
}

/// Insight derived from user's behavioral patterns.
class EngineInsight {
  final String label;
  final String emoji;
  const EngineInsight(this.label, this.emoji);
}

// ─────────────────────────────────────────────────────────────────────────────
//  HeartQueueEngine Implementation
// ─────────────────────────────────────────────────────────────────────────────

class HeartQueueEngine {
  // ── Centralized Configurable Weights ───────────────────────────────────────
  MatchingWeights weights;

  HeartQueueEngine({MatchingWeights? initialWeights})
      : weights = initialWeights ?? const MatchingWeights();

  // ── Factor Dynamic Multipliers (adjusted by behavioral learning) ───────────
  double _wInterests = 1.00;
  double _wDistance  = 1.00;
  double _wAge       = 1.00;

  // ── Behavioral Signal Counters ─────────────────────────────────────────────
  final Map<String, int> _likesByVibe      = {};
  final Map<String, int> _quickSkipsByVibe = {};
  final Map<String, int> _likesByAgeGroup  = {};
  final Map<String, int> _skipsByAgeGroup  = {};
  final Map<String, int> _likesByDistBand  = {};
  final Map<String, int> _skipsByDistBand  = {};

  int _totalLikes = 0;
  int _totalSkips = 0;

  // ── Anti-Repetition Ring Buffer ───────────────────────────────────────────
  final List<String> _recentlyDisplayed = [];
  static const _displayWindowSize = 60;

  // ── Skip-Velocity Tracker ──────────────────────────────────────────────────
  final Map<String, DateTime> _displayedAt = {};

  // ── Vibe Archetypes ────────────────────────────────────────────────────────
  static const _vibes = [
    'Warm Current', 'Soft Rebel',  'Golden Hour',
    'Quiet Storm',  'Soft Chaos',  'Night Owl',
  ];

  // ── Interest Taxonomy ──────────────────────────────────────────────────────
  static const Map<String, List<String>> _interestCategories = {
    'music': ['music', 'dancing', 'hip hop', 'indie', 'singing', 'guitar', 'piano'],
    'culture': ['movies', 'theatre', 'art', 'photography', 'fashion', 'museums', 'cinema'],
    'outdoors': ['fitness', 'yoga', 'surfing', 'nature', 'sports', 'hiking', 'running', 'gym'],
    'intellect': ['books', 'astrology', 'writing', 'science', 'tech', 'coding', 'philosophy'],
    'lifestyle': ['coffee', 'food', 'cooking', 'pets', 'travel', 'wine', 'baking', 'dogs', 'cats'],
    'gaming': ['gaming', 'esports', 'anime', 'board games', 'playstation', 'pc'],
  };

  static const Set<String> _rareInterests = {
    'surfing', 'astrology', 'theatre', 'photography', 'philosophy', 'esports',
  };

  // ──────────────────────────────────────────────────────────────────────────
  //  STAGE 1: HARD ELIGIBILITY FILTER
  // ──────────────────────────────────────────────────────────────────────────

  /// Evaluates whether a candidate profile is 100% eligible to be shown.
  /// NEVER OVERRIDDEN BY COMPATIBILITY SCORE.
  bool isCandidateEligible({
    required UserModel currentUser,
    required UserModel candidate,
    required double minAge,
    required double maxAge,
    required double maxDistance,
    required bool matchIrrespective,
    double? deviceLat,
    double? deviceLon,
    Set<String> excludedIds = const {},
    Set<String> unlikedIds = const {},
    String? overrideInterestedIn, // 'auto' | 'male' | 'female' | 'all'
  }) {
    // 1. Never show yourself or invalid candidate
    if (candidate.id.isEmpty || candidate.id == currentUser.id) {
      return false;
    }

    // 2. Discoverability & active status
    if (!candidate.isDiscoverable) {
      return false;
    }

    // 3. Suspended / banned accounts
    if (candidate.isCurrentlySuspended) {
      return false;
    }

    // 4. Two-way block list: User blocked candidate OR candidate blocked user
    if (currentUser.blockedUsers.contains(candidate.id) ||
        candidate.blockedUsers.contains(currentUser.id)) {
      return false;
    }

    // 5. Already matched
    if (currentUser.matches.contains(candidate.id)) {
      return false;
    }

    // 6. Already followed / liked
    if (currentUser.following.contains(candidate.id)) {
      return false;
    }

    // 7. Already disliked / passed / unliked / pending in session
    if (currentUser.dislikedUsers.contains(candidate.id)) {
      return false;
    }
    if (excludedIds.contains(candidate.id) || unlikedIds.contains(candidate.id)) {
      return false;
    }

    // 8. Age constraints
    if (candidate.age < minAge || candidate.age > maxAge) {
      return false;
    }

    // 9. STRICT GENDER & DATING PREFERENCE (MUTUAL RECIPROCITY)
    final userGender = currentUser.normalizedGender;
    final candidateGender = candidate.normalizedGender;

    // Determine what genders currentUser is seeking
    final Set<String> userSoughtGenders = _resolveSoughtGenders(
      currentUser: currentUser,
      overridePreference: overrideInterestedIn,
    );

    // Forward check: Does the current user want candidate's gender?
    if (!userSoughtGenders.contains(candidateGender)) {
      return false; // Candidate's gender is NOT in currentUser's desired preferences
    }

    // Reciprocal check: Does candidate want currentUser's gender?
    // CANDIDATE RECIPROCITY RULE:
    // Only enforce reciprocal restriction if candidate has EXPLICITLY configured `interestedIn`.
    // If candidate's `interestedIn` is empty (legacy or unconfigured profile), candidate
    // does not restrict/reject the current user.
    if (candidate.interestedIn.isNotEmpty) {
      final Set<String> candidateSoughtGenders = _resolveSoughtGenders(
        currentUser: candidate,
        overridePreference: null,
      );

      if (!candidateSoughtGenders.contains(userGender)) {
        return false; // CurrentUser's gender is NOT accepted by candidate (e.g. lesbian seeking female rejects male)
      }
    }

    // 10. Dealbreakers (Hard Filters)
    if (currentUser.dealbreakers.isNotEmpty) {
      for (final dealbreaker in currentUser.dealbreakers) {
        final clean = dealbreaker.trim().toLowerCase();
        if (candidate.dealbreakers.contains('non_$clean') ||
            candidate.interests.any((i) => i.toLowerCase().contains(clean))) {
          return false;
        }
      }
    }

    // 11. Distance & location constraints
    if (!matchIrrespective) {
      final distKm = LocationHelper.getDistanceKm(
        lat1: deviceLat,
        lon1: deviceLon,
        loc1: currentUser.location,
        loc2: candidate.location,
        id1: currentUser.id,
        id2: candidate.id,
      );
      if (distKm > maxDistance) {
        return false;
      }
    }

    return true;
  }

  /// Filters an entire candidate list through Stage 1 Hard Eligibility.
  /// If the candidate pool within the initial local radius has fewer than 2 candidates,
  /// adaptively widens the radius (first 150 km, then global/irrespective)
  /// WITHOUT EVER violating hard gender/preference, age, block, or moderation constraints
  /// (per Requirement #11).
  List<UserModel> filterEligibleCandidates({
    required UserModel currentUser,
    required List<UserModel> candidates,
    required double minAge,
    required double maxAge,
    required double maxDistance,
    required bool matchIrrespective,
    double? deviceLat,
    double? deviceLon,
    Set<String> excludedIds = const {},
    Set<String> unlikedIds = const {},
    String? overrideInterestedIn,
  }) {
    // 1. Initial attempt with user's configured distance
    final local = candidates.where((candidate) {
      return isCandidateEligible(
        currentUser: currentUser,
        candidate: candidate,
        minAge: minAge,
        maxAge: maxAge,
        maxDistance: maxDistance,
        matchIrrespective: matchIrrespective,
        deviceLat: deviceLat,
        deviceLon: deviceLon,
        excludedIds: excludedIds,
        unlikedIds: unlikedIds,
        overrideInterestedIn: overrideInterestedIn,
      );
    }).toList();

    // If local pool is healthy (>= 2 candidates) or already unrestricted, return as-is
    if (local.length >= 2 || matchIrrespective) {
      return local;
    }

    // 2. Adaptive stage A: Intermediate widening (e.g. 150 km)
    final widened = candidates.where((candidate) {
      return isCandidateEligible(
        currentUser: currentUser,
        candidate: candidate,
        minAge: minAge,
        maxAge: maxAge,
        maxDistance: math.max(maxDistance * 3, 150.0),
        matchIrrespective: false,
        deviceLat: deviceLat,
        deviceLon: deviceLon,
        excludedIds: excludedIds,
        unlikedIds: unlikedIds,
        overrideInterestedIn: overrideInterestedIn,
      );
    }).toList();

    if (widened.length >= 2) {
      return widened;
    }

    // 3. Adaptive stage B: Global / Irrespective fallback
    // (Strict gender preference, age limits, and blocks are STILL 100% active!)
    final global = candidates.where((candidate) {
      return isCandidateEligible(
        currentUser: currentUser,
        candidate: candidate,
        minAge: minAge,
        maxAge: maxAge,
        maxDistance: maxDistance,
        matchIrrespective: true, // relax distance filter
        deviceLat: deviceLat,
        deviceLon: deviceLon,
        excludedIds: excludedIds,
        unlikedIds: unlikedIds,
        overrideInterestedIn: overrideInterestedIn,
      );
    }).toList();

    return global;
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  STAGE 2: RAW COMPATIBILITY SCORING ENGINE
  // ──────────────────────────────────────────────────────────────────────────

  /// Scores an eligible candidate across all independent raw signals.
  ScoredProfile scoreProfile({
    required UserModel currentUser,
    required UserModel candidate,
    double? deviceLat,
    double? deviceLon,
    double minAge = 18,
    double maxAge = 35,
  }) {
    final buf = StringBuffer();
    double rawScore = 0.0;

    // ── Signal 1: Intent Compatibility (0–25 pts) ───────────────────────────
    final intentScore = _calculateIntentScore(
      currentUser.relationshipIntent,
      candidate.relationshipIntent,
    );
    final intentPts = intentScore * weights.intentWeight;
    rawScore += intentPts;
    buf.write('[Intent:${(intentScore * 100).round()}%+${intentPts.toStringAsFixed(1)}]');

    // ── Signal 2: Categorized Interests & Rare Overlap (0–20 pts) ───────────
    final interestBreakdown = _calculateInterestScore(
      currentUser.interests,
      candidate.interests,
    );
    final interestPts = interestBreakdown.totalRatio * weights.interestWeight * _wInterests;
    rawScore += interestPts;
    buf.write('[Int:${(interestBreakdown.totalRatio * 100).round()}%+${interestPts.toStringAsFixed(1)}]');

    // ── Signal 3: Personality Compatibility (Similarity + Complementarity) ───
    final myVibe = _vibeFor(currentUser.id);
    final candidateVibe = _vibeFor(candidate.id);
    final personalityScore = _calculatePersonalityScore(myVibe, candidateVibe);
    final personalityPts = personalityScore * weights.personalityWeight;
    rawScore += personalityPts;
    buf.write('[Vibe:$candidateVibe:${(personalityScore * 100).round()}%+${personalityPts.toStringAsFixed(1)}]');

    // ── Signal 4: Conversation Potential (0–15 pts) ─────────────────────────
    final conversationRatio = _calculateConversationPotential(
      currentUser: currentUser,
      candidate: candidate,
      sharedInterestsCount: interestBreakdown.sharedExact.length,
      personalityScore: personalityScore,
    );
    final conversationPts = conversationRatio * weights.conversationWeight;
    rawScore += conversationPts;
    buf.write('[Conv:${(conversationRatio * 100).round()}%+${conversationPts.toStringAsFixed(1)}]');

    // ── Signal 5: Distance Proximity (0–10 pts) ─────────────────────────────
    final distKm = LocationHelper.getDistanceKm(
      lat1: deviceLat,
      lon1: deviceLon,
      loc1: currentUser.location,
      loc2: candidate.location,
      id1: currentUser.id,
      id2: candidate.id,
    );
    final proximityRatio = _calculateProximityRatio(distKm);
    final proximityPts = proximityRatio * weights.proximityWeight * _wDistance;
    rawScore += proximityPts;
    buf.write('[Dist:${distKm.toStringAsFixed(0)}km+${proximityPts.toStringAsFixed(1)}]');

    // ── Signal 6: Age Harmony (0–5 pts) ─────────────────────────────────────
    final ageRatio = _calculateAgeHarmonyRatio(
      candidateAge: candidate.age,
      minAge: minAge,
      maxAge: maxAge,
      userAge: currentUser.age,
    );
    final agePts = ageRatio * weights.ageHarmonyWeight * _wAge;
    rawScore += agePts;
    buf.write('[Age:${candidate.age}y+${agePts.toStringAsFixed(1)}]');

    // ── Signal 7: Profile Quality & Effort (0–5 pts) ────────────────────────
    final qualityRatio = _calculateProfileQuality(candidate);
    final qualityPts = qualityRatio * weights.profileQualityWeight;
    rawScore += qualityPts;
    buf.write('[Quality:${(qualityRatio * 100).round()}%+${qualityPts.toStringAsFixed(1)}]');

    // ── Signal 8: Mutual Attraction Boost (+15 pts) ─────────────────────────
    if (candidate.likedBy.contains(currentUser.id) ||
        candidate.following.contains(currentUser.id)) {
      rawScore += weights.mutualAttractionBonus;
      buf.write('[MutualLiked+${weights.mutualAttractionBonus.toStringAsFixed(0)}]');
    }

    // ── Multipliers: Behavioral Vibe Affinity & Context ─────────────────────
    final vibeMultiplier = _vibeMultiplier(candidateVibe);
    final recencyMultiplier = _recentlyDisplayed.contains(candidate.id) ? 0.30 : 1.0;
    final onlineMultiplier = candidate.isOnline ? 1.10 : 1.0;
    final verifiedMultiplier = candidate.isVerified ? 1.08 : 1.0;

    if (vibeMultiplier != 1.0) buf.write('[VibeAff×${vibeMultiplier.toStringAsFixed(2)}]');
    if (recencyMultiplier < 1.0) buf.write('[Recent×0.30]');
    if (candidate.isOnline) buf.write('[Online×1.10]');
    if (candidate.isVerified) buf.write('[Verified×1.08]');

    final finalScore = rawScore * vibeMultiplier * recencyMultiplier * onlineMultiplier * verifiedMultiplier;

    // ── Classification & Explanation ───────────────────────────────────────
    final category = _classifyMatch(
      finalScore: finalScore,
      conversationRatio: conversationRatio,
      personalityScore: personalityScore,
      distKm: distKm,
      interestBreakdown: interestBreakdown,
    );

    final explanation = _generateMatchExplanation(
      currentUser: currentUser,
      candidate: candidate,
      category: category,
      interestBreakdown: interestBreakdown,
      distKm: distKm,
    );

    // Realistic normalized display percentage (65% to 98%)
    final basePct = (finalScore / 100.0) * 35.0;
    final displayScore = (60.0 + basePct + (interestBreakdown.sharedExact.length * 3.0)).round().clamp(65, 98);

    return ScoredProfile(
      user: candidate,
      score: finalScore,
      displayScore: displayScore,
      category: category,
      matchExplanation: explanation,
      conversationScore: conversationRatio,
      debugInfo: buf.toString(),
    );
  }

  /// Ranks candidates strictly through Stage 1 & Stage 2, sorting by compatibility.
  List<ScoredProfile> rankProfiles({
    required UserModel currentUser,
    required List<UserModel> candidates,
    double? deviceLat,
    double? deviceLon,
    double minAge = 18,
    double maxAge = 35,
    double maxDistance = 50,
    bool matchIrrespective = false,
    Set<String> excludedIds = const {},
    Set<String> unlikedIds = const {},
    String? overrideInterestedIn,
  }) {
    // Stage 1: Enforce Hard Eligibility Filters FIRST
    final eligible = filterEligibleCandidates(
      currentUser: currentUser,
      candidates: candidates,
      minAge: minAge,
      maxAge: maxAge,
      maxDistance: maxDistance,
      matchIrrespective: matchIrrespective,
      deviceLat: deviceLat,
      deviceLon: deviceLon,
      excludedIds: excludedIds,
      unlikedIds: unlikedIds,
      overrideInterestedIn: overrideInterestedIn,
    );

    if (eligible.isEmpty) return [];

    // Stage 2: Calculate deterministic compatibility scores
    final scored = eligible
        .map((candidate) => scoreProfile(
              currentUser: currentUser,
              candidate: candidate,
              deviceLat: deviceLat,
              deviceLon: deviceLon,
              minAge: minAge,
              maxAge: maxAge,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // Mark top profiles in anti-repetition tracker
    for (final sp in scored.take(4)) {
      onProfileDisplayed(sp.user.id);
    }

    return scored;
  }

  /// Convenience method returning ordered list of UserModel.
  List<UserModel> rankedUsers({
    required UserModel currentUser,
    required List<UserModel> candidates,
    double? deviceLat,
    double? deviceLon,
    double minAge = 18,
    double maxAge = 35,
    double maxDistance = 50,
    bool matchIrrespective = false,
    Set<String> excludedIds = const {},
    Set<String> unlikedIds = const {},
    String? overrideInterestedIn,
  }) {
    return rankProfiles(
      currentUser: currentUser,
      candidates: candidates,
      deviceLat: deviceLat,
      deviceLon: deviceLon,
      minAge: minAge,
      maxAge: maxAge,
      maxDistance: maxDistance,
      matchIrrespective: matchIrrespective,
      excludedIds: excludedIds,
      unlikedIds: unlikedIds,
      overrideInterestedIn: overrideInterestedIn,
    ).map((sp) => sp.user).toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  STAGE 3: CURATION & DIVERSIFICATION (Anti-Bubble)
  // ──────────────────────────────────────────────────────────────────────────

  /// Curates Discover pair for faceoff view:
  /// Slot 0 = top compatible candidate
  /// Slot 1 = contrasting vibe / discovery candidate
  List<UserModel> curateDiscoverPair(List<UserModel> ranked) {
    if (ranked.isEmpty) return [];
    if (ranked.length == 1) return [ranked[0]];

    final top = ranked[0];
    final topVibe = _vibeFor(top.id);

    UserModel? contrast;
    for (int i = 1; i < math.min(ranked.length, 8); i++) {
      if (_vibeFor(ranked[i].id) != topVibe) {
        contrast = ranked[i];
        break;
      }
    }
    contrast ??= ranked[1];
    return [top, contrast];
  }

  /// Curates a diversified recommendation feed to prevent algorithm fatigue:
  /// ~75% High compatibility, ~15% Vibe Discovery, ~10% Wildcard.
  List<ScoredProfile> curateDiversifiedQueue(List<ScoredProfile> ranked) {
    if (ranked.length <= 4) return ranked;

    final topTier = <ScoredProfile>[];
    final discoveryTier = <ScoredProfile>[];
    final wildcardTier = <ScoredProfile>[];

    for (final sp in ranked) {
      if (sp.category == MatchCategory.wildcard) {
        wildcardTier.add(sp);
      } else if (sp.category == MatchCategory.conversationMatch ||
                 sp.category == MatchCategory.sharedVibe) {
        discoveryTier.add(sp);
      } else {
        topTier.add(sp);
      }
    }

    final diversified = <ScoredProfile>[];
    int topIdx = 0;
    int discIdx = 0;
    int wildIdx = 0;

    while (topIdx < topTier.length ||
           discIdx < discoveryTier.length ||
           wildIdx < wildcardTier.length) {
      // 3 High-compatibility items
      for (int i = 0; i < 3 && topIdx < topTier.length; i++) {
        diversified.add(topTier[topIdx++]);
      }
      // 1 Discovery item
      if (discIdx < discoveryTier.length) {
        diversified.add(discoveryTier[discIdx++]);
      }
      // 1 Wildcard item (if available)
      if (wildIdx < wildcardTier.length) {
        diversified.add(wildcardTier[wildIdx++]);
      }
    }

    return diversified;
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  PUBLIC INTERACTION & BEHAVIORAL TRACKING
  // ──────────────────────────────────────────────────────────────────────────

  void onProfileDisplayed(String profileId) {
    _displayedAt.putIfAbsent(profileId, () => DateTime.now());
    if (!_recentlyDisplayed.contains(profileId)) {
      _recentlyDisplayed.add(profileId);
      if (_recentlyDisplayed.length > _displayWindowSize) {
        _recentlyDisplayed.removeAt(0);
      }
    }
  }

  void onLike(UserModel liked, {double? distKm}) {
    _totalLikes++;
    final vibe = _vibeFor(liked.id);
    _likesByVibe[vibe] = (_likesByVibe[vibe] ?? 0) + 1;

    final ag = _ageGroup(liked.age);
    _likesByAgeGroup[ag] = (_likesByAgeGroup[ag] ?? 0) + 1;

    if (distKm != null) {
      final band = _distBand(distKm);
      _likesByDistBand[band] = (_likesByDistBand[band] ?? 0) + 1;
    }
    _displayedAt.remove(liked.id);
    _rebalanceWeights();
  }

  void onSkip(UserModel skipped, {double? distKm}) {
    _totalSkips++;
    final vibe = _vibeFor(skipped.id);
    final shownAt = _displayedAt.remove(skipped.id);

    if (shownAt != null) {
      final ms = DateTime.now().difference(shownAt).inMilliseconds;
      if (ms < 900) {
        // Quick skip = strong disinterest signal
        _quickSkipsByVibe[vibe] = (_quickSkipsByVibe[vibe] ?? 0) + 1;
      }
    }

    final ag = _ageGroup(skipped.age);
    _skipsByAgeGroup[ag] = (_skipsByAgeGroup[ag] ?? 0) + 1;

    if (distKm != null) {
      final band = _distBand(distKm);
      _skipsByDistBand[band] = (_skipsByDistBand[band] ?? 0) + 1;
    }
  }

  void reset() {
    _likesByVibe.clear();
    _quickSkipsByVibe.clear();
    _likesByAgeGroup.clear();
    _skipsByAgeGroup.clear();
    _likesByDistBand.clear();
    _skipsByDistBand.clear();
    _recentlyDisplayed.clear();
    _displayedAt.clear();
    _totalLikes = 0;
    _totalSkips = 0;
    _wInterests = 1.0;
    _wDistance  = 1.0;
    _wAge       = 1.0;
  }

  List<EngineInsight> get insights {
    final result = <EngineInsight>[];
    if (_totalLikes < 3) return result;

    if (_likesByVibe.isNotEmpty) {
      final top = _likesByVibe.entries.reduce((a, b) => a.value > b.value ? a : b);
      result.add(EngineInsight('You love ${top.key} vibes', '✨'));
    }
    if (_likesByAgeGroup.isNotEmpty) {
      final top = _likesByAgeGroup.entries.reduce((a, b) => a.value > b.value ? a : b);
      result.add(EngineInsight('Your sweet spot: ${top.key}', '🎯'));
    }
    if (_likesByDistBand.isNotEmpty) {
      final top = _likesByDistBand.entries.reduce((a, b) => a.value > b.value ? a : b);
      result.add(EngineInsight('You prefer ${top.key} matches', '📍'));
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  INTERNAL CALCULATION HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  Set<String> _resolveSoughtGenders({
    required UserModel currentUser,
    String? overridePreference,
  }) {
    if (overridePreference != null && overridePreference.isNotEmpty && overridePreference != 'auto') {
      final clean = overridePreference.trim().toLowerCase();
      if (clean == 'all' || clean == 'everyone') {
        return {'male', 'female', 'other'};
      }
      if (clean == 'man' || clean == 'men') return {'male'};
      if (clean == 'woman' || clean == 'women') return {'female'};
      return {clean};
    }

    final eff = currentUser.effectiveInterestedIn.map((g) => g.trim().toLowerCase()).toSet();
    if (eff.contains('all') || eff.contains('everyone')) {
      return {'male', 'female', 'other'};
    }
    return eff;
  }

  double _calculateIntentScore(String? intentA, String? intentB) {
    if (intentA == null || intentB == null || intentA.isEmpty || intentB.isEmpty) {
      return 0.50; // Neutral default if not set
    }
    final a = intentA.trim().toLowerCase();
    final b = intentB.trim().toLowerCase();

    if (a == b) return 1.00;

    // Intent alignment matrix
    final pair = {a, b};
    if (pair.contains('serious') && pair.contains('open')) return 0.65;
    if (pair.contains('casual') && pair.contains('open')) return 0.70;
    if (pair.contains('friendship') && pair.contains('open')) return 0.60;
    if (pair.contains('serious') && pair.contains('friendship')) return 0.35;
    if (pair.contains('casual') && pair.contains('friendship')) return 0.40;
    if (pair.contains('serious') && pair.contains('casual')) return 0.10; // Strong divergence

    return 0.50;
  }

  _InterestBreakdown _calculateInterestScore(List<String> listA, List<String> listB) {
    final setA = listA.map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();
    final setB = listB.map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();

    if (setA.isEmpty || setB.isEmpty) {
      return const _InterestBreakdown(
        exactRatio: 0.1,
        categoryRatio: 0.1,
        rareBonus: 0.0,
        totalRatio: 0.1,
        sharedExact: [],
        sharedCategories: [],
      );
    }

    final sharedExact = setA.intersection(setB).toList();
    final union = setA.union(setB).length;
    final exactRatio = sharedExact.length / math.max(union, 1);

    // Category mapping
    final catsA = _mapToCategories(setA);
    final catsB = _mapToCategories(setB);
    final sharedCats = catsA.intersection(catsB).toList();
    final catUnion = catsA.union(catsB).length;
    final categoryRatio = sharedCats.isNotEmpty ? (sharedCats.length / math.max(catUnion, 1)) : 0.0;

    // Rare-interest bonus
    double rareBonus = 0.0;
    for (final s in sharedExact) {
      if (_rareInterests.contains(s)) rareBonus += 0.15;
    }
    rareBonus = rareBonus.clamp(0.0, 0.30);

    final totalRatio = (exactRatio * 0.65 + categoryRatio * 0.25 + rareBonus).clamp(0.0, 1.0);

    return _InterestBreakdown(
      exactRatio: exactRatio,
      categoryRatio: categoryRatio,
      rareBonus: rareBonus,
      totalRatio: totalRatio,
      sharedExact: sharedExact,
      sharedCategories: sharedCats,
    );
  }

  Set<String> _mapToCategories(Set<String> interests) {
    final result = <String>{};
    for (final interest in interests) {
      for (final entry in _interestCategories.entries) {
        if (entry.value.contains(interest) || interest.contains(entry.key)) {
          result.add(entry.key);
        }
      }
    }
    return result;
  }

  double _calculatePersonalityScore(String vibeA, String vibeB) {
    if (vibeA == vibeB) {
      return 0.85; // Strong similarity
    }

    final pair = {vibeA, vibeB};
    // Complementary synergies
    if (pair.contains('Quiet Storm') && pair.contains('Warm Current')) return 0.95; // Calm depth + gentle warmth
    if (pair.contains('Soft Rebel') && pair.contains('Soft Chaos')) return 0.90;   // Dynamic adventurous synergy
    if (pair.contains('Night Owl') && pair.contains('Soft Chaos')) return 0.88;    // Spontaneous night vibes
    if (pair.contains('Golden Hour') && pair.contains('Warm Current')) return 0.85; // Radiant positivity
    if (pair.contains('Soft Rebel') && pair.contains('Quiet Storm')) return 0.80;  // Intriguing contrast
    if (pair.contains('Golden Hour') && pair.contains('Soft Rebel')) return 0.75;

    return 0.60; // Balanced neutral baseline
  }

  double _calculateConversationPotential({
    required UserModel currentUser,
    required UserModel candidate,
    required int sharedInterestsCount,
    required double personalityScore,
  }) {
    double score = 0.30; // Baseline

    // Shared interests provide concrete talking points
    if (sharedInterestsCount >= 3) {
      score += 0.35;
    } else if (sharedInterestsCount >= 1) {
      score += 0.20;
    }

    // Bio length provides conversational substance
    final bioLen = candidate.bio?.trim().length ?? 0;
    if (bioLen >= 40) {
      score += 0.15;
    } else if (bioLen >= 15) {
      score += 0.10;
    }

    // Personality banter synergy
    if (personalityScore >= 0.8) {
      score += 0.15;
    }

    // Zodiac harmony conversational hook
    if (currentUser.zodiacSign != null && candidate.zodiacSign != null) {
      score += 0.05;
    }

    return score.clamp(0.1, 1.0);
  }

  double _calculateProximityRatio(double distKm) {
    if (distKm <= 3)  return 1.00;
    if (distKm <= 10) return 0.85;
    if (distKm <= 25) return 0.70;
    if (distKm <= 50) return 0.50;
    return 0.25;
  }

  double _calculateAgeHarmonyRatio({
    required int candidateAge,
    required double minAge,
    required double maxAge,
    required int userAge,
  }) {
    final medianPreferred = (minAge + maxAge) / 2.0;
    final distFromMedian = (candidateAge - medianPreferred).abs();

    if (distFromMedian <= 2) return 1.0;
    if (distFromMedian <= 4) return 0.8;
    if (distFromMedian <= 7) return 0.6;
    return 0.4;
  }

  double _calculateProfileQuality(UserModel user) {
    double score = 0.0;
    if (user.avatarUrl?.isNotEmpty == true) score += 0.30;
    if (user.photos.length >= 2) score += 0.25;
    if ((user.bio?.length ?? 0) >= 20) score += 0.25;
    if (user.interests.length >= 3) score += 0.10;
    if (user.isVerified) score += 0.10;
    return score.clamp(0.0, 1.0);
  }

  MatchCategory _classifyMatch({
    required double finalScore,
    required double conversationRatio,
    required double personalityScore,
    required double distKm,
    required _InterestBreakdown interestBreakdown,
  }) {
    if (finalScore >= 78) return MatchCategory.highCompatibility;
    if (conversationRatio >= 0.75) return MatchCategory.conversationMatch;
    if (personalityScore >= 0.88 || interestBreakdown.sharedCategories.length >= 2) {
      return MatchCategory.sharedVibe;
    }
    if (distKm <= 8) return MatchCategory.nearbyMatch;
    return MatchCategory.wildcard;
  }

  String _generateMatchExplanation({
    required UserModel currentUser,
    required UserModel candidate,
    required MatchCategory category,
    required _InterestBreakdown interestBreakdown,
    required double distKm,
  }) {
    final parts = <String>[];

    // Shared interests
    if (interestBreakdown.sharedExact.isNotEmpty) {
      final sharedTop = interestBreakdown.sharedExact
          .take(2)
          .map((s) => s.substring(0, 1).toUpperCase() + s.substring(1))
          .join(' & ');
      parts.add('You both love $sharedTop');
    } else if (interestBreakdown.sharedCategories.isNotEmpty) {
      final cat = interestBreakdown.sharedCategories.first;
      parts.add('Shared passion for $cat');
    }

    // Relationship intent alignment
    if (currentUser.relationshipIntent != null &&
        currentUser.relationshipIntent == candidate.relationshipIntent) {
      final intentName = currentUser.relationshipIntent == 'serious'
          ? 'something serious'
          : currentUser.relationshipIntent == 'casual'
              ? 'casual dating'
              : 'new connections';
      parts.add('both looking for $intentName');
    }

    // Proximity
    if (distKm <= 10) {
      parts.add('and live nearby');
    }

    if (parts.isNotEmpty) {
      final sentence = parts.join(', ');
      return sentence[0].toUpperCase() + sentence.substring(1) + '.';
    }

    // Fallbacks grounded in profile attributes
    if (candidate.isVerified) {
      return 'Verified profile with high conversation spark.';
    }
    return 'Complementary energy and shared curiosity.';
  }

  double _vibeMultiplier(String vibe) {
    final likes = _likesByVibe[vibe] ?? 0;
    final skips = _quickSkipsByVibe[vibe] ?? 0;
    if (likes + skips == 0) return 1.0;
    final affinity = (likes + 1.0) / (likes + skips + 2.0);
    return 0.75 + (affinity * 0.65);
  }

  void _rebalanceWeights() {
    if (_totalLikes < 3) return;

    final totalVibeSignals =
        _likesByVibe.values.fold(0, (a, b) => a + b) +
        _quickSkipsByVibe.values.fold(0, (a, b) => a + b);
    if (totalVibeSignals > 5) {
      _wInterests = (_wInterests + 0.02).clamp(0.6, 1.6);
    }

    final distLikes = _likesByDistBand.values.fold(0, (a, b) => a + b);
    final distSkips = _skipsByDistBand.values.fold(0, (a, b) => a + b);
    if (distLikes + distSkips > 5) {
      final nearbyLikes = _likesByDistBand['nearby'] ?? 0;
      if (nearbyLikes / math.max(distLikes, 1) > 0.6) {
        _wDistance = (_wDistance + 0.04).clamp(0.6, 1.8);
      }
    }

    final ageLikes = _likesByAgeGroup.values.fold(0, (a, b) => a + b);
    final ageSkips = _skipsByAgeGroup.values.fold(0, (a, b) => a + b);
    if (ageLikes + ageSkips > 5) {
      _wAge = (_wAge + 0.01).clamp(0.5, 1.5);
    }
  }

  String _vibeFor(String id) => _vibes[id.hashCode.abs() % _vibes.length];

  String _ageGroup(int age) {
    if (age <= 22) return '18–22';
    if (age <= 27) return '23–27';
    if (age <= 32) return '28–32';
    if (age <= 37) return '33–37';
    return '38+';
  }

  String _distBand(double km) {
    if (km <= 15) return 'nearby';
    if (km <= 40) return 'mid-range';
    return 'far';
  }
}

class _InterestBreakdown {
  final double exactRatio;
  final double categoryRatio;
  final double rareBonus;
  final double totalRatio;
  final List<String> sharedExact;
  final List<String> sharedCategories;

  const _InterestBreakdown({
    required this.exactRatio,
    required this.categoryRatio,
    required this.rareBonus,
    required this.totalRatio,
    required this.sharedExact,
    required this.sharedCategories,
  });
}
