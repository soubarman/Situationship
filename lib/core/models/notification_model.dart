class NotificationModel {
  final String id;
  final String userId;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String type; // 'reaction', 'chat_request', 'gift'
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
  });

  NotificationModel copyWith({
    String? id,
    String? userId,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? type,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? isRead,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
    );
  }

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    DateTime parseTime(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val.runtimeType.toString().contains('Timestamp')) return val.toDate();
      return DateTime.now();
    }

    return NotificationModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      senderAvatar: map['senderAvatar'],
      type: map['type'] ?? 'reaction',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      createdAt: parseTime(map['createdAt']),
      isRead: map['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'type': type,
      'title': title,
      'body': body,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isRead': isRead,
    };
  }
}
