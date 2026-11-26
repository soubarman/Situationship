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
        contextManager: contextManager,
      );
      if (answerInterpretation != null) {
        return answerInterpretation;
      }
    }

    // ── 8. Check for Out-of-Domain Requests (coding, homework, etc.) ───────────
    if (_isOutOfDomain(clean)) {
      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.askingQuestion,
        topic: ConversationTopic.outOfDomain,
        confidence: 0.98,
      );
    }

    // ── 9. Check for App Features FAQ ──────────────────────────────────────────
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

      final qualifications = _extractQualifications(clean);
      final selfTraits = _extractSelfTraits(clean);
      final posPrefs = statedPreferences.where((p) => p.polarity == PreferencePolarity.positive && p.scope == PreferenceScope.datingRequirement).toList();
      final negPrefs = statedPreferences.where((p) => p.polarity == PreferencePolarity.negative).toList();

      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.answering,
        topic: _inferTopicFromPreferences(statedPreferences),
        isAnswerToLastQuestion: isAdditive,
        isExplicitDiscoveryRequest: false, // Strict decision gate: NEVER search automatically
        extractedPreferences: statedPreferences,
        qualificationsAndExceptions: qualifications,
        userSelfTraits: selfTraits,
        positivePreferences: posPrefs,
        negativePreferences: negPrefs,
        userActualIntention: _summarizeIntention(posPrefs, negPrefs, qualifications, selfTraits),
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
    return (clean.contains('talk about') && clean.contains('instead')) ||
        clean.startsWith('let s talk about') ||
        clean.startsWith('lets talk about') ||
        clean.contains('change topic') ||
        clean.contains('switch topic') ||
        clean.contains('switch gears') ||
        clean.contains('enough about dating') ||
        clean.startsWith('anyway ') ||
        clean.startsWith('by the way') ||
        clean.contains('what music do you') ||
        clean.contains('what songs do you') ||
        clean.contains('what artists do you');
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
        clean.contains('actually change that') ||
        clean.contains('wait i made') ||
        clean.contains('not too') ||
        clean.contains('no i mean') ||
        clean.contains('no, i mean') ||
        clean.contains('wait, instead') ||
        clean.contains('change that to') ||
        clean.contains('maybe not') ||
        clean.contains('on second thought') ||
        clean.contains('scratch that');
  }

  static List<UserDatingPreference> _extractPreferencesFromCorrection(String clean, int turn) {
    final prefs = <UserDatingPreference>[];
    if (clean.contains('not extremely outgoing') || clean.contains('not too outgoing') || (clean.contains('outgoing') && clean.contains('maybe not'))) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'moderately outgoing / balanced',
        polarity: PreferencePolarity.positive,
        sourceTurn: turn,
      ));
      return prefs;
    } else if (clean.contains('outgoing') && clean.contains('calm')) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'outgoing but calm',
        polarity: PreferencePolarity.positive,
        sourceTurn: turn,
      ));
      return prefs;
    }
    final general = _extractPreferences(clean, turn);
    if (general.isNotEmpty) return general;
    return prefs;
  }

  static bool _isRejection(String clean) {
    return _matchesAny(clean, [
      'not interested', 'not feeling these', 'dont like', "don't like",
      'not like this', 'different people', 'none of these', 'skip', 'pass'
    ]);
  }

  static String? _detectEmotionalTone(String clean) {
    if (clean.contains('terrible day') || clean.contains('rough day') || clean.contains('day at work') || clean.contains('bad day') || clean.contains('exhausted') || clean.contains('exhausting') || clean.contains('awful day')) return 'work_stress';
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
      'show me people', 'look for someone', 'get me a date', 'who matches that',
      'know anyone', 'introduce me', 'connect me with', 'set me up with',
      'connect with someone', 'grab coffee with',
      'who would get along with me', 'could introduce me', 'introduce me to somebody'
    ]);
  }

  static ConversationInterpretation? _interpretAnswerToQuestion({
    required String utterance,
    required String clean,
    required ExpectedAnswerType expectedType,
    required int sourceTurn,
    required ConversationContextManager contextManager,
  }) {
    if (clean == 'both' || clean == 'both actually' || clean == 'both of them' || clean.startsWith('both')) {
      final lastQ = (contextManager.lastAssistantQuestion ?? '').toLowerCase();
      final currentTopic = contextManager.structuredState.currentTopic;
      String cat = 'lifestyle';
      String val = 'shared passion';
      if (lastQ.contains('photo') || currentTopic == ConversationTopic.photography) {
        cat = 'photography';
        val = 'photography';
      } else if (lastQ.contains('travel') || currentTopic == ConversationTopic.travel) {
        cat = 'travel';
        val = 'travelling';
      } else if (lastQ.contains('music') || currentTopic == ConversationTopic.music) {
        cat = 'music';
        val = 'music';
      }

      return ConversationInterpretation(
        originalUtterance: utterance,
        speechAct: SpeechAct.answering,
        topic: currentTopic,
        isAnswerToLastQuestion: true,
        isExplicitDiscoveryRequest: false,
        referencesToPreviousTurns: const ['both'],
        userActualIntention: 'Applies preference to both personal activity and partner requirement',
        extractedPreferences: [
          UserDatingPreference(
            category: cat,
            value: val,
            scope: PreferenceScope.datingRequirement,
            sourceTurn: sourceTurn,
          ),
          UserDatingPreference(
            category: cat,
            value: val,
            scope: PreferenceScope.personalInterest,
            sourceTurn: sourceTurn,
          ),
        ],
        confidence: 0.96,
      );
    }
    switch (expectedType) {
      case ExpectedAnswerType.humourStyle:
      case ExpectedAnswerType.partnerTrait:
        if (clean.contains('dark')) {
          return ConversationInterpretation(
            originalUtterance: utterance,
            speechAct: SpeechAct.answering,
            topic: ConversationTopic.humour,
            isAnswerToLastQuestion: true,
            isExplicitDiscoveryRequest: false,
            extractedPreferences: [
              UserDatingPreference(
                category: 'humour',
                value: 'dark humour',
                scope: PreferenceScope.datingRequirement,
                sourceTurn: sourceTurn,
              ),
            ],
            confidence: 0.95,
          );
        }
        if (clean.contains('funny') || clean.contains('sarcas') || clean.contains('banter') || clean.contains('joke') || clean.contains('witty') || clean.contains('silly') || clean.contains('laugh') || clean.contains('humour') || clean.contains('humor')) {
          String val = 'good sense of humour';
          if (clean.contains('sarcas')) val = 'sarcasm';
          if (clean.contains('silly')) val = 'silly jokes';
          if (clean.contains('banter')) val = 'playful banter';
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
        if (clean == 'yes' || clean == 'sure' || clean == 'yeah' || clean == 'yep' || clean == 'do it' || clean == 'please' || clean.contains('yes please') || clean.contains('show me')) {
          return ConversationInterpretation(
            originalUtterance: utterance,
            speechAct: SpeechAct.requestingAction,
            topic: ConversationTopic.dating,
            isAnswerToLastQuestion: true,
            isExplicitDiscoveryRequest: true,
            confidence: 0.95,
          );
        } else if (clean.startsWith('no') ||
                   clean.contains('not now') ||
                   clean.contains('maybe later') ||
                   clean.contains('not right now') ||
                   clean == 'nope' ||
                   clean.contains('pass') ||
                   clean.contains('later') ||
                   clean.contains('hold on')) {
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

  static bool _isOutOfDomain(String clean) {
    return clean.contains('python') ||
        clean.contains('coding') ||
        clean.contains('javascript') ||
        clean.contains('homework') ||
        clean.contains('script') ||
        clean.contains('solve this equation') ||
        clean.contains('code a');
  }

  static bool _isAppFeatures(String clean) {
    return clean.contains('coin') ||
        clean.contains('confession') ||
        clean.contains('spotlight') ||
        clean.contains('verified') ||
        clean.contains('vibematrix') ||
        clean.contains('vibe matrix') ||
        clean.contains('private') ||
        clean.contains('privacy') ||
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

    final isTravelNegated = clean.contains('care about travel') ||
        clean.contains('not into travel') ||
        clean.contains('not really into travel') ||
        clean.contains('not into travelling') ||
        clean.contains('not really into travelling') ||
        clean.contains('not interested in travel') ||
        clean.contains('hate travel') ||
        clean.contains('no travel');

    if (!isTravelNegated && (clean.contains('travel') || clean.contains('travelling') || clean.contains('traveler'))) {
      prefs.add(UserDatingPreference(
        category: 'travel',
        value: 'travelling',
        sourceTurn: turn,
      ));
    }
    if (clean.contains('music') || clean.contains('musician') || clean.contains('guitar') || clean.contains('band')) {
      prefs.add(UserDatingPreference(
        category: 'music',
        value: 'music',
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
    if (clean.contains('creative') || clean.contains('art') || clean.contains('design') || clean.contains('artist')) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'creative',
        sourceTurn: turn,
      ));
    }
    if (clean.contains('introvert')) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'introverted',
        scope: PreferenceScope.datingRequirement,
        sourceTurn: turn,
      ));
    }
    final isUserQuieter = clean.contains('usually the quieter') ||
        clean.contains('i m usually the quieter') ||
        clean.contains('i am usually the quieter') ||
        clean.contains('quieter one anyway') ||
        clean.contains('i am quieter') ||
        clean.contains('i m quieter');

    if (!isUserQuieter && (clean.contains('quiet') || clean.contains('calm'))) {
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
    if (clean.contains('dark humour') || clean.contains('dark humor')) {
      prefs.add(UserDatingPreference(
        category: 'humour',
        value: 'dark humour',
        sourceTurn: turn,
      ));
    } else if (clean.contains('funny') || clean.contains('humor') || clean.contains('humour') || clean.contains('sarcas') || clean.contains('sarkas') || clean.contains('silly') || clean.contains('joke') || clean.contains('banter') || clean.contains('laugh')) {
      prefs.add(UserDatingPreference(
        category: 'humour',
        value: (clean.contains('sarcas') || clean.contains('sarkas'))
            ? 'sarcasm'
            : (clean.contains('silly') ? 'silly jokes' : (clean.contains('joke') ? 'jokes' : 'humorous')),
        sourceTurn: turn,
      ));
    }
    if (clean.contains('ambitious') || clean.contains('ambition')) {
      prefs.add(UserDatingPreference(
        category: 'personality',
        value: 'ambitious',
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
    final hasNoSmoking = clean.contains('non smoker') ||
        clean.contains('no smoking') ||
        clean.contains('pakka non-smoker') ||
        clean.contains('pakka non smoker') ||
        clean.contains('strictly non smoker') ||
        clean.contains("doesn't smoke") ||
        clean.contains("doesnt smoke") ||
        clean.contains("doesn t smoke") ||
        (clean.contains("smoke") && (clean.contains("don t") || clean.contains("dont") || clean.contains("not") || clean.contains("no")));

    if (hasNoSmoking) {
      prefs.add(UserDatingPreference(
        category: 'dealbreaker',
        value: 'smoking',
        polarity: PreferencePolarity.negative,
        sourceTurn: turn,
      ));
    }

    final isDrinkingAcceptable = clean.contains("drinking isn't a problem") ||
        clean.contains("drinking isnt a problem") ||
        clean.contains("occasional drinking") ||
        clean.contains("drink occasionally") ||
        clean.contains("drinks are fine");

    if (!isDrinkingAcceptable && (clean.contains('non drinker') || clean.contains('no drinking') || clean.contains('strictly no alcohol'))) {
      prefs.add(UserDatingPreference(
        category: 'dealbreaker',
        value: 'drinking',
        polarity: PreferencePolarity.negative,
        sourceTurn: turn,
      ));
    }
    if (clean.contains('timepass') || clean.contains('serious vibe') || clean.contains('serious relationship') || clean.contains('not looking for any timepass')) {
      prefs.add(UserDatingPreference(
        category: 'intent',
        value: 'serious',
        sourceTurn: turn,
      ));
    }

    return prefs;
  }

  static List<String> _extractQualifications(String clean) {
    final list = <String>[];
    if (clean.contains('hold a conversation') || clean.contains('hold conversation') || clean.contains('can conversation') || clean.contains('talk easily') || clean.contains('communicate easily') || clean.contains('talk easy')) {
      list.add('can hold a conversation / communicate easily');
    }
    if (clean.contains('drinking') && (clean.contains('problem') || clean.contains('occasional') || clean.contains('fine'))) {
      list.add('occasional drinking acceptable');
    }
    if (clean.contains('not offensive') || clean.contains('not the offensive')) {
      list.add('not offensive');
    }
    return list;
  }

  static List<String> _extractSelfTraits(String clean) {
    final list = <String>[];
    if (clean.contains('usually the quieter') || clean.contains('i m usually the quieter') || clean.contains('quieter one anyway') || clean.contains('i am quieter') || clean.contains('i m quieter')) {
      list.add('quieter');
    }
    if (clean.contains('not really into travelling myself') || clean.contains('not into travel myself') || clean.contains('not really into travel myself')) {
      list.add('not into travelling');
    }
    return list;
  }

  static String _summarizeIntention(
    List<UserDatingPreference> pos,
    List<UserDatingPreference> neg,
    List<String> quals,
    List<String> self,
  ) {
    final parts = <String>[];
    if (pos.isNotEmpty) parts.add('seeking ${pos.map((p) => p.value).join(", ")}');
    if (quals.isNotEmpty) parts.add('qualifications: ${quals.join(", ")}');
    if (neg.isNotEmpty) parts.add('dealbreakers: ${neg.map((p) => p.value).join(", ")}');
    if (self.isNotEmpty) parts.add('self traits: ${self.join(", ")}');
    return parts.join('; ');
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
