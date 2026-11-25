import 'vibe_matrix_matcher.dart';

/// Broad speech acts representing the pragmatic intent of an utterance in dialogue
enum SpeechAct {
  /// Answering an outstanding question asked by the assistant
  answering,

  /// Asking a question (advice, app feature, profile detail)
  askingQuestion,

  /// Requesting an explicit application action (e.g. search profiles, clear chat)
  requestingAction,

  /// Correcting or refining a previously stated preference
  correctingPreference,

  /// Rejecting a recommended candidate or suggested preference
  rejectingProfile,

  /// Sharing personal emotions, feelings, or state of mind (boredom, loneliness, burnout)
  expressingEmotion,

  /// Explicitly changing the conversational topic ("let's talk about music instead")
  changingTopic,

  /// Acknowledging or agreeing with the assistant ("sounds good", "cool", "okay")
  acknowledging,

  /// Light casual banter, greeting, small talk, or jokes
  casualBanter,
}

/// The core topic of the ongoing conversational discourse
enum ConversationTopic {
  general,
  humour,
  dating,
  travel,
  photography,
  music,
  lifestyle,
  emotionalSupport,
  appFeatures,
  outOfDomain,
}

/// Dialogue stage of the conversational interaction
enum DialogueStage {
  greeting,
  rapportBuilding,
  preferenceExploration,
  discoveryReady,
  evaluatingMatches,
  providingAdvice,
  providingSupport,
}

/// Polarity of an extracted preference
enum PreferencePolarity {
  positive,
  negative,
  neutral,
}

/// Scope of a preference to distinguish dating requirements from personal hobbies
enum PreferenceScope {
  /// A requirement or strong preference for a prospective partner
  datingRequirement,

  /// A personal interest or activity enjoyed by the user themselves
  personalInterest,

  /// A temporary or passing topic in conversation
  temporaryTopic,

  /// A hypothetical musing or tentative thought
  hypothetical,
}

/// Expected answer type to the assistant's previous question
enum ExpectedAnswerType {
  none,
  humourStyle,
  musicGenre,
  hobbyOrPassion,
  datingGoal,
  partnerTrait,
  confirmation,
}

/// Specific pending action waiting for user confirmation
enum PendingAppAction {
  none,
  confirmDiscovery,
  confirmRefinement,
  viewProfileDetails,
}

/// A structured, validated user preference
class UserDatingPreference {
  final String category; // 'humour', 'travel', 'photography', 'music', 'lifestyle', 'personality', etc.
  final String value;    // e.g. 'sarcasm', 'outdoor road trips', 'analog 35mm'
  final PreferencePolarity polarity;
  final PreferenceScope scope;
  final double confidence;
  final int sourceTurn;
  final bool isExplicitlyConfirmed;

  const UserDatingPreference({
    required this.category,
    required this.value,
    this.polarity = PreferencePolarity.positive,
    this.scope = PreferenceScope.datingRequirement,
    this.confidence = 0.9,
    this.sourceTurn = 0,
    this.isExplicitlyConfirmed = false,
  });

  UserDatingPreference copyWith({
    String? category,
    String? value,
    PreferencePolarity? polarity,
    PreferenceScope? scope,
    double? confidence,
    int? sourceTurn,
    bool? isExplicitlyConfirmed,
  }) {
    return UserDatingPreference(
      category: category ?? this.category,
      value: value ?? this.value,
      polarity: polarity ?? this.polarity,
      scope: scope ?? this.scope,
      confidence: confidence ?? this.confidence,
      sourceTurn: sourceTurn ?? this.sourceTurn,
      isExplicitlyConfirmed: isExplicitlyConfirmed ?? this.isExplicitlyConfirmed,
    );
  }
}

/// Rich semantic interpretation of an incoming user utterance
class ConversationInterpretation {
  final String originalUtterance;
  final SpeechAct speechAct;
  final ConversationTopic topic;
  final bool isAnswerToLastQuestion;
  final bool isExplicitDiscoveryRequest;
  final bool isCorrection;
  final bool isTopicChange;
  final List<UserDatingPreference> extractedPreferences;
  final String? emotionalTone; // 'boredom', 'loneliness', 'dating_fatigue', 'work_stress', etc.
  final double confidence;
  final bool needsClarification;
  final String? clarificationPrompt;
  final String? userActualIntention;
  final List<String> qualificationsAndExceptions;
  final List<String> userSelfTraits;
  final List<UserDatingPreference> positivePreferences;
  final List<UserDatingPreference> negativePreferences;
  final List<String> referencesToPreviousTurns;
  final bool isAmbiguous;

  const ConversationInterpretation({
    required this.originalUtterance,
    required this.speechAct,
    required this.topic,
    this.isAnswerToLastQuestion = false,
    this.isExplicitDiscoveryRequest = false,
    this.isCorrection = false,
    this.isTopicChange = false,
    this.extractedPreferences = const [],
    this.emotionalTone,
    this.confidence = 0.9,
    this.needsClarification = false,
    this.clarificationPrompt,
    this.userActualIntention,
    this.qualificationsAndExceptions = const [],
    this.userSelfTraits = const [],
    this.positivePreferences = const [],
    this.negativePreferences = const [],
    this.referencesToPreviousTurns = const [],
    this.isAmbiguous = false,
  });
}

/// Complete typed state representing the conversational session
class StructuredConversationState {
  // A. Conversational Context
  ConversationTopic currentTopic;
  String currentObjective;
  String? lastAssistantQuestion;
  ExpectedAnswerType expectedAnswerType;
  DialogueStage dialogueStage;

  // B. Dating Preference Context
  final List<UserDatingPreference> preferences;
  final List<UserDatingPreference> correctedPreferences;

  // C. Profile Discovery Context
  List<CupidMatchResult> lastRecommendedMatches;
  final Set<String> rejectedProfileIds;

  // D. Pending Application Actions
  PendingAppAction pendingAction;
  DateTime lastInteraction;

  StructuredConversationState({
    this.currentTopic = ConversationTopic.general,
    this.currentObjective = 'explore_vibe',
    this.lastAssistantQuestion,
    this.expectedAnswerType = ExpectedAnswerType.none,
    this.dialogueStage = DialogueStage.greeting,
    List<UserDatingPreference>? preferences,
    List<UserDatingPreference>? correctedPreferences,
    List<CupidMatchResult>? lastRecommendedMatches,
    Set<String>? rejectedProfileIds,
    this.pendingAction = PendingAppAction.none,
    DateTime? lastInteraction,
  })  : preferences = preferences ?? [],
        correctedPreferences = correctedPreferences ?? [],
        lastRecommendedMatches = lastRecommendedMatches ?? [],
        rejectedProfileIds = rejectedProfileIds ?? {},
        lastInteraction = lastInteraction ?? DateTime.now();

  bool get hasActiveProfileContext => lastRecommendedMatches.isNotEmpty;

  List<String> get activeProfileNames =>
      lastRecommendedMatches.map((m) => m.candidate.name).toList();

  /// Adds or updates a dating preference, resolving corrections
  void addOrUpdatePreference(UserDatingPreference newPref) {
    // Check if correcting an existing preference in the same category
    final existingIdx = preferences.indexWhere((p) => p.category == newPref.category);
    if (existingIdx != -1) {
      correctedPreferences.add(preferences[existingIdx]);
      preferences[existingIdx] = newPref;
    } else {
      preferences.add(newPref);
    }
  }

  /// Removes preferences in a category
  void removePreferenceCategory(String category) {
    preferences.removeWhere((p) => p.category == category);
  }

  /// Resets dating preferences without destroying the conversational greeting
  void clearPreferences() {
    preferences.clear();
    correctedPreferences.clear();
  }

  /// Full state reset
  void reset() {
    currentTopic = ConversationTopic.general;
    currentObjective = 'explore_vibe';
    lastAssistantQuestion = null;
    expectedAnswerType = ExpectedAnswerType.none;
    dialogueStage = DialogueStage.greeting;
    preferences.clear();
    correctedPreferences.clear();
    lastRecommendedMatches.clear();
    rejectedProfileIds.clear();
    pendingAction = PendingAppAction.none;
    lastInteraction = DateTime.now();
  }
}
