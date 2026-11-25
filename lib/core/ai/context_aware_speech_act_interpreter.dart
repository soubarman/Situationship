import 'structured_conversation_state.dart';
import 'conversation_context_manager.dart';
import 'conversational_intent.dart';

/// Context-aware semantic speech act and intent interpreter.
/// Interprets utterances in the context of the surrounding dialogue rather than in isolation.
class ContextAwareSpeechActInterpreter {
  /// Interprets a user utterance considering conversation history and outstanding questions
  static ConversationInterpretation interpret(
    String utterance, {
    required ConversationContextManager contextManager,
  }) {
    final clean = _clean(utterance);
    final history = contextManager.turnHistory;
    final lastQuestion = contextManager.lastAssistantQuestion;
    final expectedType = contextManager.expectedAnswerType;

    // ── 1. Check for Reset / Action Request ────────────────────────────────────
    if (_matchesAny(clean, [
      'reset', 'start over', 'clear chat', 'restart', 'clear criteria',
      'forget everything', 'new search', 'start fresh', 'clean slate'
    ])) {
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.requestingAction,
        topic: ConversationTopic.general,
        confidence: 0.98,
      );
    }

    // ── 2. Check for Topic Change Request ──────────────────────────────────────
    if (_isTopicChange(clean)) {
      final newTopic = _extractNewTopic(clean);
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.changingTopic,
        topic: newTopic,
        isTopicChange: true,
        confidence: 0.95,
      );
    }

    // ── 3. Check for Preference Correction ─────────────────────────────────────
    if (_isCorrection(clean)) {
      final correctedPrefs = _extractPreferencesFromCorrection(clean, history.length);
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.correctingPreference,
        topic: ConversationTopic.dating,
        isCorrection: true,
        extractedPreferences: correctedPrefs,
        confidence: 0.92,
      );
    }

    // ── 4. Check for Profile Rejection ─────────────────────────────────────────
    if (contextManager.hasActiveProfileContext && _isRejection(clean)) {
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.rejectingProfile,
        topic: ConversationTopic.dating,
        confidence: 0.95,
      );
    }

    // ── 5. Check for Emotional Expression ──────────────────────────────────────
    final emotionalTone = _detectEmotionalTone(clean);
    if (emotionalTone != null) {
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.expressingEmotion,
        topic: ConversationTopic.emotionalSupport,
        emotionalTone: emotionalTone,
        confidence: 0.94,
      );
    }

    // ── 6. Check for Explicit Profile Discovery Request ────────────────────────
    if (_isExplicitDiscoveryRequest(clean)) {
      final explicitPrefs = _extractPreferences(clean, history.length);
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.requestingAction,
        topic: explicitPrefs.isNotEmpty ? _inferTopicFromPreferences(explicitPrefs) : ConversationTopic.dating,
        isExplicitDiscoveryRequest: true,
        extractedPreferences: explicitPrefs,
        confidence: 0.95,
      );
    }

    // ── 7. Contextual Answer to Outstanding Assistant Question ─────────────────
    if (expectedType != ExpectedAnswerType.none && lastQuestion != null) {
      final answerInterpretation = _interpretAnswerToQuestion(
        utterance: utterance,
        clean: clean,
        expectedType: expectedType,
        sourceTurn: history.length,
      );
      if (answerInterpretation != null) {
        return answerInterpretation;
      }
    }

    // ── 8. Check for App Features FAQ ──────────────────────────────────────────
    if (_isAppFeatures(clean)) {
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.askingQuestion,
        topic: ConversationTopic.appFeatures,
        confidence: 0.92,
      );
    }

    // ── 9. Check for Dating Advice Inquiry ─────────────────────────────────────
    if (_isDatingAdvice(clean)) {
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.askingQuestion,
        topic: ConversationTopic.dating,
        confidence: 0.90,
      );
    }

    // ── 10. Preference Statement (Without Requesting Discovery Search) ──────────
    final statedPreferences = _extractPreferences(clean, history.length);
    if (statedPreferences.isNotEmpty) {
      final isAdditive = clean.startsWith('also ') ||
          clean.startsWith('and ') ||
          clean.contains('too') ||
          clean.contains('as well');

      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.answering,
        topic: _inferTopicFromPreferences(statedPreferences),
        isAnswerToLastQuestion: isAdditive,
        isExplicitDiscoveryRequest: false, // Strict decision gate: NEVER search automatically
        extractedPreferences: statedPreferences,
        confidence: 0.88,
      );
    }

    // ── 11. Casual Acknowledgment or Short Reply ────────────────────────────────
    if (_isAcknowledgment(clean)) {
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.acknowledging,
        topic: contextManager.structuredState.currentTopic,
        confidence: 0.85,
      );
    }

    // ── 12. Ambiguous Short Input (Needs Clarification) ────────────────────────
    if (clean.length < 4 || clean == 'maybe' || clean == 'hm' || clean == 'idk') {
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.casualBanter,
        topic: ConversationTopic.general,
        confidence: 0.50,
        needsClarification: true,
        clarificationPrompt: "I'm listening! Tell me a bit more about what you have in mind.",
      );
    }

    // ── 13. Default: Casual Conversation ───────────────────────────────────────
    return ConversationInterpretation(
      originalUtterance: utterance,
      speechAct: SpeechAct.casualBanter,
      topic: ConversationTopic.general,
      confidence: 0.70,
    );
  }

  // ── Helper Resolvers ────────────────────────────────────────────────────────

  static bool _isTopicChange(String clean) {
    return clean.contains('talk about') && clean.contains('instead') ||
        clean.startsWith('let\'s talk about') ||
        clean.startsWith('lets talk about') ||
        clean.contains('change topic') ||
        clean.contains('switch topic') ||
        clean.contains('enough about dating');
  }

  static ConversationTopic _extractNewTopic(String clean) {
    if (clean.contains('music')) return ConversationTopic.music;
    if (clean.contains('travel')) return ConversationTopic.travel;
    if (clean.contains('photo')) return ConversationTopic.photography;
    if (clean.contains('joke') || clean.contains('humor') || clean.contains('humour')) return ConversationTopic.humour;
    if (clean.contains('food') || clean.contains('fitness') || clean.contains('lifestyle')) return ConversationTopic.lifestyle;
    return ConversationTopic.general;
  }

  static bool _isCorrection(String clean) {
    return clean.startsWith('actually') ||
        clean.contains('not too') ||
        clean.contains('no i mean') ||
        clean.contains('no, i mean') ||
        clean.contains('wait, instead') ||
        clean.contains('change that to');
  }

  static List<UserDatingPreference> _extractPreferencesFromCorrection(String clean, int turn) {
    final prefs = <UserDatingPreference>[];
    if (clean.contains('outgoing') && clean.contains('calm')) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'outgoing but calm',
        polarity: PreferencePolarity.positive,
        sourceTurn: turn,
      ));
    } else if (clean.contains('outgoing')) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'outgoing',
        polarity: PreferencePolarity.positive,
        sourceTurn: turn,
      ));
    } else if (clean.contains('gaming')) {
      prefs.add(UserDatingPreference(
        category: 'lifestyle',
        value: 'gaming',
        polarity: PreferencePolarity.positive,
        sourceTurn: turn,
      ));
    }
    return prefs;
  }

  static bool _isRejection(String clean) {
    return _matchesAny(clean, [
      'not interested', 'not feeling these', 'dont like', "don't like",
      'not like this', 'different people', 'none of these', 'skip', 'pass'
    ]);
  }

  static String? _detectEmotionalTone(String clean) {
    if (clean.contains('bored') || clean.contains('boring')) return 'boredom';
    if (clean.contains('lonel')) return 'loneliness';
    if (clean.contains('ghost')) return 'ghosting';
    if (clean.contains('exhaust') || clean.contains('tired of dating') || clean.contains('dating fatigue')) return 'dating_fatigue';
    if (clean.contains('nervous') || clean.contains('anxious')) return 'dating_anxiety';
    return null;
  }

  static bool _isExplicitDiscoveryRequest(String clean) {
    return _matchesAny(clean, [
      'find someone', 'find me', 'show me profiles', 'recommend someone',
      'match me', 'find someone like that', 'can you find someone',
      'show me people', 'look for someone', 'get me a date', 'who matches that'
    ]);
  }

  static ConversationInterpretation? _interpretAnswerToQuestion({
    required String utterance,
    required String clean,
    required ExpectedAnswerType expectedType,
    required int sourceTurn,
  }) {
    switch (expectedType) {
      case ExpectedAnswerType.humourStyle:
      case ExpectedAnswerType.partnerTrait:
        if (clean.contains('funny') || clean.contains('sarcas') || clean.contains('banter') || clean.contains('joke') || clean.contains('witty') || clean.contains('silly') || clean.contains('laugh')) {
          String val = 'funny banter';
          if (clean.contains('sarcas')) val = 'sarcasm';
          if (clean.contains('silly')) val = 'silly jokes';
          return ConversationInterpretation(
            originalUtterance: utterance,
            speechAct: SpeechAct.answering,
            topic: ConversationTopic.humour,
            isAnswerToLastQuestion: true,
            isExplicitDiscoveryRequest: false,
            extractedPreferences: [
              UserDatingPreference(
                category: 'humour',
                value: val,
                scope: PreferenceScope.datingRequirement,
                sourceTurn: sourceTurn,
              ),
            ],
            confidence: 0.95,
          );
        }
        break;

      case ExpectedAnswerType.hobbyOrPassion:
        // When asked "What do you enjoy doing on weekends?", an answer is a personal hobby, not an automatic partner requirement
        if (clean.contains('photo') || clean.contains('travel') || clean.contains('music') || clean.contains('read') || clean.contains('hike')) {
          String val = clean;
          String cat = 'lifestyle';
          if (clean.contains('photo')) { val = 'photography'; cat = 'photography'; }
          if (clean.contains('travel')) { val = 'travelling'; cat = 'travel'; }
          if (clean.contains('music')) { val = 'music'; cat = 'music'; }
          return ConversationInterpretation(
            originalUtterance: utterance,
            speechAct: SpeechAct.answering,
            topic: _topicFromCategory(cat),
            isAnswerToLastQuestion: true,
            isExplicitDiscoveryRequest: false,
            extractedPreferences: [
              UserDatingPreference(
                category: cat,
                value: val,
                scope: PreferenceScope.personalInterest, // Not forced discovery requirement
                sourceTurn: sourceTurn,
              ),
            ],
            confidence: 0.94,
          );
        }
        break;

      case ExpectedAnswerType.musicGenre:
        return ConversationInterpretation(
          originalUtterance: utterance,
          speechAct: SpeechAct.answering,
          topic: ConversationTopic.music,
          isAnswerToLastQuestion: true,
          isExplicitDiscoveryRequest: false,
          extractedPreferences: [
            UserDatingPreference(
              category: 'music',
              value: clean,
              scope: PreferenceScope.personalInterest,
              sourceTurn: sourceTurn,
            ),
          ],
          confidence: 0.92,
        );

      case ExpectedAnswerType.confirmation:
        if (clean == 'yes' || clean == 'sure' || clean == 'yeah' || clean == 'yep' || clean == 'do it' || clean == 'please') {
          return ConversationInterpretation(
            originalUtterance: utterance,
            speechAct: SpeechAct.requestingAction,
            topic: ConversationTopic.dating,
            isAnswerToLastQuestion: true,
            isExplicitDiscoveryRequest: true,
            confidence: 0.95,
          );
        } else if (clean == 'no' || clean == 'not now' || clean == 'maybe later' || clean == 'nope') {
          return ConversationInterpretation(
            originalUtterance: utterance,
            speechAct: SpeechAct.answering,
            topic: ConversationTopic.dating,
            isAnswerToLastQuestion: true,
            isExplicitDiscoveryRequest: false,
            confidence: 0.95,
          );
        }
        break;

      default:
        break;
    }
    return null;
  }

  static bool _isAppFeatures(String clean) {
    return clean.contains('coin') ||
        clean.contains('confession') ||
        clean.contains('spotlight') ||
        clean.contains('verified') ||
        clean.contains('how does situationship work');
  }

  static bool _isDatingAdvice(String clean) {
    return clean.contains('first date') ||
        clean.contains('opener') ||
        clean.contains('icebreaker') ||
        clean.contains('red flag') ||
        clean.contains('green flag') ||
        clean.contains('profile advice');
  }

  static List<UserDatingPreference> _extractPreferences(String clean, int turn) {
    final prefs = <UserDatingPreference>[];

    if (clean.contains('travel') || clean.contains('travelling') || clean.contains('traveler')) {
      prefs.add(UserDatingPreference(
        category: 'travel',
        value: 'travelling',
        sourceTurn: turn,
      ));
    }
    if (clean.contains('photo') || clean.contains('camera')) {
      prefs.add(UserDatingPreference(
        category: 'photography',
        value: 'photography',
        sourceTurn: turn,
      ));
    }
    if (clean.contains('quiet') || clean.contains('calm')) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'quiet & calm',
        sourceTurn: turn,
      ));
    }
    if (clean.contains('outgoing') || clean.contains('social')) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'outgoing',
        sourceTurn: turn,
      ));
    }
    if (clean.contains('interesting')) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'interesting',
        sourceTurn: turn,
      ));
    }
    if (clean.contains('funny') || clean.contains('humor') || clean.contains('humour') || clean.contains('sarcas') || clean.contains('silly') || clean.contains('joke') || clean.contains('banter') || clean.contains('laugh')) {
      prefs.add(UserDatingPreference(
        category: 'humour',
        value: clean.contains('sarcas')
            ? 'sarcasm'
            : (clean.contains('silly') ? 'silly jokes' : (clean.contains('joke') ? 'jokes' : 'humorous')),
        sourceTurn: turn,
      ));
    }
    if (clean.contains('gaming') || clean.contains('gamer')) {
      prefs.add(UserDatingPreference(
        category: 'lifestyle',
        value: 'gaming',
        sourceTurn: turn,
      ));
    }
    if (clean.contains('non smoker') || clean.contains('no smoking')) {
      prefs.add(UserDatingPreference(
        category: 'dealbreaker',
        value: 'smoking',
        polarity: PreferencePolarity.negative,
        sourceTurn: turn,
      ));
    }

    return prefs;
  }

  static ConversationTopic _inferTopicFromPreferences(List<UserDatingPreference> prefs) {
    if (prefs.isEmpty) return ConversationTopic.general;
    final cat = prefs.first.category;
    return _topicFromCategory(cat);
  }

  static ConversationTopic _topicFromCategory(String cat) {
    switch (cat) {
      case 'travel': return ConversationTopic.travel;
      case 'photography': return ConversationTopic.photography;
      case 'music': return ConversationTopic.music;
      case 'humour': return ConversationTopic.humour;
      case 'lifestyle': return ConversationTopic.lifestyle;
      default: return ConversationTopic.dating;
    }
  }

  static bool _isAcknowledgment(String clean) {
    return clean == 'ok' ||
        clean == 'cool' ||
        clean == 'sounds good' ||
        clean == 'awesome' ||
        clean == 'got it' ||
        clean == 'nice' ||
        clean == 'thanks' ||
        clean == 'thank you';
  }

  static String _clean(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool _matchesAny(String target, List<String> patterns) {
    for (final p in patterns) {
      if (target == p || target.contains(p)) return true;
    }
    return false;
  }
}
