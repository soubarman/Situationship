import 'dart:math' as math;
import 'vibe_matrix_vocabulary.dart';
import 'conversational_intent.dart';

/// Structured outcome of on-device semantic sentence understanding
class NLUIntentResult {
  final String originalQuery;
  final Map<String, double> denseVector; // dimensionId -> normalized weight (0.0 to 1.0)
  final List<String> detectedDimensionIds;
  final List<String> dealbreakers;
  final String? targetRelationshipIntent;
  final String? genderHint; // 'female' | 'male' | null
  final List<String> extractedKeywords;
  final String naturalSummary;
  final bool isMoreOrContinuation;
  final ConversationalIntent conversationalIntent;
  final IntentClassificationResult? classification;

  const NLUIntentResult({
    required this.originalQuery,
    required this.denseVector,
    required this.detectedDimensionIds,
    required this.dealbreakers,
    this.targetRelationshipIntent,
    this.genderHint,
    required this.extractedKeywords,
    required this.naturalSummary,
    this.isMoreOrContinuation = false,
    this.conversationalIntent = ConversationalIntent.profileDiscovery,
    this.classification,
  });

  bool get isEmpty => detectedDimensionIds.isEmpty && dealbreakers.isEmpty && !isMoreOrContinuation;
}

class OnDeviceNLUEngine {
  /// Analyzes a conversational user query completely on-device
  static NLUIntentResult parse(
    String query, {
    bool hasActiveProfileContext = false,
    List<String> activeProfileNames = const [],
  }) {
    if (query.trim().isEmpty) {
      return const NLUIntentResult(
        originalQuery: '',
        denseVector: {},
        detectedDimensionIds: [],
        dealbreakers: [],
        extractedKeywords: [],
        naturalSummary: 'Open to everyone',
        isMoreOrContinuation: false,
        conversationalIntent: ConversationalIntent.casualChat,
      );
    }

    // 0. Classify High-Level Conversational Intent & Entities
    final classification = ConversationalIntentClassifier.classify(
      query,
      hasActiveProfileContext: hasActiveProfileContext,
      activeProfileNames: activeProfileNames,
    );

    final normalized = _cleanText(query);
    final tokens = normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    final isMore = classification.intent == ConversationalIntent.profileContinuation ||
        _containsAny(normalized, [
          'more profiles', 'no more profiles', 'no more', 'is there no more',
          'any other profiles', 'any other profile', 'other profiles', 'other profile',
          'any other', 'another profile', 'another one', 'show more', 'show me more',
          'anyone else', 'who else', 'someone else', 'show others', 'different profiles',
          'different people', 'different one', 'different profile', 'is that all',
          'is that it', 'any more', 'next', 'more', 'others',
        ]);

    // 1. Gender intent detection
    final genderHint = classification.entities.genderHint ??
        (_containsAny(normalized, ['girl', 'woman', 'female', 'chick', 'lady', 'her', 'she'])
            ? 'female'
            : (_containsAny(normalized, ['boy', 'guy', 'man', 'male', 'dude', 'him', 'he'])
                ? 'male'
                : null));

    // 2. Dealbreakers & Negation parsing
    final dealbreakers = <String>{...classification.entities.dealbreakers};
    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (VibeMatrixVocabulary.negationTokens.contains(token)) {
        final clauseEnd = math.min(i + 6, tokens.length);
        final clause = tokens.sublist(i + 1, clauseEnd).join(' ');

        if (clause.contains('smoke') || clause.contains('smoking') || clause.contains('cigarette')) {
          dealbreakers.add('smoking');
        }
        if (clause.contains('drink') || clause.contains('drinking') || clause.contains('alcohol') || clause.contains('booze')) {
          dealbreakers.add('drinking');
        }
        if (clause.contains('casual') || clause.contains('hookup')) {
          dealbreakers.add('casual');
        }
      }
    }

    if (normalized.contains('non smoker') || normalized.contains('no smoking')) {
      dealbreakers.add('smoking');
    }
    if (normalized.contains('non drinker') || normalized.contains('teetotaler') || normalized.contains('no alcohol') || normalized.contains('sober')) {
      dealbreakers.add('drinking');
    }

    // 3. Dense semantic vector extraction over VibeMatrix vocabulary
    final rawScores = <String, double>{};
    final detectedIds = <String>[];
    final extractedWords = <String>[];

    for (final dim in VibeMatrixVocabulary.dimensions) {
      double matchScore = 0.0;

      for (final syn in dim.synonyms) {
        if (syn.contains(' ')) {
          if (normalized.contains(syn)) {
            matchScore += 2.0 * dim.defaultWeight;
            extractedWords.add(syn);
          }
        } else {
          if (tokens.contains(syn)) {
            matchScore += 1.0 * dim.defaultWeight;
            extractedWords.add(syn);
          }
        }
      }

      if (matchScore > 0) {
        rawScores[dim.id] = matchScore;
        detectedIds.add(dim.id);
      }
    }

    // 4. Intent classification
    String? relationshipIntent = classification.entities.relationshipIntent;
    if (relationshipIntent == null) {
      if (rawScores.containsKey('intent_serious') || normalized.contains('serious') || normalized.contains('long term')) {
        relationshipIntent = 'serious';
      } else if (rawScores.containsKey('intent_casual') || normalized.contains('casual') || normalized.contains('situationship')) {
        relationshipIntent = 'casual';
      } else if (rawScores.containsKey('intent_friendship') || normalized.contains('friend')) {
        relationshipIntent = 'friendship';
      }
    }

    // 5. Vector Normalization (L2-norm so dot product == Cosine Similarity)
    final denseVector = <String, double>{};
    if (rawScores.isNotEmpty) {
      double sumSquares = 0.0;
      for (final val in rawScores.values) {
        sumSquares += val * val;
      }
      final norm = math.sqrt(sumSquares);
      if (norm > 0) {
        rawScores.forEach((key, val) {
          denseVector[key] = val / norm;
        });
      }
    }

    // 6. Synthesize natural language summary
    final naturalSummary = _buildSummary(detectedIds, dealbreakers.toList(), relationshipIntent);

    return NLUIntentResult(
      originalQuery: query,
      denseVector: denseVector,
      detectedDimensionIds: detectedIds,
      dealbreakers: dealbreakers.toList(),
      targetRelationshipIntent: relationshipIntent,
      genderHint: genderHint,
      extractedKeywords: extractedWords.toSet().toList(),
      naturalSummary: naturalSummary,
      isMoreOrContinuation: isMore,
      conversationalIntent: classification.intent,
      classification: classification,
    );
  }

  static String _cleanText(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _containsAny(String text, List<String> targets) {
    for (final t in targets) {
      if (RegExp('\\b$t\\b').hasMatch(text)) return true;
    }
    return false;
  }

  static String _buildSummary(
    List<String> detectedIds,
    List<String> dealbreakers,
    String? intent,
  ) {
    final parts = <String>[];

    final traits = detectedIds.take(3).map((id) {
      final dim = VibeMatrixVocabulary.dimensions.firstWhere(
        (d) => d.id == id,
        orElse: () => VibeDimension(id: id, canonicalName: id, category: '', synonyms: []),
      );
      return dim.canonicalName;
    }).toList();

    if (traits.isNotEmpty) {
      parts.add(traits.join(', '));
    }

    if (intent != null) {
      parts.add('seeking $intent relationship');
    }

    if (dealbreakers.isNotEmpty) {
      parts.add('no ${dealbreakers.join(', ')}');
    }

    return parts.isEmpty ? 'Looking for great vibes' : parts.join(' • ');
  }
}
