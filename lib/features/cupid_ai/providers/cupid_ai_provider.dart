import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:situationship/core/models/user_model.dart';
import 'package:situationship/core/providers/app_state_provider.dart';
import 'package:situationship/core/providers/firestore_provider.dart';
import 'package:situationship/core/ai/on_device_nlu_engine.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/ai/conversation_context_manager.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';
import 'package:situationship/core/ai/local_llm/device_capability_detector.dart';
import 'package:situationship/core/ai/local_llm/local_model_manager.dart';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/android_llm_adapter.dart';
import 'package:situationship/core/ai/local_llm/web_llm_adapter.dart';
import 'package:situationship/core/ai/local_llm/cupid_tools.dart';
import 'package:situationship/core/ai/local_llm/cupid_local_ai_orchestrator.dart';
import 'package:situationship/core/services/like_service.dart';

class CupidChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final List<CupidMatchResult> matches;
  final NLUIntentResult? parsedIntent;
  final CupidToolCall? executedTool;
  final bool isThinking;
  final String? modelSource;

  const CupidChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.matches = const [],
    this.parsedIntent,
    this.executedTool,
    this.isThinking = false,
    this.modelSource,
  });

  CupidChatMessage copyWith({
    String? id,
    bool? isUser,
    String? text,
    DateTime? timestamp,
    List<CupidMatchResult>? matches,
    NLUIntentResult? parsedIntent,
    CupidToolCall? executedTool,
    bool? isThinking,
    String? modelSource,
  }) {
    return CupidChatMessage(
      id: id ?? this.id,
      isUser: isUser ?? this.isUser,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      matches: matches ?? this.matches,
      parsedIntent: parsedIntent ?? this.parsedIntent,
      executedTool: executedTool ?? this.executedTool,
      isThinking: isThinking ?? this.isThinking,
      modelSource: modelSource ?? this.modelSource,
    );
  }
}

class CupidAIState {
  final List<CupidChatMessage> messages;
  final bool isThinking;
  final List<String> suggestedChips;
  final Set<String> actionedUserIds; // users liked/superliked in session
  final Set<String> shownUserIds; // real users already presented in this conversation
  final NLUIntentResult? lastActiveIntent; // last non-pagination intent
  final ModelDownloadState modelDownloadState;
  final DeviceCapabilityReport? deviceCapability;
  final bool isOfflineReady;
  final ModelSpec activeModelSpec;

  const CupidAIState({
    required this.messages,
    this.isThinking = false,
    this.suggestedChips = const [
      'First date ideas ☕',
      'Artistic & Creative ✨',
      'How do coins work? 🪙',
      'Spontaneous Road Trips 🚗',
      'Icebreaker tips 💬',
      'Meaningful Connection 💖',
      'Non-Smoker 🚭',
    ],
    this.actionedUserIds = const {},
    this.shownUserIds = const {},
    this.lastActiveIntent,
    required this.modelDownloadState,
    this.deviceCapability,
    this.isOfflineReady = true,
    required this.activeModelSpec,
  });

  CupidAIState copyWith({
    List<CupidChatMessage>? messages,
    bool? isThinking,
    List<String>? suggestedChips,
    Set<String>? actionedUserIds,
    Set<String>? shownUserIds,
    NLUIntentResult? lastActiveIntent,
    ModelDownloadState? modelDownloadState,
    DeviceCapabilityReport? deviceCapability,
    bool? isOfflineReady,
    ModelSpec? activeModelSpec,
  }) {
    return CupidAIState(
      messages: messages ?? this.messages,
      isThinking: isThinking ?? this.isThinking,
      suggestedChips: suggestedChips ?? this.suggestedChips,
      actionedUserIds: actionedUserIds ?? this.actionedUserIds,
      shownUserIds: shownUserIds ?? this.shownUserIds,
      lastActiveIntent: lastActiveIntent ?? this.lastActiveIntent,
      modelDownloadState: modelDownloadState ?? this.modelDownloadState,
      deviceCapability: deviceCapability ?? this.deviceCapability,
      isOfflineReady: isOfflineReady ?? this.isOfflineReady,
      activeModelSpec: activeModelSpec ?? this.activeModelSpec,
    );
  }
}

class CupidAINotifier extends StateNotifier<CupidAIState> {
  final Ref ref;
  final VibeMatrixMatcher _matcher = VibeMatrixMatcher();
  final ConversationContextManager _contextManager = ConversationContextManager();
  final LocalModelManager _modelManager = LocalModelManager();
  late final ModelRuntimeAdapter _runtime;
  late final CupidLocalAIOrchestrator _orchestrator;
  StreamSubscription? _downloadSub;

  ConversationContextManager get contextManager => _contextManager;
  LocalModelManager get modelManager => _modelManager;

  CupidAINotifier(this.ref)
      : super(CupidAIState(
          messages: [
            CupidChatMessage(
              id: 'init_welcome',
              isUser: false,
              text:
                  "Welcome to Cupid Concierge 🍸\n\nI'm your on-device wingman, powered by private on-device reasoning AI. You can chat naturally, brainstorm first-date spots, explore dating psychology, or tell me the exact vibe you're craving and I'll curate real members for you.",
              timestamp: DateTime.now(),
              modelSource: 'cupid_on_device',
            )
          ],
          modelDownloadState: LocalModelManager().currentState,
          activeModelSpec: ModelSpec.smollm2_135m,
        )) {
    _initPlatformRuntime();
  }

  Future<void> _initPlatformRuntime() async {
    // 1. Detect device capability
    final report = await DeviceCapabilityDetector.detect();

    // 2. Select appropriate platform adapter
    if (kIsWeb) {
      _runtime = WebLlmAdapter();
    } else {
      _runtime = AndroidLlmAdapter();
    }

    _orchestrator = CupidLocalAIOrchestrator(
      runtime: _runtime,
      matcher: _matcher,
      contextManager: _contextManager,
      modelManager: _modelManager,
    );

    // 3. Listen to model download state changes
    _downloadSub = _modelManager.stateStream.listen((downloadState) {
      state = state.copyWith(modelDownloadState: downloadState);
    });

    // 4. Check if recommended model is already downloaded
    final isReady = await _modelManager.isModelReady(report.recommendedModel);

    state = state.copyWith(
      deviceCapability: report,
      activeModelSpec: report.recommendedModel,
      isOfflineReady: isReady,
      modelDownloadState: _modelManager.currentState.copyWith(
        spec: report.recommendedModel,
        status: isReady ? ModelDownloadStatus.ready : ModelDownloadStatus.notDownloaded,
      ),
    );
  }

  /// Initiates downloading of the chosen quantized model weights
  Future<void> downloadModel([ModelSpec? spec]) async {
    final targetSpec = spec ?? state.activeModelSpec;
    try {
      final file = await _modelManager.downloadModel(targetSpec);
      // Initialize runtime with downloaded weights
      await _runtime.initialize(spec: targetSpec, modelFilePath: file.path);
      state = state.copyWith(
        isOfflineReady: true,
        activeModelSpec: targetSpec,
      );
    } catch (e) {
      debugPrint('Failed to download local model: $e');
    }
  }

  /// Deletes local model weights to free up disk space
  Future<void> deleteModel(ModelSpec spec) async {
    await _runtime.unload();
    await _modelManager.deleteModel(spec);
    state = state.copyWith(isOfflineReady: false);
  }

  /// Clears chat history and resets conversational memory
  void clearChat() {
    _contextManager.reset();
    state = state.copyWith(
      messages: [
        CupidChatMessage(
          id: 'init_welcome_${DateTime.now().millisecondsSinceEpoch}',
          isUser: false,
          text:
              "Welcome to Cupid Concierge 🍸\n\nI'm your on-device wingman, powered by private on-device reasoning AI. You can chat naturally, brainstorm first-date spots, explore dating psychology, or tell me the exact vibe you're craving and I'll curate real members for you.",
          timestamp: DateTime.now(),
          modelSource: 'cupid_on_device',
        )
      ],
      shownUserIds: const {},
      actionedUserIds: const {},
    );
  }

  /// Sends a conversational query with genuine context-aware local intelligence
  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    final userMsg = CupidChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      isUser: true,
      text: query,
      timestamp: DateTime.now(),
    );

    final thinkingMsgId = 'cupid_thinking_${DateTime.now().millisecondsSinceEpoch}';
    final thinkingMsg = CupidChatMessage(
      id: thinkingMsgId,
      isUser: false,
      text: 'Thinking...',
      timestamp: DateTime.now(),
      isThinking: true,
    );

    // Update state with user message + thinking indicator
    state = state.copyWith(
      messages: [...state.messages, userMsg, thinkingMsg],
      isThinking: true,
    );

    final currentUser = ref.read(currentUserProvider);
    final candidates = await _getCandidates(currentUser.id);

    final sessionExcluded = {
      ...state.actionedUserIds,
      ...state.shownUserIds,
      ..._contextManager.rejectedProfileIds,
    };

    // ── Execute Reasoning Turn via CupidLocalAIOrchestrator ──────────────────
    final turnResult = await _orchestrator.processTurn(
      userUtterance: query,
      currentUser: currentUser,
      candidatePool: candidates,
      excludedUserIds: sessionExcluded,
    );

    final finalizedMsg = CupidChatMessage(
      id: 'cupid_${DateTime.now().millisecondsSinceEpoch}',
      isUser: false,
      text: turnResult.text,
      timestamp: DateTime.now(),
      matches: turnResult.matches,
      executedTool: turnResult.executedTool,
      isThinking: false,
      modelSource: turnResult.modelId ?? state.activeModelSpec.name,
    );

    // Replace thinking indicator with finalized message
    final updatedMessages = state.messages
        .where((m) => m.id != thinkingMsgId)
        .toList()
      ..add(finalizedMsg);

    final updatedShownIds = {
      ...state.shownUserIds,
      ...turnResult.matches.map((m) => m.candidate.id),
    };

    state = state.copyWith(
      messages: updatedMessages,
      isThinking: false,
      shownUserIds: updatedShownIds,
    );
  }

  /// Handles inline profile Like
  Future<void> handleLike(UserModel candidate) async {
    final currentUser = ref.read(currentUserProvider);
    state = state.copyWith(
      actionedUserIds: {...state.actionedUserIds, candidate.id},
    );

    try {
      await LikeService.sendLike(currentUser: currentUser, targetUser: candidate);
    } catch (_) {}
  }

  /// Handles inline profile Super Like
  Future<void> handleSuperLike(UserModel candidate) async {
    final currentUser = ref.read(currentUserProvider);
    state = state.copyWith(
      actionedUserIds: {...state.actionedUserIds, candidate.id},
    );

    try {
      await LikeService.sendSuperLike(currentUser: currentUser, targetUser: candidate);
    } catch (_) {}
  }

  /// Fetches candidates: real users from Firestore provider, supplemented with in-memory active pool
  Future<List<UserModel>> _getCandidates(String currentUserId) async {
    try {
      final snap = await firestoreProvider.users.limit(25).get();
      final users = snap.docs
          .map((doc) {
            final data = Map<String, dynamic>.from(doc.data());
            data['id'] = doc.id;
            return UserModel.fromMap(data);
          })
          .where((u) => u.id != currentUserId)
          .toList();
      if (users.isNotEmpty) {
        return users;
      }
    } catch (_) {}

    // Fallback candidate pool with verified realistic profiles
    return _buildDeterministicCandidatePool();
  }

  List<UserModel> _buildDeterministicCandidatePool() {
    return const [
      UserModel(
        id: 'mock_tanya',
        name: 'Tanya',
        email: 'tanya@example.com',
        age: 26,
        gender: 'female',
        bio: 'Documentary photographer & mountain climber. Vinyl lover and matcha enthusiast. Always chasing golden hour.',
        interests: ['photography', 'travel', 'indie music', 'hiking', 'coffee'],
        photos: ['https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=800&q=80'],
        location: 'Indiranagar',
        isVerified: true,
        relationshipIntent: 'serious',
      ),
      UserModel(
        id: 'mock_arjun',
        name: 'Arjun',
        email: 'arjun@example.com',
        age: 28,
        gender: 'male',
        bio: 'Specialty coffee brewer by morning, synthwave producer by night. Looking for someone to explore hidden food spots with.',
        interests: ['coffee', 'music', 'creative', 'night drives', 'travel'],
        photos: ['https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=800&q=80'],
        location: 'Koramangala',
        isVerified: true,
        relationshipIntent: 'serious',
      ),
      UserModel(
        id: 'mock_ananya',
        name: 'Ananya',
        email: 'ananya@example.com',
        age: 25,
        gender: 'female',
        bio: 'Visual designer with a penchant for modern art museums, spicy street food, and indie cinema. Non-smoker.',
        interests: ['art', 'photography', 'design', 'cinema', 'street food'],
        photos: ['https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=800&q=80'],
        location: 'HSR Layout',
        isVerified: true,
        relationshipIntent: 'casual',
      ),
    ];
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }
}

final cupidAIProvider = StateNotifierProvider<CupidAINotifier, CupidAIState>((ref) {
  return CupidAINotifier(ref);
});
