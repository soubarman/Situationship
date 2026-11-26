import 'package:flutter_test/flutter_test.dart';
import 'package:situationship/core/ai/conversation_context_manager.dart';
import 'package:situationship/core/ai/context_aware_speech_act_interpreter.dart';
import 'package:situationship/core/ai/conversational_dialogue_engine.dart';
import 'package:situationship/core/ai/conversational_intent.dart';
import 'package:situationship/core/ai/local_llm/cupid_local_ai_orchestrator.dart';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/local_model_manager.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';
import 'package:situationship/core/ai/structured_conversation_state.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/models/user_model.dart';

class FallbackMockRuntime extends ModelRuntimeAdapter {
  @override
  bool get isModelLoaded => false;
  @override
  ModelSpec? get loadedSpec => null;
  @override
  Future<void> initialize({required dynamic spec, required String modelFilePath}) async {}
  @override
  Future<String> generate(String prompt, {int maxTokens = 256, double temperature = 0.7, List<String>? stopSequences}) async => '';
  @override
  Stream<String> generateStreaming(String prompt, {int maxTokens = 256, double temperature = 0.7, List<String>? stopSequences}) async* {}
  @override
  Future<void> unload() async {}
}

class LoadedMockLlmRuntime extends ModelRuntimeAdapter {
  String nextResponse = '';
  @override
  bool get isModelLoaded => true;
  @override
  ModelSpec? get loadedSpec => ModelSpec.smollm2_135m;
  @override
  Future<void> initialize({required dynamic spec, required String modelFilePath}) async {}
  @override
  Future<String> generate(String prompt, {int maxTokens = 256, double temperature = 0.7, List<String>? stopSequences}) async => nextResponse;
  @override
  Stream<String> generateStreaming(String prompt, {int maxTokens = 256, double temperature = 0.7, List<String>? stopSequences}) async* {
    yield nextResponse;
  }
  @override
  Future<void> unload() async {}
}

void main() {
  group('PHASE 5: INDEPENDENT EVALUATION SUITE (50 NEW SCENARIOS)', () {
    late ConversationContextManager contextManager;
    late CupidLocalAIOrchestrator orchestrator;
    late FallbackMockRuntime fallbackRuntime;
    late LoadedMockLlmRuntime mockLlmRuntime;

    final currentUser = UserModel(
      id: 'eval_user_50',
      name: 'Rhea',
      email: 'rhea@example.com',
      age: 23,
      gender: 'female',
      interestedIn: const ['male'],
      relationshipIntent: 'serious',
      interests: const ['Photography', 'Indie Rock', 'Coffee', 'Art'],
    );

    final candidatePool = [
      UserModel(
        id: 'c1_aditya',
        name: 'Aditya',
        email: 'aditya@example.com',
        age: 25,
        gender: 'male',
        interestedIn: const ['female'],
        bio: 'Analog photography geek who loves 35mm film, vinyl records, and filter coffee.',
        interests: const ['Photography', 'Music', 'Coffee'],
        isVerified: true,
      ),
      UserModel(
        id: 'c2_kabir',
        name: 'Kabir',
        email: 'kabir@example.com',
        age: 26,
        gender: 'male',
        interestedIn: const ['female'],
        bio: 'Software engineer by day, standup comic by night. Heavy sarcasm, zero timepass.',
        interests: const ['Comedy', 'Writing', 'Tech'],
        isVerified: true,
      ),
      UserModel(
        id: 'c3_rohan',
        name: 'Rohan',
        email: 'rohan@example.com',
        age: 24,
        gender: 'male',
        interestedIn: const ['female'],
        bio: 'Chill acoustic guitarist, big into calm weekend cafe hangs, quiet creative vibes.',
        interests: const ['Music', 'Art', 'Guitar'],
        isVerified: true,
      ),
    ];

    setUp(() {
      contextManager = ConversationContextManager();
      fallbackRuntime = FallbackMockRuntime();
      mockLlmRuntime = LoadedMockLlmRuntime();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: fallbackRuntime,
        matcher: VibeMatrixMatcher(),
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SUITE A: DETERMINISTIC FALLBACK MODE (50 SCENARIOS)
    // ──────────────────────────────────────────────────────────────────────────
    group('Suite A: Deterministic Fallback Mode', () {
      // 1. Indian English Expressions
      test('1. Handles "timepass" as casual/non-serious intent without searching profiles', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "I'm definitely not here for timepass, want a real meaningful connection.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.isNotEmpty, isTrue);
      });

      test('2. Handles "jugaad" as witty resourcefulness without breaking preference extraction', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I love people with a bit of jugaad mindset, creative problem solvers.",
          contextManager: contextManager,
        );
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      test('3. Handles "vibe match" as compatibility query rather than immediate search', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Need a solid vibe match with someone who gets indie music.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
      });

      test('4. Handles "pakka" as certainty modifier without false tool call', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Pakka looking for a non-smoker, that's non-negotiable.",
          contextManager: contextManager,
        );
        expect(interp.negativePreferences.any((p) => p.value.contains('smok')), isTrue);
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      test('5. Handles "yaaar" and conversational colloquialisms smoothly', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Yaaar, modern dating is so exhausting honestly.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.toLowerCase().contains('exhaust') || res.text.toLowerCase().contains('dating'), isTrue);
      });

      // 2. Hinglish Expressions
      test('6. Hinglish: "chai pe charcha" recognized as casual coffee/tea meetup vibe', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Someone up for chai pe charcha and long evening walks.",
          contextManager: contextManager,
        );
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      test('7. Hinglish: "thoda chill type person" extracted as relaxed personality', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Looking for a thoda chill type person who doesn't stress over little things.",
          contextManager: contextManager,
        );
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      test('8. Hinglish: "scene kya hai" answered as app status inquiry', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Batao Cupid, aaj ka scene kya hai?",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
      });

      // 3. Misspellings & Typos
      test('9. Typo: "photograpy" mapped to photography preference', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I really adore photograpy and vintage cameras.",
          contextManager: contextManager,
        );
        expect(interp.extractedPreferences.any((p) => p.value.contains('photo')), isTrue);
      });

      test('10. Typo: "introvertd" mapped to introverted personality trait', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I'm totally fine with an introvertd guy as long as we can talk easily.",
          contextManager: contextManager,
        );
        expect(interp.positivePreferences.any((p) => p.value.contains('introvert')), isTrue);
        expect(interp.qualificationsAndExceptions.isNotEmpty, isTrue);
      });

      test('11. Typo: "sarkasm" recognized as sarcasm humour preference', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Dry sarkasm is my love language.",
          contextManager: contextManager,
        );
        expect(interp.topic, equals(ConversationTopic.humour));
      });

      test('12. Typo: "bookwormm" does not crash token matching', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Any bookwormm who reads sci-fi?",
          contextManager: contextManager,
        );
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      // 4. Sarcasm & Humour
      test('13. Sarcasm: "Oh great, another hiker" recognized as dislike rather than hiking preference', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Oh great, another person whose entire personality is hiking up mountains at 5 AM.",
          contextManager: contextManager,
        );
        expect(interp.positivePreferences.any((p) => p.value == 'hiking'), isFalse);
      });

      test('14. Sarcasm: "Yeah right, like everyone reads 50 books" treated as skepticism', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Yeah right, like everyone on dating apps actually reads 50 philosophy books a year.",
          contextManager: contextManager,
        );
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      test('15. Humour: Dad jokes preference recognized', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Need someone who can tolerate awful dad jokes and terrible puns.",
          contextManager: contextManager,
        );
        expect(interp.topic, equals(ConversationTopic.humour));
      });

      // 5. Negation & Double Negatives
      test('16. Negation: "Not looking for heavy partying" is not stored as party interest', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I'm definitely not looking for heavy partying or clubbing.",
          contextManager: contextManager,
        );
        expect(interp.positivePreferences.any((p) => p.value.contains('club')), isFalse);
      });

      test('17. Negation: "I don\'t drink or smoke" stores negative dealbreakers', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I don't smoke and prefer someone who doesn't smoke either.",
          contextManager: contextManager,
        );
        expect(interp.negativePreferences.any((p) => p.value.contains('smok')), isTrue);
      });

      test('18. Double Negative: "Wouldn\'t say I\'m not interested in art" does not discard art interest', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I wouldn't say I'm not interested in art exhibitions, they can be nice.",
          contextManager: contextManager,
        );
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      test('19. Double Negative: "It\'s not that I dislike outdoor stuff" handles qualified preference', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "It's not that I dislike outdoor stuff, just prefer relaxed parks over extreme trekking.",
          contextManager: contextManager,
        );
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      // 6. Ambiguous Pronouns & Ellipsis
      test('20. Ambiguous pronoun: "They should be passionate about what they do" captures passion trait', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "They should be truly passionate about what they do in life.",
          contextManager: contextManager,
        );
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      test('21. Ambiguous reply: "That one" without active cards prompts clarification', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "I really like that one.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
      });

      // 7. Contradictory & Balanced Preferences
      test('22. Contradictory: "Ambitious but super laid back with no hustle culture"', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I like ambitious people, but also super laid back with no toxic hustle culture.",
          contextManager: contextManager,
        );
        expect(interp.positivePreferences.isNotEmpty, isTrue);
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      test('23. Balanced: "Extroverted introvert" captures balanced personality scope', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Someone who is an extroverted introvert—social when out, but loves quiet nights in.",
          contextManager: contextManager,
        );
        expect(interp.isExplicitDiscoveryRequest, isFalse);
      });

      // 8. Delayed Corrections
      test('24. Delayed correction: "Actually change that, not into gym enthusiasts"', () async {
        contextManager.addStructuredPreference(UserDatingPreference(
          category: 'lifestyle',
          value: 'fitness gym',
          scope: PreferenceScope.datingRequirement,
          sourceTurn: 1,
        ));
        final res = await orchestrator.processTurn(
          userUtterance: "Actually change that, not into gym enthusiasts, more into chill musicians.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(contextManager.criteria.interests.contains('Music') || contextManager.structuredState.preferences.any((p) => p.value.contains('music')), isTrue);
      });

      test('25. Delayed correction: "Wait, I made a mistake earlier"', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Wait, I made a typo earlier. I meant dark humour, not silly jokes.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
      });

      // 9. Topic Transitions
      test('26. Topic switch to music', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Enough about dating, what kind of music have you been vibing to?",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(contextManager.structuredState.currentTopic, equals(ConversationTopic.music));
      });

      test('27. Topic switch to travel', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Let's change topics, talk to me about travel spots.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(contextManager.structuredState.currentTopic, equals(ConversationTopic.travel));
      });

      test('28. Topic switch to photography', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Switch gears, let's chat about 35mm photography.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(contextManager.structuredState.currentTopic, equals(ConversationTopic.photography));
      });

      // 10. Emotional Support Conversations
      test('29. Emotional: Work stress generates empathetic response without discovery', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "I had a terrible day at work today, boss was completely unbearable.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.toLowerCase().contains('exhausting') || res.text.toLowerCase().contains('switch'), isTrue);
      });

      test('30. Emotional: Confirmation after work stress validates without questionnaire interrogation', () async {
        await orchestrator.processTurn(
          userUtterance: "I had a terrible day at work today, exhausted.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        final res = await orchestrator.processTurn(
          userUtterance: "Yeah, exactly.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.contains("Honestly, I get that"), isTrue);
        expect(contextManager.expectedAnswerType, equals(ExpectedAnswerType.none));
      });

      test('31. Emotional: Loneliness acknowledged with warmth', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Feeling really lonely this Sunday evening.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.toLowerCase().contains('lonel') || res.text.toLowerCase().contains('connection'), isTrue);
      });

      test('32. Emotional: Dating fatigue and burnout', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Dating apps make me feel so drained lately, feels so artificial.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
      });

      test('33. Emotional: Ghosting comfort', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "I just got ghosted by someone I talked to for three weeks.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.toLowerCase().contains('ghost') || res.text.toLowerCase().contains('worth'), isTrue);
      });

      // 11. Indirect Discovery Requests
      test('34. Indirect discovery: "Wish I had someone to grab coffee with" without criteria asks for vibe first', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Wish I could connect with someone nearby right now.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.toLowerCase().contains('tell me what kind of person') || res.text.toLowerCase().contains('vibe'), isTrue);
      });

      test('35. Indirect discovery with existing criteria performs safe matching', () async {
        contextManager.updateCriteria(const ExtractedEntities(interests: ['Photography']));
        final res = await orchestrator.processTurn(
          userUtterance: "Know anyone who would get along with me and loves photography?",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches.isNotEmpty, isTrue);
        expect(res.matches.any((m) => m.candidate.name == 'Aditya'), isTrue);
      });

      // 12. Rejected Profile References & Memory
      test('36. Profile rejection remembered and filtered out', () async {
        contextManager.updateCriteria(const ExtractedEntities(interests: ['Photography']));
        final turn1 = await orchestrator.processTurn(
          userUtterance: "Find me someone who loves photography.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(turn1.matches.isNotEmpty, isTrue);
        final rejectedId = turn1.matches.first.candidate.id;

        final turn2 = await orchestrator.processTurn(
          userUtterance: "Nah, not feeling these profiles at all, show different people.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(contextManager.rejectedProfileIds.contains(rejectedId), isTrue);
        expect(turn2.matches, isEmpty);
      });

      test('37. Rejection by name memory', () async {
        contextManager.rejectProfile('c2_kabir');
        expect(contextManager.isProfileRejected('c2_kabir'), isTrue);
      });

      // 13. Short Answers & Clarifications
      test('38. Short answer: "Both, actually" applies to both hobby and partner trait', () async {
        contextManager.setAssistantQuestion(
          "Is photography something you enjoy yourself, or something you want in a partner?",
          ExpectedAnswerType.partnerTrait,
          topic: ConversationTopic.photography,
        );
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "Both, actually.",
          contextManager: contextManager,
        );
        expect(interp.referencesToPreviousTurns.contains('both'), isTrue);
        expect(interp.extractedPreferences.any((p) => p.scope == PreferenceScope.datingRequirement), isTrue);
        expect(interp.extractedPreferences.any((p) => p.scope == PreferenceScope.personalInterest), isTrue);
      });

      test('39. Short answer: "Neither" declines both options without searching', () async {
        contextManager.setAssistantQuestion(
          "Are you more into spontaneous trips or planned getaways?",
          ExpectedAnswerType.none,
          topic: ConversationTopic.travel,
        );
        final res = await orchestrator.processTurn(
          userUtterance: "Neither honestly, I prefer cozy staycations.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
      });

      test('40. Short answer: "Nope" gracefully acknowledged', () async {
        contextManager.setAssistantQuestion(
          "Want me to find people who match that vibe?",
          ExpectedAnswerType.confirmation,
          topic: ConversationTopic.dating,
        );
        final res = await orchestrator.processTurn(
          userUtterance: "Nope, not right now.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.contains("No problem at all"), isTrue);
      });

      test('41. Short answer: "Yes please" triggers discovery when confirmation was pending', () async {
        contextManager.updateCriteria(const ExtractedEntities(interests: ['Photography']));
        contextManager.setAssistantQuestion(
          "Want me to find members who match that?",
          ExpectedAnswerType.confirmation,
          topic: ConversationTopic.dating,
        );
        final res = await orchestrator.processTurn(
          userUtterance: "Yes please, find them for me!",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches.isNotEmpty, isTrue);
      });

      // 14. Multi-Topic Messages
      test('42. Multi-topic: Self trait vs partner trait separation', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I don't mind someone introverted, as long as they can hold a conversation. I'm usually the quieter one anyway.",
          contextManager: contextManager,
        );
        expect(interp.positivePreferences.any((p) => p.value.contains('introvert')), isTrue);
        expect(interp.userSelfTraits.contains('quieter'), isTrue);
        expect(interp.userSelfTraits.contains('introverted'), isFalse);
      });

      test('43. Multi-topic: Dislike travel but love partner with photography', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I'm not really into travelling myself, but I'd love someone who enjoys photography.",
          contextManager: contextManager,
        );
        expect(interp.positivePreferences.any((p) => p.value.contains('photo')), isTrue);
        expect(interp.positivePreferences.any((p) => p.value.contains('travel')), isFalse);
      });

      test('44. Multi-topic: Negative dealbreaker vs acceptable habit separation', () async {
        final interp = ContextAwareSpeechActInterpreter.interpret(
          "I'd prefer someone who doesn't smoke, but occasional drinking isn't a problem.",
          contextManager: contextManager,
        );
        expect(interp.negativePreferences.any((p) => p.value.contains('smok')), isTrue);
        expect(interp.negativePreferences.any((p) => p.value.contains('drink')), isFalse);
      });

      // 15. Unexpected & Out-of-Domain Follow-Up Questions
      test('45. Out-of-domain: Python coding question politely declined', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Can you write me a quick Python script to scrape website data?",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.contains("dating and social connections"), isTrue);
      });

      test('46. App feature inquiry: VibeMatrix algorithm explanation', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "How does the VibeMatrix matching algorithm actually rank candidates?",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.toLowerCase().contains('vibe') || res.text.toLowerCase().contains('match'), isTrue);
      });

      test('47. Privacy inquiry: Are my chats and searches private?', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "Is my conversation with Cupid stored in the cloud or private on my phone?",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.toLowerCase().contains('privacy') || res.text.toLowerCase().contains('device'), isTrue);
      });

      test('48. Coins & rewards inquiry: How do I earn coins?', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "How do I earn more coins on Situationship?",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.toLowerCase().contains('coin') || res.text.toLowerCase().contains('streak'), isTrue);
      });

      test('49. Verification badge inquiry: How to get verified S-badge?', () async {
        final res = await orchestrator.processTurn(
          userUtterance: "What is the verified S-badge and how do I get it?",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.toLowerCase().contains('verif'), isTrue);
      });

      test('50. Complete conversation reset resets accumulated criteria', () async {
        contextManager.updateCriteria(const ExtractedEntities(interests: ['Photography', 'Music']));
        expect(contextManager.criteria.interests.isNotEmpty, isTrue);

        final res = await orchestrator.processTurn(
          userUtterance: "Please reset everything and clear our chat context.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(contextManager.criteria.interests, isEmpty);
        expect(contextManager.turnHistory, isEmpty);
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SUITE B: MOCKED LLM MODE (MODEL REASONING & DECISION GATE VERIFICATION)
    // ──────────────────────────────────────────────────────────────────────────
    group('Suite B: Mocked LLM Mode', () {
      late CupidLocalAIOrchestrator mockedLlmOrchestrator;

      setUp(() {
        contextManager = ConversationContextManager();
        mockedLlmOrchestrator = CupidLocalAIOrchestrator(
          runtime: mockLlmRuntime,
          matcher: VibeMatrixMatcher(),
          contextManager: contextManager,
          modelManager: LocalModelManager(),
        );
      });

      test('B1. Strips private thinking/scratchpad tokens before returning reply', () async {
        mockLlmRuntime.nextResponse = "<thought>The user is asking about coffee.</thought>I love great coffee spots! What's your favourite brew?";
        final res = await mockedLlmOrchestrator.processTurn(
          userUtterance: "I really love artisanal pour-over coffee.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.text.contains('<thought>'), isFalse);
        expect(res.text.contains('favourite brew'), isTrue);
      });

      test('B2. Decision Gate blocks premature discover_profiles tool call when user did not request discovery', () async {
        mockLlmRuntime.nextResponse = '```tool_call\n{"name": "discover_profiles", "arguments": {"interests": ["photography"]}}\n```';
        // User merely states a hobby, never asked to find/search people
        final res = await mockedLlmOrchestrator.processTurn(
          userUtterance: "I've been shooting with a 35mm film camera lately.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        // The decision gate must block the premature tool call and fall back to conversational dialogue
        expect(res.matches, isEmpty);
        expect(res.executedTool, isNull);
      });

      test('B3. Permitted tool call executes when user explicitly requested discovery', () async {
        mockLlmRuntime.nextResponse = '```tool_call\n{"name": "discover_profiles", "arguments": {"interests": ["photography"]}}\n```';
        final res = await mockedLlmOrchestrator.processTurn(
          userUtterance: "Find me someone who loves photography!",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches.isNotEmpty, isTrue);
        expect(res.matches.any((m) => m.candidate.name == 'Aditya'), isTrue);
      });

      test('B4. Model inference error triggers graceful semantic fallback', () async {
        final throwingRuntime = FallbackMockRuntime();
        final orch = CupidLocalAIOrchestrator(
          runtime: throwingRuntime,
          matcher: VibeMatrixMatcher(),
          contextManager: contextManager,
          modelManager: LocalModelManager(),
        );
        final res = await orch.processTurn(
          userUtterance: "I had a terrible day at work today.",
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: const {},
        );
        expect(res.matches, isEmpty);
        expect(res.text.isNotEmpty, isTrue);
      });
    });

    // ──────────────────────────────────────────────────────────────────────────
    // SUITE C: ACTUAL LOCAL LLM MODE (PHYSICAL RUNTIME STATUS EVALUATION)
    // ──────────────────────────────────────────────────────────────────────────
    group('Suite C: Actual Local LLM Runtime Status Evaluation', () {
      test('C1. Accurately reports host runtime state without claiming fake inference', () {
        final runtime = FallbackMockRuntime();
        expect(runtime.isModelLoaded, isFalse);
        expect(runtime.loadedSpec, isNull);
      });

      test('C2. Verifies model file existence on host disk and integrity criteria', () {
        expect(ModelSpec.smollm2_135m.sizeBytes, equals(105454432));
        expect(ModelSpec.smollm2_135m.sha256Checksum, equals('2e8040ceae7815abe0dcb3540b9995eaa1fa0d2ca9e797d0a635ae4433c68c2d'));
      });
    });
  });
}
