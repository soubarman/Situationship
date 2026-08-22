// lib/features/verification/data/models/challenge_model.dart

class ChallengeModel {
  final String challengeId;
  final String code;
  final String phrase;
  final String action;
  final String movement;
  final String expiresAt;
  final int ttlSeconds;

  const ChallengeModel({
    required this.challengeId,
    required this.code,
    required this.phrase,
    required this.action,
    required this.movement,
    required this.expiresAt,
    required this.ttlSeconds,
  });

  factory ChallengeModel.fromJson(Map<String, dynamic> json) {
    return ChallengeModel(
      challengeId: json['challengeId'] as String,
      code: json['code'] as String,
      phrase: json['phrase'] as String,
      action: json['action'] as String,
      movement: json['movement'] as String,
      expiresAt: json['expiresAt'] as String,
      ttlSeconds: json['ttlSeconds'] as int? ?? 900,
    );
  }

  DateTime get expiresAtDateTime => DateTime.parse(expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAtDateTime);
}
