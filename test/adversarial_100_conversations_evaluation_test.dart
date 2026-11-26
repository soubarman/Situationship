import 'package:flutter_test/flutter_test.dart';
import 'package:situationship/core/models/user_model.dart';
import 'package:situationship/core/ai/structured_conversation_state.dart';
import 'package:situationship/core/ai/conversational_intent.dart';
import 'package:situationship/core/ai/conversation_context_manager.dart';
import 'package:situationship/core/ai/context_aware_speech_act_interpreter.dart';
import 'package:situationship/core/ai/conversational_dialogue_engine.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/ai/local_llm/cupid_local_ai_orchestrator.dart';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/local_model_manager.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';

class MockLLMRuntimeAdapter implements ModelRuntimeAdapter {
  String? mockOutput;

  @override
  bool get isModelLoaded => false;

  @override
  ModelSpec? get loadedSpec => null;

  @override
  Future<void> initialize({required ModelSpec spec, required String modelFilePath}) async {}

  @override
  Stream<String> generateStreaming(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    List<String> stopSequences = const ['<|im_end|>', '<end_of_turn>', '<|eot_id|>'],
  }) async* {
    yield mockOutput ?? "";
  }

  @override
  Future<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    List<String> stopSequences = const ['<|im_end|>', '<end_of_turn>', '<|eot_id|>'],
  }) async {
    return mockOutput ?? "";
  }

  @override
  Future<void> unload() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConversationContextManager contextManager;
  late VibeMatrixMatcher matcher;
  late MockLLMRuntimeAdapter mockRuntime;
  late CupidLocalAIOrchestrator orchestrator;

  final currentUser = UserModel(
    id: 'user_main',
    name: 'Rohan',
    email: 'rohan@example.com',
    age: 26,
    gender: 'male',
    interestedIn: const ['female'],
    interests: const ['photography', 'coffee', 'indie music', 'art'],
    location: 'Indiranagar, Bangalore',
    bio: 'Software engineer and weekend photographer looking for genuine conversations.',
  );

  final candidatePool = [
    UserModel(
      id: 'candidate_tanya',
      name: 'Tanya',
      email: 'tanya@example.com',
      age: 25,
      gender: 'female',
      interestedIn: const ['male'],
      interests: const ['photography', 'indie music', 'travel', 'art'],
      location: 'Indiranagar, Bangalore',
      bio: 'Analog film photographer and matcha lover. Let’s explore quiet spots.',
    ),
    UserModel(
      id: 'candidate_ananya',
      name: 'Ananya',
      email: 'ananya@example.com',
      age: 26,
      gender: 'female',
      interestedIn: const ['male'],
      interests: const ['art', 'books', 'museums', 'coffee'],
      location: 'Koramangala, Bangalore',
      bio: 'Visual designer who loves gallery walks, dark chocolate, and late evening jazz.',
    ),
    UserModel(
      id: 'candidate_aditya',
      name: 'Aditya',
      email: 'aditya@example.com',
      age: 28,
      gender: 'male',
      interestedIn: const ['female'],
      interests: const ['hiking', 'camping', 'fitness', 'travel'],
      location: 'HSR Layout, Bangalore',
      bio: 'Mountain enthusiast and weekend trek leader.',
    ),
    UserModel(
      id: 'candidate_priya',
      name: 'Priya',
      email: 'priya@example.com',
      age: 24,
      gender: 'female',
      interestedIn: const ['male'],
      interests: const ['music', 'concerts', 'food', 'dogs'],
      location: 'Indiranagar, Bangalore',
      bio: 'Indie music lover and dog mom. Always down for street food tours.',
    ),
  ];

  Future<CupidTurnResult> runTurn(String utterance) {
    return orchestrator.processTurn(
      userUtterance: utterance,
      currentUser: currentUser,
      candidatePool: candidatePool,
      excludedUserIds: const {},
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 1: Casual Everyday Chit-Chat (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 1: Casual Everyday Chit-Chat', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('1. Morning greeting receives warm social reply without dating search', () async {
      final res = await runTurn("Hey Cupid, good morning!");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
      expect(res.text.toLowerCase().contains('searching'), isFalse);
    });

    test('2. Casual evening decompression receives empathetic casual reply', () async {
      final res = await runTurn("Just finished work, what a long day.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('3. Movie comment acknowledges entertainment without dating questionnaire', () async {
      final res = await runTurn("I'm watching a classic sci-fi movie right now.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('movie') || res.text.toLowerCase().contains('watch'), isTrue);
    });

    test('4. Walking/relaxation comment is received naturally', () async {
      final res = await runTurn("Taking a relaxing evening walk around the park.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('5. Pure chill comment does not initiate matchmaking', () async {
      final res = await runTurn("I'm just chilling today, zero plans.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('6. Food commentary sparks light casual chat', () async {
      final res = await runTurn("Having pizza for dinner, best day ever!");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('food') || res.text.toLowerCase().contains('cook'), isTrue);
    });

    test('7. Asking about AI availability receives polite concierge explanation', () async {
      final res = await runTurn("Do you ever sleep or are you on 24/7?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('cupid') || res.text.toLowerCase().contains('wingman'), isTrue);
    });

    test('8. Weekend inquiry is met with balanced recharge vs explore advice', () async {
      final res = await runTurn("What should I do this weekend?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('weekend'), isTrue);
    });

    test('9. Music listening comment is validated without pushing profile discovery', () async {
      final res = await runTurn("Just listening to some quiet ambient music and relaxing.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('10. Multi-turn casual conversation produces varied, non-repetitive responses', () async {
      final t1 = await runTurn("Hey there!");
      final t2 = await runTurn("Just sitting on the balcony.");
      final t3 = await runTurn("Enjoying the cool breeze tonight.");
      expect(t1.matches, isEmpty);
      expect(t2.matches, isEmpty);
      expect(t3.matches, isEmpty);
      expect(t2.text, isNot(equals(t3.text)));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 2: Humour, Sarcasm & Banter (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 2: Humour, Sarcasm & Banter', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('11. Asking for a dating joke returns witty relatable humor', () async {
      final res = await runTurn("Tell me a funny joke about dating apps.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('joke') || res.text.toLowerCase().contains('golden retriever') || res.text.toLowerCase().contains('bio'), isTrue);
    });

    test('12. Sarcasm about hiking clichés is acknowledged as satire not a hiking preference', () async {
      final res = await runTurn("Oh great, another person whose entire life is hiking mountains.");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.interests.contains('hiking'), isFalse);
    });

    test('13. Sarcasm about reading 50 books is treated as skepticism', () async {
      final res = await runTurn("Yeah right, like everyone on here reads 50 books a year.");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.interests.contains('books'), isFalse);
    });

    test('14. Internet slang "I am dead haha" recognized as laughter not distress', () async {
      final res = await runTurn("I am dead haha that prompt was hilarious.");
      expect(res.matches, isEmpty);
      expect(contextManager.structuredState.currentTopic, isNot(equals(ConversationTopic.emotionalSupport)));
    });

    test('15. Dad joke request is met with humor', () async {
      final res = await runTurn("Got any good dad jokes for me?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('16. Self-deprecating banter is met with warmth without diagnosing trauma', () async {
      final res = await runTurn("My dog gives way better dating advice than any of my friends.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('17. Lighthearted inquiry about AI judgment is reassured politely', () async {
      final res = await runTurn("Are you secretly judging my bio?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('cupid') || res.text.toLowerCase().contains('wingman'), isTrue);
    });

    test('18. Pineapple pizza banter does not record pizza as a strict dating dealbreaker', () async {
      final res = await runTurn("If I say I like pineapple on pizza, will you unmatch me?");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.dealbreakers.contains('pizza'), isFalse);
    });

    test('19. Witty banter about worst opening lines does not initiate candidate search', () async {
      final res = await runTurn("Is there an award for the absolute worst opening line ever written?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('20. Playful request to make the user laugh receives funny response', () async {
      final res = await runTurn("Make me laugh, I need a smile today!");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('bio') || res.text.toLowerCase().contains('retriever') || res.text.toLowerCase().contains('joke'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 3: Indian English, Hinglish & Cultural Nuances (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 3: Indian English & Hinglish', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('21. "Scene kya hai" recognized as casual greeting not search', () async {
      final res = await runTurn("Scene kya hai Cupid?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('bas chal raha hai') || res.text.toLowerCase().contains('scene'), isTrue);
    });

    test('22. "Timepass" recognized as casual intent without creating marriage filters', () async {
      final res = await runTurn("I'm just here for some timepass today, nothing serious.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('low-pressure') || res.text.toLowerCase().contains('timepass'), isTrue);
    });

    test('23. "Chai pe charcha" recognized as ideal casual coffee/tea meetup vibe', () async {
      final res = await runTurn("Chai pe charcha sounds like the ideal first date.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('chai') || res.text.toLowerCase().contains('meetup'), isTrue);
    });

    test('24. "Thoda chill type person" extracted as relaxed personality', () async {
      final res = await runTurn("Looking for someone thoda chill and fun.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('25. "Jugaad" recognized as witty resourcefulness not a broken keyword', () async {
      final res = await runTurn("Can you do some jugaad for modern dating?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('jugaad'), isTrue);
    });

    test('26. "Pakka" understood as certainty modifier', () async {
      final res = await runTurn("Pakka she is into indie music?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('27. "Yaar dating is exhausting" handled with empathy and colloquial rapport', () async {
      final res = await runTurn("Yaar, dating is so exhausting sometimes.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('28. "Bro need some ideas" recognized as casual request for date tips', () async {
      final res = await runTurn("Bro, need some quick first date ideas.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('date') || res.text.toLowerCase().contains('coffee'), isTrue);
    });

    test('29. Traffic rant validated without recommending a transit app', () async {
      final res = await runTurn("Bangalore traffic literally killed my last date vibe.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('30. "Kya chal raha hai" answered as social status check', () async {
      final res = await runTurn("Kya chal raha hai Cupid?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('bas') || res.text.toLowerCase().contains('chilling'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 4: Emotional Support & Empathetic Validation (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 4: Emotional Support & Empathetic Validation', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('31. Ghosting disclosure receives compassionate validation without dating quiz', () async {
      final res = await runTurn("I got ghosted after three great dates, feeling awful.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('ghosting'), isTrue);
      expect(res.text.toLowerCase().contains('would you like me to look for members'), isFalse);
    });

    test('32. Work burnout receives decompression empathy', () async {
      final res = await runTurn("Work was so overwhelming today, I'm completely drained.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('exhausting') || res.text.toLowerCase().contains('decompress'), isTrue);
    });

    test('33. Loneliness statement is validated gently', () async {
      final res = await runTurn("Feeling really lonely tonight, honestly.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('lonely') || res.text.toLowerCase().contains('valid'), isTrue);
    });

    test('34. Dating app inadequacy insecurity met with genuine reassurance', () async {
      final res = await runTurn("Dating apps make me feel like I am not good enough sometimes.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('valid') || res.text.toLowerCase().contains('exhausting'), isTrue);
    });

    test('35. Pre-date anxiety receives comforting low-pressure advice', () async {
      final res = await runTurn("I get anxious before meeting someone new in person.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('36. Breakup vulnerability handled with gentle pace without rushing into dating', () async {
      final res = await runTurn("Going through a rough breakup, taking things very slow.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
      expect(res.text.toLowerCase().contains('search now'), isFalse);
    });

    test('37. Frustration with listening validated authentically', () async {
      final res = await runTurn("Why does it feel so hard to find someone who actually listens?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('38. Small talk fatigue met with understanding', () async {
      final res = await runTurn("I'm just so tired of small talk that goes nowhere.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('39. Follow-up to emotional context does NOT ask for dating preferences', () async {
      await runTurn("Work was terrible today, just drained.");
      final res = await runTurn("Yeah, pretty much just want silence tonight.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('peace') || res.text.toLowerCase().contains('take it easy'), isTrue);
      expect(res.text.toLowerCase().contains('what other qualities do you value'), isFalse);
    });

    test('40. Unequal effort lament validated with self-worth reminder', () async {
      final res = await runTurn("I feel like I always give way more effort than I receive.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 5: Ambiguous, Short & Multi-Turn Follow-Ups (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 5: Ambiguous, Short & Multi-Turn Follow-Ups', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('41. Ambiguous "maybe" asks gentle clarification without searching', () async {
      final res = await runTurn("maybe");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('listening') || res.text.toLowerCase().contains('tell me'), isTrue);
    });

    test('42. Ambiguous "idk" clarifies intent gently', () async {
      final res = await runTurn("idk");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('43. "Both" resolves to previous question context', () async {
      contextManager.setAssistantQuestion(
        "Is photography a hobby for you or something you want in a partner?",
        ExpectedAnswerType.partnerTrait,
        topic: ConversationTopic.photography,
      );
      final res = await runTurn("Both actually");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('both') || res.text.toLowerCase().contains('sharing'), isTrue);
    });

    test('44. Short response "Sci-fi" resolves to genre context', () async {
      contextManager.setAssistantQuestion(
        "What kind of books or movies do you love?",
        ExpectedAnswerType.partnerTrait,
        topic: ConversationTopic.general,
      );
      final res = await runTurn("Sci-fi mostly");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('45. Short single-token "k" does not crash engine or trigger search', () async {
      final res = await runTurn("k");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('46. "Sounds good" acts as polite acknowledgment', () async {
      final res = await runTurn("sounds good");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('47. "Thanks for the advice" acknowledged warmly', () async {
      final res = await runTurn("That makes a lot of sense, thanks!");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('48. Follow-up "What about coffee spots instead?" switches topic smoothly', () async {
      final res = await runTurn("What about quiet coffee spots instead?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('49. Short contextual agreement in conversation does not force search', () async {
      final res = await runTurn("Definitely");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('50. "Tell me more" continues open conversation', () async {
      final res = await runTurn("Tell me more about that.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 6: Relationship Advice & Dating Psychology (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 6: Relationship Advice & Dating Psychology', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('51. Green flags query answered with thoughtful relationship criteria', () async {
      final res = await runTurn("What are the biggest green flags to look for early on?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('green flag') || res.text.toLowerCase().contains('communication'), isTrue);
    });

    test('52. Red flags inquiry highlights communication shortcomings', () async {
      final res = await runTurn("What are common red flags people ignore?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('flag') || res.text.toLowerCase().contains('communication'), isTrue);
    });

    test('53. First date spots query recommends low-pressure environments', () async {
      final res = await runTurn("What makes a great first date spot?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('coffee') || res.text.toLowerCase().contains('low-pressure'), isTrue);
    });

    test('54. Icebreaker tips query provides non-generic openers', () async {
      final res = await runTurn("How do I start a conversation that is not just 'hey'?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('opener') || res.text.toLowerCase().contains('specific detail'), isTrue);
    });

    test('55. Double texting query answered with psychological perspective', () async {
      final res = await runTurn("Is double texting really that bad?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('56. Texting first etiquette answered thoughtfully', () async {
      final res = await runTurn("Should I text first or wait for them?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('57. When to discuss intentions answered with balance', () async {
      final res = await runTurn("When is the right time to talk about what we are looking for?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('58. Declining a second date advice maintains kindness and clarity', () async {
      final res = await runTurn("How do I politely decline a second date?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('59. Bio improvement question gives practical advice', () async {
      final res = await runTurn("How can I make my bio stand out without sounding pretentious?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });

    test('60. Genuine chemistry question answered with authenticity focus', () async {
      final res = await runTurn("How do you know if you have genuine chemistry with someone?");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 7: Personal Traits vs. Partner Preferences & Qualifications (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 7: Personal Traits vs. Partner Preferences & Qualifications', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('61. Self-trait "I am an introvert" stored as self attribute not partner filter', () async {
      final res = await runTurn("I am a quiet introvert software engineer who reads sci-fi.");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.interests.contains('introvert'), isFalse);
    });

    test('62. Partner trait "I want someone into art" stored as partner requirement', () async {
      final res = await runTurn("I want someone into art.");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.interests.contains('art'), isTrue);
    });

    test('63. Qualified preference "Coffee dates in quiet spots" does not trigger broad caffeine search', () async {
      final res = await runTurn("I enjoy coffee dates, but only in quiet local spots.");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.interests.contains('coffee'), isTrue);
    });

    test('64. Negative preference "I don\'t smoke" stored as dealbreaker not positive hobby', () async {
      final res = await runTurn("I don't smoke and can't stand cigarettes.");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.dealbreakers.contains('smoker'), isTrue);
      expect(contextManager.criteria.interests.contains('smoke'), isFalse);
    });

    test('65. Additive preference appends without wiping existing criteria', () async {
      await runTurn("I want someone into photography.");
      await runTurn("Also they must love indie music.");
      expect(contextManager.criteria.interests.contains('photography'), isTrue);
      expect(contextManager.criteria.interests.contains('music'), isTrue);
    });

    test('66. Age preference specifies demographic range', () async {
      await runTurn("Looking for someone around 24 to 28.");
      expect(contextManager.criteria.minAge, equals(24));
      expect(contextManager.criteria.maxAge, equals(28));
    });

    test('67. Differentiates self-cooking from partner street-food preference', () async {
      final res = await runTurn("I cook Italian at home, but I want a partner who loves exploring street food.");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.interests.contains('food'), isTrue);
    });

    test('68. Qualification "Travels, but not constantly" qualifies frequency', () async {
      final res = await runTurn("I don't mind someone who travels, but not every single weekend.");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.interests.contains('travel'), isTrue);
    });

    test('69. Long-term relationship intent stored distinctly from casual intent', () async {
      await runTurn("Looking for a serious long-term relationship, absolutely no hookups.");
      expect(contextManager.criteria.relationshipIntent, equals('serious'));
    });

    test('70. Occasional gym-goer not labeled as extreme fitness requirement', () async {
      final res = await runTurn("I go to the gym occasionally, but I'm definitely not a gym freak.");
      expect(res.matches, isEmpty);
      expect(contextManager.criteria.dealbreakers.contains('fitness'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 8: Preference Corrections & Contradiction Handling (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 8: Preference Corrections & Contradiction Handling', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('71. "Actually scratch that, no nightlife" removes nightlife preference', () async {
      await runTurn("I like nightlife.");
      expect(contextManager.criteria.interests.contains('nightlife'), isTrue);
      await runTurn("Actually scratch that, I don't want someone into nightlife.");
      expect(contextManager.criteria.interests.contains('nightlife'), isFalse);
    });

    test('72. "I meant hiking, not clubbing" replaces clubbing with hiking', () async {
      await runTurn("Find people into clubbing.");
      await runTurn("Wait, I meant hiking, not clubbing!");
      expect(contextManager.criteria.interests.contains('clubbing'), isFalse);
      expect(contextManager.criteria.interests.contains('hiking'), isTrue);
    });

    test('73. Gender preference correction updates genderHint', () async {
      await runTurn("Looking for guys.");
      expect(contextManager.criteria.genderHint, equals('male'));
      await runTurn("No, sorry, looking for women, not men.");
      expect(contextManager.criteria.genderHint, equals('female'));
    });

    test('74. Age correction updates min and max age boundaries', () async {
      await runTurn("Looking for age 20 to 22.");
      await runTurn("Wait, I meant 25 to 29.");
      expect(contextManager.criteria.minAge, equals(25));
      expect(contextManager.criteria.maxAge, equals(29));
    });

    test('75. Multi-turn preference replacement replaces old criteria', () async {
      await runTurn("I want someone into photography.");
      await runTurn("Actually, I prefer indie musicians instead.");
      expect(contextManager.criteria.interests.contains('music'), isTrue);
    });

    test('76. Ambivalent correction "That is not what I meant at all" asks clarification', () async {
      await runTurn("I want quiet coffee.");
      final res = await runTurn("No, that's not what I meant at all!");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('mistake') || res.text.toLowerCase().contains('meant'), isTrue);
    });

    test('77. Clearing dealbreaker removes negative constraint', () async {
      await runTurn("I don't want any smokers.");
      expect(contextManager.criteria.dealbreakers.contains('smoker'), isTrue);
      await runTurn("Never mind about the non-smoker rule, social is fine.");
      expect(contextManager.criteria.dealbreakers.contains('smoker'), isFalse);
    });

    test('78. Explicit reset wipes criteria and conversation memory', () async {
      await runTurn("I want someone into art and books.");
      expect(contextManager.criteria.interests.isNotEmpty, isTrue);
      final res = await runTurn("Reset everything and let's start fresh.");
      expect(contextManager.criteria.interests, isEmpty);
      expect(res.text.toLowerCase().contains('reset'), isTrue);
    });

    test('79. Rejecting a candidate profile records their ID in rejectedProfileIds', () async {
      await runTurn("Find me someone who loves photography and indie music.");
      final res = await runTurn("I'm not feeling Tanya's vibe at all, show someone else.");
      expect(contextManager.rejectedProfileIds.contains('candidate_tanya'), isTrue);
      expect(res.text.toLowerCase().contains('noted') || res.text.toLowerCase().contains('won\'t show'), isTrue);
    });

    test('80. "Clear chat" cleans conversation context', () async {
      await runTurn("Looking for dancers.");
      final res = await runTurn("Clear chat");
      expect(contextManager.criteria.interests, isEmpty);
      expect(res.text.toLowerCase().contains('reset'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 9: Topic Switching & App Features FAQ (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 9: Topic Switching & App Features FAQ', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('81. Topic switch to music switches topic smoothly', () async {
      final res = await runTurn("Enough about dating, let's talk about music instead.");
      expect(res.matches, isEmpty);
      expect(contextManager.structuredState.currentTopic, equals(ConversationTopic.music));
      expect(res.text.toLowerCase().contains('music'), isTrue);
    });

    test('82. Topic switch to travel switches context', () async {
      final res = await runTurn("Let's switch gears, what is your favorite travel destination?");
      expect(res.matches, isEmpty);
      expect(contextManager.structuredState.currentTopic, equals(ConversationTopic.travel));
      expect(res.text.toLowerCase().contains('travel'), isTrue);
    });

    test('83. Topic switch to photography prompts for camera interest', () async {
      final res = await runTurn("Let's talk about photography instead.");
      expect(res.matches, isEmpty);
      expect(contextManager.structuredState.currentTopic, equals(ConversationTopic.photography));
      expect(res.text.toLowerCase().contains('photography'), isTrue);
    });

    test('84. Asking about Coins explains in-app reward economy', () async {
      final res = await runTurn("How do coins work on Situationship?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('coin'), isTrue);
    });

    test('85. Asking about Confessions explains anonymous feature', () async {
      final res = await runTurn("What is an Anonymous Confession in the app?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('confession'), isTrue);
    });

    test('86. Asking about Spotlight explains visibility boost', () async {
      final res = await runTurn("What does Spotlight do?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('spotlight'), isTrue);
    });

    test('87. Asking about Verification explains S-badge challenge', () async {
      final res = await runTurn("How do I get the verified S-badge?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('verif'), isTrue);
    });

    test('88. Coding requests are politely declined as out of domain', () async {
      final res = await runTurn("Write a python script to reverse a linked list.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('coding') || res.text.toLowerCase().contains('exclusively'), isTrue);
    });

    test('89. Homework requests are politely declined as out of domain', () async {
      final res = await runTurn("Solve my calculus homework integral dx/(x^2 + 1).");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('homework') || res.text.toLowerCase().contains('exclusively'), isTrue);
    });

    test('90. Multi-topic casual utterance does not hallucinate search', () async {
      final res = await runTurn("I like indie rock, spicy ramen, and quiet art galleries.");
      expect(res.matches, isEmpty);
      expect(res.text.isNotEmpty, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SUITE 10: Profile Discovery, Decision Gate & Candidate Matching (10 Conversations)
  // ══════════════════════════════════════════════════════════════════════════
  group('Suite 10: Profile Discovery, Decision Gate & Candidate Matching', () {
    setUp(() {
      contextManager = ConversationContextManager();
      matcher = VibeMatrixMatcher();
      mockRuntime = MockLLMRuntimeAdapter();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: mockRuntime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    test('91. Explicit profile search finds matching candidates', () async {
      final res = await runTurn("Find me someone who loves photography and indie music.");
      expect(res.matches.isNotEmpty, isTrue);
      expect(res.matches.any((m) => m.candidate.name == 'Tanya'), isTrue);
      expect(res.text.toLowerCase().contains('tanya'), isTrue);
    });

    test('92. Implied discovery request without criteria prompts for vibe before searching', () async {
      final res = await runTurn("Introduce me to someone.");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('tell me what kind of person') || res.text.toLowerCase().contains('vibe'), isTrue);
    });

    test('93. Confirmation to search with stored criteria triggers candidate discovery', () async {
      final t1 = await runTurn("I really love art and quiet museum walks.");
      print('DEBUG TEST 93 T1 TEXT: "${t1.text}", CRITERIA: ${contextManager.criteria.interests}');
      final res = await runTurn("Yes, please find someone who matches that!");
      print('DEBUG TEST 93 T2 TEXT: "${res.text}", MATCHES: ${res.matches.length}');
      expect(res.matches.isNotEmpty, isTrue);
      expect(res.matches.any((m) => m.candidate.name == 'Ananya'), isTrue);
    });

    test('94. Search with multiple specific passions finds top reciprocal match', () async {
      final res = await runTurn("Show me profiles of women who love photography and travel.");
      expect(res.matches.isNotEmpty, isTrue);
      expect(res.matches.first.candidate.name, equals('Tanya'));
    });

    test('95. Rejected profile is never returned on subsequent search', () async {
      await runTurn("Find me someone who loves photography and indie music.");
      await runTurn("I don't like Tanya, show me someone else.");
      final res = await runTurn("Find me another person who loves music.");
      expect(res.matches.any((m) => m.candidate.id == 'candidate_tanya'), isFalse);
    });

    test('96. Inquiring about profile details resolves candidate name', () async {
      await runTurn("Find me someone into photography.");
      final res = await runTurn("Tell me more about Tanya.");
      expect(res.text.toLowerCase().contains('tanya') || res.text.toLowerCase().contains('analog'), isTrue);
    });

    test('97. Empty search criteria handles gracefully without crash', () async {
      final res = await runTurn("Find me someone into deep sea scuba archaeology.");
      print('DEBUG TEST 97 TEXT: "${res.text}"');
      expect(res.text.toLowerCase().contains('widen') || res.text.toLowerCase().contains('didn\'t find'), isTrue);
    });

    test('98. Admitting uncertainty for live profile visits', () async {
      final res = await runTurn("Who viewed my profile today?");
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('can\'t see') || res.text.toLowerCase().contains('liked you'), isTrue);
    });

    test('99. Admitting uncertainty for predicting future relationships', () async {
      final res = await runTurn("Will I find true love this month?");
      print('DEBUG TEST 99 TEXT: "${res.text}"');
      expect(res.matches, isEmpty);
      expect(res.text.toLowerCase().contains('crystal ball') || res.text.toLowerCase().contains('authentic'), isTrue);
    });

    test('100. Complete multi-turn end-to-end journey: Casual chat -> emotional share -> preference buildup -> explicit discovery', () async {
      // Turn 1: Casual
      final t1 = await runTurn("Hey Cupid!");
      expect(t1.matches, isEmpty);

      // Turn 2: Emotional
      final t2 = await runTurn("Work was so crazy today.");
      expect(t2.matches, isEmpty);

      // Turn 3: Preference statement
      final t3 = await runTurn("I really enjoy quiet art galleries and indie rock.");
      expect(t3.matches, isEmpty);
      expect(contextManager.criteria.interests.contains('art'), isTrue);

      // Turn 4: Explicit discovery request
      final t4 = await runTurn("Can you show me profiles who share that vibe?");
      expect(t4.matches.isNotEmpty, isTrue);
      expect(t4.matches.any((m) => m.candidate.name == 'Ananya' || m.candidate.name == 'Tanya'), isTrue);
    });
  });
}
