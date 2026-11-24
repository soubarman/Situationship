import '../../core/models/user_model.dart';
import 'on_device_nlu_engine.dart';
import 'vibe_matrix_vocabulary.dart';

class MatchRationale {
  final String headline;
  final String detailedExplanation;
  final String icebreakerSuggestion;

  const MatchRationale({
    required this.headline,
    required this.detailedExplanation,
    required this.icebreakerSuggestion,
  });
}

class MatchRationaleGenerator {
  /// Generates a warm, authentic dating concierge explanation completely on-device
  static MatchRationale generate({
    required UserModel candidate,
    required NLUIntentResult userIntent,
    required List<String> matchedDimensionIds,
    required int compatibilityScore,
  }) {
    final name = candidate.name.split(' ').first;

    // 1. Resolve human-readable trait labels
    final traitNames = matchedDimensionIds.map((id) {
      final dim = VibeMatrixVocabulary.dimensions.firstWhere(
        (d) => d.id == id,
        orElse: () => VibeDimension(id: id, canonicalName: id, category: '', synonyms: []),
      );
      return dim.canonicalName;
    }).toList();

    // 2. Headline
    final headline = '$compatibilityScore% Vibe Compatibility';

    // 3. Narrative generation based on candidate attributes and user intent
    final buffer = StringBuffer();
    buffer.write('I handpicked $name for you. ');

    if (matchedDimensionIds.contains('indie') || matchedDimensionIds.contains('retro') || matchedDimensionIds.contains('music')) {
      buffer.write('You both have an ear for indie & alternative music, ');
    } else if (matchedDimensionIds.contains('artistic') || matchedDimensionIds.contains('design') || matchedDimensionIds.contains('photography')) {
      buffer.write('Her creative, artistic energy directly mirrors what you\'re looking for, ');
    } else if (matchedDimensionIds.contains('philosophical') || matchedDimensionIds.contains('ambitious')) {
      buffer.write('She loves meaningful conversations and shares your ambitious drive, ');
    } else if (matchedDimensionIds.contains('introvert')) {
      buffer.write('She appreciates cozy, quiet vibes rather than loud superficial scenes, ');
    } else if (traitNames.isNotEmpty) {
      buffer.write('Your energies align across ${traitNames.take(2).join(' and ')}, ');
    } else {
      buffer.write('Your energies align across mutual passions, ');
    }

    if (candidate.relationshipIntent != null && candidate.relationshipIntent == userIntent.targetRelationshipIntent) {
      buffer.write('and she is also specifically looking for something ${candidate.relationshipIntent}.');
    } else if (candidate.isVerified) {
      buffer.write('plus she is verified on Situationship.');
    } else {
      buffer.write('with an undeniable spark in lifestyle.');
    }

    // 4. Personalized icebreaker starter
    String icebreaker = 'Say Hi to $name ✨';
    if (candidate.interests.isNotEmpty) {
      final sharedInterest = candidate.interests.first;
      icebreaker = 'Ask $name about her take on $sharedInterest!';
    } else if (matchedDimensionIds.contains('indie')) {
      icebreaker = 'Ask what song is currently on repeat in her playlist 🎧';
    } else if (matchedDimensionIds.contains('coffee')) {
      icebreaker = 'Ask for her favorite hidden cafe in town ☕';
    } else if (matchedDimensionIds.contains('night_owl')) {
      icebreaker = 'Ask about her favorite late night drive route 🌙';
    }

    return MatchRationale(
      headline: headline,
      detailedExplanation: buffer.toString(),
      icebreakerSuggestion: icebreaker,
    );
  }
}
