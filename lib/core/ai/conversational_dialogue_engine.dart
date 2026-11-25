import 'dart:math' as math;
import 'package:situationship/core/models/user_model.dart';
import 'conversational_intent.dart';
import 'conversation_context_manager.dart';
import 'vibe_matrix_matcher.dart';
import 'structured_conversation_state.dart';

/// Pure on-device context-aware conversational response generator.
/// Synthesizes contextual, emotionally intelligent dialogue without rigid templates or cloud LLM calls.
class ConversationalDialogueEngine {
  static final math.Random _rng = math.Random();

  /// Generates a natural conversational response tailored to intent, interpretation, and dialogue context
  static String generateResponse({
    required IntentClassificationResult classification,
    required ConversationContextManager contextManager,
    required UserModel currentUser,
    List<CupidMatchResult> matches = const [],
    int totalCandidatesAvailable = 0,
    ConversationInterpretation? interpretation,
  }) {
    // 1. If explicit interpretation is provided, drive response through Dialogue Policy
    if (interpretation != null) {
      return _generateContextualResponse(
        interpretation: interpretation,
        contextManager: contextManager,
        currentUser: currentUser,
        matches: matches,
      );
    }

    // 2. Fallback to classification-based routing
    switch (classification.intent) {
      case ConversationalIntent.casualChat:
        return _handleCasualChat(classification, contextManager);

      case ConversationalIntent.emotionalSupport:
        return _handleEmotionalSupport(classification, contextManager);

      case ConversationalIntent.datingAdvice:
        return _handleDatingAdvice(classification);

      case ConversationalIntent.appFeatures:
        return _handleAppFeatures(classification);

      case ConversationalIntent.profileInquiry:
        return _handleProfileInquiry(classification, contextManager);

      case ConversationalIntent.profileFeedback:
        return _handleProfileFeedback(classification, contextManager);

      case ConversationalIntent.clarification:
        return _handleClarification(classification);

      case ConversationalIntent.conversationReset:
        contextManager.reset();
        return "I've reset our conversation context! Tell me fresh: what kind of person or vibe are you in the mood to discover?";

      case ConversationalIntent.unsupported:
        return "I'm designed exclusively as your wingman for dating and social connections on Situationship, so I can't help with coding, homework, or general trivia! But if you want to find people who share your passions, I'm right here.";

      case ConversationalIntent.profileDiscovery:
      case ConversationalIntent.preferenceRefinement:
      case ConversationalIntent.profileContinuation:
        return _handleProfileDiscoveryResponse(
          classification: classification,
          contextManager: contextManager,
          matches: matches,
          totalCandidates: totalCandidatesAvailable,
        );
    }
  }

  // ── Contextual Dialogue Policy Dispatcher ───────────────────────────────────

  static String _generateContextualResponse({
    required ConversationInterpretation interpretation,
    required ConversationContextManager contextManager,
    required UserModel currentUser,
    required List<CupidMatchResult> matches,
  }) {
    // A. Explicit Action: Profile Discovery / Search
    if (interpretation.isExplicitDiscoveryRequest) {
      return _handleProfileDiscovery(
        contextManager: contextManager,
        matches: matches,
      );
    }

    // B. Rejection of Recommended Profile
    if (interpretation.speechAct == SpeechAct.rejectingProfile) {
      return "Got it! I've noted that and won't show them again. Would you like to explore a different vibe, or adjust what you're looking for?";
    }

    // C. Preference Correction
    if (interpretation.isCorrection) {
      final summary = interpretation.extractedPreferences.map((p) => p.value).join(' and ');
      contextManager.setAssistantQuestion(
        "Want me to find people who align with your updated vibe?",
        ExpectedAnswerType.confirmation,
        topic: ConversationTopic.dating,
      );
      return "Got it, adjusted that! So you prefer someone $summary. Makes total sense. Would you like me to look for members nearby with that energy?";
    }

    // D. Topic Change Request
    if (interpretation.isTopicChange) {
      return _handleTopicChange(interpretation.topic, contextManager);
    }

    // E. Emotional Support
    if (interpretation.speechAct == SpeechAct.expressingEmotion || interpretation.topic == ConversationTopic.emotionalSupport) {
      return _handleEmotionalContext(interpretation.emotionalTone, contextManager);
    }

    // F. Answering Outstanding Assistant Question
    if (interpretation.isAnswerToLastQuestion) {
      return _handleAnswerToQuestion(interpretation, contextManager);
    }

    // G. Stating a Dating Preference (Without Asking to Search)
    if (interpretation.extractedPreferences.isNotEmpty) {
      return _handleStatedPreference(interpretation, contextManager);
    }

    // H. Ambiguous / Short Input Requiring Clarification
    if (interpretation.needsClarification) {
      return interpretation.clarificationPrompt ??
          "I'm listening! Tell me a bit more about what kind of energy or connection you have in mind.";
    }

    // I. Casual Banter / Open Discourse
    return _handleCasualDiscourse(interpretation, contextManager);
  }

  // ── Dialogue Handlers ───────────────────────────────────────────────────────

  static String _handleAnswerToQuestion(
    ConversationInterpretation interpretation,
    ConversationContextManager contextManager,
  ) {
    final expected = contextManager.expectedAnswerType;
    final q = interpretation.originalUtterance.toLowerCase();

    if (expected == ExpectedAnswerType.humourStyle ||
        expected == ExpectedAnswerType.partnerTrait ||
        interpretation.topic == ConversationTopic.humour) {
      if (q.contains('sarcas')) {
        contextManager.setAssistantQuestion(
          "What else stands out to you when you connect with someone?",
          ExpectedAnswerType.partnerTrait,
          topic: ConversationTopic.humour,
        );
        return "Dry wit and sharp comebacks—love that. It's rare to find someone who can banter back and forth like that. What else stands out to you when you meet someone new?";
      }

      if (q.contains('silly') || q.contains('joke')) {
        contextManager.setAssistantQuestion(
          "Would you like me to find members nearby who share that exact wavelength?",
          ExpectedAnswerType.confirmation,
          topic: ConversationTopic.dating,
        );
        return "So witty with a goofy side. You get the best of both worlds! Would you like me to find members nearby who share that exact wavelength?";
      }

      if (q.contains('funny') || q.contains('laugh')) {
        contextManager.setAssistantQuestion(
          "Are you more into witty sarcasm, silly humour, or playful teasing?",
          ExpectedAnswerType.humourStyle,
          topic: ConversationTopic.humour,
        );
        return "Someone who can make you laugh is such a good foundation. Are you more into witty sarcasm, silly humour, or playful teasing?";
      }
    }

    if (expected == ExpectedAnswerType.hobbyOrPassion) {
      if (q.contains('photo')) {
        contextManager.setAssistantQuestion(
          "Are you more into analog 35mm film, street photography, or capturing landscapes?",
          ExpectedAnswerType.none,
          topic: ConversationTopic.photography,
        );
        return "Photography is such a great creative outlet! Are you more into analog 35mm film, street photography, or capturing landscapes?";
      }
    }

    if (expected == ExpectedAnswerType.confirmation) {
      if (interpretation.isExplicitDiscoveryRequest) {
        return "Searching for members who match that energy now...";
      } else {
        return "No problem at all! We can just chat or take things at your own pace. Tell me whatever is on your mind.";
      }
    }

    // General answer acknowledgment
    final prefValues = interpretation.extractedPreferences.map((p) => p.value).join(' & ');
    if (prefValues.isNotEmpty) {
      contextManager.setAssistantQuestion(
        "Want me to find people who match that?",
        ExpectedAnswerType.confirmation,
        topic: ConversationTopic.dating,
      );
      return "That sounds like a wonderful quality. Having shared passions for $prefValues makes connecting so much easier. Would you like me to look for members with that vibe?";
    }

    return "I hear you! What other qualities do you value most in someone?";
  }

  static String _handleStatedPreference(
    ConversationInterpretation interpretation,
    ConversationContextManager contextManager,
  ) {
    final q = interpretation.originalUtterance.toLowerCase();

    // Check if user is saying "I want someone interesting..."
    if (q.contains('interesting')) {
      contextManager.setAssistantQuestion(
        "What does 'interesting' look like for you?",
        ExpectedAnswerType.partnerTrait,
        topic: ConversationTopic.dating,
      );
      return "'Interesting' can mean so many different things—creative artists, spontaneous travelers, or deep thinkers. What does 'interesting' look like for you?";
    }

    final hasTravel = q.contains('travel') || q.contains('travelling');
    final hasPhoto = q.contains('photo') || q.contains('camera');

    if (hasTravel && hasPhoto) {
      contextManager.setAssistantQuestion(
        "Want me to search for members nearby who love traveling and photography?",
        ExpectedAnswerType.confirmation,
        topic: ConversationTopic.dating,
      );
      return "Travel and photography go hand-in-hand—exploring new places and capturing the memories. Would you like me to find someone like that for you?";
    }

    if (hasTravel) {
      contextManager.setAssistantQuestion(
        "Do you picture spontaneous weekend getaways or big international trips?",
        ExpectedAnswerType.none,
        topic: ConversationTopic.travel,
      );
      return "An explorer at heart! Travelling tells you so much about how someone handles adventure. Do you picture spontaneous weekend getaways or big international trips?";
    }

    if (hasPhoto) {
      contextManager.setAssistantQuestion(
        "Want me to find people who share that passion?",
        ExpectedAnswerType.confirmation,
        topic: ConversationTopic.photography,
      );
      return "Photography is such a visual, observant passion. It says a lot about how someone sees the world. Would you like me to search for someone like that?";
    }

    final summary = interpretation.extractedPreferences.map((p) => p.value).join(' & ');
    contextManager.setAssistantQuestion(
      "Want me to find members who match that?",
      ExpectedAnswerType.confirmation,
      topic: ConversationTopic.dating,
    );
    return "Noted! Someone into $summary. What other vibes or qualities make you feel truly connected?";
  }

  static String _handleTopicChange(ConversationTopic newTopic, ConversationContextManager contextManager) {
    contextManager.structuredState.currentTopic = newTopic;

    switch (newTopic) {
      case ConversationTopic.music:
        contextManager.setAssistantQuestion(
          "What artists or albums have you had on repeat lately?",
          ExpectedAnswerType.musicGenre,
          topic: ConversationTopic.music,
        );
        return "Let's dive into music! What artists or albums have you had on repeat lately?";

      case ConversationTopic.travel:
        contextManager.setAssistantQuestion(
          "What's the best trip you've ever taken?",
          ExpectedAnswerType.none,
          topic: ConversationTopic.travel,
        );
        return "I love talking about travel. What's the most memorable place you've ever visited?";

      case ConversationTopic.photography:
        contextManager.setAssistantQuestion(
          "Do you shoot film or digital?",
          ExpectedAnswerType.none,
          topic: ConversationTopic.photography,
        );
        return "Let's talk photography! Do you shoot analog 35mm film or digital?";

      default:
        return "Sure thing, let's switch gears! What's on your mind today?";
    }
  }

  static String _handleEmotionalContext(String? tone, ConversationContextManager contextManager) {
    contextManager.structuredState.currentTopic = ConversationTopic.emotionalSupport;

    switch (tone) {
      case 'boredom':
        contextManager.setAssistantQuestion(
          "What kind of conversations usually pull you out of a rut?",
          ExpectedAnswerType.humourStyle,
          topic: ConversationTopic.humour,
        );
        return "Boredom is usually just your mind asking for something that sparks curiosity. What kind of conversations usually pull you out of a rut? Deep banter, music debates, or funny jokes?";

      case 'loneliness':
        return "Feeling lonely is heavy, and it's completely okay to sit with that feeling. You don't need a crowd of people—just one or two authentic connections who really understand you. We'll take it one gentle step at a time.";

      case 'ghosting':
        return "Ghosting genuinely stings, and it's completely valid to feel frustrated by it. But remember: someone disappearing abruptly reflects their communication shortcomings, not your worth. You deserve effort that's mutual.";

      default:
        return "I hear you. Dating and social connections can feel exhausting at times. Whatever you're feeling right now is completely valid. If you want to talk it through, I'm here.";
    }
  }

  static String _handleProfileDiscovery({
    required ConversationContextManager contextManager,
    required List<CupidMatchResult> matches,
  }) {
    if (matches.isEmpty) {
      final summary = contextManager.criteria.naturalSummary();
      return "I searched our community for members matching $summary, but didn't find an exact match nearby right now. Would you like me to widen our distance range or explore another passion you love?";
    }

    if (matches.length == 1) {
      final m = matches.first;
      final traits = m.highlightTraits.take(2).join(' and ');
      return "I found a standout connection! ${m.candidate.name} (${m.candidate.age}) aligns with your shared passions for ${traits.isNotEmpty ? traits : 'compatible energy'}. Take a look at who stands out to you:";
    }

    final names = matches.map((m) => '${m.candidate.name} (${m.candidate.age})').join(' and ');
    final shared = matches.first.highlightTraits.take(2).join(' & ');
    return "Found standout members who match your wavelength! Here are $names, connected by ${shared.isNotEmpty ? shared : 'mutual chemistry'}. Take a look at who catches your eye:";
  }

  static String _handleCasualDiscourse(
    ConversationInterpretation interpretation,
    ConversationContextManager contextManager,
  ) {
    final q = interpretation.originalUtterance.toLowerCase().trim();

    if (q.contains('interesting')) {
      contextManager.setAssistantQuestion(
        "What does 'interesting' look like for you?",
        ExpectedAnswerType.partnerTrait,
        topic: ConversationTopic.dating,
      );
      return "'Interesting' can mean so many different things—creative artists, spontaneous travelers, or deep thinkers. What does 'interesting' look like for you?";
    }

    if (q.contains('how are you') || q.contains('how r u')) {
      return "I'm doing well, thank you! More importantly, how is your day going? Ready to explore new connections, or just relaxing?";
    }

    if (q.contains('who are you') || q.contains('what are you')) {
      return "I'm Cupid Concierge — your on-device wingman for Situationship. I'm here to chat, brainstorm ideas, and help you find people who match your energy.";
    }

    if (contextManager.turnHistory.isNotEmpty) {
      return "I'm listening! Tell me what kind of person or energy would make your day a little brighter.";
    }

    contextManager.setAssistantQuestion(
      "Looking to discover someone new today, or need some thoughts on dating?",
      ExpectedAnswerType.datingGoal,
      topic: ConversationTopic.general,
    );
    return "Hey! Good to see you. Tell me what's on your mind — looking to discover someone new today, or need some thoughts on dating?";
  }

  // ── Legacy Compatibility Handlers ──────────────────────────────────────────

  static String _handleCasualChat(IntentClassificationResult res, ConversationContextManager contextManager) {
    return _handleCasualDiscourse(
      ConversationInterpretation(
        originalUtterance: res.originalQuery,
        speechAct: SpeechAct.casualBanter,
        topic: ConversationTopic.general,
      ),
      contextManager,
    );
  }

  static String _handleEmotionalSupport(IntentClassificationResult res, ConversationContextManager contextManager) {
    return _handleEmotionalContext(res.subCategory.isNotEmpty ? res.subCategory : 'general', contextManager);
  }

  static String _handleDatingAdvice(IntentClassificationResult res) {
    switch (res.subCategory) {
      case 'first_date':
        return 'For a first date, low-pressure environments are best: an independent coffee shop with a short park stroll, an interesting dessert bar, or an interactive activity like an arcade or vintage flea market. Skip stiff 3-course dinners—they feel too much like a job interview.';
      case 'icebreaker':
        return 'The secret to a great opener is finding one specific detail in their bio or photos and asking an open question about it. Skip "Hey" or "How are you"—instead try: "I saw you\'re into indie rock—what\'s the one album you\'d never skip a track on?" It gives them something fun and easy to answer.';
      case 'flags':
        return 'A major green flag is consistent communication and someone who asks thoughtful follow-ups about your interests. A red flag is someone who runs hot and cold, cancels repeatedly without rescheduling, or only reaches out late at night when it\'s convenient for them.';
      default:
        return 'Authenticity beats perfection every time. The most attractive thing you can bring to dating is curiosity about the other person and confidence in your own passions.';
    }
  }

  static String _handleAppFeatures(IntentClassificationResult res) {
    switch (res.subCategory) {
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

  static String _handleProfileInquiry(IntentClassificationResult res, ConversationContextManager contextManager) {
    final targetMatch = contextManager.resolveProfileReference(res.entities);
    if (targetMatch != null) {
      final c = targetMatch.candidate;
      return "${c.name} (${c.age}) stood out because of their shared passions. Here is their vibe: '${c.bio ?? 'Genuine energy and great compatibility.'}' Would you like to send them a like?";
    } else {
      return "Which profile were you curious about? Tell me their name or which recommendation caught your attention!";
    }
  }

  static String _handleProfileFeedback(IntentClassificationResult res, ConversationContextManager contextManager) {
    return "Got it! I've noted that and won't show them again. Would you like to explore a different vibe, or adjust what you're looking for?";
  }

  static String _handleClarification(IntentClassificationResult res) {
    return "I'm listening! Tell me a bit more about what kind of energy or connection you have in mind.";
  }

  static String _handleProfileDiscoveryResponse({
    required IntentClassificationResult classification,
    required ConversationContextManager contextManager,
    required List<CupidMatchResult> matches,
    required int totalCandidates,
  }) {
    return _handleProfileDiscovery(contextManager: contextManager, matches: matches);
  }
}
