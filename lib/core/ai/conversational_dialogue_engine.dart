import 'dart:math' as math;
import 'package:situationship/core/models/user_model.dart';
import 'conversational_intent.dart';
import 'conversation_context_manager.dart';
import 'vibe_matrix_matcher.dart';

/// Pure on-device dynamic conversational response generator.
/// Synthesizes contextual, emotionally intelligent dialogue without rigid templates or cloud LLM calls.
class ConversationalDialogueEngine {
  static final math.Random _rng = math.Random();

  /// Generates a natural conversational response tailored to intent and context
  static String generateResponse({
    required IntentClassificationResult classification,
    required ConversationContextManager contextManager,
    required UserModel currentUser,
    List<CupidMatchResult> matches = const [],
    int totalCandidatesAvailable = 0,
  }) {
    switch (classification.intent) {
      case ConversationalIntent.casualChat:
        return _handleCasualChat(classification, contextManager);

      case ConversationalIntent.emotionalSupport:
        return _handleEmotionalSupport(classification);

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

  // ── 1. Casual Chat & Banter ────────────────────────────────────────────────
  static String _handleCasualChat(IntentClassificationResult res, ConversationContextManager contextManager) {
    final q = res.originalQuery.toLowerCase().trim();

    if (q.contains('joke') || res.subCategory == 'joke') {
      final jokes = [
        'Why do dating apps make terrible chefs? Because they always end up burning the toast while waiting for the perfect match.',
        'Are you a wifi signal? Because I\'m feeling a connection, but my signal drops every time I try to talk to people at parties.',
        'My dating life is like a software release: full of unexpected bugs, constantly in beta, and waiting for an upgrade.',
      ];
      return jokes[_rng.nextInt(jokes.length)];
    }

    if (q.contains('who are you') || q.contains('what are you')) {
      return "I'm Cupid Concierge — Situationship's on-device wingman. I help you find real people with compatible energy, brainstorm icebreakers, or talk through dating ideas without the generic swiping fatigue.";
    }

    if (q.contains('how are you') || q.contains('how r u')) {
      final replies = [
        "I'm feeling energized! More importantly, how is your day treating you? Ready to meet someone interesting, or just unwinding?",
        "Doing great! Tuning into the community's wavelengths. What kind of energy are you looking to bring into your circle today?",
      ];
      return replies[_rng.nextInt(replies.length)];
    }

    if (q.contains('thank') || q.contains('thx')) {
      return 'Anytime! I\'ve got your back. Let me know whenever you want to explore more vibes or chat.';
    }

    // Mid-conversation follow-up awareness
    if (contextManager.turnHistory.isNotEmpty) {
      final ongoingReplies = [
        'I\'m listening! Tell me what kind of person or energy would make your day a little brighter.',
        'I hear you. What\'s a quality or passion you\'d really love to see in someone right now?',
        'Sounds like a plan. Tell me what kind of person you\'d enjoy having a great conversation with!',
      ];
      return ongoingReplies[_rng.nextInt(ongoingReplies.length)];
    }

    // Default warm greeting / casual check-in
    final greetings = [
      'Hey! Good to see you. Tell me what\'s on your mind — looking to discover someone new today, or need some thoughts on dating?',
      'Hey there! What kind of vibe are you drawn to lately? Quiet bookish souls, spontaneous road trippers, or someone into great music?',
    ];
    return greetings[_rng.nextInt(greetings.length)];
  }

  // ── 2. Emotional Support & Empathy ─────────────────────────────────────────
  static String _handleEmotionalSupport(IntentClassificationResult res) {
    switch (res.subCategory) {
      case 'boredom':
        return 'Boredom is often just an invitation to find something that sparks your curiosity. What kind of conversations usually pull you out of a rut? Deep philosophy, music debates, or funny banter?';

      case 'ghosting':
        return "Ghosting genuinely stings, and it's completely valid to feel frustrated by it. But remember: someone disappearing abruptly reflects their inability to communicate honestly, not your worth. You deserve connections where effort is mutual.";

      case 'loneliness':
        return "Feeling lonely is a heavy feeling, and it happens to almost everyone at some point. It's okay to feel that way. You don't need a hundred friends or matches—just one or two authentic people who truly get you. Take it one gentle step at a time.";

      case 'dating_anxiety':
        return "Nerves before meeting someone or sending a first message are totally normal. Remember, you don't have to perform or be flawless. The best connections happen when you show up as your real, slightly quirky self.";

      case 'dating_fatigue':
        return "Dating app burnout is real when swiping feels like a checklist. Give yourself permission to pause and take a breather. High-quality connections happen when you're genuinely curious, not when you're forcing it.";

      default:
        return 'I hear you. Dating and social connections can be messy and overwhelming at times. Whatever you\'re feeling right now is completely valid. If you want to talk it through or take a different angle, I\'m here.';
    }
  }

  // ── 3. Dating Advice & Social Guidance ─────────────────────────────────────
  static String _handleDatingAdvice(IntentClassificationResult res) {
    switch (res.subCategory) {
      case 'first_date':
        return 'For a first date, low-pressure environments are best: an independent coffee shop with a short park stroll, an interesting dessert bar, or an interactive activity like an arcade or vintage flea market. Skip stiff 3-course dinners—they feel too much like a job interview.';

      case 'icebreaker':
        return 'The secret to a great opener is finding one specific detail in their bio or photos and asking an open question about it. Skip "Hey" or "How are you"—instead try: "I saw you\'re into indie rock—what\'s the one album you\'d never skip a track on?" It gives them something fun and easy to answer.';

      case 'flags':
        return 'A major green flag is consistent communication and someone who asks thoughtful follow-ups about your interests. A red flag is someone who runs hot and cold, cancels repeatedly without rescheduling, or only reaches out late at night when it\'s convenient for them.';

      case 'profile_advice':
        return 'Great profiles tell a visual story: 1) A clear, smiling headshot as photo #1 with good lighting, 2) A photo engaged in a hobby you love, 3) A candid full-body picture. In your bio, write what you\'re genuinely passionate about rather than listing generic clichés.';

      default:
        return 'The best dating advice is usually simple: communicate your intentions clearly, pay attention to whether their actions match their words, and don\'t try to impress people you\'re not even sure you like yet.';
    }
  }

  // ── 4. Situationship App Features & FAQ ───────────────────────────────────
  static String _handleAppFeatures(IntentClassificationResult res) {
    switch (res.subCategory) {
      case 'coins':
        return 'Coins are Situationship\'s internal economy. You can use them to unlock public phone numbers on verified profiles, send Super Likes to stand out in someone\'s queue, or activate Spotlight to boost your profile visibility.';

      case 'confession':
        return 'Anonymous Confession lets you leave a secret, locked note on someone\'s profile. They will receive your message with your identity masked. Once you start chatting, you have the choice to request or reveal identities whenever you feel comfortable.';

      case 'spotlight':
        return 'Spotlight is our local visibility booster. When activated, your profile is prioritized at the very top of the Discovery radar for everyone nearby in your city for the duration of the boost.';

      case 'verification':
        return 'The Verified S-Badge confirms that a member is 100% authentic and matches their photos. You can complete verification in your profile by recording a quick private gesture challenge. It gives other members confidence that you\'re real.';

      default:
        return 'Situationship is designed to create real chemistry without traditional dating app friction. We feature pure on-device matching, video/photo verification, anonymous confessions, and privacy-first connections.';
    }
  }

  // ── 5. Inquiring About a Specific Profile ──────────────────────────────────
  static String _handleProfileInquiry(
    IntentClassificationResult res,
    ConversationContextManager contextManager,
  ) {
    final targetMatch = contextManager.resolveProfileReference(res.entities);

    if (targetMatch == null) {
      if (contextManager.lastRecommendedMatches.isNotEmpty) {
        final names = contextManager.activeProfileNames.join(', ');
        return 'Which profile were you curious about? From our recent recommendations, I have $names on your radar.';
      }
      return 'I don\'t have a specific profile loaded in our conversation right now. Tell me what kind of person you\'re hoping to meet, and I\'ll curate fresh recommendations for you!';
    }

    final c = targetMatch.candidate;
    final traits = targetMatch.highlightTraits.take(3).join(', ');
    final bioSnippet = (c.bio != null && c.bio!.trim().isNotEmpty) ? c.bio! : 'They share great natural chemistry with your preferences.';

    return '${c.name} (${c.age}) stood out because of their ${traits.isNotEmpty ? traits : 'vibe'}. Here\'s what they say: "$bioSnippet" They look like a great match if you appreciate genuine ${c.interests.isNotEmpty ? c.interests.first : 'energy'}. Would you like to send them a like, or explore others?';
  }

  // ── 6. Profile Feedback & Exclusion ───────────────────────────────────────
  static String _handleProfileFeedback(
    IntentClassificationResult res,
    ConversationContextManager contextManager,
  ) {
    return 'Understood. I\'ve noted that preference and excluded those profiles from your current discovery pool. Tell me what direction you\'d like to steer in instead!';
  }

  // ── 7. Ambiguous or Short Replies ─────────────────────────────────────────
  static String _handleClarification(IntentClassificationResult res) {
    final options = [
      'Tell me a little more—what kind of vibe, passions, or qualities catch your attention?',
      'I\'m listening! Are you in the mood to meet someone creative, someone outdoorsy, or maybe a quiet thinker?',
      'Take your time! What\'s something you value most in someone you\'d like to spend an evening with?',
    ];
    return options[_rng.nextInt(options.length)];
  }

  // ── 8. Profile Discovery & Recommendation Synthesis ───────────────────────
  static String _handleProfileDiscoveryResponse({
    required IntentClassificationResult classification,
    required ConversationContextManager contextManager,
    required List<CupidMatchResult> matches,
    required int totalCandidates,
  }) {
    if (matches.isEmpty) {
      if (classification.intent == ConversationalIntent.profileContinuation) {
        return 'You\'ve explored all the active profiles currently matching those criteria in your community! You can reset our chat to explore a fresh vibe or tell me other passions you enjoy.';
      }
      return 'I couldn\'t find any active members matching all those specific criteria right now. Try broadening your preferences or exploring another passion (like indie music, travel, or photography)!';
    }

    final summary = contextManager.criteria.naturalSummary();

    if (classification.intent == ConversationalIntent.preferenceRefinement) {
      final intros = [
        'Updated your criteria to include $summary. Here are the profiles that best match this refined wavelength:',
        'Refining your search for $summary. Here are your top matches:',
      ];
      return intros[_rng.nextInt(intros.length)];
    }

    if (classification.intent == ConversationalIntent.profileContinuation) {
      final intros = [
        'Here are more members active nearby who match your $summary criteria:',
        'Found more connections sharing your energy:',
      ];
      return intros[_rng.nextInt(intros.length)];
    }

    // Fresh discovery
    if (contextManager.criteria.isEmpty) {
      final generalIntros = [
        'I curated some vibrant members active in your community right now. Take a look at who catches your eye:',
        'Here are standout profiles with genuine chemistry to get you started. Tell me who sparks your curiosity:',
        'Connecting you with energetic members on Situationship right now. Take a look at these top matches:',
      ];
      return generalIntros[_rng.nextInt(generalIntros.length)];
    }

    final intros = [
      'Here are standout members who match your $summary vibe. Take a look at who stands out to you:',
      'I curated these members based on your interest in $summary. Here are your top matches:',
      'Found great mutual chemistry for $summary! Take a look at who catches your eye:',
    ];
    return intros[_rng.nextInt(intros.length)];
  }
}
