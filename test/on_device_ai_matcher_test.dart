import 'package:flutter_test/flutter_test.dart';
import 'package:situationship/core/ai/on_device_nlu_engine.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/ai/match_rationale_generator.dart';
import 'package:situationship/core/models/user_model.dart';

void main() {
  group('On-Device Cupid AI: Natural Language Understanding (NLU)', () {
    test('Correctly extracts complex multi-attribute intents and dealbreakers', () {
      const query =
          "I want an artistic girl who loves indie rock, late night drives, doesn't smoke or drink, and is looking for something serious";

      final result = OnDeviceNLUEngine.parse(query);

      expect(result.genderHint, equals('female'));
      expect(result.targetRelationshipIntent, equals('serious'));
      expect(result.dealbreakers, contains('smoking'));
      expect(result.dealbreakers, contains('drinking'));
      expect(result.detectedDimensionIds, contains('artistic'));
      expect(result.detectedDimensionIds, contains('indie'));
      expect(result.detectedDimensionIds, contains('night_owl'));
      expect(result.detectedDimensionIds, contains('intent_serious'));
      expect(result.denseVector.isNotEmpty, isTrue);
    });

    test('Handles casual and spontaneous vibes without negations', () {
      const query = "Someone spontaneous and chill who loves coffee and road trips";

      final result = OnDeviceNLUEngine.parse(query);

      expect(result.detectedDimensionIds, contains('spontaneous'));
      expect(result.detectedDimensionIds, contains('chill'));
      expect(result.detectedDimensionIds, contains('coffee'));
      expect(result.dealbreakers, isEmpty);
    });

    test('Detects pagination / continuation intent correctly', () {
      final res1 = OnDeviceNLUEngine.parse("Is there no more profiles");
      final res2 = OnDeviceNLUEngine.parse("Show me more");
      final res3 = OnDeviceNLUEngine.parse("Anyone else?");

      expect(res1.isMoreOrContinuation, isTrue);
      expect(res2.isMoreOrContinuation, isTrue);
      expect(res3.isMoreOrContinuation, isTrue);
    });
  });

  group('On-Device Cupid AI: VibeMatrix™ Matcher & HeartQueue™ Fusion', () {
    final matcher = VibeMatrixMatcher();

    final currentUser = UserModel(
      id: 'current_user_1',
      name: 'Rohan',
      email: 'rohan@situationship.com',
      age: 24,
      gender: 'male',
      interestedIn: const ['female'],
      relationshipIntent: 'serious',
      interests: const ['Indie Rock', 'Coffee', 'Design'],
    );

    final candidateArtistic = UserModel(
      id: 'cand_artistic',
      name: 'Maya',
      email: 'maya@situationship.com',
      age: 23,
      gender: 'female',
      interestedIn: const ['male'],
      relationshipIntent: 'serious',
      bio: 'Photographer and analog film lover. Constantly listening to Arctic Monkeys.',
      interests: const ['Photography', 'Indie Rock', 'Coffee'],
      isVerified: true,
    );

    final candidateSmoker = UserModel(
      id: 'cand_smoker',
      name: 'Priya',
      email: 'priya@situationship.com',
      age: 23,
      gender: 'female',
      interestedIn: const ['male'],
      relationshipIntent: 'serious',
      bio: 'Social smoker, party enthusiast.',
      interests: const ['Clubbing', 'Parties'],
    );

    final candidateIncompatibleGender = UserModel(
      id: 'cand_male',
      name: 'Arjun',
      email: 'arjun@situationship.com',
      age: 25,
      gender: 'male',
      interestedIn: const ['female'],
      bio: 'Artistic coder and indie fan.',
      interests: const ['Indie Rock'],
    );

    test('Ranks semantic match higher and rejects dealbreaker and wrong gender', () {
      final intent = OnDeviceNLUEngine.parse(
        "Find me an artistic girl who loves indie rock and photography, doesn't smoke, and wants something serious",
      );

      final matches = matcher.findMatches(
        currentUser: currentUser,
        candidates: [candidateArtistic, candidateSmoker, candidateIncompatibleGender],
        intent: intent,
      );

      // Candidate Maya must be the top recommendation
      expect(matches.isNotEmpty, isTrue);
      expect(matches.first.candidate.id, equals('cand_artistic'));
      expect(matches.first.compatibilityScore, greaterThanOrEqualTo(80));

      // Smoker candidate must be filtered out by dealbreaker
      final matchedIds = matches.map((m) => m.candidate.id).toList();
      expect(matchedIds, isNot(contains('cand_smoker')));

      // Incompatible gender must be strictly rejected by HeartQueue
      expect(matchedIds, isNot(contains('cand_male')));
    });

    test('Generates detailed match rationale and conversational icebreaker', () {
      final intent = OnDeviceNLUEngine.parse("Artistic indie music lover for serious relationship");
      final rationale = MatchRationaleGenerator.generate(
        candidate: candidateArtistic,
        userIntent: intent,
        matchedDimensionIds: const ['indie', 'artistic', 'intent_serious'],
        compatibilityScore: 94,
      );

      expect(rationale.headline, contains('94%'));
      expect(rationale.detailedExplanation, contains('Maya'));
      expect(rationale.detailedExplanation.toLowerCase(), contains('indie'));
      expect(rationale.icebreakerSuggestion.isNotEmpty, isTrue);
    });

    test('Handles generic "matches me" query by comparing candidate with current user profile', () {
      final intent = OnDeviceNLUEngine.parse("Can you find me a profile that matches me");

      // Maya shares Indie Rock, Coffee, and Serious intent with currentUser (Rohan)
      final matches = matcher.findMatches(
        currentUser: currentUser,
        candidates: [candidateArtistic, candidateSmoker],
        intent: intent,
      );

      expect(matches.isNotEmpty, isTrue);
      expect(matches.first.candidate.id, equals('cand_artistic'));
      expect(matches.first.compatibilityScore, greaterThanOrEqualTo(75));
    });

    test('Gracefully finds matches using conversational relaxation when profiles are not discoverable', () {
      final unconfiguredCandidate = UserModel(
        id: 'cand_unconfigured',
        name: 'Sara',
        email: 'sara@test.com', // test account email
        age: 23,
        gender: 'female',
        isDiscoverable: false, // undiscoverable
        interests: const ['Art', 'Design'],
      );

      final intent = OnDeviceNLUEngine.parse("Artistic & creative");
      final matches = matcher.findMatches(
        currentUser: currentUser,
        candidates: [unconfiguredCandidate],
        intent: intent,
      );

      // Relaxed conversational fallback should still recommend candidate Sara
      expect(matches.isNotEmpty, isTrue);
      expect(matches.first.candidate.id, equals('cand_unconfigured'));
    });

    test('Paginates properly by excluding already shown profiles', () {
      final cand1 = candidateArtistic;
      final cand2 = UserModel(
        id: 'cand_2',
        name: 'Chloe',
        email: 'chloe@situationship.com',
        age: 24,
        gender: 'female',
        interests: const ['Photography', 'Coffee'],
      );

      final intent = OnDeviceNLUEngine.parse("Artistic & creative");

      // Turn 1: Cand 1 is shown
      final turn1 = matcher.findMatches(
        currentUser: currentUser,
        candidates: [cand1, cand2],
        intent: intent,
        limit: 1,
      );
      expect(turn1.first.candidate.id, equals('cand_artistic'));

      // Turn 2: Cand 1 is excluded because it was already shown -> Cand 2 is returned
      final turn2 = matcher.findMatches(
        currentUser: currentUser,
        candidates: [cand1, cand2],
        intent: intent,
        excludedIds: {turn1.first.candidate.id},
        limit: 1,
      );
      expect(turn2.first.candidate.id, equals('cand_2'));
    });
  });
}
