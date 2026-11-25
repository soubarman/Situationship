import 'package:flutter_test/flutter_test.dart';
import 'package:situationship/core/ai/conversation_context_manager.dart';
import 'package:situationship/core/ai/context_aware_speech_act_interpreter.dart';
import 'package:situationship/core/ai/conversational_dialogue_engine.dart';
import 'package:situationship/core/ai/local_llm/cupid_local_ai_orchestrator.dart';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/local_model_manager.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';
import 'package:situationship/core/ai/structured_conversation_state.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/models/user_model.dart';

class MockRuntimeAdapter extends ModelRuntimeAdapter {
  @override
  bool get isModelLoaded => false;

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
  group('Cupid Concierge: Adversarial Conversational Evaluation Suite', () {
    late ConversationContextManager contextManager;
    late CupidLocalAIOrchestrator orchestrator;

    final currentUser = UserModel(
      id: 'user_eval_1',
      name: 'Aarav',
      email: 'aarav@example.com',
      age: 25,
      gender: 'male',
      interestedIn: const ['female'],
      relationshipIntent: 'serious',
      interests: const ['Music', 'Coffee', 'Design'],
    );

    final candidatePool = [
      UserModel(
        id: 'candidate_kavya',
        name: 'Kavya',
        email: 'kavya@example.com',
        age: 24,
        gender: 'female',
        bio: 'Standup comedy fan with a love for dark humour and witty banter.',
        interests: const ['Comedy', 'Writing', 'Art'],
        isVerified: true,
      ),
      UserModel(
        id: 'candidate_meera',
        name: 'Meera',
        email: 'meera@example.com',
        age: 26,
        gender: 'female',
        bio: 'Creative designer who paints and illustrates. Hates long flights.',
        interests: const ['Design', 'Painting', 'Indie Music'],
        isVerified: true,
      ),
      UserModel(
        id: 'candidate_tanya',
        name: 'Tanya',
        email: 'tanya@example.com',
        age: 23,
        gender: 'female',
        bio: 'Wanderlust traveler exploring new countries every month.',
        interests: const ['Travel', 'Backpacking', 'Photography'],
        isVerified: false,
      ),
    ];

    setUp(() {
      contextManager = ConversationContextManager();
      orchestrator = CupidLocalAIOrchestrator(
        runtime: MockRuntimeAdapter(),
        contextManager: contextManager,
        modelManager: LocalModelManager(),
        matcher: VibeMatrixMatcher(),
      );
    });

    // ── Conversation A: Short preference reply ─────────────────────────────────
    test('Conversation A: Cupid understands short reply as a partner preference', () async {
      contextManager.setAssistantQuestion(
        "What kind of person do you usually connect with?",
        ExpectedAnswerType.partnerTrait,
        topic: ConversationTopic.dating,
      );

      final turn = await orchestrator.processTurn(
        userUtterance: "Someone with a good sense of humour.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty, reason: 'Must not trigger premature discovery');
      final traits = contextManager.criteria.personalityTraits;
      expect(traits.any((t) => t.toLowerCase().contains('humour') || t.toLowerCase().contains('humor')), isTrue);
    });

    // ── Conversation B: Qualified preference ──────────────────────────────────
    test('Conversation B: Cupid retains both positive preference and its qualification', () async {
      contextManager.setAssistantQuestion(
        "What kind of humour do you enjoy?",
        ExpectedAnswerType.humourStyle,
        topic: ConversationTopic.humour,
      );

      final turn = await orchestrator.processTurn(
        userUtterance: "Dark humour, but not the offensive kind.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty);
      // Verify dark humour retained without offensive tag
      final humourPrefs = contextManager.structuredPreferences.where((p) => p.category == 'humour').toList();
      expect(humourPrefs, isNotEmpty);
      expect(humourPrefs.first.value.toLowerCase(), contains('dark humour'));
      expect(humourPrefs.first.value.toLowerCase(), isNot(contains('offensive')));
    });

    // ── Conversation C: Implied discovery request ─────────────────────────────
    test('Conversation C: Implied discovery request recognizes user intent and clarifies missing criteria', () async {
      // User asks to be introduced without stating preferences first
      final turn = await orchestrator.processTurn(
        userUtterance: "Know anyone who would get along with me?",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      // Should recognize the desire to find someone, but ask what kind of vibe they seek
      expect(turn.matches, isEmpty);
      expect(contextManager.expectedAnswerType, isNot(equals(ExpectedAnswerType.none)));
      expect(turn.text.toLowerCase(), anyOf(contains('vibe'), contains('kind of person'), contains('looking for')));
    });

    // ── Conversation D: Ambiguous hobby scope ─────────────────────────────────
    test('Conversation D: Ambiguous hobby clarifies scope rather than assuming partner requirement', () async {
      final turn = await orchestrator.processTurn(
        userUtterance: "I like photography.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty);
      expect(turn.text.toLowerCase(), anyOf(
        contains('yourself'),
        contains('partner'),
        contains('you enjoy'),
        contains('someone who shares'),
      ));
    });

    // ── Conversation E: Negative interest + positive preference ───────────────
    test('Conversation E: Negative interest is not stored as a positive dating requirement', () async {
      final turn = await orchestrator.processTurn(
        userUtterance: "I don't really care about travelling, but I'd love someone creative.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty);
      expect(contextManager.criteria.interests, isNot(contains('travelling')));
      expect(contextManager.criteria.personalityTraits.any((t) => t.contains('creative')), isTrue);
    });

    // ── Conversation F: Correction without explicit replacement ───────────────
    test('Conversation F: Clarifies when user indicates previous interpretation was wrong', () async {
      contextManager.setAssistantQuestion(
        "I can search for someone quiet and calm!",
        ExpectedAnswerType.confirmation,
        topic: ConversationTopic.dating,
      );

      final turn = await orchestrator.processTurn(
        userUtterance: "Actually, that isn't what I meant.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty);
      expect(turn.text.toLowerCase(), anyOf(
        contains('what did you mean'),
        contains('tell me what you meant'),
        contains('clarify'),
        contains('my mistake'),
        contains('on your mind'),
      ));
      expect(turn.text, isNot(contains('someone .')));
    });

    // ── Conversation G: Polite confirmation decline ───────────────────────────
    test('Conversation G: Declines confirmation gracefully without initiating discovery', () async {
      contextManager.setAssistantQuestion(
        "Would you like me to find someone matching those preferences?",
        ExpectedAnswerType.confirmation,
        topic: ConversationTopic.dating,
      );

      final turn = await orchestrator.processTurn(
        userUtterance: "Not right now. Maybe later.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty);
      expect(turn.text.toLowerCase(), anyOf(contains('no problem'), contains('take your time'), contains('whenever')));
    });

    // ── Conversation H: Indirect discovery request ────────────────────────────
    test('Conversation H: Recognises indirect discovery request when criteria exists', () async {
      contextManager.addStructuredPreference(UserDatingPreference(
        category: 'lifestyle',
        value: 'indie films and coffee',
      ));

      final turn = await orchestrator.processTurn(
        userUtterance: "Think you could introduce me to somebody like that?",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isNotEmpty, reason: 'Criteria exists and user requested introduction');
    });

    // ── Conversation I: Topic transition with trailing interests ──────────────
    test('Conversation I: Responds to topic change and does not treat casual mentions as romantic requirements', () async {
      final turn = await orchestrator.processTurn(
        userUtterance: "I love travelling. Photography is cool too. Anyway, what music do you listen to?",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn.matches, isEmpty);
      expect(contextManager.structuredState.currentTopic, equals(ConversationTopic.music));
      expect(turn.text.toLowerCase(), anyOf(contains('music'), contains('artists'), contains('listen')));
    });

    // ── Conversation J: Indian English expressions ────────────────────────────
    test('Conversation J: Handles Indian English nuances (timepass, jugaad, vibe match)', () async {
      final turn1 = await orchestrator.processTurn(
        userUtterance: "Yaar, not looking for any timepass, want a serious vibe match.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(turn1.matches, isEmpty);
      expect(contextManager.criteria.relationshipIntent, equals('serious'));

      final turn2 = await orchestrator.processTurn(
        userUtterance: "Pakka non-smoker only please.",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(contextManager.criteria.dealbreakers, contains('smoking'));
    });
  });
}
