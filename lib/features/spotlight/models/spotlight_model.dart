import 'package:cloud_firestore/cloud_firestore.dart';

class SpotlightSession {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final int prizePool;
  final bool isActive;
  final int minStartingBid;
  final int activeBidders;

  SpotlightSession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.prizePool,
    required this.isActive,
    required this.minStartingBid,
    required this.activeBidders,
  });

  factory SpotlightSession.fromMap(String id, Map<String, dynamic> map) {
    return SpotlightSession(
      id: id,
      startTime: map['startTime'] != null ? (map['startTime'] as Timestamp).toDate() : DateTime.now(),
      endTime: map['endTime'] != null ? (map['endTime'] as Timestamp).toDate() : DateTime.now().add(const Duration(hours: 1)),
      prizePool: map['prizePool'] ?? 0,
      isActive: map['isActive'] ?? false,
      minStartingBid: map['minStartingBid'] ?? 200,
      activeBidders: map['activeBidders'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'prizePool': prizePool,
      'isActive': isActive,
      'minStartingBid': minStartingBid,
      'activeBidders': activeBidders,
    };
  }
}

class SpotlightBid {
  final String id;
  final String sessionId;
  final String userId;
  final String username;
  final String profileImageUrl;
  final bool isVerified;
  final int amount;
  final DateTime timestamp;
  final int rank;

  SpotlightBid({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.username,
    required this.profileImageUrl,
    required this.isVerified,
    required this.amount,
    required this.timestamp,
    required this.rank,
  });

  factory SpotlightBid.fromMap(String id, Map<String, dynamic> map) {
    return SpotlightBid(
      id: id,
      sessionId: map['sessionId'] ?? '',
      userId: map['userId'] ?? '',
      username: map['username'] ?? '',
      profileImageUrl: map['profileImageUrl'] ?? '',
      isVerified: map['isVerified'] ?? false,
      amount: map['amount'] ?? 0,
      timestamp: map['timestamp'] != null ? (map['timestamp'] as Timestamp).toDate() : DateTime.now(),
      rank: map['rank'] ?? 999,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'userId': userId,
      'username': username,
      'profileImageUrl': profileImageUrl,
      'isVerified': isVerified,
      'amount': amount,
      'timestamp': Timestamp.fromDate(timestamp),
      'rank': rank,
    };
  }
}
