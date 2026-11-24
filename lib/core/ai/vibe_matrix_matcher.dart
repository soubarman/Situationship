import 'dart:math' as math;
import '../../core/models/user_model.dart';
import '../../core/utils/heart_queue_engine.dart';
import 'vibe_matrix_vocabulary.dart';
import 'on_device_nlu_engine.dart';
import 'match_rationale_generator.dart';

class CupidMatchResult {
  final UserModel candidate;
  final int compatibilityScore; // 60 - 99%
  final List<String> highlightTraits;
  final MatchRationale rationale;
  final double rawCosine;

  const CupidMatchResult({
    required this.candidate,
    required this.compatibilityScore,
    required this.highlightTraits,
    required this.rationale,
    required this.rawCosine,
  });
}

class VibeMatrixMatcher {
  final HeartQueueEngine _heartQueue = HeartQueueEngine();

  /// Builds an on-device dense semantic vector representation for a candidate profile
  Map<String, double> vectorizeProfile(UserModel candidate) {
    final rawScores = <String, double>{};

    // Combine profile text sources
    final bioText = (candidate.bio ?? '').toLowerCase();
    final interestsText = candidate.interests.join(' ').toLowerCase();
    final fullText = '$bioText $interestsText';

    for (final dim in VibeMatrixVocabulary.dimensions) {
      double score = 0.0;

      // Check category match
      for (final syn in dim.synonyms) {
        if (fullText.contains(syn)) {
          score += 1.5 * dim.defaultWeight;
        }
      }

      // Check direct interest string match
      for (final interest in candidate.interests) {
        final lowerInterest = interest.toLowerCase();
        if (dim.synonyms.any((s) => s.contains(lowerInterest) || lowerInterest.contains(s))) {
          score += 2.0 * dim.defaultWeight;
        }
      }

      // Relationship intent dimension
      if (candidate.relationshipIntent != null) {
        if (dim.id == 'intent_${candidate.relationshipIntent}') {
          score += 3.0;
        }
      }

      // Dealbreakers check
      if (dim.id == 'non_smoker' && !fullText.contains('smoke')) {
        score += 0.5;
      }
      if (dim.id == 'non_drinker' && !fullText.contains('drink') && !fullText.contains('alcohol')) {
        score += 0.5;
      }

      if (score > 0) {
        rawScores[dim.id] = score;
      }
    }

    // Normalize to unit length (L2 norm)
    final denseVector = <String, double>{};
    if (rawScores.isNotEmpty) {
      double sumSquares = 0.0;
      for (final val in rawScores.values) {
        sumSquares += val * val;
      }
      final norm = math.sqrt(sumSquares);
      if (norm > 0) {
        rawScores.forEach((k, v) => denseVector[k] = v / norm);
      }
    }

    return denseVector;
  }

  /// Calculates cosine similarity between query vector and profile vector
  double calculateCosineSimilarity(Map<String, double> queryVec, Map<String, double> profileVec) {
    if (queryVec.isEmpty || profileVec.isEmpty) return 0.0;

    double dotProduct = 0.0;
    queryVec.forEach((dimId, queryWeight) {
      if (profileVec.containsKey(dimId)) {
        dotProduct += queryWeight * profileVec[dimId]!;
      }
    });

    return dotProduct.clamp(0.0, 1.0);
  }

  /// Ranks candidates completely on-device
  List<CupidMatchResult> findMatches({
    required UserModel currentUser,
    required List<UserModel> candidates,
    required NLUIntentResult intent,
    Set<String> excludedIds = const {},
    int limit = 5,
  }) {
    if (candidates.isEmpty) return [];

    // Derive effective query vector: if conversational query had no specific vibe keywords
    // (e.g. "Can you find me a profile that matches me", "recommend someone"),
    // use the current user's own profile vector as the target preference!
    Map<String, double> effectiveQueryVector = intent.denseVector;
    final isMatchingUserProfile = effectiveQueryVector.isEmpty;
    if (isMatchingUserProfile) {
      effectiveQueryVector = vectorizeProfile(currentUser);
    }

    final genderOverride = intent.genderHint != null ? [intent.genderHint!] : null;

    // ── STAGE 1: Strict HeartQueue Pre-qualification ───────────────────────────
    final strictEligible = <UserModel>[];

    for (final candidate in candidates) {
      if (candidate.id == currentUser.id) continue;
      if (excludedIds.contains(candidate.id)) continue;

      final isEligible = _heartQueue.isCandidateEligible(
        currentUser: currentUser,
        candidate: candidate,
        minAge: 18,
        maxAge: 70,
        maxDistance: double.infinity,
        matchIrrespective: true, // Allow nation-wide or global for conversational concierge
        excludedIds: excludedIds,
        overrideInterestedIn: genderOverride?.first,
      );

      if (!isEligible) continue;

      // Dealbreaker checks
      if (intent.dealbreakers.contains('smoking')) {
        final bio = (candidate.bio ?? '').toLowerCase();
        if (bio.contains('smoker') || bio.contains('smoking') || bio.contains('cigarettes')) {
          continue;
        }
      }
      if (intent.dealbreakers.contains('drinking')) {
        final bio = (candidate.bio ?? '').toLowerCase();
        if (bio.contains('drinks') || bio.contains('drinking') || bio.contains('alcoholic')) {
          continue;
        }
      }

      strictEligible.add(candidate);
    }

    // ── STAGE 1B: Conversational Fallback Relaxation ──────────────────────────
    // If strict HeartQueue filters eliminated everyone (e.g. user already swiped on
    // candidates in the swipe tab, candidate isDiscoverable flag is unconfigured,
    // or test accounts exist during development), relax non-critical filters so the
    // conversational concierge never delivers an empty dead end.
    List<UserModel> pool = strictEligible;

    if (pool.length < 2) {
      final relaxedEligible = <UserModel>[];

      for (final candidate in candidates) {
        if (candidate.id == currentUser.id) continue;
        if (excludedIds.contains(candidate.id)) continue;
        if (currentUser.blockedUsers.contains(candidate.id)) continue;

        // Gender filter:
        // 1. If user explicitly asked for "girl" / "guy" in chat, respect that strictly.
        if (intent.genderHint != null && candidate.normalizedGender != intent.genderHint) {
          continue;
        }
        // 2. If user has interestedIn set, prefer that gender if any match exists.
        if (intent.genderHint == null && currentUser.interestedIn.isNotEmpty) {
          final prefers = currentUser.interestedIn.map((g) => g.toLowerCase()).toSet();
          final matchesPref = prefers.contains(candidate.normalizedGender) || prefers.contains('all') || prefers.contains('both');
          if (!matchesPref) {
            // Keep as lowest priority candidate only if pool is starving
            final anyMatchesPref = candidates.any((c) =>
                c.id != currentUser.id &&
                !excludedIds.contains(c.id) &&
                (prefers.contains(c.normalizedGender) || prefers.contains('all')));
            if (anyMatchesPref) continue;
          }
        }

        // Dealbreakers are always respected
        if (intent.dealbreakers.contains('smoking')) {
          final bio = (candidate.bio ?? '').toLowerCase();
          if (bio.contains('smoker') || bio.contains('smoking') || bio.contains('cigarettes')) {
            continue;
          }
        }
        if (intent.dealbreakers.contains('drinking')) {
          final bio = (candidate.bio ?? '').toLowerCase();
          if (bio.contains('drinks') || bio.contains('drinking') || bio.contains('alcoholic')) {
            continue;
          }
        }

        relaxedEligible.add(candidate);
      }

      if (relaxedEligible.isNotEmpty) {
        pool = relaxedEligible;
      }
    }

    // ── STAGE 2: Dense Semantic Vector Scoring ─────────────────────────────────
    final scoredResults = <CupidMatchResult>[];

    for (final candidate in pool) {
      final profileVec = vectorizeProfile(candidate);
      final rawCosine = calculateCosineSimilarity(effectiveQueryVector, profileVec);

      // Mutual trait highlights
      final matchedDimensionIds = <String>[];
      for (final dimId in effectiveQueryVector.keys) {
        if (profileVec.containsKey(dimId)) {
          matchedDimensionIds.add(dimId);
        }
      }

      // Calculate displayed compatibility score (68% to 98%)
      double blended = 0.68;
      if (effectiveQueryVector.isNotEmpty) {
        blended = 0.68 + (rawCosine * 0.28);
      } else {
        final sharedInterests = candidate.interests.where((i) => currentUser.interests.contains(i)).length;
        blended = 0.72 + (sharedInterests * 0.05).clamp(0.0, 0.22);
      }

      // Quality bonuses
      if (candidate.isVerified) blended += 0.02;
      if ((candidate.bio ?? '').length > 30) blended += 0.02;
      if (candidate.photos.length >= 2) blended += 0.01;

      final finalPercentage = (blended * 100).round().clamp(68, 98);

      // Resolve human-readable trait labels
      final highlightTraits = matchedDimensionIds.take(3).map((id) {
        final dim = VibeMatrixVocabulary.dimensions.firstWhere(
          (d) => d.id == id,
          orElse: () => VibeDimension(id: id, canonicalName: id, category: '', synonyms: []),
        );
        return dim.canonicalName;
      }).toList();

      if (highlightTraits.isEmpty && candidate.interests.isNotEmpty) {
        highlightTraits.addAll(candidate.interests.take(2));
      }

      final rationale = MatchRationaleGenerator.generate(
        candidate: candidate,
        userIntent: intent,
        matchedDimensionIds: matchedDimensionIds,
        compatibilityScore: finalPercentage,
      );

      scoredResults.add(CupidMatchResult(
        candidate: candidate,
        compatibilityScore: finalPercentage,
        highlightTraits: highlightTraits,
        rationale: rationale,
        rawCosine: rawCosine,
      ));
    }

    // ── STAGE 3: Rank descending by compatibility score & raw cosine ───────────
    scoredResults.sort((a, b) {
      final comp = b.compatibilityScore.compareTo(a.compatibilityScore);
      if (comp != 0) return comp;
      return b.rawCosine.compareTo(a.rawCosine);
    });

    return scoredResults.take(limit).toList();
  }
}
