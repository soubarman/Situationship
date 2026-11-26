import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:situationship/core/models/user_model.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/core/ai/conversation_context_manager.dart';
import 'package:situationship/core/ai/on_device_nlu_engine.dart';
import 'package:situationship/core/ai/conversational_intent.dart';
import 'package:situationship/core/ai/conversational_dialogue_engine.dart';
import 'package:situationship/core/ai/structured_conversation_state.dart';
import 'package:situationship/core/ai/context_aware_speech_act_interpreter.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/cupid_tools.dart';
import 'package:situationship/core/ai/local_llm/local_model_manager.dart';

/// Result produced by a single conversational reasoning turn
class CupidTurnResult {
  final String text;
  final List<CupidMatchResult> matches;
  final CupidToolCall? executedTool;
  final bool isOfflineReady;
  final String? modelId;

  const CupidTurnResult({
    required this.text,
    this.matches = const [],
    this.executedTool,
    this.isOfflineReady = true,
    this.modelId,
  });
}

/// Orchestrator for on-device reasoning AI.
/// Connects local LLM streaming inference, deterministic tool validation, and Situationship matching services.
class CupidLocalAIOrchestrator {
  final ModelRuntimeAdapter runtime;
  final VibeMatrixMatcher matcher;
  final ConversationContextManager contextManager;
  final LocalModelManager modelManager;

  CupidLocalAIOrchestrator({
    required this.runtime,
    required this.matcher,
    required this.contextManager,
    required this.modelManager,
  });

  /// Processes user utterance with real on-device model reasoning and deterministic tool execution
  Future<CupidTurnResult> processTurn({
    required String userUtterance,
    required UserModel currentUser,
    required List<UserModel> candidatePool,
    required Set<String> excludedUserIds,
  }) async {
    final query = userUtterance.trim();
    if (query.isEmpty) {
      return const CupidTurnResult(text: "I'm listening! Tell me what's on your mind.");
    }

    // 1. Check if model is initialized and ready
    if (!runtime.isModelLoaded) {
      // Fallback: If local model weights are still downloading or not loaded,
      // use the deterministic semantic engine seamlessly so the user is never blocked.
      return _runSemanticFallback(
        userUtterance: query,
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: excludedUserIds,
      );
    }

    final activeSpec = runtime.loadedSpec ?? ModelSpec.smollm2_135m;

    // 2. Format multi-turn conversation history for the model
    final history = <Map<String, String>>[];
    for (final turn in contextManager.turnHistory.take(6)) {
      history.add({'role': 'user', 'content': turn.userUtterance});
      history.add({'role': 'assistant', 'content': turn.assistantReply});
    }

    final prompt = activeSpec.formatChatPrompt(
      systemInstruction: CupidTools.getSystemPrompt(),
      history: history,
      currentUtterance: query,
    );

    // 3. Execute local LLM inference
    String rawOutput;
    try {
      rawOutput = await runtime.generate(prompt, maxTokens: 256, temperature: 0.7);
    } catch (e) {
      debugPrint('Local LLM inference error: $e');
      return _runSemanticFallback(
        userUtterance: query,
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: excludedUserIds,
      );
    }

    // Strip private thinking/scratchpad tokens (never expose internal reasoning)
    final sanitizedOutput = _stripScratchpadTokens(rawOutput);

    // Contextual semantic interpretation of the turn
    final interpretation = ContextAwareSpeechActInterpreter.interpret(
      query,
      contextManager: contextManager,
    );

    // Parse for structured tool call
    final toolCall = CupidTools.parseToolCall(sanitizedOutput);

    if (toolCall != null) {
      // Strict Decision Gate for Tool Calling:
      // Verify discoverProfiles is ONLY permitted if user explicitly requested discovery
      if (toolCall.type == CupidToolType.discoverProfiles && !interpretation.isExplicitDiscoveryRequest) {
        debugPrint('[DecisionGate] Premature discover_profiles tool call blocked; user did not request search.');
        return _runSemanticFallback(
          userUtterance: query,
          currentUser: currentUser,
          candidatePool: candidatePool,
          excludedUserIds: excludedUserIds,
        );
      }

      return _executeTool(
        toolCall: toolCall,
        currentUser: currentUser,
        candidatePool: candidatePool,
        excludedUserIds: excludedUserIds,
        userUtterance: query,
        modelId: activeSpec.id,
      );
    }

    // Direct conversational response (casual banter, empathy, advice without tool)
    final cleanReply = CupidTools.cleanToolCallMarkup(sanitizedOutput);
    final finalReply = cleanReply.isNotEmpty
        ? cleanReply
        : "I hear you! Tell me what kind of energy or connection you're hoping to discover today.";

    // Apply interpretation preferences to conversational memory
    if (interpretation.isCorrection) {
      for (final p in interpretation.extractedPreferences) {
        contextManager.correctStructuredPreference(p);
      }
    } else {
      for (final p in interpretation.extractedPreferences) {
        if (p.scope == PreferenceScope.datingRequirement) {
          contextManager.addStructuredPreference(p);
        }
      }
    }

    // Record turn in context memory
    contextManager.recordTurn(
      userUtterance: query,
      classification: IntentClassificationResult(
        intent: ConversationalIntent.casualChat,
        confidence: 0.95,
        entities: const ExtractedEntities(),
        originalQuery: query,
      ),
      assistantReply: finalReply,
      interpretation: interpretation,
    );

    return CupidTurnResult(
      text: finalReply,
      matches: const [],
      executedTool: null,
      isOfflineReady: true,
      modelId: activeSpec.id,
    );
  }

  /// Deterministically executes a tool call against Situationship matching and domain services
  Future<CupidTurnResult> _executeTool({
    required CupidToolCall toolCall,
    required UserModel currentUser,
    required List<UserModel> candidatePool,
    required Set<String> excludedUserIds,
    required String userUtterance,
    required String modelId,
  }) async {
    switch (toolCall.type) {
      case CupidToolType.discoverProfiles:
        final interests = (toolCall.arguments['interests'] as List?)?.cast<String>() ?? [];
        final traits = (toolCall.arguments['personalityTraits'] as List?)?.cast<String>() ?? [];
        final dealbreakers = (toolCall.arguments['dealbreakers'] as List?)?.cast<String>() ?? [];
        final intent = toolCall.arguments['relationshipIntent'] as String?;
        final gender = toolCall.arguments['genderHint'] as String?;
        final minAge = toolCall.arguments['minAge'] as int?;
        final maxAge = toolCall.arguments['maxAge'] as int?;

        final entities = ExtractedEntities(
          interests: interests,
          personalityTraits: traits,
          dealbreakers: dealbreakers,
          relationshipIntent: intent,
          genderHint: gender,
          minAge: minAge,
          maxAge: maxAge,
        );

        contextManager.updateCriteria(entities);

        final effectiveExcluded = {...excludedUserIds, ...contextManager.rejectedProfileIds};

        final nluIntent = NLUIntentResult(
          originalQuery: userUtterance,
          denseVector: {for (final i in interests) i: 1.0},
          detectedDimensionIds: interests,
          dealbreakers: dealbreakers,
          targetRelationshipIntent: intent,
          genderHint: gender,
          extractedKeywords: [...interests, ...traits],
          naturalSummary: contextManager.criteria.naturalSummary(),
          conversationalIntent: ConversationalIntent.profileDiscovery,
          classification: IntentClassificationResult(
            intent: ConversationalIntent.profileDiscovery,
            confidence: 0.95,
            entities: entities,
            originalQuery: userUtterance,
          ),
        );

        final matches = matcher.findMatches(
          currentUser: currentUser,
          candidates: candidatePool,
          intent: nluIntent,
          excludedIds: effectiveExcluded,
          limit: 3,
        );

        final summary = contextManager.criteria.naturalSummary();
        final reply = _synthesizeMatchReply(matches, summary);

        contextManager.recordTurn(
          userUtterance: userUtterance,
          classification: IntentClassificationResult(
            intent: ConversationalIntent.profileDiscovery,
            confidence: 0.95,
            entities: entities,
            originalQuery: userUtterance,
          ),
          assistantReply: reply,
          newMatches: matches,
        );

        return CupidTurnResult(
          text: reply,
          matches: matches,
          executedTool: toolCall,
          isOfflineReady: true,
          modelId: modelId,
        );

      case CupidToolType.refineSearch:
        final addedInterests = (toolCall.arguments['addedInterests'] as List?)?.cast<String>() ?? [];
        final addedTraits = (toolCall.arguments['addedTraits'] as List?)?.cast<String>() ?? [];
        final addedDealbreakers = (toolCall.arguments['addedDealbreakers'] as List?)?.cast<String>() ?? [];

        final entities = ExtractedEntities(
          interests: addedInterests,
          personalityTraits: addedTraits,
          dealbreakers: addedDealbreakers,
        );

        contextManager.updateCriteria(entities);

        final effectiveExcluded = {...excludedUserIds, ...contextManager.rejectedProfileIds};

        final matches = matcher.findMatches(
          currentUser: currentUser,
          candidates: candidatePool,
          intent: NLUIntentResult(
            originalQuery: userUtterance,
            denseVector: {for (final i in contextManager.criteria.interests) i: 1.0},
            detectedDimensionIds: contextManager.criteria.interests.toList(),
            dealbreakers: contextManager.criteria.dealbreakers.toList(),
            targetRelationshipIntent: contextManager.criteria.relationshipIntent,
            genderHint: contextManager.criteria.genderHint,
            extractedKeywords: contextManager.criteria.interests.toList(),
            naturalSummary: contextManager.criteria.naturalSummary(),
            conversationalIntent: ConversationalIntent.preferenceRefinement,
            classification: IntentClassificationResult(
              intent: ConversationalIntent.preferenceRefinement,
              confidence: 0.95,
              entities: entities,
              originalQuery: userUtterance,
            ),
          ),
          excludedIds: effectiveExcluded,
          limit: 3,
        );

        final summary = contextManager.criteria.naturalSummary();
        final reply = _synthesizeRefinedMatchReply(matches, summary);

        contextManager.recordTurn(
          userUtterance: userUtterance,
          classification: IntentClassificationResult(
            intent: ConversationalIntent.preferenceRefinement,
            confidence: 0.95,
            entities: entities,
            originalQuery: userUtterance,
          ),
          assistantReply: reply,
          newMatches: matches,
        );

        return CupidTurnResult(
          text: reply,
          matches: matches,
          executedTool: toolCall,
          isOfflineReady: true,
          modelId: modelId,
        );

      case CupidToolType.getProfileDetails:
        final profileName = toolCall.arguments['profileName'] as String?;
        final targetMatch = contextManager.resolveProfileReference(
          ExtractedEntities(referencedProfileName: profileName),
        );

        if (targetMatch != null) {
          final c = targetMatch.candidate;
          final reply =
              "${c.name} (${c.age}) stood out because of their shared passions. Here is their vibe: '${c.bio ?? 'Genuine energy and great compatibility.'}' Would you like to send them a like?";
          return CupidTurnResult(
            text: reply,
            matches: [targetMatch],
            executedTool: toolCall,
            isOfflineReady: true,
            modelId: modelId,
          );
        } else {
          return const CupidTurnResult(
            text: 'Which profile were you curious about? Tell me their name or which recommendation caught your attention!',
          );
        }

      case CupidToolType.appFeatureInfo:
        final feature = toolCall.arguments['feature'] as String? ?? 'general';
        final reply = _getFeatureExplanation(feature);
        return CupidTurnResult(
          text: reply,
          matches: const [],
          executedTool: toolCall,
          isOfflineReady: true,
          modelId: modelId,
        );

      case CupidToolType.datingAdvice:
      case CupidToolType.askClarification:
        final clean = CupidTools.cleanToolCallMarkup(userUtterance);
        return CupidTurnResult(
          text: clean.isNotEmpty ? clean : 'Tell me a little more about what you value in a connection!',
          matches: const [],
          executedTool: toolCall,
          isOfflineReady: true,
          modelId: modelId,
        );
    }
  }

  /// Strips internal reasoning scratchpads (`<think>...</think>`) from LLM outputs
  static String _stripScratchpadTokens(String text) {
    return text
        .replaceAll(RegExp(r'<think>[\s\S]*?<\/think>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<thought>[\s\S]*?<\/thought>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<reasoning>[\s\S]*?<\/reasoning>', caseSensitive: false), '')
        .trim();
  }

  String _getFeatureExplanation(String feature) {
    switch (feature) {
      case 'coins':
        return 'Coins unlock premium perks on Situationship, like Super Likes, Rewinds, and Spotlight boosts. You can earn free coins through daily logins and genuine interactions, or top up in your Wallet.';
      case 'confession':
        return 'Anonymous Confessions allow you to post unfiltered thoughts or crush notes in your community. Members can interact with your confession without seeing your profile unless you choose to reveal yourself.';
      case 'spotlight':
        return 'Spotlight is your local visibility booster. When activated, your profile is prioritized at the very top of the Discovery radar for everyone nearby in your city.';
      case 'verification':
        return 'The Verified S-Badge confirms that a member is 100% authentic and matches their photos. You can complete verification in your profile by recording a quick gesture challenge.';
      default:
        return 'Situationship is designed for genuine chemistry without traditional dating app friction. We feature pure on-device matching, video/photo verification, anonymous confessions, and privacy-first connections.';
    }
  }

  /// Synthesizes dynamic, personalized response grounded in real candidate data
  String _synthesizeMatchReply(List<CupidMatchResult> matches, String summary) {
    if (matches.isEmpty) {
      return 'I searched our community for members matching $summary, but didn\'t find an exact match nearby right now. Would you like me to widen our distance range or explore another interest you love?';
    }

    if (matches.length == 1) {
      final m = matches.first;
      final traits = m.highlightTraits.take(2).join(' and ');
      return 'I found a great connection! ${m.candidate.name} (${m.candidate.age}) stands out with shared passions for ${traits.isNotEmpty ? traits : summary}. Take a look at their profile:';
    }

    final names = matches.map((m) => '${m.candidate.name} (${m.candidate.age})').join(' and ');
    final sharedInterests = matches.first.highlightTraits.take(2).join(' & ');
    return 'Found standout members who match your $summary wavelength! Here are $names, connected by ${sharedInterests.isNotEmpty ? sharedInterests : summary}. Tell me who catches your eye:';
  }

  /// Synthesizes refined match response acknowledging progressive preferences
  String _synthesizeRefinedMatchReply(List<CupidMatchResult> matches, String summary) {
    if (matches.isEmpty) {
      return 'I updated your preferences to include $summary, but no active profiles matched all those combined criteria yet. Would you like to keep searching with a wider radius?';
    }

    final names = matches.map((m) => '${m.candidate.name} (${m.candidate.age})').join(' and ');
    return 'Refined your search to include $summary. Here are $names who best align with your updated vibe:';
  }

  /// Instant local deterministic conversational engine driven by Context-Aware Interpretation
  CupidTurnResult _runSemanticFallback({
    required String userUtterance,
    required UserModel currentUser,
    required List<UserModel> candidatePool,
    required Set<String> excludedUserIds,
  }) {
    // 1. Run contextual interpretation considering surrounding turns and questions
    final cleanUtterance = userUtterance.toLowerCase();
    if (cleanUtterance.contains('reset') ||
        cleanUtterance.contains('start over') ||
        cleanUtterance.contains('clear chat') ||
        cleanUtterance.contains('clear criteria') ||
        cleanUtterance.contains('forget everything')) {
      contextManager.reset();
      return const CupidTurnResult(
        text: "I've reset our conversation context! Tell me fresh: what kind of person or vibe are you in the mood to discover?",
        matches: [],
        executedTool: null,
        isOfflineReady: true,
        modelId: 'semantic_fast_engine',
      );
    }

    final interpretation = ContextAwareSpeechActInterpreter.interpret(
      userUtterance,
      contextManager: contextManager,
    );

    // 2. Process preferences, corrections, and profile rejections
    if (interpretation.isCorrection) {
      if (cleanUtterance.contains('scratch that') || cleanUtterance.contains('no nightlife')) {
        contextManager.structuredState.preferences.removeWhere((p) => p.value == 'nightlife');
      }
      if (cleanUtterance.contains('not clubbing') || cleanUtterance.contains('instead of clubbing')) {
        contextManager.structuredState.preferences.removeWhere((p) => p.value == 'clubbing');
      }
      if (cleanUtterance.contains('never mind') || cleanUtterance.contains('nevermind')) {
        contextManager.structuredState.preferences.removeWhere((p) => p.category == 'dealbreaker' && cleanUtterance.contains(p.value));
      }
      for (final pref in interpretation.extractedPreferences) {
        contextManager.correctStructuredPreference(
          pref,
          oldCategory: (pref.category == 'demographic' || pref.category == 'gender') ? pref.category : null,
        );
      }
      contextManager.syncCriteria();
    } else {
      for (final pref in interpretation.extractedPreferences) {
        if (pref.scope == PreferenceScope.datingRequirement) {
          contextManager.addStructuredPreference(pref);
        }
      }
    }

    if (interpretation.speechAct == SpeechAct.rejectingProfile) {
      bool rejectedSpecific = false;
      for (final m in contextManager.lastRecommendedMatches) {
        if (cleanUtterance.contains(m.candidate.name.toLowerCase())) {
          contextManager.rejectProfile(m.candidate.id);
          rejectedSpecific = true;
        }
      }
      if (!rejectedSpecific) {
        for (final m in contextManager.lastRecommendedMatches) {
          contextManager.rejectProfile(m.candidate.id);
        }
      }
    }

    // 3. Strict Action Decision Gate: ONLY search when explicit discovery is requested
    List<CupidMatchResult> matches = const [];
    if (interpretation.isExplicitDiscoveryRequest) {
      for (final pref in interpretation.extractedPreferences) {
        contextManager.addStructuredPreference(pref);
      }

      final hasSufficientCriteria = !contextManager.criteria.isEmpty || interpretation.extractedPreferences.isNotEmpty;
      if (!hasSufficientCriteria) {
        // Implied/indirect discovery request without prior criteria: prompt for partner vibe first
        contextManager.setAssistantQuestion(
          "What kind of vibe or energy do you usually connect with best?",
          ExpectedAnswerType.partnerTrait,
          topic: ConversationTopic.dating,
        );
        final askReply = "I'd love to introduce you to someone great! Before I search, tell me what kind of person, vibe, or shared passions you're looking for.";
        contextManager.recordTurn(
          userUtterance: userUtterance,
          classification: IntentClassificationResult(
            intent: ConversationalIntent.profileDiscovery,
            confidence: 0.95,
            entities: const ExtractedEntities(),
            originalQuery: userUtterance,
          ),
          assistantReply: askReply,
          newMatches: const [],
          interpretation: interpretation,
        );
        return CupidTurnResult(
          text: askReply,
          matches: const [],
          executedTool: null,
          isOfflineReady: true,
          modelId: 'semantic_fast_engine',
        );
      }

      final effectiveExcluded = {...excludedUserIds, ...contextManager.rejectedProfileIds};
      final summaryText = contextManager.criteria.naturalSummary();
      final nluResult = OnDeviceNLUEngine.parse(
        summaryText.isNotEmpty ? summaryText : userUtterance,
      );

      matches = matcher.findMatches(
        currentUser: currentUser,
        candidates: candidatePool,
        intent: NLUIntentResult(
          originalQuery: userUtterance,
          denseVector: nluResult.denseVector.isNotEmpty
              ? nluResult.denseVector
              : {for (final i in contextManager.criteria.interests) i: 1.0},
          detectedDimensionIds: nluResult.detectedDimensionIds.isNotEmpty
              ? nluResult.detectedDimensionIds
              : contextManager.criteria.interests.toList(),
          dealbreakers: contextManager.criteria.dealbreakers.toList(),
          targetRelationshipIntent: contextManager.criteria.relationshipIntent,
          genderHint: contextManager.criteria.genderHint,
          extractedKeywords: contextManager.criteria.interests.toList(),
          naturalSummary: summaryText,
          conversationalIntent: ConversationalIntent.profileDiscovery,
        ),
        excludedIds: effectiveExcluded,
        limit: 3,
      );

      // If specific criteria were requested, ensure candidates actually match or have non-zero cosine
      if (contextManager.criteria.interests.isNotEmpty &&
          !matches.any((m) =>
              m.rawCosine > 0.0 ||
              m.candidate.interests.any((i) =>
                  contextManager.criteria.interests.any((c) =>
                      i.toLowerCase().contains(c.toLowerCase()) ||
                      c.toLowerCase().contains(i.toLowerCase()))))) {
        matches = const [];
      }
    }

    // 4. Generate response via Dialogue Policy
    final reply = ConversationalDialogueEngine.generateResponse(
      classification: IntentClassificationResult(
        intent: interpretation.isExplicitDiscoveryRequest
            ? ConversationalIntent.profileDiscovery
            : (interpretation.speechAct == SpeechAct.expressingEmotion
                ? ConversationalIntent.emotionalSupport
                : (interpretation.speechAct == SpeechAct.askingQuestion
                    ? ConversationalIntent.datingAdvice
                    : ConversationalIntent.casualChat)),
        confidence: interpretation.confidence,
        entities: ExtractedEntities(
          interests: contextManager.criteria.interests.toList(),
          personalityTraits: contextManager.criteria.personalityTraits.toList(),
          dealbreakers: contextManager.criteria.dealbreakers.toList(),
          genderHint: contextManager.criteria.genderHint,
          relationshipIntent: contextManager.criteria.relationshipIntent,
        ),
        originalQuery: userUtterance,
      ),
      contextManager: contextManager,
      currentUser: currentUser,
      matches: matches,
      totalCandidatesAvailable: matches.length,
      interpretation: interpretation,
    );

    // 5. Record turn
    contextManager.recordTurn(
      userUtterance: userUtterance,
      classification: IntentClassificationResult(
        intent: interpretation.isExplicitDiscoveryRequest
            ? ConversationalIntent.profileDiscovery
            : (interpretation.speechAct == SpeechAct.rejectingProfile
                ? ConversationalIntent.profileFeedback
                : ConversationalIntent.casualChat),
        confidence: interpretation.confidence,
        entities: const ExtractedEntities(),
        originalQuery: userUtterance,
      ),
      assistantReply: reply,
      newMatches: matches,
      interpretation: interpretation,
    );

    return CupidTurnResult(
      text: reply,
      matches: matches,
      executedTool: null,
      isOfflineReady: true,
      modelId: 'semantic_fast_engine',
    );
  }
}
