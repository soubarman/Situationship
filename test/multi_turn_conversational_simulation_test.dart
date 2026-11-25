import 'package:flutter_test/flutter_test.dart';
import 'package:situationship/core/ai/conversational_intent.dart';
import 'package:situationship/core/ai/local_llm/cupid_local_ai_orchestrator.dart';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/local_model_manager.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/ai/conversation_context_manager.dart';
import 'package:situationship/core/ai/structured_conversation_state.dart';
import 'package:situationship/core/models/user_model.dart';

class MockRuntimeAdapter extends ModelRuntimeAdapter {
  @override
  bool get isModelLoaded => false; // Simulates pure local deterministic engine

  @override
  ModelSpec? get loadedSpec => null;

  @override
  Future<void> initialize({required dynamic spec, required String modelFilePath}) async {}

  @override
  Future<String> generate(String prompt, {int maxTokens = 256, double temperature = 0.7, List<String>? stopSequences}) async {
    return '';
  }

  @override
  Stream<String> generateStreaming(String prompt, {int maxTokens = 256, double temperature = 0.7, List<String>? stopSequences}) async* {}

  @override
  Future<void> unload() async {}
}

void main() {
  group('Cupid Concierge: Multi-Turn Conversation Simulation & Quality Suite', () {
    late ConversationContextManager contextManager;
    late CupidLocalAIOrchestrator orchestrator;

    final currentUser = UserModel(
      id: 'user_rohan',
      name: 'Rohan',
      email: 'rohan@example.com',
      age: 24,
      gender: 'male',
      interestedIn: const ['female'],
      relationshipIntent: 'serious',
      interests: const ['Travel', 'Photography', 'Music'],
    );

    final candidateMaya = UserModel(
      id: 'user_maya',
      name: 'Maya',
      email: 'maya@example.com',
      age: 23,
      gender: 'female',
      bio: 'Analog 35mm film photographer and spontaneous road tripper.',
      interests: const ['Photography', 'Travel', 'Indie Rock'],
      isVerified: true,
    );

    final candidatePriya = UserModel(
      id: 'user_priya',
      name: 'Priya',
      email: 'priya@example.com',
      age: 24,
      gender: 'female',
      bio: 'Software engineer who loves quiet cafes and deep podcasts.',
      interests: const ['Coffee', 'Books', 'Tech'],
      isVerified: false,
    );

    final candidateGamer = UserModel(
      id: 'user_tanva',
      name: 'Tanva',
      email: 'tanva@example.com',
      age: 26,
      gender: 'female',
      bio: 'Battle royale gaming all night. Level 100.',
      interests: const ['Gaming', 'Anime'],
      isVerified: false,
    );

    final candidatePool = [candidateMaya, candidatePriya, candidateGamer];

    setUp(() {
      contextManager = ConversationContextManager();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: MockRuntimeAdapter(),
        matcher: VibeMatrixMatcher(),
        contextManager: contextManager,
        modelManager: LocalModelManager(),
      );
    });

    // ── Scenario A: Humour ────────────────────────────────────────────────────
    test('Scenario A: Multi-turn dialogue explores humour without premature profile discovery', () async {
      // Step 1: Assistant asked: "What kind of conversations do you enjoy?"
      contextManager.setAssistantQuestion(
        "What kind of conversations do you enjoy?",
        ExpectedAnswerType.humourStyle,
        topic: ConversationTopic.humour,
      );

      // Turn 1: User replies "Funny ones."
      final turn1 = await orchestrator.processTurn(
        userUtterance: "Funny ones.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn1.matches, isEmpty, reason: 'Must NOT discover profiles on conversational answer');
      expect(turn1.text.toLowerCase(), contains('laugh'));
      expect(contextManager.expectedAnswerType, equals(ExpectedAnswerType.humourStyle));

      // Turn 2: User refines "Mostly sarcasm."
      final turn2 = await orchestrator.processTurn(
        userUtterance: "Mostly sarcasm.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn2.matches, isEmpty, reason: 'Must NOT discover profiles on refinement');
      expect(turn2.text.toLowerCase(), contains('wit'));

      // Turn 3: User adds "And silly jokes sometimes."
      final turn3 = await orchestrator.processTurn(
        userUtterance: "And silly jokes sometimes.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn3.matches, isEmpty, reason: 'Must NOT discover profiles until user requests search');
      expect(turn3.text.toLowerCase(), contains('wavelength'));

      // Verify preferences retained in structured state
      final humourPrefs = contextManager.structuredPreferences
          .where((p) => p.category == 'humour')
          .map((p) => p.value)
          .toList();
      expect(humourPrefs, isNotEmpty);
    });

    // ── Scenario B: Dating Preferences ────────────────────────────────────────
    test('Scenario B: Progressive preference gathering with strict action gate', () async {
      // Turn 1: "I want someone interesting in my life."
      final turn1 = await orchestrator.processTurn(
        userUtterance: "I want someone interesting in my life.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );
      expect(turn1.matches, isEmpty, reason: 'Ambiguous request must not trigger profile discovery');
      expect(turn1.text.toLowerCase(), contains('interesting'));

      // Turn 2: "Someone who likes travelling."
      final turn2 = await orchestrator.processTurn(
        userUtterance: "Someone who likes travelling.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );
      expect(turn2.matches, isEmpty, reason: 'Stating travel preference must not trigger discovery');
      expect(contextManager.criteria.interests, contains('travelling'));

      // Turn 3: "Photography too."
      final turn3 = await orchestrator.processTurn(
        userUtterance: "Photography too.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );
      expect(turn3.matches, isEmpty, reason: 'Adding photography must not trigger discovery');
      expect(contextManager.criteria.interests, contains('photography'));

      // Turn 4: Explicit request "Find someone like that."
      final turn4 = await orchestrator.processTurn(
        userUtterance: "Find someone like that.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );
      expect(turn4.matches, isNotEmpty, reason: 'Explicit request must trigger profile discovery');
      expect(turn4.matches.first.candidate.name, equals('Maya'));
      expect(turn4.text.toLowerCase(), contains('maya'));
    });

    // ── Scenario C: Emotional Support ─────────────────────────────────────────
    test('Scenario C: Emotional messages receive support without dumping profile cards', () async {
      // Turn 1: "I'm having a boring day."
      final turn1 = await orchestrator.processTurn(
        userUtterance: "I'm having a boring day.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );
      expect(turn1.matches, isEmpty, reason: 'Boredom is emotional support, not profile search');
      expect(turn1.text.toLowerCase(), contains('boredom'));

      // Turn 2: "I feel a little lonely too."
      final turn2 = await orchestrator.processTurn(
        userUtterance: "I feel a little lonely too.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );
      expect(turn2.matches, isEmpty, reason: 'Loneliness must be validated gently without profile cards');
      expect(turn2.text.toLowerCase(), contains('lonely'));
    });

    // ── Scenario D: Topic Change ──────────────────────────────────────────────
    test('Scenario D: User changes topic to music without collecting dating preferences', () async {
      contextManager.updateCriteria(ExtractedEntities(interests: ['travel']));

      final turn = await orchestrator.processTurn(
        userUtterance: "Let's talk about music instead.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty);
      expect(contextManager.structuredState.currentTopic, equals(ConversationTopic.music));
      expect(turn.text.toLowerCase(), contains('music'));
    });

    // ── Scenario E: Corrections ───────────────────────────────────────────────
    test('Scenario E: Corrections update earlier preferences rather than storing contradictions', () async {
      // Turn 1: "I prefer someone quiet."
      await orchestrator.processTurn(
        userUtterance: "I prefer someone quiet.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );
      expect(contextManager.criteria.personalityTraits, contains('quiet & calm'));

      // Turn 2: "Actually, not too quiet. Someone outgoing but calm."
      final turn2 = await orchestrator.processTurn(
        userUtterance: "Actually, not too quiet. Someone outgoing but calm.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn2.matches, isEmpty);
      expect(turn2.text.toLowerCase(), contains('adjusted'));
      expect(contextManager.criteria.personalityTraits, contains('outgoing but calm'));
    });

    // ── Scenario F: Ambiguous Intent ──────────────────────────────────────────
    test('Scenario F: Ambiguous intent asks gentle clarification instead of guessing', () async {
      final turn = await orchestrator.processTurn(
        userUtterance: "Maybe someone interesting.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty);
      expect(turn.text.toLowerCase(), contains('interesting'));
    });

    // ── Scenario G: Profile Rejection ─────────────────────────────────────────
    test('Scenario G: Rejected profiles are remembered and excluded from subsequent turns', () async {
      // Setup active matches
      final turnDiscovery = await orchestrator.processTurn(
        userUtterance: "Find someone into photography.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );
      expect(turnDiscovery.matches, isNotEmpty);
      final rejectedId = turnDiscovery.matches.first.candidate.id;

      // User rejects: "Not interested."
      final turnReject = await orchestrator.processTurn(
        userUtterance: "Not interested.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turnReject.matches, isEmpty);
      expect(contextManager.isProfileRejected(rejectedId), isTrue);

      // Subsequent discovery must NOT include rejected candidate
      final turnSubsequent = await orchestrator.processTurn(
        userUtterance: "Find someone else.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      for (final m in turnSubsequent.matches) {
        expect(m.candidate.id, isNot(equals(rejectedId)));
      }
    });

    // ── Scenario H: Multiple Meanings (Personal Activity vs Dating Requirement)
    test('Scenario H: Personal activity answer is not converted to a romantic requirement', () async {
      // Cupid asked: "What do you enjoy doing on weekends?"
      contextManager.setAssistantQuestion(
        "What do you enjoy doing on weekends?",
        ExpectedAnswerType.hobbyOrPassion,
        topic: ConversationTopic.lifestyle,
      );

      // User answers: "Photography."
      final turn = await orchestrator.processTurn(
        userUtterance: "Photography.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty, reason: 'Personal hobby answer must NOT trigger romantic profile search');
      expect(turn.text.toLowerCase(), contains('photography'));
      expect(turn.text.toLowerCase(), contains('film'));
    });
  });
}
