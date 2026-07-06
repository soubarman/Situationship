class BoostAnalyticsEvent {
  final String type; // 'boost_purchased', 'impression', 'engagement'
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  BoostAnalyticsEvent({
    required this.type,
    required this.timestamp,
    this.metadata = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'metadata': metadata,
    };
  }
}
