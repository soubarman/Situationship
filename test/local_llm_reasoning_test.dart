import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:situationship/core/models/user_model.dart';
import 'package:situationship/core/ai/conversational_intent.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/ai/conversation_context_manager.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';
import 'package:situationship/core/ai/local_llm/device_capability_detector.dart';
import 'package:situationship/core/ai/local_llm/cupid_tools.dart';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/cupid_local_ai_orchestrator.dart';
import 'package:situationship/core/ai/local_llm/local_model_manager.dart';

/// Mock in-memory runtime adapter simulating local LLM inference
class MockLocalLLMRuntime implements ModelRuntimeAdapter {
  ModelSpec? _spec;
  bool _isLoaded = false;
  String Function(String prompt)? responseGenerator;

  @override
  ModelSpec? get loadedSpec => _spec;

  @override
  bool get isModelLoaded => _isLoaded;

  @override
  Future<void> initialize({
    required ModelSpec spec,
    required String modelFilePath,
  }) async {
    _spec = spec;
    _isLoaded = true;
  }

  @override
  Stream<String> generateStreaming(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    List<String> stopSequences = const [],
  }) async* {
    if (!_isLoaded) throw StateError('Model not loaded');
    final response = responseGenerator != null
        ? responseGenerator!(prompt)
        : 'Mock LLM output';
    // Yield tokens chunk by chunk
    for (final word in response.split(' ')) {
      yield '$word ';
    }
  }

  @override
  Future<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    List<String> stopSequences = const [],
  }) async {
    if (!_isLoaded) throw StateError('Model not loaded');
    return responseGenerator != null
        ? responseGenerator!(prompt)
        : 'Mock LLM output';
  }

  @override
  Future<void> unload() async {
    _isLoaded = false;
    _spec = null;
  }
}

void main() {
  group('Cupid Local LLM Architecture', () {
    late UserModel currentUser;
    late List<UserModel> candidatePool;
    late VibeMatrixMatcher matcher;
    late ConversationContextManager contextManager;
    late LocalModelManager modelManager;

    setUp(() {
      currentUser = const UserModel(
        id: 'test_current_user',
        name: 'Kabir',
        email: 'kabir@test.com',
        age: 27,
        gender: 'male',
        interests: ['travel', 'photography', 'indie music'],
        location: 'Bangalore',
      );

      candidatePool = const [
        UserModel(
          id: 'cand_tanya',
          name: 'Tanya',
          email: 'tanya@test.com',
          age: 26,
          gender: 'female',
          bio: 'Documentary photographer & mountain climber.',
          interests: ['travel', 'photography', 'hiking'],
          location: 'Bangalore',
        ),
        UserModel(
          id: 'cand_priya',
          name: 'Priya',
          email: 'priya@test.com',
          age: 25,
          gender: 'female',
          bio: 'Specialty coffee brewer and film photography lover.',
          interests: ['coffee', 'photography', 'art'],
          location: 'Bangalore',
        ),
        UserModel(
          id: 'cand_rohit',
          name: 'Rohit',
          email: 'rohit@test.com',
          age: 28,
          gender: 'male',
          bio: 'Software architect and marathon runner.',
          interests: ['tech', 'running', 'fitness'],
          location: 'Bangalore',
        ),
      ];

      matcher = VibeMatrixMatcher();
      contextManager = ConversationContextManager();
      modelManager = LocalModelManager();
    });

    test('1. Model Specs & ChatML / Gemma Template Formatting', () {
      const spec = ModelSpec.smollm2_135m;
      expect(spec.id, 'smollm2-135m-q4');
      expect(spec.quantization, 'Q4_K_M');
      expect(spec.tier, DeviceTier.low);

      final prompt = spec.formatChatPrompt(
        systemInstruction: 'You are Cupid Concierge.',
        history: [
          {'role': 'user', 'content': 'Hi'},
          {'role': 'assistant', 'content': 'Hello there!'}
        ],
        currentUtterance: 'Find someone who loves photography',
      );

      expect(prompt, contains('<|im_start|>system\nYou are Cupid Concierge.<|im_end|>'));
      expect(prompt, contains('<|im_start|>user\nHi<|im_end|>'));
      expect(prompt, contains('<|im_start|>assistant\nHello there!<|im_end|>'));
      expect(prompt, contains('<|im_start|>user\nFind someone who loves photography<|im_end|>'));
      expect(prompt, endsWith('<|im_start|>assistant\n'));
    });

    test('2. Device Capability Detection assigns hardware tiers', () async {
      final report = await DeviceCapabilityDetector.detect(forceRefresh: true);
      expect(report.estimatedRamMb, greaterThan(0));
      expect(report.processorCount, greaterThan(0));
      expect(report.recommendedModel, isNotNull);
      expect(report.reasoning, isNotEmpty);
    });

    test('3. Structured Tool Parsing extracts discover_profiles tool calls', () {
      const llmOutput = '''
I found some great vibes for you!
```tool_call
{
  "name": "discover_profiles",
  "arguments": {
    "interests": ["travel", "photography"],
    "relationshipIntent": "serious",
    "genderHint": "female"
  }
}
```
''';

      final toolCall = CupidTools.parseToolCall(llmOutput);
      expect(toolCall, isNotNull);
      expect(toolCall!.type, CupidToolType.discoverProfiles);
      expect(toolCall.arguments['interests'], ['travel', 'photography']);
      expect(toolCall.arguments['relationshipIntent'], 'serious');
      expect(toolCall.arguments['genderHint'], 'female');

      final cleanText = CupidTools.cleanToolCallMarkup(llmOutput);
      expect(cleanText, 'I found some great vibes for you!');
    });

    test('4. Orchestrator executes tool against real VibeMatrixMatcher and candidate pool', () async {
      final runtime = MockLocalLLMRuntime();
      await runtime.initialize(
        spec: ModelSpec.smollm2_135m,
        modelFilePath: 'mock_path.gguf',
      );

      // Simulate model deciding to invoke the profile discovery tool
      runtime.responseGenerator = (prompt) => '''
```tool_call
{
  "name": "discover_profiles",
  "arguments": {
    "interests": ["photography", "travel"],
    "genderHint": "female"
  }
}
```
''';

      final orchestrator = CupidLocalAIOrchestrator(
        runtime: runtime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: modelManager,
      );

      final result = await orchestrator.processTurn(
        userUtterance: 'Find me someone into photography and travelling',
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(result.executedTool, isNotNull);
      expect(result.executedTool!.name, 'discover_profiles');
      expect(result.matches.isNotEmpty, isTrue);

      // Tanya and Priya matched photography/travel
      final matchNames = result.matches.map((m) => m.candidate.name).toList();
      expect(matchNames, contains('Tanya'));
      expect(matchNames, isNot(contains('Rohit'))); // Rohit filtered out by gender/interests

      // Turn was recorded in context
      expect(contextManager.turnHistory.length, 1);
      expect(contextManager.criteria.interests, contains('photography'));
    });

    test('5. Multi-turn reasoning: follow-up refinement updates criteria incrementally', () async {
      final runtime = MockLocalLLMRuntime();
      await runtime.initialize(
        spec: ModelSpec.smollm2_135m,
        modelFilePath: 'mock_path.gguf',
      );

      final orchestrator = CupidLocalAIOrchestrator(
        runtime: runtime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: modelManager,
      );

      // Turn 1: Initial discovery
      runtime.responseGenerator = (prompt) => '''
```tool_call
{"name": "discover_profiles", "arguments": {"interests": ["photography"]}}
```
''';
      await orchestrator.processTurn(
        userUtterance: 'I want someone who loves photography',
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );
      expect(contextManager.criteria.interests, contains('photography'));

      // Turn 2: Preference Refinement
      runtime.responseGenerator = (prompt) => '''
```tool_call
{"name": "refine_search", "arguments": {"addedInterests": ["coffee"]}}
```
''';
      final result2 = await orchestrator.processTurn(
        userUtterance: 'and also coffee lovers',
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(result2.executedTool!.name, 'refine_search');
      expect(contextManager.criteria.interests, containsAll(['photography', 'coffee']));
      expect(result2.matches.first.candidate.name, 'Priya'); // Priya matches both photography & coffee
    });

    test('6. Casual conversation & emotional support generates direct empathetic dialogue without tools', () async {
      final runtime = MockLocalLLMRuntime();
      await runtime.initialize(
        spec: ModelSpec.smollm2_135m,
        modelFilePath: 'mock_path.gguf',
      );

      runtime.responseGenerator = (prompt) =>
          "Hey Kabir! Having a boring day is totally valid. Let's shake things up—want me to find someone spontaneous, or just chat through funny first date stories?";

      final orchestrator = CupidLocalAIOrchestrator(
        runtime: runtime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: modelManager,
      );

      final result = await orchestrator.processTurn(
        userUtterance: "Hey Cupid, I'm having a pretty boring day",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(result.executedTool, isNull);
      expect(result.matches.isEmpty, isTrue);
      expect(result.text, contains('Having a boring day is totally valid'));
      expect(contextManager.turnHistory.length, 1);
    });

    test('7. Strips private reasoning tokens (<think>...</think>) before presenting to user', () async {
      final runtime = MockLocalLLMRuntime();
      await runtime.initialize(
        spec: ModelSpec.smollm2_135m,
        modelFilePath: 'mock_path.gguf',
      );

      runtime.responseGenerator = (prompt) => '''
<think>
User is feeling discouraged about modern dating apps.
Need to provide empathetic reassurance without pushing match cards immediately.
</think>
Dating fatigue is real when conversations feel like interviews. Give yourself permission to take a breath! Genuine connections happen when you are relaxed.
''';

      final orchestrator = CupidLocalAIOrchestrator(
        runtime: runtime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: modelManager,
      );

      final result = await orchestrator.processTurn(
        userUtterance: "I'm so exhausted with dating apps",
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      expect(result.text, isNot(contains('<think>')));
      expect(result.text, isNot(contains('User is feeling discouraged')));
      expect(result.text, contains('Dating fatigue is real'));
    });

    test('8. Offline operation & SHA-256 integrity verification', () async {
      // Create temporary test file
      final tempDir = await Directory.systemTemp.createTemp('cupid_test_');
      final testFile = File('${tempDir.path}/test_model.bin');
      await testFile.writeAsString('SITUATIONSHIP_LOCAL_LLM_WEIGHTS_CONTENT');

      final digest = await sha256.bind(testFile.openRead()).first;
      final expectedHash = digest.toString();

      final isValid = await modelManager.verifyIntegrity(testFile, expectedHash);
      expect(isValid, isTrue);

      final isCorruptValid = await modelManager.verifyIntegrity(testFile, 'corrupt_hash_0000');
      expect(isCorruptValid, isFalse);

      await tempDir.delete(recursive: true);
    });

    test('9. Rejected profile tracking prevents re-recommending disliked candidates', () async {
      final runtime = MockLocalLLMRuntime();
      await runtime.initialize(
        spec: ModelSpec.smollm2_135m,
        modelFilePath: 'mock_path.gguf',
      );

      final orchestrator = CupidLocalAIOrchestrator(
        runtime: runtime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: modelManager,
      );

      // User rejects Tanya
      contextManager.rejectProfile('cand_tanya');
      expect(contextManager.isProfileRejected('cand_tanya'), isTrue);

      runtime.responseGenerator = (prompt) => '''
```tool_call
{"name": "discover_profiles", "arguments": {"interests": ["photography"]}}
```
''';

      final result = await orchestrator.processTurn(
        userUtterance: 'Find someone who loves photography',
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: {},
      );

      final matchNames = result.matches.map((m) => m.candidate.name).toList();
      // Tanya must be excluded because she was rejected by the user
      expect(matchNames, isNot(contains('Tanya')));
      // Priya remains eligible
      expect(matchNames, contains('Priya'));
    });

    test('10. Empty match results are reported honestly without fabricating profiles', () async {
      final runtime = MockLocalLLMRuntime();
      await runtime.initialize(
        spec: ModelSpec.smollm2_135m,
        modelFilePath: 'mock_path.gguf',
      );

      final orchestrator = CupidLocalAIOrchestrator(
        runtime: runtime,
        matcher: matcher,
        contextManager: contextManager,
        modelManager: modelManager,
      );

      runtime.responseGenerator = (prompt) => '''
```tool_call
{"name": "discover_profiles", "arguments": {"interests": ["deep_sea_diving", "astrophysics"]}}
```
''';

      // When candidate pool has no matching active members in community
      final result = await orchestrator.processTurn(
        userUtterance: 'Find someone into astrophysics and deep sea diving',
        currentUser: currentUser,
        candidatePool: const [],
        excludedUserIds: {},
      );

      expect(result.matches.isEmpty, isTrue);
      // Explains honestly that no active members matched
      expect(result.text, contains('didn\'t find an exact match'));
      expect(result.text, contains('widen our distance range'));
    });

    test('11. Privacy & memory cleanup: clearMemory clears all criteria and rejected history', () {
      contextManager.updateCriteria(const ExtractedEntities(interests: ['photography', 'hiking']));
      contextManager.rejectProfile('cand_tanya');

      expect(contextManager.criteria.interests.isNotEmpty, isTrue);
      expect(contextManager.rejectedProfileIds.isNotEmpty, isTrue);

      contextManager.clearMemory();

      expect(contextManager.criteria.isEmpty, isTrue);
      expect(contextManager.rejectedProfileIds.isEmpty, isTrue);
      expect(contextManager.turnHistory.isEmpty, isTrue);
    });
  });
}
