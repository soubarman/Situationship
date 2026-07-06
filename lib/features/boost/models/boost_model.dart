import 'package:cloud_firestore/cloud_firestore.dart';

class BoostModel {
  final String id;
  final String contentId;
  final String contentType;       // 'take' | 'photo' | 'general_post'
  final String boostScope;        // 'local' | 'regional' | 'extended'
  final String boostTier;         // 'standard' | 'premium'
  final DateTime startTime;
  final DateTime endTime;
  final int coinCost;
  final double reachMultiplier;
  final String ownerUserId;
  final double ownerLatitude;
  final double ownerLongitude;
  final double radiusKm;
  final DateTime cooldownUntil;
  final bool eligibilityCheckPassed;
  final bool expiredNotificationSent;

  BoostModel({
    required this.id,
    required this.contentId,
    required this.contentType,
    required this.boostScope,
    required this.boostTier,
    required this.startTime,
    required this.endTime,
    required this.coinCost,
    required this.reachMultiplier,
    required this.ownerUserId,
    required this.ownerLatitude,
    required this.ownerLongitude,
    required this.radiusKm,
    required this.cooldownUntil,
    required this.eligibilityCheckPassed,
    this.expiredNotificationSent = false,
  });

  factory BoostModel.fromMap(Map<String, dynamic> map, String docId) {
    return BoostModel(
      id: docId,
      contentId: map['contentId'] ?? '',
      contentType: map['contentType'] ?? 'general_post',
      boostScope: map['boostScope'] ?? 'local',
      boostTier: map['boostTier'] ?? 'standard',
      startTime: (map['startTime'] as Timestamp).toDate(),
      endTime: (map['endTime'] as Timestamp).toDate(),
      coinCost: map['coinCost'] ?? 0,
      reachMultiplier: (map['reachMultiplier'] ?? 1.0).toDouble(),
      ownerUserId: map['ownerUserId'] ?? '',
      ownerLatitude: (map['ownerLatitude'] ?? 0.0).toDouble(),
      ownerLongitude: (map['ownerLongitude'] ?? 0.0).toDouble(),
      radiusKm: (map['radiusKm'] ?? 5.0).toDouble(),
      cooldownUntil: (map['cooldownUntil'] as Timestamp).toDate(),
      eligibilityCheckPassed: map['eligibilityCheckPassed'] ?? false,
      expiredNotificationSent: map['expiredNotificationSent'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'contentId': contentId,
      'contentType': contentType,
      'boostScope': boostScope,
      'boostTier': boostTier,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'coinCost': coinCost,
      'reachMultiplier': reachMultiplier,
      'ownerUserId': ownerUserId,
      'ownerLatitude': ownerLatitude,
      'ownerLongitude': ownerLongitude,
      'radiusKm': radiusKm,
      'cooldownUntil': Timestamp.fromDate(cooldownUntil),
      'eligibilityCheckPassed': eligibilityCheckPassed,
      'expiredNotificationSent': expiredNotificationSent,
    };
  }

  BoostModel copyWith({
    String? id,
    String? contentId,
    String? contentType,
    String? boostScope,
    String? boostTier,
    DateTime? startTime,
    DateTime? endTime,
    int? coinCost,
    double? reachMultiplier,
    String? ownerUserId,
    double? ownerLatitude,
    double? ownerLongitude,
    double? radiusKm,
    DateTime? cooldownUntil,
    bool? eligibilityCheckPassed,
    bool? expiredNotificationSent,
  }) {
    return BoostModel(
      id: id ?? this.id,
      contentId: contentId ?? this.contentId,
      contentType: contentType ?? this.contentType,
      boostScope: boostScope ?? this.boostScope,
      boostTier: boostTier ?? this.boostTier,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      coinCost: coinCost ?? this.coinCost,
      reachMultiplier: reachMultiplier ?? this.reachMultiplier,
      ownerUserId: ownerUserId ?? this.ownerUserId,
      ownerLatitude: ownerLatitude ?? this.ownerLatitude,
      ownerLongitude: ownerLongitude ?? this.ownerLongitude,
      radiusKm: radiusKm ?? this.radiusKm,
      cooldownUntil: cooldownUntil ?? this.cooldownUntil,
      eligibilityCheckPassed: eligibilityCheckPassed ?? this.eligibilityCheckPassed,
      expiredNotificationSent: expiredNotificationSent ?? this.expiredNotificationSent,
    );
  }
}
