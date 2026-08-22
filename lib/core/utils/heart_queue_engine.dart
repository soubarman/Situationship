import 'dart:math' as math;
import '../models/user_model.dart';
import 'location_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  HeartQueue™ Engine  v2.0
//  Smart Matching Algorithm for Situationship
// ─────────────────────────────────────────────────────────────────────────────
//
//  SCORING MODEL  (base max ~100 pts + multipliers)
//  ┌─────────────────────────────────┬──────────┬──────────────────────────┐
//  │ Factor                          │ Max Pts  │ Notes                    │
//  ├─────────────────────────────────┼──────────┼──────────────────────────┤
//  │ 1. Mutual Attraction            │  40 pts  │ They liked you first     │
//  │ 2. Soul Compatibility           │  25 pts  │ Shared interests         │
//  │ 3. Proximity                    │  20 pts  │ Haversine distance       │
//  │ 4. Age Harmony                  │  10 pts  │ Age delta                │
//  │ 5. Profile Completeness         │   5 pts  │ Bio, avatar, interests   │
//  ├─────────────────────────────────┼──────────┼──────────────────────────┤
//  │ 6. Vibe Affinity ×              │ ×0.75–1.40│ Learned from behavior   │
//  │ 7. Recency Penalty ×            │ ×0.65    │ Anti-repetition          │
//  │ 8. Online Bonus ×               │ ×1.10    │ Currently online         │
//  │ 9. Verified Boost ×             │ ×1.08    │ Verified badge           │
//  └─────────────────────────────────┴──────────┴──────────────────────────┘
//
//  BEHAVIORAL LEARNING
//  • Tracks per-vibe & per-age-group like/skip ratios
//  • Detects "quick skips" (< 900ms) as strong rejection signals
//  • Adjusts _wInterests, _wDistance, _wAge weights after every 3 likes
//  • Emits actionable insights ("You love Warm Current vibes", etc.)
//
//  PAIR CURATION
//  • curateDiscoverPair(): top-scored + contrasting-vibe for interesting choice
//
//  MATCH LIFECYCLE
//  • Like → pending transaction (3s undo window via HeartQueue algorithm)
//  • Undo → atomic rollback of both liked + paired profiles
//  • Commit → finalise to confirmed sets
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable result of scoring a single profile.
class ScoredProfile {
  final UserModel user;
  final double score;       // raw engine score
  final int displayScore;   // 0–99 "match %" shown to user
  final String debugInfo;   // developer logging

  const ScoredProfile({
    required this.user,
    required this.score,
    required this.displayScore,
    required this.debugInfo,
  });
}

/// Insight derived from user's behavioral pattern.
class EngineInsight {
  final String label;
  final String emoji;
  const EngineInsight(this.label, this.emoji);
}

// ─────────────────────────────────────────────────────────────────────────────

class HeartQueueEngine {
  // ── Factor Weights (adjusted by behavioral learning) ──────────────────────
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

  // ── Anti-Repetition: ring buffer of recently-displayed profile IDs ─────────
  final List<String> _recentlyDisplayed = [];
  static const _displayWindowSize = 60; // track last 60 displayed profiles

  // ── Skip-Velocity Tracker ──────────────────────────────────────────────────
  final Map<String, DateTime> _displayedAt = {};

  // ── Vibe Labels (matches discover_tab + nearly_souls_tab) ─────────────────
  static const _vibes = [
    'Warm Current', 'Soft Rebel',  'Golden Hour',
    'Quiet Storm',  'Soft Chaos',  'Night Owl',
  ];

  // ─── Public Interface ──────────────────────────────────────────────────────

  /// Call whenever a profile card becomes visible on screen.
  void onProfileDisplayed(String profileId) {
    _displayedAt.putIfAbsent(profileId, () => DateTime.now());
    if (!_recentlyDisplayed.contains(profileId)) {
      _recentlyDisplayed.add(profileId);
      if (_recentlyDisplayed.length > _displayWindowSize) {
        _recentlyDisplayed.removeAt(0);
      }
    }
  }

  /// Record a confirmed like. Updates behavioral weights.
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

  /// Record a permanent skip. Detects quick-skips via velocity.
  void onSkip(UserModel skipped, {double? distKm}) {
    _totalSkips++;
    final vibe   = _vibeFor(skipped.id);
    final shownAt = _displayedAt.remove(skipped.id);

    if (shownAt != null) {
      final ms = DateTime.now().difference(shownAt).inMilliseconds;
      if (ms < 900) {
        // Strong rejection signal
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

  /// Score one candidate profile.
  ScoredProfile scoreProfile({
    required UserModel currentUser,
    required UserModel candidate,
    double? deviceLat,
    double? deviceLon,
  }) {
    final buf = StringBuffer();
    double s   = 0;

    // 1. Mutual Attraction (0–40)
    if (candidate.likedBy.contains(currentUser.id) ||
        candidate.following.contains(currentUser.id)) {
      s += 40;
      buf.write('[MutualAttr+40]');
    }

    // 2. Soul Compatibility: Jaccard interest overlap (0–25)
    final mySet    = currentUser.interests.toSet();
    final theirSet = candidate.interests.toSet();
    final shared   = mySet.intersection(theirSet).length;
    final union    = math.max(mySet.union(theirSet).length, 1);
    final soulPts  = (shared / union) * 25.0 * _wInterests;
    s += soulPts;
    buf.write('[Soul+${soulPts.toStringAsFixed(1)}]');

    // 3. Proximity (0–20)
    final distKm = LocationHelper.getDistanceKm(
      lat1: deviceLat, lon1: deviceLon,
      loc1: currentUser.location,
      loc2: candidate.location,
      id1:  currentUser.id,
      id2:  candidate.id,
    );
    final proxPts = _proximityScore(distKm) * _wDistance;
    s += proxPts;
    buf.write('[Prox+${proxPts.toStringAsFixed(1)}@${distKm.toStringAsFixed(0)}km]');

    // 4. Age Harmony (0–10)
    final ageDiff = (currentUser.age - candidate.age).abs();
    final agePts  = _ageScore(ageDiff) * _wAge;
    s += agePts;
    buf.write('[Age+${agePts.toStringAsFixed(1)}]');

    // 5. Profile Completeness (0–5)
    double cpPts = 0;
    if (candidate.avatarUrl?.isNotEmpty == true) cpPts += 2.0;
    if ((candidate.bio?.length ?? 0) > 15)       cpPts += 2.0;
    if (candidate.interests.length >= 3)          cpPts += 0.5;
    if (candidate.isVerified)                     cpPts += 0.5;
    s += cpPts;
    buf.write('[Complete+$cpPts]');

    // 6. Vibe Affinity Multiplier (×0.75–1.40)
    final vibe  = _vibeFor(candidate.id);
    final vibeM = _vibeMultiplier(vibe);
    buf.write('[Vibe:$vibe×${vibeM.toStringAsFixed(2)}]');

    // 7. Recency Penalty (×0.30) — strong anti-repetition
    final recencyM = _recentlyDisplayed.contains(candidate.id) ? 0.30 : 1.0;
    if (recencyM < 1.0) buf.write('[Recent×0.30]');

    // 8. Online Bonus (×1.10)
    final onlineM = candidate.isOnline ? 1.10 : 1.0;
    if (candidate.isOnline) buf.write('[Online×1.10]');

    // 9. Verified Boost (×1.08)
    final verifiedM = candidate.isVerified ? 1.08 : 1.0;
    if (candidate.isVerified) buf.write('[Verified×1.08]');

    s = s * vibeM * recencyM * onlineM * verifiedM;

    // Display match % (stable hash-based, boosted by Jaccard overlap)
    final jaccardBonus = shared > 0 ? (shared / union * 12).round() : 0;
    final displayScore =
        (76 + jaccardBonus + (candidate.id.hashCode.abs() % 10)).clamp(72, 99);

    return ScoredProfile(
      user: candidate,
      score: s,
      displayScore: displayScore,
      debugInfo: buf.toString(),
    );
  }

  /// Rank all candidates by score (highest first). Also marks top profiles
  /// as "displayed" in the anti-repetition window.
  List<ScoredProfile> rankProfiles({
    required UserModel currentUser,
    required List<UserModel> candidates,
    double? deviceLat,
    double? deviceLon,
  }) {
    if (candidates.isEmpty) return [];
    final scored = candidates
        .map((u) => scoreProfile(
              currentUser: currentUser,
              candidate: u,
              deviceLat: deviceLat,
              deviceLon: deviceLon,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // Mark the top 4 as displayed so skip-velocity tracking is ready
    for (final sp in scored.take(4)) {
      onProfileDisplayed(sp.user.id);
    }
    return scored;
  }

  /// Convenience: returns [UserModel] list sorted by score.
  List<UserModel> rankedUsers({
    required UserModel currentUser,
    required List<UserModel> candidates,
    double? deviceLat,
    double? deviceLon,
  }) =>
      rankProfiles(
        currentUser: currentUser,
        candidates: candidates,
        deviceLat: deviceLat,
        deviceLon: deviceLon,
      ).map((sp) => sp.user).toList();

  /// Curates the best Discover pair from an already-ranked list.
  ///
  /// Rules:
  ///  • Position 0 = highest-scored (the "safe bet")
  ///  • Position 1 = highest-scored with a DIFFERENT vibe (the "contrast")
  ///    → creates an interesting tension: familiar vs. unexpected
  ///  • Falls back to top-2 if no contrast exists in top-8
  List<UserModel> curateDiscoverPair(List<UserModel> ranked) {
    if (ranked.isEmpty) return [];
    if (ranked.length == 1) return [ranked[0]];

    final top     = ranked[0];
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

  /// Behavioral insights — can be shown in a "Your Type" summary screen.
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
    if (_totalLikes > 0 && _totalSkips > 0) {
      final ratio = _totalLikes / (_totalLikes + _totalSkips);
      if (ratio > 0.6) {
        result.add(const EngineInsight("You're an open heart", '💖'));
      } else if (ratio < 0.25) {
        result.add(const EngineInsight('You know exactly what you want', '🔥'));
      }
    }
    return result;
  }

  /// Full reset — call on logout.
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

  // ─── Internal Helpers ──────────────────────────────────────────────────────

  double _proximityScore(double km) {
    if (km <= 3)  return 20.0;
    if (km <= 10) return 16.0;
    if (km <= 20) return 12.0;
    if (km <= 35) return  8.0;
    if (km <= 60) return  4.0;
    return 1.5;
  }

  double _ageScore(int diff) {
    if (diff <= 1)  return 10.0;
    if (diff <= 3)  return  8.0;
    if (diff <= 6)  return  5.0;
    if (diff <= 10) return  2.0;
    return 0.0;
  }

  /// Vibe affinity multiplier: smoothed Bayesian estimate.
  /// Maps behavioral like/skip ratio → ×0.75 (disliked) to ×1.40 (loved).
  double _vibeMultiplier(String vibe) {
    final likes = _likesByVibe[vibe]      ?? 0;
    final skips = _quickSkipsByVibe[vibe] ?? 0;
    if (likes + skips == 0) return 1.0;
    final affinity = (likes + 1.0) / (likes + skips + 2.0); // Laplace smoothed
    return 0.75 + (affinity * 0.65);  // maps [0..1] → [0.75..1.40]
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

  String _vibeFor(String id)  => _vibes[id.hashCode.abs() % _vibes.length];
  String _ageGroup(int age)   {
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
