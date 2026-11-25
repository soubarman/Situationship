import 'package:flutter_test/flutter_test.dart';
import 'package:situationship/core/ai/on_device_nlu_engine.dart';
import 'package:situationship/core/ai/conversational_intent.dart';
import 'package:situationship/core/ai/conversation_context_manager.dart';
import 'package:situationship/core/ai/conversational_dialogue_engine.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/ai/match_rationale_generator.dart';
import 'package:situationship/core/models/user_model.dart';

void main() {
  group('Intelligent Conversational AI: Multi-Intent & Context Architecture', () {
    final currentUser = UserModel(
      id: 'usr_rohan',
      name: 'Rohan',
      email: 'rohan@situationship.com',
      age: 24,
      gender: 'male',
      interestedIn: const ['female'],
      relationshipIntent: 'serious',
      interests: const ['Music', 'Coffee'],
    );

    final candidateMaya = UserModel(
      id: 'cand_maya',
      name: 'Maya',
      email: 'maya@situationship.com',
      age: 23,
      gender: 'female',
      interestedIn: const ['male'],
      relationshipIntent: 'serious',
      bio: 'Analog photography addict and indie vinyl collector.',
      interests: const ['Photography', 'Indie Rock', 'Coffee'],
      isVerified: true,
    );

    final candidatePriya = UserModel(
      id: 'cand_priya',
      name: 'Priya',
      email: 'priya@situationship.com',
      age: 24,
      gender: 'female',
      interestedIn: const ['male'],
      relationshipIntent: 'casual',
      bio: 'World traveler and food explorer. Road trips every weekend.',
      interests: const ['Travel', 'Food', 'Road Trips'],
      isVerified: false,
    );

    final candidateSmoker = UserModel(
      id: 'cand_smoker',
      name: 'Zara',
      email: 'zara@situationship.com',
      age: 22,
      gender: 'female',
      interestedIn: const ['male'],
      bio: 'Heavy smoker, party enthusiast.',
      interests: const ['Clubbing'],
    );

    final allCandidates = [candidateMaya, candidatePriya, candidateSmoker];

    // ── Scenario A: Casual Conversation ──────────────────────────────────────
    test('Scenario A: Casual conversation does NOT force profile recommendations', () {
      final resBored = OnDeviceNLUEngine.parse("I'm bored.");
      expect(resBored.conversationalIntent, equals(ConversationalIntent.emotionalSupport));

      final reply = ConversationalDialogueEngine.generateResponse(
        classification: resBored.classification!,
        contextManager: ConversationContextManager(),
        currentUser: currentUser,
      );
      expect(reply.isNotEmpty, isTrue);
      expect(reply.toLowerCase(), contains('curiosity'));

      final resGreeting = OnDeviceNLUEngine.parse("Hello, how are you today?");
      expect(resGreeting.conversationalIntent, equals(ConversationalIntent.casualChat));

      final resJoke = OnDeviceNLUEngine.parse("Tell me a joke");
      expect(resJoke.conversationalIntent, equals(ConversationalIntent.casualChat));
      final jokeReply = ConversationalDialogueEngine.generateResponse(
        classification: resJoke.classification!,
        contextManager: ConversationContextManager(),
        currentUser: currentUser,
      );
      expect(jokeReply.isNotEmpty, isTrue);
    });

    // ── Scenario B: Emotional Conversation ───────────────────────────────────
    test('Scenario B: Emotional messages receive empathetic support without profiles', () {
      final resGhosted = OnDeviceNLUEngine.parse("I got ghosted today and it sucks");
      expect(resGhosted.conversationalIntent, equals(ConversationalIntent.emotionalSupport));

      final resLonely = OnDeviceNLUEngine.parse("Feeling lonely lately");
      expect(resLonely.conversationalIntent, equals(ConversationalIntent.emotionalSupport));

      final reply = ConversationalDialogueEngine.generateResponse(
        classification: resGhosted.classification!,
        contextManager: ConversationContextManager(),
        currentUser: currentUser,
      );
      expect(reply.toLowerCase(), contains('ghosting'));
      expect(reply.toLowerCase(), contains('worth'));
    });

    // ── Scenario C: General Knowledge & Dating Advice ────────────────────────
    test('Scenario C: Dating advice questions are answered thoughtfully without profiles', () {
      final resDate = OnDeviceNLUEngine.parse("What's a good first date idea?");
      expect(resDate.conversationalIntent, equals(ConversationalIntent.datingAdvice));

      final resOpener = OnDeviceNLUEngine.parse("How to break the ice with someone new?");
      expect(resOpener.conversationalIntent, equals(ConversationalIntent.datingAdvice));

      final reply = ConversationalDialogueEngine.generateResponse(
        classification: resDate.classification!,
        contextManager: ConversationContextManager(),
        currentUser: currentUser,
      );
      expect(reply.toLowerCase(), contains('first date'));
      expect(reply.toLowerCase(), contains('coffee'));
    });

    // ── Scenario D: Profile Discovery ────────────────────────────────────────
    test('Scenario D: Profile discovery requests trigger real candidate matching', () {
      final res = OnDeviceNLUEngine.parse("Find someone who likes indie rock and photography");
      expect(res.conversationalIntent, equals(ConversationalIntent.profileDiscovery));
      expect(res.classification!.entities.interests, contains('music'));
      expect(res.classification!.entities.interests, contains('photography'));

      final matcher = VibeMatrixMatcher();
      final matches = matcher.findMatches(
        currentUser: currentUser,
        candidates: allCandidates,
        intent: res,
      );

      expect(matches.isNotEmpty, isTrue);
      expect(matches.first.candidate.name, equals('Maya'));
    });

    // ── Scenario E: Multiple Preferences In One Request ──────────────────────
    test('Scenario E: Correctly extracts multiple preferences, dealbreakers and intent', () {
      final res = OnDeviceNLUEngine.parse(
        "I want an adventurous girl who loves road trips, doesn't smoke, and is seeking a casual situationship",
      );

      expect(res.conversationalIntent, equals(ConversationalIntent.profileDiscovery));
      expect(res.genderHint, equals('female'));
      expect(res.targetRelationshipIntent, equals('casual'));
      expect(res.dealbreakers, contains('smoking'));
      expect(res.classification!.entities.personalityTraits, contains('adventurous'));

      final matcher = VibeMatrixMatcher();
      final matches = matcher.findMatches(
        currentUser: currentUser,
        candidates: allCandidates,
        intent: res,
      );

      expect(matches.any((m) => m.candidate.name == 'Zara'), isFalse); // Smoker excluded
      expect(matches.any((m) => m.candidate.name == 'Priya'), isTrue); // Adventurous traveler included
    });

    // ── Scenario F: Follow-up Preference Refinement Across Turns ──────────────
    test('Scenario F: Multi-turn context manager accumulates preferences progressively', () {
      final manager = ConversationContextManager();

      // Turn 1: "I like people who enjoy travelling"
      final turn1 = OnDeviceNLUEngine.parse("I like people who enjoy travelling");
      manager.recordTurn(
        userUtterance: "I like people who enjoy travelling",
        classification: turn1.classification!,
        assistantReply: "Travel lovers bring great energy! Anyone specific?",
      );
      expect(manager.criteria.interests, contains('travel'));

      // Turn 2: "And someone who loves photography"
      final turn2 = OnDeviceNLUEngine.parse(
        "And someone who loves photography",
        hasActiveProfileContext: true,
      );
      expect(turn2.conversationalIntent, equals(ConversationalIntent.preferenceRefinement));
      manager.recordTurn(
        userUtterance: "And someone who loves photography",
        classification: turn2.classification!,
        assistantReply: "Added photography to your radar.",
      );
      expect(manager.criteria.interests, contains('travel'));
      expect(manager.criteria.interests, contains('photography'));

      // Turn 3: "Someone more adventurous"
      final turn3 = OnDeviceNLUEngine.parse(
        "Someone more adventurous",
        hasActiveProfileContext: true,
      );
      expect(turn3.conversationalIntent, equals(ConversationalIntent.preferenceRefinement));
      manager.recordTurn(
        userUtterance: "Someone more adventurous",
        classification: turn3.classification!,
        assistantReply: "Looking for adventurous spirits.",
      );
      expect(manager.criteria.personalityTraits, contains('adventurous'));
      expect(manager.criteria.interests, contains('travel'));
      expect(manager.criteria.interests, contains('photography'));
    });

    // ── Scenario G: Reference to Previously Recommended Profile ──────────────
    test('Scenario G: Resolves ordinal and name references to previous recommendations', () {
      final manager = ConversationContextManager();

      final mockMatchMaya = CupidMatchResult(
        candidate: candidateMaya,
        compatibilityScore: 94,
        highlightTraits: const ['Analog Photography', 'Indie Rock'],
        rationale: const MatchRationale(
          headline: '94% Vibe Match',
          detailedExplanation: 'Maya shares your love for analog photography and indie music.',
          icebreakerSuggestion: 'Ask Maya about her favorite 35mm film stock!',
        ),
        rawCosine: 0.92,
      );
      final mockMatchPriya = CupidMatchResult(
        candidate: candidatePriya,
        compatibilityScore: 88,
        highlightTraits: const ['Traveler', 'Spontaneous'],
        rationale: const MatchRationale(
          headline: '88% Vibe Match',
          detailedExplanation: 'Priya matches your energy for spontaneous road trips.',
          icebreakerSuggestion: 'Ask Priya about her last road trip destination!',
        ),
        rawCosine: 0.85,
      );

      // Record recommendation turn
      final discTurn = OnDeviceNLUEngine.parse("Find someone creative");
      manager.recordTurn(
        userUtterance: "Find someone creative",
        classification: discTurn.classification!,
        assistantReply: "Here are your matches:",
        newMatches: [mockMatchMaya, mockMatchPriya],
      );

      expect(manager.hasActiveProfileContext, isTrue);

      // Query about "the first one"
      final turnOrdinal = OnDeviceNLUEngine.parse(
        "Tell me more about the first one",
        hasActiveProfileContext: true,
        activeProfileNames: manager.activeProfileNames,
      );
      expect(turnOrdinal.conversationalIntent, equals(ConversationalIntent.profileInquiry));
      final resolvedFirst = manager.resolveProfileReference(turnOrdinal.classification!.entities);
      expect(resolvedFirst?.candidate.name, equals('Maya'));

      // Query by name "Tell me about Priya"
      final turnNamed = OnDeviceNLUEngine.parse(
        "Tell me about Priya",
        hasActiveProfileContext: true,
        activeProfileNames: manager.activeProfileNames,
      );
      expect(turnNamed.conversationalIntent, equals(ConversationalIntent.profileInquiry));
      final resolvedPriya = manager.resolveProfileReference(turnNamed.classification!.entities);
      expect(resolvedPriya?.candidate.name, equals('Priya'));
    });

    // ── Scenario H: Unrelated Questions During Profile Discovery ─────────────
    test('Scenario H: Answering app questions mid-discovery does not wipe criteria or spam profiles', () {
      final manager = ConversationContextManager();

      // Start discovery
      final turnDisc = OnDeviceNLUEngine.parse("Find music lovers");
      manager.recordTurn(
        userUtterance: "Find music lovers",
        classification: turnDisc.classification!,
        assistantReply: "Looking for music fans...",
      );
      expect(manager.criteria.interests, contains('music'));

      // Ask about Coins
      final turnCoins = OnDeviceNLUEngine.parse("How do coins work?");
      expect(turnCoins.conversationalIntent, equals(ConversationalIntent.appFeatures));

      final reply = ConversationalDialogueEngine.generateResponse(
        classification: turnCoins.classification!,
        contextManager: manager,
        currentUser: currentUser,
      );
      expect(reply.toLowerCase(), contains('coins'));
      expect(reply.toLowerCase(), contains('spotlight'));

      // Verify criteria preserved
      expect(manager.criteria.interests, contains('music'));
    });

    // ── Scenario I: Misspelled and Informal Messages ─────────────────────────
    test('Scenario I: Handles abbreviations and common misspellings gracefully', () {
      final res1 = OnDeviceNLUEngine.parse("im so tierd of dating");
      expect(res1.conversationalIntent, equals(ConversationalIntent.emotionalSupport));

      final res2 = OnDeviceNLUEngine.parse("find me a gril who likes travellin");
      expect(res2.conversationalIntent, equals(ConversationalIntent.profileDiscovery));
      expect(res2.genderHint, equals('female'));
      expect(res2.classification!.entities.interests, contains('travel'));
    });

    // ── Scenario J: Ambiguous Messages ───────────────────────────────────────
    test('Scenario J: Ambiguous short replies ask gentle clarification rather than guessing', () {
      final resHm = OnDeviceNLUEngine.parse("hm");
      expect(resHm.conversationalIntent, equals(ConversationalIntent.clarification));

      final reply = ConversationalDialogueEngine.generateResponse(
        classification: resHm.classification!,
        contextManager: ConversationContextManager(),
        currentUser: currentUser,
      );
      expect(reply.isNotEmpty, isTrue);
    });

    // ── Scenario K: Repeated Messages ────────────────────────────────────────
    test('Scenario K: Responds dynamically without rigid repetitive scripts', () {
      final res1 = OnDeviceNLUEngine.parse("hello");
      final reply1 = ConversationalDialogueEngine.generateResponse(
        classification: res1.classification!,
        contextManager: ConversationContextManager(),
        currentUser: currentUser,
      );
      expect(reply1.isNotEmpty, isTrue);
    });

    // ── Scenario L: Conversation Reset ───────────────────────────────────────
    test('Scenario L: Reset clears criteria and resets context completely', () {
      final manager = ConversationContextManager();
      final turnDisc = OnDeviceNLUEngine.parse("Find music lovers");
      manager.recordTurn(
        userUtterance: "Find music lovers",
        classification: turnDisc.classification!,
        assistantReply: "Found some",
      );
      expect(manager.criteria.isEmpty, isFalse);

      final resetIntent = OnDeviceNLUEngine.parse("start over");
      expect(resetIntent.conversationalIntent, equals(ConversationalIntent.conversationReset));

      manager.reset();
      expect(manager.criteria.isEmpty, isTrue);
      expect(manager.hasActiveProfileContext, isFalse);
    });

    // ── Scenario M: Unsupported Requests ─────────────────────────────────────
    test('Scenario M: Non-dating/coding requests are politely declined as out of domain', () {
      final resCode = OnDeviceNLUEngine.parse("Write a python script for quicksort");
      expect(resCode.conversationalIntent, equals(ConversationalIntent.unsupported));

      final reply = ConversationalDialogueEngine.generateResponse(
        classification: resCode.classification!,
        contextManager: ConversationContextManager(),
        currentUser: currentUser,
      );
      expect(reply.toLowerCase(), contains('dating'));
      expect(reply.toLowerCase(), contains('coding'));
    });
  });
}
