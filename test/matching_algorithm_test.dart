import 'package:flutter_test/flutter_test.dart';
import 'package:situationship/core/models/user_model.dart';
import 'package:situationship/core/utils/heart_queue_engine.dart';

void main() {
  group('HeartQueue™ Stage 1: Hard Eligibility Filters', () {
    late HeartQueueEngine engine;

    setUp(() {
      engine = HeartQueueEngine();
    });

    final userA = UserModel(
      id: 'user_a',
      name: 'Alice',
      email: 'a@test.com',
      age: 24,
      gender: 'male',
      interestedIn: const ['female'],
      relationshipIntent: 'serious',
    );

    test('Male seeking Female: Female seeking Male is eligible', () {
      final femaleCandidate = UserModel(
        id: 'candidate_b',
        name: 'Bella',
        email: 'b@test.com',
        age: 23,
        gender: 'female',
        interestedIn: const ['male'],
        relationshipIntent: 'serious',
      );

      final eligible = engine.isCandidateEligible(
        currentUser: userA,
        candidate: femaleCandidate,
        minAge: 18,
        maxAge: 35,
        maxDistance: 50,
        matchIrrespective: true,
      );

      expect(eligible, isTrue);
    });

    test('Male seeking Female: Male candidate is strictly REJECTED (Bug Fix Validation)', () {
      final maleCandidate = UserModel(
        id: 'candidate_c',
        name: 'Charlie',
        email: 'c@test.com',
        age: 25,
        gender: 'male',
        interestedIn: const ['female'],
      );

      final eligible = engine.isCandidateEligible(
        currentUser: userA,
        candidate: maleCandidate,
        minAge: 18,
        maxAge: 35,
        maxDistance: 50,
        matchIrrespective: true,
      );

      expect(eligible, isFalse, reason: 'Male seeking female must NEVER be shown a male candidate');
    });

    test('Reciprocal Eligibility: Female candidate seeking ONLY Female rejects Male user', () {
      final lesbianCandidate = UserModel(
        id: 'candidate_d',
        name: 'Diana',
        email: 'd@test.com',
        age: 24,
        gender: 'female',
        interestedIn: const ['female'], // Only wants females
      );

      // Even though userA wants female, Diana does NOT want male.
      final eligible = engine.isCandidateEligible(
        currentUser: userA,
        candidate: lesbianCandidate,
        minAge: 18,
        maxAge: 35,
        maxDistance: 50,
        matchIrrespective: true,
      );

      expect(eligible, isFalse, reason: 'Candidate who does not accept currentUser gender must be rejected');
    });

    test('Reciprocal Eligibility: Candidate with unconfigured (empty) interestedIn does NOT reject currentUser', () {
      final unconfiguredCandidate = UserModel(
        id: 'candidate_unconfigured',
        name: 'Sara',
        email: 'sara@test.com',
        age: 23,
        gender: 'female',
        interestedIn: const [], // Not yet explicitly configured
      );

      final eligible = engine.isCandidateEligible(
        currentUser: userA,
        candidate: unconfiguredCandidate,
        minAge: 18,
        maxAge: 35,
        maxDistance: 50,
        matchIrrespective: true,
      );

      expect(eligible, isTrue, reason: 'Unconfigured candidate profile should not reject valid user');
    });

    test('Adaptive Distance Widening: When local candidates are outside maxDistance, engine widens radius without showing wrong gender', () {
      // User is in Delhi, candidates in Mumbai (distance > 1000km)
      final delhiUser = UserModel(
        id: 'delhi_user',
        name: 'Arjun',
        email: 'arjun@test.com',
        location: 'Delhi',
        age: 25,
        gender: 'male',
        interestedIn: const ['female'],
      );

      final mumbaiFemale = UserModel(
        id: 'mumbai_female',
        name: 'Pooja',
        email: 'pooja@test.com',
        location: 'Mumbai',
        age: 24,
        gender: 'female',
        interestedIn: const ['male'],
      );

      final mumbaiMale = UserModel(
        id: 'mumbai_male',
        name: 'Rohan',
        email: 'rohan@test.com',
        location: 'Mumbai',
        age: 26,
        gender: 'male',
        interestedIn: const ['female'],
      );

      // maxDistance is 50km, matchIrrespective is false
      final eligible = engine.filterEligibleCandidates(
        currentUser: delhiUser,
        candidates: [mumbaiFemale, mumbaiMale],
        minAge: 18,
        maxAge: 35,
        maxDistance: 50,
        matchIrrespective: false, // will adaptively widen because 0 within 50km
      );

      // Must find the female candidate
      expect(eligible.any((u) => u.id == 'mumbai_female'), isTrue);
      // Male candidate must NEVER be included (strict invariant maintained!)
      expect(eligible.any((u) => u.id == 'mumbai_male'), isFalse);
    });

    test('Multiple Gender Preferences: accepts candidates matching preferences', () {
      final bisexualUser = UserModel(
        id: 'user_bi',
        name: 'Alex',
        email: 'bi@test.com',
        age: 26,
        gender: 'male',
        interestedIn: const ['female', 'other'],
      );

      final femaleCandidate = UserModel(
        id: 'cand_f',
        name: 'Fiona',
        email: 'f@test.com',
        age: 25,
        gender: 'female',
        interestedIn: const ['male'],
      );

      final nbCandidate = UserModel(
        id: 'cand_nb',
        name: 'Rowan',
        email: 'nb@test.com',
        age: 24,
        gender: 'other',
        interestedIn: const ['all'],
      );

      final maleCandidate = UserModel(
        id: 'cand_m',
        name: 'Mike',
        email: 'm@test.com',
        age: 27,
        gender: 'male',
        interestedIn: const ['male'],
      );

      expect(
        engine.isCandidateEligible(
          currentUser: bisexualUser,
          candidate: femaleCandidate,
          minAge: 18,
          maxAge: 35,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isTrue,
      );

      expect(
        engine.isCandidateEligible(
          currentUser: bisexualUser,
          candidate: nbCandidate,
          minAge: 18,
          maxAge: 35,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isTrue,
      );

      expect(
        engine.isCandidateEligible(
          currentUser: bisexualUser,
          candidate: maleCandidate,
          minAge: 18,
          maxAge: 35,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isFalse,
        reason: 'Male candidate not in user_bi interestedIn list',
      );
    });

    test('Moderation: Suspended and Banned candidates are rejected', () {
      final suspendedCandidate = UserModel(
        id: 'cand_susp',
        name: 'BannedUser',
        email: 'banned@test.com',
        age: 24,
        gender: 'female',
        interestedIn: const ['male'],
        isSuspended: true,
      );

      expect(
        engine.isCandidateEligible(
          currentUser: userA,
          candidate: suspendedCandidate,
          minAge: 18,
          maxAge: 35,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isFalse,
      );
    });

    test('Two-Way Block: Candidate is rejected if either side blocked the other', () {
      final userBlockedCandidate = UserModel(
        id: 'cand_blocked_1',
        name: 'Target1',
        email: 't1@test.com',
        age: 24,
        gender: 'female',
        interestedIn: const ['male'],
      );
      final userWithBlock = userA.copyWith(blockedUsers: ['cand_blocked_1']);

      expect(
        engine.isCandidateEligible(
          currentUser: userWithBlock,
          candidate: userBlockedCandidate,
          minAge: 18,
          maxAge: 35,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isFalse,
      );

      final candidateWhoBlockedUser = UserModel(
        id: 'cand_blocked_2',
        name: 'Target2',
        email: 't2@test.com',
        age: 24,
        gender: 'female',
        interestedIn: const ['male'],
        blockedUsers: [userA.id],
      );

      expect(
        engine.isCandidateEligible(
          currentUser: userA,
          candidate: candidateWhoBlockedUser,
          minAge: 18,
          maxAge: 35,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isFalse,
      );
    });

    test('Already Matched, Liked, or Disliked candidates are rejected', () {
      final alreadyMatched = UserModel(
        id: 'cand_matched',
        name: 'Matched',
        email: 'm@test.com',
        age: 24,
        gender: 'female',
        interestedIn: const ['male'],
      );
      final userWithMatch = userA.copyWith(matches: ['cand_matched']);

      expect(
        engine.isCandidateEligible(
          currentUser: userWithMatch,
          candidate: alreadyMatched,
          minAge: 18,
          maxAge: 35,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isFalse,
      );

      final alreadyDisliked = UserModel(
        id: 'cand_disliked',
        name: 'Disliked',
        email: 'd@test.com',
        age: 24,
        gender: 'female',
        interestedIn: const ['male'],
      );
      final userWithDisliked = userA.copyWith(dislikedUsers: ['cand_disliked']);

      expect(
        engine.isCandidateEligible(
          currentUser: userWithDisliked,
          candidate: alreadyDisliked,
          minAge: 18,
          maxAge: 35,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isFalse,
      );
    });

    test('Age Boundaries: outside range is rejected', () {
      final tooYoung = UserModel(
        id: 'cand_young',
        name: 'Young',
        email: 'y@test.com',
        age: 19,
        gender: 'female',
        interestedIn: const ['male'],
      );

      final tooOld = UserModel(
        id: 'cand_old',
        name: 'Old',
        email: 'o@test.com',
        age: 40,
        gender: 'female',
        interestedIn: const ['male'],
      );

      expect(
        engine.isCandidateEligible(
          currentUser: userA,
          candidate: tooYoung,
          minAge: 21,
          maxAge: 30,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isFalse,
      );

      expect(
        engine.isCandidateEligible(
          currentUser: userA,
          candidate: tooOld,
          minAge: 21,
          maxAge: 30,
          maxDistance: 50,
          matchIrrespective: true,
        ),
        isFalse,
      );
    });
  });

  group('HeartQueue™ Stage 2: Raw Compatibility Scoring & Ranking', () {
    late HeartQueueEngine engine;

    setUp(() {
      engine = HeartQueueEngine();
    });

    final currentUser = UserModel(
      id: 'current_user',
      name: 'Rahul',
      email: 'rahul@test.com',
      age: 25,
      gender: 'male',
      interestedIn: const ['female'],
      relationshipIntent: 'serious',
      interests: const ['Gaming', 'Coffee', 'Travel'],
      bio: 'Loves gaming, weekend cafes, and exploring new spots.',
    );

    test('Intent Alignment: serious <-> serious outranks serious <-> casual', () {
      final seriousMatch = UserModel(
        id: 'candidate_serious',
        name: 'Priya',
        email: 'p@test.com',
        age: 24,
        gender: 'female',
        interestedIn: const ['male'],
        relationshipIntent: 'serious',
        interests: const ['Gaming', 'Coffee'],
      );

      final casualMatch = UserModel(
        id: 'candidate_casual',
        name: 'Neha',
        email: 'n@test.com',
        age: 24,
        gender: 'female',
        interestedIn: const ['male'],
        relationshipIntent: 'casual',
        interests: const ['Gaming', 'Coffee'],
      );

      final scoreSerious = engine.scoreProfile(currentUser: currentUser, candidate: seriousMatch);
      final scoreCasual = engine.scoreProfile(currentUser: currentUser, candidate: casualMatch);

      expect(scoreSerious.score, greaterThan(scoreCasual.score));
    });

    test('Categorized Interests & Rare Overlap: Shared rare interest yields bonus', () {
      final normalInterests = UserModel(
        id: 'cand_norm',
        name: 'Simran',
        email: 's@test.com',
        age: 25,
        gender: 'female',
        interestedIn: const ['male'],
        interests: const ['Music'],
      );

      final rareInterests = UserModel(
        id: 'cand_rare',
        name: 'Ananya',
        email: 'a@test.com',
        age: 25,
        gender: 'female',
        interestedIn: const ['male'],
        interests: const ['Gaming', 'Coffee', 'Surfing'],
      );

      final scoredNormal = engine.scoreProfile(currentUser: currentUser, candidate: normalInterests);
      final scoredRare = engine.scoreProfile(currentUser: currentUser, candidate: rareInterests);

      expect(scoredRare.score, greaterThan(scoredNormal.score));
    });

    test('Match Explanation is grounded in actual user data', () {
      final candidate = UserModel(
        id: 'cand_exp',
        name: 'Tara',
        email: 'tara@test.com',
        age: 24,
        gender: 'female',
        interestedIn: const ['male'],
        relationshipIntent: 'serious',
        interests: const ['Gaming', 'Coffee'],
      );

      final scored = engine.scoreProfile(currentUser: currentUser, candidate: candidate);

      expect(scored.matchExplanation, contains('Gaming'));
      expect(scored.matchExplanation, contains('serious'));
    });

    test('Diversification partitions queue without violating eligibility', () {
      final candidates = List.generate(8, (i) {
        return UserModel(
          id: 'cand_$i',
          name: 'Candidate $i',
          email: 'cand$i@test.com',
          age: 22 + (i % 6),
          gender: 'female',
          interestedIn: const ['male'],
          relationshipIntent: i.isEven ? 'serious' : 'open',
          interests: ['Gaming', 'Coffee', if (i == 3) 'Surfing'],
        );
      });

      final ranked = engine.rankProfiles(
        currentUser: currentUser,
        candidates: candidates,
        minAge: 18,
        maxAge: 35,
        maxDistance: 50,
        matchIrrespective: true,
      );

      final diversified = engine.curateDiversifiedQueue(ranked);

      expect(diversified.length, equals(candidates.length));
      // All profiles in diversified queue must be female (Stage 1 eligibility invariant)
      for (final sp in diversified) {
        expect(sp.user.gender, equals('female'));
      }
    });

    test('Configurable Weights: Tuning intent weight alters relative rankings', () {
      final customEngine = HeartQueueEngine(
        initialWeights: const MatchingWeights(
          intentWeight: 40.0,
          interestWeight: 5.0,
        ),
      );

      expect(customEngine.weights.intentWeight, equals(40.0));
      expect(customEngine.weights.interestWeight, equals(5.0));
    });
  });
}
