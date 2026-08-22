// lib/features/verification/data/models/verification_status_model.dart

class AttemptModel {
  final int attemptNumber;
  final String status;
  final String reason;
  final String challengeId;
  final String jobId;
  final String timestamp;

  const AttemptModel({
    required this.attemptNumber,
    required this.status,
    required this.reason,
    required this.challengeId,
    required this.jobId,
    required this.timestamp,
  });

  factory AttemptModel.fromMap(Map<String, dynamic> map) {
    return AttemptModel(
      attemptNumber: map['attemptNumber'] as int? ?? 0,
      status: map['status'] as String? ?? 'pending',
      reason: map['reason'] as String? ?? '',
      challengeId: map['challengeId'] as String? ?? '',
      jobId: map['jobId'] as String? ?? '',
      timestamp: map['timestamp'] as String? ?? '',
    );
  }
}

class VerificationStatusModel {
  final String status;         // 'not_started' | 'pending' | 'approved' | 'rejected' | 'manual_review'
  final double? score;
  final String? reason;
  final String? badge;
  final int attemptsUsed;
  final int attemptsRemaining;
  final DateTime? lastAttemptAt;
  final String? jobId;
  final List<AttemptModel> attemptsList;

  const VerificationStatusModel({
    required this.status,
    this.score,
    this.reason,
    this.badge,
    this.attemptsUsed = 0,
    this.attemptsRemaining = 5,
    this.lastAttemptAt,
    this.jobId,
    this.attemptsList = const [],
  });

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
  bool get isManualReview => status == 'manual_review';
  bool get isNotStarted => status == 'not_started';
  bool get canRetry => !isApproved && attemptsRemaining > 0;

  factory VerificationStatusModel.notStarted() => const VerificationStatusModel(
        status: 'not_started',
        attemptsUsed: 0,
        attemptsRemaining: 5,
        attemptsList: [],
      );

  factory VerificationStatusModel.fromMap(Map<String, dynamic> map) {
    final attempts = map['verificationAttempts'] as int? ?? 0;
    final attemptsListMap = map['attemptsList'] as List<dynamic>? ?? const [];
    final attemptsList = attemptsListMap
        .map((x) => AttemptModel.fromMap(Map<String, dynamic>.from(x as Map)))
        .toList();

    return VerificationStatusModel(
      status: map['verificationStatus'] as String? ?? 'not_started',
      score: (map['verificationScore'] as num?)?.toDouble(),
      reason: map['verificationReason'] as String?,
      badge: map['verifiedBadge'] as String?,
      attemptsUsed: attempts,
      attemptsRemaining: (5 - attempts).clamp(0, 5),
      jobId: map['currentJobId'] as String?,
      attemptsList: attemptsList,
    );
  }
}
