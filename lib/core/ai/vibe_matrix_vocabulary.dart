/// ─────────────────────────────────────────────────────────────────────────────
/// Situationship VibeMatrix™ Semantic Domain Ontology & Vocabulary
/// Pure On-Device Semantic Dictionary for Dating & Social Intent Understanding
/// ─────────────────────────────────────────────────────────────────────────────
library;

class VibeDimension {
  final String id;
  final String canonicalName;
  final String category; // 'personality' | 'music' | 'lifestyle' | 'creative' | 'intent' | 'vibe'
  final List<String> synonyms;
  final double defaultWeight;

  const VibeDimension({
    required this.id,
    required this.canonicalName,
    required this.category,
    required this.synonyms,
    this.defaultWeight = 1.0,
  });
}

class VibeMatrixVocabulary {
  static const List<VibeDimension> dimensions = [
    // ── 1. Personality & Social Archetype ──────────────────────────────────────
    VibeDimension(
      id: 'introvert',
      canonicalName: 'Introverted & Thoughtful',
      category: 'personality',
      synonyms: [
        'introvert', 'introverted', 'quiet', 'shy', 'homebody', 'calm',
        'reserved', 'lowkey', 'cozy', 'stays in', 'peaceful', 'private'
      ],
      defaultWeight: 1.2,
    ),
    VibeDimension(
      id: 'extrovert',
      canonicalName: 'Extroverted & Outgoing',
      category: 'personality',
      synonyms: [
        'extrovert', 'extroverted', 'outgoing', 'social', 'party', 'parties',
        'life of the party', 'talkative', 'high energy', 'bubbly', 'loud'
      ],
      defaultWeight: 1.2,
    ),
    VibeDimension(
      id: 'ambitious',
      canonicalName: 'Ambitious & Driven',
      category: 'personality',
      synonyms: [
        'ambitious', 'driven', 'founder', 'entrepreneur', 'startup', 'hustler',
        'career-oriented', 'smart', 'goal-oriented', 'hardworking', 'success'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'philosophical',
      canonicalName: 'Deep Thinker & Philosophical',
      category: 'personality',
      synonyms: [
        'deep', 'philosophy', 'intellectual', 'curious', 'reader', 'bookworm',
        'existential', 'meaningful', 'late night talks', 'conversations', 'debates'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'spontaneous',
      canonicalName: 'Spontaneous & Adventurous',
      category: 'personality',
      synonyms: [
        'spontaneous', 'adventurous', 'wild', 'road trip', 'impulsive',
        'unplanned', 'thrill', 'explore', 'wanderlust', 'free spirit'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'chill',
      canonicalName: 'Chill & Laidback',
      category: 'personality',
      synonyms: [
        'chill', 'laidback', 'relaxed', 'easygoing', 'no drama', 'zen',
        'wholesome', 'peaceful', 'down to earth'
      ],
      defaultWeight: 1.0,
    ),
    VibeDimension(
      id: 'romantic',
      canonicalName: 'Hopeless Romantic',
      category: 'personality',
      synonyms: [
        'romantic', 'lover', 'flowers', 'date night', 'affectionate',
        'love letters', 'cuddles', 'tender', 'gentle', 'sweet', 'soft'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'goofy',
      canonicalName: 'Humorous & Playful',
      category: 'personality',
      synonyms: [
        'goofy', 'funny', 'humor', 'memes', 'silly', 'wit', 'sarcastic',
        'banter', 'playful', 'cracks jokes', 'laugh', 'giggly'
      ],
      defaultWeight: 1.0,
    ),

    // ── 2. Creative & Passion Pursuits ─────────────────────────────────────────
    VibeDimension(
      id: 'artistic',
      canonicalName: 'Artistic & Aesthetic',
      category: 'creative',
      synonyms: [
        'art', 'artistic', 'artist', 'painting', 'drawing', 'sketching',
        'museum', 'galleries', 'aesthetic', 'sculpture', 'creative', 'visual'
      ],
      defaultWeight: 1.2,
    ),
    VibeDimension(
      id: 'photography',
      canonicalName: 'Photography & Film',
      category: 'creative',
      synonyms: [
        'photo', 'photography', 'photographer', 'cinema', 'cinematography',
        'camera', '35mm', 'analog', 'film', 'polaroid', 'movies', 'cinephile'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'writing',
      canonicalName: 'Writing & Literature',
      category: 'creative',
      synonyms: [
        'writing', 'writer', 'poetry', 'poet', 'books', 'novels',
        'literature', 'stories', 'journaling', 'reading'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'design',
      canonicalName: 'Design & Architecture',
      category: 'creative',
      synonyms: [
        'design', 'designer', 'ui/ux', 'architecture', 'fashion', 'styling',
        'typography', 'interior design', 'minimalist'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'tech',
      canonicalName: 'Tech & Engineering',
      category: 'creative',
      synonyms: [
        'tech', 'technology', 'developer', 'coding', 'engineer', 'ai',
        'software', 'nerd', 'hacker', 'builds', 'geek'
      ],
      defaultWeight: 1.0,
    ),

    // ── 3. Music & Subcultures ────────────────────────────────────────────────
    VibeDimension(
      id: 'indie',
      canonicalName: 'Indie & Alternative',
      category: 'music',
      synonyms: [
        'indie', 'indie rock', 'indie pop', 'alternative', 'shoegaze',
        'bedroom pop', 'tame impala', 'arctic monkeys', 'mitski', 'boygenius'
      ],
      defaultWeight: 1.3,
    ),
    VibeDimension(
      id: 'retro',
      canonicalName: 'Retro & 80s/90s Vinyl',
      category: 'music',
      synonyms: [
        'retro', '80s', '90s', 'vintage', 'vinyl', 'nostalgic', 'disco',
        'synthwave', 'cassette', 'old school', 'fleetwood mac', 'queen'
      ],
      defaultWeight: 1.2,
    ),
    VibeDimension(
      id: 'rock',
      canonicalName: 'Rock & Metal',
      category: 'music',
      synonyms: [
        'rock', 'punk', 'metal', 'grunge', 'electric guitar', 'drums',
        'nirvana', 'hard rock', 'concerts', 'moshpit'
      ],
      defaultWeight: 1.2,
    ),
    VibeDimension(
      id: 'hiphop',
      canonicalName: 'Hip-Hop & R&B',
      category: 'music',
      synonyms: [
        'hiphop', 'hip hop', 'rap', 'r&b', 'rnb', 'soul', 'beats',
        'kendrick', 'drake', 'frank ocean', 'sza', 'urban'
      ],
      defaultWeight: 1.2,
    ),
    VibeDimension(
      id: 'electronic',
      canonicalName: 'EDM & Techno',
      category: 'music',
      synonyms: [
        'edm', 'techno', 'house music', 'rave', 'raves', 'electronic',
        'dj', 'festivals', 'clubbing', 'boiler room'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'acoustic',
      canonicalName: 'Acoustic & Folk',
      category: 'music',
      synonyms: [
        'acoustic', 'folk', 'guitar', 'singer-songwriter', 'campfire',
        'lofi', 'lo-fi', 'chill beats', 'soft melodies'
      ],
      defaultWeight: 1.1,
    ),

    // ── 4. Lifestyle, Habits & Vibe ───────────────────────────────────────────
    VibeDimension(
      id: 'fitness',
      canonicalName: 'Fitness & Athletic',
      category: 'lifestyle',
      synonyms: [
        'gym', 'fitness', 'workout', 'lifting', 'crossfit', 'runner', 'running',
        'yoga', 'pilates', 'athletic', 'sports', 'calisthenics', 'gains'
      ],
      defaultWeight: 1.2,
    ),
    VibeDimension(
      id: 'coffee',
      canonicalName: 'Coffee & Cafe Hopping',
      category: 'lifestyle',
      synonyms: [
        'coffee', 'cafe', 'cafes', 'espresso', 'cappuccino', 'matcha',
        'cafe hopping', 'coffee dates', 'barista', 'croissant'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'foodie',
      canonicalName: 'Foodie & Cooking',
      category: 'lifestyle',
      synonyms: [
        'food', 'foodie', 'cooking', 'chef', 'bake', 'baking', 'street food',
        'fine dining', 'ramen', 'tasting', 'recipes', 'eats'
      ],
      defaultWeight: 1.0,
    ),
    VibeDimension(
      id: 'travel',
      canonicalName: 'Traveler & Explorer',
      category: 'lifestyle',
      synonyms: [
        'travel', 'traveling', 'traveler', 'mountains', 'beach', 'hiking',
        'trekking', 'camping', 'backpacking', 'flights', 'places'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'pet_lover',
      canonicalName: 'Pet & Animal Lover',
      category: 'lifestyle',
      synonyms: [
        'dog', 'dogs', 'cat', 'cats', 'dog lover', 'cat lover', 'pets',
        'puppy', 'kitten', 'animal lover'
      ],
      defaultWeight: 1.2,
    ),
    VibeDimension(
      id: 'night_owl',
      canonicalName: 'Night Owl & Midnight Drives',
      category: 'lifestyle',
      synonyms: [
        'night owl', 'late night', 'midnight', 'night drives', 'stargazing',
        '3am talks', 'after dark', 'moon'
      ],
      defaultWeight: 1.1,
    ),
    VibeDimension(
      id: 'nature',
      canonicalName: 'Nature & Outdoors',
      category: 'lifestyle',
      synonyms: [
        'nature', 'outdoors', 'greenery', 'plants', 'sunsets', 'sunrise',
        'gardening', 'hiking', 'mountains'
      ],
      defaultWeight: 1.0,
    ),

    // ── 5. Relationship Intentions ────────────────────────────────────────────
    VibeDimension(
      id: 'intent_serious',
      canonicalName: 'Serious & Long Term',
      category: 'intent',
      synonyms: [
        'serious', 'long term', 'long-term', 'commitment', 'committed',
        'meaningful', 'forever', 'marriage', 'deep connection', 'monogamous'
      ],
      defaultWeight: 1.4,
    ),
    VibeDimension(
      id: 'intent_casual',
      canonicalName: 'Casual & Fun',
      category: 'intent',
      synonyms: [
        'casual', 'short term', 'situationship', 'fun', 'hookup', 'spontaneous',
        'nothing serious', 'vibes only', 'see where it goes'
      ],
      defaultWeight: 1.4,
    ),
    VibeDimension(
      id: 'intent_friendship',
      canonicalName: 'Friendship First',
      category: 'intent',
      synonyms: [
        'friendship', 'friends', 'new friends', 'buddies', 'platonic', 'connection'
      ],
      defaultWeight: 1.2,
    ),

    // ── 6. Dealbreakers (Negations / Exclusions) ──────────────────────────────
    VibeDimension(
      id: 'non_smoker',
      canonicalName: 'Non-Smoker',
      category: 'lifestyle',
      synonyms: ['non smoker', 'no smoking', 'doesnt smoke', 'clean lungs', 'no cigarettes'],
      defaultWeight: 1.3,
    ),
    VibeDimension(
      id: 'non_drinker',
      canonicalName: 'Non-Drinker (Teetotaler)',
      category: 'lifestyle',
      synonyms: ['sober', 'no alcohol', 'teetotaler', 'doesnt drink', 'non drinker'],
      defaultWeight: 1.3,
    ),
  ];

  /// Set of common stop words to ignore during NLU parsing
  static const Set<String> stopWords = {
    'i', 'me', 'my', 'myself', 'we', 'our', 'ours', 'ourselves', 'you', "you're",
    'he', 'she', 'him', 'her', 'it', 'its', 'they', 'them', 'their', 'what',
    'which', 'who', 'whom', 'this', 'that', 'these', 'those', 'am', 'is', 'are',
    'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had', 'having', 'do',
    'does', 'did', 'doing', 'a', 'an', 'the', 'and', 'but', 'if', 'or', 'because',
    'as', 'until', 'while', 'of', 'at', 'by', 'for', 'with', 'about', 'against',
    'between', 'into', 'through', 'during', 'before', 'after', 'above', 'below',
    'to', 'from', 'up', 'down', 'in', 'out', 'on', 'off', 'over', 'under', 'again',
    'further', 'then', 'once', 'here', 'there', 'when', 'where', 'why', 'how',
    'all', 'any', 'both', 'each', 'few', 'more', 'most', 'other', 'some', 'such',
    'only', 'own', 'same', 'so', 'than', 'too', 'very', 's', 't', 'can', 'will',
    'just', 'don', 'should', 'now', 'want', 'looking', 'find', 'suggest', 'someone',
    'girl', 'boy', 'person', 'profile', 'profiles', 'match', 'matches', 'please', 'like'
  };

  /// Common negation tokens
  static const Set<String> negationTokens = {
    'no', 'not', 'never', 'dont', "don't", 'doesnt', "doesn't", 'without', 'except', 'hate', 'dislike'
  };
}

