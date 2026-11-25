/// Broad functional intents for the Situationship conversational assistant
enum ConversationalIntent {
  /// Casual conversation: greetings, small talk, boredom, jokes, light banter
  casualChat,

  /// Emotional support: dating fatigue, ghosting, loneliness, heartbreak, nervousness
  emotionalSupport,

  /// Dating & social advice: first date ideas, opening lines, profile tips, red flags
  datingAdvice,

  /// App FAQ & features: how coins work, anonymous confessions, spotlight, verification
  appFeatures,

  /// Profile discovery: explicit request to find or recommend matches
  profileDiscovery,

  /// Preference refinement: adding to or modifying criteria ("someone more adventurous", "and also into photography")
  preferenceRefinement,

  /// Inquiry about a recommended profile: "tell me more about Maya", "why did you pick the second one?"
  profileInquiry,

  /// Continuation / pagination: "show more", "anyone else", "show different ones"
  profileContinuation,

  /// Feedback / exclusion: "not like this one", "I don't like smokers", "different people"
  profileFeedback,

  /// Ambiguous or very short query requiring clarification: "maybe", "hm", "ok"
  clarification,

  /// Conversation reset: "start over", "reset", "clear criteria"
  conversationReset,

  /// Unsupported domain: coding, math, medical, general external web queries
  unsupported,
}

/// Extracted semantic entities from conversational input
class ExtractedEntities {
  final List<String> interests;
  final List<String> personalityTraits;
  final String? relationshipIntent; // 'serious' | 'casual' | 'open' | 'friendship'
  final List<String> dealbreakers; // e.g. 'smoking', 'drinking'
  final String? genderHint; // 'female' | 'male'
  final int? minAge;
  final int? maxAge;
  final bool prefersNearby;
  final int? referencedProfileIndex; // 0 for first, 1 for second, 2 for third
  final String? referencedProfileName;

  const ExtractedEntities({
    this.interests = const [],
    this.personalityTraits = const [],
    this.relationshipIntent,
    this.dealbreakers = const [],
    this.genderHint,
    this.minAge,
    this.maxAge,
    this.prefersNearby = false,
    this.referencedProfileIndex,
    this.referencedProfileName,
  });

  bool get hasCriteria =>
      interests.isNotEmpty ||
      personalityTraits.isNotEmpty ||
      relationshipIntent != null ||
      dealbreakers.isNotEmpty ||
      genderHint != null ||
      minAge != null ||
      maxAge != null ||
      prefersNearby;

  ExtractedEntities copyWith({
    List<String>? interests,
    List<String>? personalityTraits,
    String? relationshipIntent,
    List<String>? dealbreakers,
    String? genderHint,
    int? minAge,
    int? maxAge,
    bool? prefersNearby,
    int? referencedProfileIndex,
    String? referencedProfileName,
  }) {
    return ExtractedEntities(
      interests: interests ?? this.interests,
      personalityTraits: personalityTraits ?? this.personalityTraits,
      relationshipIntent: relationshipIntent ?? this.relationshipIntent,
      dealbreakers: dealbreakers ?? this.dealbreakers,
      genderHint: genderHint ?? this.genderHint,
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      prefersNearby: prefersNearby ?? this.prefersNearby,
      referencedProfileIndex: referencedProfileIndex ?? this.referencedProfileIndex,
      referencedProfileName: referencedProfileName ?? this.referencedProfileName,
    );
  }
}

/// Outcome of intent classification
class IntentClassificationResult {
  final ConversationalIntent intent;
  final double confidence; // 0.0 to 1.0
  final ExtractedEntities entities;
  final String originalQuery;
  final String subCategory; // e.g. 'first_date', 'ghosting', 'coins'

  const IntentClassificationResult({
    required this.intent,
    required this.confidence,
    required this.entities,
    required this.originalQuery,
    this.subCategory = '',
  });
}

/// Pure on-device semantic intent classifier & entity extractor
class ConversationalIntentClassifier {
  static IntentClassificationResult classify(
    String query, {
    bool hasActiveProfileContext = false,
    List<String> activeProfileNames = const [],
  }) {
    final clean = _clean(query);
    final entities = extractEntities(query, activeProfileNames: activeProfileNames);

    // 1. Conversation Reset Intent
    if (_matchesAny(clean, [
      'reset', 'start over', 'clear chat', 'restart', 'clear criteria',
      'forget everything', 'new search', 'start fresh', 'clean slate'
    ])) {
      return IntentClassificationResult(
        intent: ConversationalIntent.conversationReset,
        confidence: 0.95,
        entities: entities,
        originalQuery: query,
        subCategory: 'reset',
      );
    }

    // 2. Unsupported Domain Intent (Code, Math, General Non-Dating Web Inquiries)
    if (_matchesAny(clean, [
      'write code', 'python script', 'javascript', 'solve equation', 'calculate',
      'derivative of', 'integral of', 'who is the president of', 'capital of',
      'debug this', 'write an essay', 'do my homework', 'weather in'
    ]) || clean.startsWith('code ') || clean.contains('def ') || clean.contains('function()')) {
      return IntentClassificationResult(
        intent: ConversationalIntent.unsupported,
        confidence: 0.92,
        entities: entities,
        originalQuery: query,
        subCategory: 'out_of_domain',
      );
    }

    // 3. Situationship App Features & FAQ Intent
    if (_matchesAny(clean, [
      'how do coins work', 'what are coins', 'buy coins', 'earn coins',
      'anonymous confession', 'secret confession', 'confession works',
      'how does confession work', 'what is spotlight', 'how to use spotlight',
      'how to get verified', 'verification process', 's badge', 's-badge',
      'what is situationship', 'how does matching work', 'rewind work', 'undo swipe'
    ]) || clean.contains('coin') || clean.contains('confession') || clean.contains('spotlight') || clean.contains('verified')) {
      String sub = 'general_faq';
      if (clean.contains('coin')) sub = 'coins';
      if (clean.contains('confession')) sub = 'confession';
      if (clean.contains('spotlight')) sub = 'spotlight';
      if (clean.contains('verifi') || clean.contains('s badge')) sub = 'verification';

      return IntentClassificationResult(
        intent: ConversationalIntent.appFeatures,
        confidence: 0.90,
        entities: entities,
        originalQuery: query,
        subCategory: sub,
      );
    }

    // 4. Specific Profile Inquiry (referring to a previously shown profile by index or name)
    if (hasActiveProfileContext &&
        (entities.referencedProfileIndex != null || entities.referencedProfileName != null ||
            _matchesAny(clean, [
              'tell me more about', 'why did you pick', 'why her', 'why him',
              'what does she like', 'what does he like', 'tell me about the first',
              'tell me about the second', 'tell me about the third', 'about the first one',
              'about the second one', 'about the third one', 'who is this'
            ]))) {
      return IntentClassificationResult(
        intent: ConversationalIntent.profileInquiry,
        confidence: 0.88,
        entities: entities,
        originalQuery: query,
        subCategory: 'profile_detail',
      );
    }

    // 5. Profile Feedback / Exclusion Intent
    if (hasActiveProfileContext && _matchesAny(clean, [
      'not like this', 'not feeling these', 'dont like', "don't like", 'not like the first',
      'not like the second', 'someone different', 'different people', 'none of these',
      'no smokers', 'too young', 'too far'
    ])) {
      return IntentClassificationResult(
        intent: ConversationalIntent.profileFeedback,
        confidence: 0.87,
        entities: entities,
        originalQuery: query,
        subCategory: 'exclusion',
      );
    }

    // 6. Continuation / Pagination Intent
    if (_matchesAny(clean, [
      'show more', 'show me more', 'more profiles', 'anyone else', 'who else',
      'someone else', 'show others', 'any more', 'next profiles', 'next one',
      'any other profiles', 'is there more', 'other options'
    ])) {
      return IntentClassificationResult(
        intent: ConversationalIntent.profileContinuation,
        confidence: 0.92,
        entities: entities,
        originalQuery: query,
        subCategory: 'more',
      );
    }

    // 7. Emotional Support & Empathy Intent
    final hasEmotionalKeyword = _matchesAny(clean, [
      'im bored', "i'm bored", 'boring day', 'so bored', 'bored', 'feeling lonely', 'feel lonely',
      'lonely', 'got ghosted', 'i got ghosted', 'ghosting sucks', 'heartbroken',
      'dating is hard', 'dating is exhausting', 'dating fatigue', 'nervous about',
      'scared of rejection', 'feeling down', 'sad today', 'nobody likes me',
      'tired of dating', 'tierd of dating', 'tired of dating apps', 'done with dating',
      'sick of dating', 'breakup', 'broke up', 'feel unloved', 'bad date', 'awful date'
    ]);

    if (hasEmotionalKeyword) {
      String sub = 'general_support';
      if (clean.contains('ghost')) sub = 'ghosting';
      if (clean.contains('bored') || clean.contains('boring')) sub = 'boredom';
      if (clean.contains('lonel')) sub = 'loneliness';
      if (clean.contains('nervous') || clean.contains('scared')) sub = 'dating_anxiety';
      if (clean.contains('exhaust') || clean.contains('tired') || clean.contains('tierd')) sub = 'dating_fatigue';

      return IntentClassificationResult(
        intent: ConversationalIntent.emotionalSupport,
        confidence: 0.90,
        entities: entities,
        originalQuery: query,
        subCategory: sub,
      );
    }

    // 8. Dating & Social Advice Intent
    if (_matchesAny(clean, [
      'first date idea', 'first date spot', 'good first date', 'how to break the ice',
      'how to start a conversation', 'what should i say', 'opening line',
      'conversation starter', 'good opener', 'red flag', 'green flag',
      'how do i know if they like me', 'signs they like me', 'how to ask someone out',
      'what should i wear', 'how to keep a conversation going', 'profile tips',
      'make my profile better', 'dating advice'
    ])) {
      String sub = 'dating_advice';
      if (clean.contains('first date') || clean.contains('date spot')) sub = 'first_date';
      if (clean.contains('ice') || clean.contains('opener') || clean.contains('what should i say')) sub = 'icebreaker';
      if (clean.contains('red flag') || clean.contains('green flag')) sub = 'flags';
      if (clean.contains('profile')) sub = 'profile_advice';

      return IntentClassificationResult(
        intent: ConversationalIntent.datingAdvice,
        confidence: 0.89,
        entities: entities,
        originalQuery: query,
        subCategory: sub,
      );
    }

    // 9. Casual Chat / Banter Intent
    if (_matchesAny(clean, [
      'hello', 'hi', 'hey', 'sup', 'yo', 'good morning', 'good evening', 'how are you',
      'how r u', 'who are you', 'what are you', 'tell me a joke', 'make me laugh',
      'are you real', 'what can you do', 'nice to meet you', 'thank you', 'thanks'
    ]) || clean == 'hi' || clean == 'hey' || clean == 'hello' || clean == 'sup') {
      return IntentClassificationResult(
        intent: ConversationalIntent.casualChat,
        confidence: 0.92,
        entities: entities,
        originalQuery: query,
        subCategory: clean.contains('joke') ? 'joke' : 'greeting',
      );
    }

    // 10. Preference Refinement Intent (modifying previous criteria)
    final isExplicitDiscovery = _matchesAny(clean, [
      'find someone', 'find me', 'show me', 'recommend someone', 'looking for someone',
      'match me with', 'search for', 'can you find', 'need someone', 'want someone',
      'meet someone', 'someone interesting', 'someone new', 'connect with someone',
      'introduce me to', 'get me a date'
    ]);

    if (!isExplicitDiscovery && hasActiveProfileContext &&
        (clean.startsWith('and ') || clean.startsWith('also ') || clean.startsWith('someone ') ||
            clean.startsWith('more ') || clean.contains('more adventurous') || clean.contains('closer') ||
            entities.hasCriteria)) {
      return IntentClassificationResult(
        intent: ConversationalIntent.preferenceRefinement,
        confidence: 0.85,
        entities: entities,
        originalQuery: query,
        subCategory: 'refinement',
      );
    }

    // 11. Profile Discovery Intent
    if (isExplicitDiscovery || entities.hasCriteria) {
      return IntentClassificationResult(
        intent: ConversationalIntent.profileDiscovery,
        confidence: 0.88,
        entities: entities,
        originalQuery: query,
        subCategory: 'search',
      );
    }

    // 12. Short or Ambiguous Intent
    if (clean.length < 5 || clean == 'ok' || clean == 'cool' || clean == 'yes' || clean == 'no' || clean == 'maybe' || clean == 'sure' || clean == 'idk') {
      return IntentClassificationResult(
        intent: ConversationalIntent.clarification,
        confidence: 0.75,
        entities: entities,
        originalQuery: query,
        subCategory: 'short_reply',
      );
    }

    // Default Fallback: Treat as Casual Chat rather than forcing unwanted profile recommendations
    return IntentClassificationResult(
      intent: ConversationalIntent.casualChat,
      confidence: 0.60,
      entities: entities,
      originalQuery: query,
      subCategory: 'open_chat',
    );
  }

  /// Extracts structured entities (passions, traits, intents, age, location, etc.)
  static ExtractedEntities extractEntities(String query, {List<String> activeProfileNames = const []}) {
    final clean = _clean(query);

    // 1. Gender hint
    String? gender;
    if (_matchesAny(clean, ['girl', 'girls', 'woman', 'women', 'female', 'chick', 'she', 'her', 'ladies'])) {
      gender = 'female';
    } else if (_matchesAny(clean, ['boy', 'boys', 'guy', 'guys', 'man', 'men', 'male', 'dude', 'he', 'him'])) {
      gender = 'male';
    }

    // 2. Relationship Intent
    String? relationshipIntent;
    if (_matchesAny(clean, ['serious', 'long term', 'settle down', 'meaningful', 'commitment', 'partner'])) {
      relationshipIntent = 'serious';
    } else if (_matchesAny(clean, ['casual', 'situationship', 'fun', 'hookup', 'short term', 'nothing serious'])) {
      relationshipIntent = 'casual';
    } else if (_matchesAny(clean, ['friend', 'friends', 'friendship', 'platonic', 'buddies'])) {
      relationshipIntent = 'friendship';
    } else if (_matchesAny(clean, ['open', 'open relationship', 'ethical non monogamy', 'enm'])) {
      relationshipIntent = 'open';
    }

    // 3. Dealbreakers
    final dealbreakers = <String>[];
    if (_matchesAny(clean, ['no smoking', 'non smoker', 'doesnt smoke', "doesn't smoke", 'no cigarettes'])) {
      dealbreakers.add('smoking');
    }
    if (_matchesAny(clean, ['no drinking', 'non drinker', 'doesnt drink', "doesn't drink", 'sober', 'teetotaler'])) {
      dealbreakers.add('drinking');
    }

    // 4. Age extraction (e.g. "between 22 and 26", "in their 20s", "older than 25")
    int? minAge;
    int? maxAge;
    final betweenMatch = RegExp(r'between\s+(\d{2})\s+(?:and|to|-)\s+(\d{2})').firstMatch(clean);
    if (betweenMatch != null) {
      minAge = int.tryParse(betweenMatch.group(1)!);
      maxAge = int.tryParse(betweenMatch.group(2)!);
    } else {
      final olderMatch = RegExp(r'(?:older than|above|over)\s+(\d{2})').firstMatch(clean);
      if (olderMatch != null) {
        minAge = int.tryParse(olderMatch.group(1)!);
      }
      final youngerMatch = RegExp(r'(?:younger than|under|below)\s+(\d{2})').firstMatch(clean);
      if (youngerMatch != null) {
        maxAge = int.tryParse(youngerMatch.group(1)!);
      }
      if (clean.contains('in their 20s') || clean.contains('in 20s')) {
        minAge = 20;
        maxAge = 29;
      } else if (clean.contains('in their 30s') || clean.contains('in 30s')) {
        minAge = 30;
        maxAge = 39;
      }
    }

    // Ensure compliance with legal 18+ requirement
    if (minAge != null && minAge < 18) minAge = 18;

    // 5. Location / Nearby
    final prefersNearby = _matchesAny(clean, [
      'nearby', 'close', 'close to me', 'in my city', 'around here', 'local', 'in my area'
    ]);

    // 6. Passions and Interests
    final interests = <String>[];
    final interestMap = {
      'music': ['music', 'songs', 'concerts', 'indie', 'rock', 'hip hop', 'jazz', 'vinyl', 'techno'],
      'art': ['art', 'artistic', 'painting', 'drawing', 'sketching', 'design', 'museums', 'galleries'],
      'photography': ['photography', 'photos', 'camera', 'film', 'analog', 'photographer'],
      'travel': ['travel', 'travelling', 'traveling', 'wanderlust', 'road trip', 'trips', 'explore', 'backpacking'],
      'fitness': ['gym', 'fitness', 'workout', 'yoga', 'running', 'lifting', 'crossfit', 'athletics'],
      'reading': ['books', 'reading', 'literature', 'bookworm', 'novels', 'poetry', 'writer'],
      'food': ['food', 'foodie', 'cooking', 'baking', 'chef', 'dining', 'coffee', 'cafes', 'matcha'],
      'gaming': ['gaming', 'gamer', 'games', 'playstation', 'pc gaming', 'nintendo', 'anime', 'manga'],
      'movies': ['movies', 'cinema', 'films', 'cinematography', 'shows', 'bingeing'],
      'dance': ['dance', 'dancing', 'salsa', 'ballet', 'techno clubs', 'parties'],
      'tech': ['tech', 'coding', 'startup', 'software', 'programming', 'ai', 'crypto'],
      'nature': ['hiking', 'camping', 'nature', 'mountains', 'beach', 'sunset', 'stargazing'],
    };

    interestMap.forEach((category, syns) {
      for (final s in syns) {
        if (clean.contains(s)) {
          interests.add(category);
          break;
        }
      }
    });

    // 7. Personality Traits
    final personality = <String>[];
    final traitMap = {
      'introvert': ['introvert', 'introverted', 'quiet', 'shy', 'cozy', 'stays in', 'calm'],
      'extrovert': ['extrovert', 'extroverted', 'outgoing', 'social', 'high energy', 'bubbly'],
      'adventurous': ['adventurous', 'wild', 'spontaneous', 'thrill', 'bold', 'brave'],
      'funny': ['funny', 'humorous', 'witty', 'sarcastic', 'jokes', 'hilarious', 'goofy'],
      'ambitious': ['ambitious', 'driven', 'hustler', 'hardworking', 'career oriented', 'focused'],
      'chill': ['chill', 'laidback', 'relaxed', 'easygoing', 'peaceful', 'zen'],
      'creative': ['creative', 'imaginative', 'original', 'deep thinker', 'artsy'],
      'romantic': ['romantic', 'affectionate', 'hopeless romantic', 'sweet', 'tender'],
    };

    traitMap.forEach((trait, syns) {
      for (final s in syns) {
        if (clean.contains(s)) {
          personality.add(trait);
          break;
        }
      }
    });

    // 8. Profile reference detection (ordinal or by name)
    int? refIndex;
    if (clean.contains('first') || clean.contains('1st') || clean.contains('number 1') || clean.contains('#1')) {
      refIndex = 0;
    } else if (clean.contains('second') || clean.contains('2nd') || clean.contains('number 2') || clean.contains('#2')) {
      refIndex = 1;
    } else if (clean.contains('third') || clean.contains('3rd') || clean.contains('number 3') || clean.contains('#3')) {
      refIndex = 2;
    }

    String? refName;
    for (final name in activeProfileNames) {
      if (clean.contains(name.toLowerCase())) {
        refName = name;
        break;
      }
    }

    return ExtractedEntities(
      interests: interests.toSet().toList(),
      personalityTraits: personality.toSet().toList(),
      relationshipIntent: relationshipIntent,
      dealbreakers: dealbreakers.toSet().toList(),
      genderHint: gender,
      minAge: minAge,
      maxAge: maxAge,
      prefersNearby: prefersNearby,
      referencedProfileIndex: refIndex,
      referencedProfileName: refName,
    );
  }

  static String _clean(String input) {
    var s = input
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Normalize common conversational typos & abbreviations
    s = s
        .replaceAll(RegExp(r'\btierd\b'), 'tired')
        .replaceAll(RegExp(r'\bgril\b'), 'girl')
        .replaceAll(RegExp(r'\bgurl\b'), 'girl')
        .replaceAll(RegExp(r'\btravellin\b'), 'traveling')
        .replaceAll(RegExp(r'\btravelling\b'), 'traveling')
        .replaceAll(RegExp(r'\bsmk\b'), 'smoke')
        .replaceAll(RegExp(r'\bdoesnt\b'), "doesn't")
        .replaceAll(RegExp(r'\bpls\b'), 'please');

    return s;
  }

  static bool _matchesAny(String text, List<String> triggers) {
    for (final t in triggers) {
      if (t.contains(' ')) {
        if (text.contains(t)) return true;
      } else {
        if (RegExp(r'\b' + RegExp.escape(t) + r'\b').hasMatch(text)) return true;
      }
    }
    return false;
  }
}
