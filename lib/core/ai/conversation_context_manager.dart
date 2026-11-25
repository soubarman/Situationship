import 'conversational_intent.dart';
import 'vibe_matrix_matcher.dart';
import 'structured_conversation_state.dart';

/// Single turn in a multi-turn conversation
class ConversationTurn {
  final String userUtterance;
  final ConversationalIntent intent;
  final String assistantReply;
  final DateTime timestamp;
  final List<String> matchedProfileIds;
  final ConversationInterpretation? interpretation;

  const ConversationTurn({
    required this.userUtterance,
    required this.intent,
    required this.assistantReply,
    required this.timestamp,
    this.matchedProfileIds = const [],
    this.interpretation,
  });
}

/// Accumulated profile search criteria built up over continuous conversation
class AccumulatedSearchCriteria {
  final Set<String> interests;
  final Set<String> personalityTraits;
  final Set<String> dealbreakers;
  final String? relationshipIntent;
  final String? genderHint;
  final int? minAge;
  final int? maxAge;
  final bool prefersNearby;

  const AccumulatedSearchCriteria({
    this.interests = const {},
    this.personalityTraits = const {},
    this.dealbreakers = const {},
    this.relationshipIntent,
    this.genderHint,
    this.minAge,
    this.maxAge,
    this.prefersNearby = false,
  });

  bool get isEmpty =>
      interests.isEmpty &&
      personalityTraits.isEmpty &&
      dealbreakers.isEmpty &&
      relationshipIntent == null &&
      genderHint == null &&
      minAge == null &&
      maxAge == null &&
      !prefersNearby;

  AccumulatedSearchCriteria merge(ExtractedEntities newEntities) {
    return AccumulatedSearchCriteria(
      interests: {...interests, ...newEntities.interests},
      personalityTraits: {...personalityTraits, ...newEntities.personalityTraits},
      dealbreakers: {...dealbreakers, ...newEntities.dealbreakers},
      relationshipIntent: newEntities.relationshipIntent ?? relationshipIntent,
      genderHint: newEntities.genderHint ?? genderHint,
      minAge: newEntities.minAge ?? minAge,
      maxAge: newEntities.maxAge ?? maxAge,
      prefersNearby: newEntities.prefersNearby ? true : prefersNearby,
    );
  }

  AccumulatedSearchCriteria copyWith({
    Set<String>? interests,
    Set<String>? personalityTraits,
    Set<String>? dealbreakers,
    String? relationshipIntent,
    String? genderHint,
    int? minAge,
    int? maxAge,
    bool? prefersNearby,
  }) {
    return AccumulatedSearchCriteria(
      interests: interests ?? this.interests,
      personalityTraits: personalityTraits ?? this.personalityTraits,
      dealbreakers: dealbreakers ?? this.dealbreakers,
      relationshipIntent: relationshipIntent ?? this.relationshipIntent,
      genderHint: genderHint ?? this.genderHint,
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      prefersNearby: prefersNearby ?? this.prefersNearby,
    );
  }

  String naturalSummary() {
    final parts = <String>[];
    if (genderHint != null) {
      parts.add(genderHint == 'female' ? 'women' : 'men');
    }
    if (personalityTraits.isNotEmpty) {
      parts.add(personalityTraits.join(' & '));
    }
    if (interests.isNotEmpty) {
      parts.add(interests.take(3).join(' & '));
    }
    if (relationshipIntent != null) {
      parts.add('for $relationshipIntent relationship');
    }
    if (dealbreakers.isNotEmpty) {
      parts.add('no ${dealbreakers.join(', ')}');
    }
    if (minAge != null || maxAge != null) {
      if (minAge != null && maxAge != null) {
        parts.add('ages $minAge-$maxAge');
      } else if (minAge != null) {
        parts.add('age $minAge+');
      } else {
        parts.add('under $maxAge');
      }
    }
    if (prefersNearby) {
      parts.add('nearby');
    }

    return parts.isEmpty ? 'open to compatible connections' : parts.join(' • ');
  }
}

/// Lightweight, on-device conversation memory and context manager
class ConversationContextManager {
  AccumulatedSearchCriteria _criteria = const AccumulatedSearchCriteria();
  List<CupidMatchResult> _lastRecommendedMatches = [];
  final Set<String> _rejectedProfileIds = {};
  final List<ConversationTurn> _turnHistory = [];
  String _activeTopic = 'welcome';
  DateTime _lastInteraction = DateTime.now();

  /// Structured typed state for context-aware interpretation
  final StructuredConversationState structuredState = StructuredConversationState();

  static const Duration _sessionTimeout = Duration(minutes: 45);

  AccumulatedSearchCriteria get criteria => _criteria;
  List<CupidMatchResult> get lastRecommendedMatches => _lastRecommendedMatches;
  Set<String> get rejectedProfileIds => _rejectedProfileIds;
  List<ConversationTurn> get turnHistory => _turnHistory;
  String get activeTopic => _activeTopic;
  bool get hasActiveProfileContext => _lastRecommendedMatches.isNotEmpty;

  List<String> get activeProfileNames =>
      _lastRecommendedMatches.map((m) => m.candidate.name).toList();

  String? get lastAssistantQuestion => structuredState.lastAssistantQuestion;
  ExpectedAnswerType get expectedAnswerType => structuredState.expectedAnswerType;
  List<UserDatingPreference> get structuredPreferences => structuredState.preferences;

  /// Records the question Cupid just asked so next turn can interpret answers contextually
  void setAssistantQuestion(
    String question,
    ExpectedAnswerType expectedType, {
    ConversationTopic? topic,
    String? objective,
  }) {
    structuredState.lastAssistantQuestion = question;
    structuredState.expectedAnswerType = expectedType;
    if (topic != null) structuredState.currentTopic = topic;
    if (objective != null) structuredState.currentObjective = objective;
  }

  /// Explicitly updates search criteria ahead of response generation
  void updateCriteria(ExtractedEntities entities) {
    _criteria = _criteria.merge(entities);
  }

  /// Adds a structured preference and syncs to criteria
  void addStructuredPreference(UserDatingPreference pref) {
    structuredState.addOrUpdatePreference(pref);
    _syncCriteriaFromPreferences();
  }

  /// Corrects an earlier preference
  void correctStructuredPreference(UserDatingPreference pref, {String? oldCategory}) {
    if (oldCategory != null) {
      structuredState.removePreferenceCategory(oldCategory);
    }
    structuredState.addOrUpdatePreference(pref);
    _syncCriteriaFromPreferences();
  }

  void _syncCriteriaFromPreferences() {
    final interests = <String>{};
    final traits = <String>{};
    final dealbreakers = <String>{};
    String? genderHint;
    String? relationshipIntent;

    for (final pref in structuredState.preferences) {
      if (pref.polarity == PreferencePolarity.negative) {
        dealbreakers.add(pref.value);
      } else if (pref.category == 'personality' || pref.category == 'humour') {
        traits.add(pref.value);
      } else if (pref.category == 'gender') {
        genderHint = pref.value;
      } else if (pref.category == 'intent') {
        relationshipIntent = pref.value;
      } else {
        interests.add(pref.value);
      }
    }

    _criteria = AccumulatedSearchCriteria(
      interests: interests,
      personalityTraits: traits,
      dealbreakers: dealbreakers,
      genderHint: genderHint,
      relationshipIntent: relationshipIntent,
    );
  }

  /// Updates conversational memory with a new turn
  void recordTurn({
    required String userUtterance,
    required IntentClassificationResult classification,
    required String assistantReply,
    List<CupidMatchResult> newMatches = const [],
    ConversationInterpretation? interpretation,
  }) {
    _checkExpiration();
    _lastInteraction = DateTime.now();

    // 1. Update criteria if the turn contributed search preferences
    if (classification.intent == ConversationalIntent.profileDiscovery ||
        classification.intent == ConversationalIntent.preferenceRefinement) {
      _criteria = _criteria.merge(classification.entities);
      _activeTopic = 'discovery';
    } else if (classification.intent == ConversationalIntent.datingAdvice) {
      _activeTopic = 'advice';
    } else if (classification.intent == ConversationalIntent.emotionalSupport) {
      _activeTopic = 'support';
    } else if (classification.intent == ConversationalIntent.appFeatures) {
      _activeTopic = 'faq';
    } else if (classification.intent == ConversationalIntent.conversationReset) {
      reset();
      return;
    }

    // 2. Track newly recommended matches
    if (newMatches.isNotEmpty) {
      _lastRecommendedMatches = newMatches;
      structuredState.lastRecommendedMatches = newMatches;
    }

    // 3. Handle exclusion feedback
    if (classification.intent == ConversationalIntent.profileFeedback) {
      if (classification.entities.referencedProfileIndex != null &&
          classification.entities.referencedProfileIndex! < _lastRecommendedMatches.length) {
        final excludedUser = _lastRecommendedMatches[classification.entities.referencedProfileIndex!].candidate;
        _rejectedProfileIds.add(excludedUser.id);
        structuredState.rejectedProfileIds.add(excludedUser.id);
      } else {
        for (final m in _lastRecommendedMatches) {
          _rejectedProfileIds.add(m.candidate.id);
          structuredState.rejectedProfileIds.add(m.candidate.id);
        }
      }
    }

    // 4. Append to rolling turn history (keep last 10 turns for memory efficiency)
    _turnHistory.add(ConversationTurn(
      userUtterance: userUtterance,
      intent: classification.intent,
      assistantReply: assistantReply,
      timestamp: DateTime.now(),
      matchedProfileIds: newMatches.map((m) => m.candidate.id).toList(),
      interpretation: interpretation,
    ));

    if (_turnHistory.length > 10) {
      _turnHistory.removeAt(0);
    }
  }

  /// Resolves an ordinal or name reference to a specific candidate from the last recommendations
  CupidMatchResult? resolveProfileReference(ExtractedEntities entities) {
    if (_lastRecommendedMatches.isEmpty) return null;

    if (entities.referencedProfileIndex != null &&
        entities.referencedProfileIndex! >= 0 &&
        entities.referencedProfileIndex! < _lastRecommendedMatches.length) {
      return _lastRecommendedMatches[entities.referencedProfileIndex!];
    }

    if (entities.referencedProfileName != null) {
      final nameLower = entities.referencedProfileName!.toLowerCase();
      for (final match in _lastRecommendedMatches) {
        if (match.candidate.name.toLowerCase().contains(nameLower)) {
          return match;
        }
      }
    }

    return null;
  }

  /// Explicitly marks a candidate profile as rejected by the user
  void rejectProfile(String profileId) {
    _rejectedProfileIds.add(profileId);
    structuredState.rejectedProfileIds.add(profileId);
  }

  /// Checks if a profile ID was rejected in the current conversation
  bool isProfileRejected(String profileId) => _rejectedProfileIds.contains(profileId);

  /// Clears conversational memory completely (Privacy-conscious user action)
  void clearMemory() {
    reset();
  }

  /// Resets the conversation context
  void reset() {
    _criteria = const AccumulatedSearchCriteria();
    _lastRecommendedMatches = [];
    _rejectedProfileIds.clear();
    _turnHistory.clear();
    _activeTopic = 'welcome';
    _lastInteraction = DateTime.now();
    structuredState.reset();
  }

  void _checkExpiration() {
    if (DateTime.now().difference(_lastInteraction) > _sessionTimeout) {
      reset();
    }
  }
}
