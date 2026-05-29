class MessageModel {
  final String id;
  final String senderId;
  final String text;
  final String? imageUrl;
  final DateTime createdAt;
  final bool isRead;
  final MessageType type;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.text,
    this.imageUrl,
    required this.createdAt,
    this.isRead = false,
    this.type = MessageType.text,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    DateTime parseTime(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val.runtimeType.toString().contains('Timestamp')) return (val as dynamic).toDate();
      return DateTime.now();
    }

    return MessageModel(
      id: map['id'] ?? '',
      senderId: map['senderId'] ?? '',
      text: map['text'] ?? '',
      imageUrl: map['imageUrl'],
      createdAt: parseTime(map['createdAt']),
      isRead: map['isRead'] ?? false,
      type: MessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => MessageType.text,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'text': text,
      'imageUrl': imageUrl,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isRead': isRead,
      'type': type.name,
    };
  }
}

enum MessageType { text, image, emoji, audio, sticker }

class ChatModel {
  final String id;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final bool otherUserIsOnline;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool isExpired;
  final Duration? expiresIn;
  final String status; // 'requested', 'accepted', 'blocked'
  final String? requestSenderId;
  final List<String> participants;
  final bool isConfession;
  final String? revealStatus; // null, 'requested', 'revealed', 'declined'
  final DateTime? acceptedAt;

  const ChatModel({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    this.otherUserIsOnline = false,
    required this.lastMessage,
    required this.lastMessageTime,
    this.unreadCount = 0,
    this.isExpired = false,
    this.expiresIn,
    this.status = 'accepted',
    this.requestSenderId,
    this.participants = const [],
    this.isConfession = false,
    this.revealStatus,
    this.acceptedAt,
  });

  ChatModel copyWith({
    String? id,
    String? otherUserId,
    String? otherUserName,
    String? otherUserAvatar,
    bool? otherUserIsOnline,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isExpired,
    Duration? expiresIn,
    String? status,
    String? requestSenderId,
    List<String>? participants,
    bool? isConfession,
    String? revealStatus,
    DateTime? acceptedAt,
  }) {
    return ChatModel(
      id: id ?? this.id,
      otherUserId: otherUserId ?? this.otherUserId,
      otherUserName: otherUserName ?? this.otherUserName,
      otherUserAvatar: otherUserAvatar ?? this.otherUserAvatar,
      otherUserIsOnline: otherUserIsOnline ?? this.otherUserIsOnline,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isExpired: isExpired ?? this.isExpired,
      expiresIn: expiresIn ?? this.expiresIn,
      status: status ?? this.status,
      requestSenderId: requestSenderId ?? this.requestSenderId,
      participants: participants ?? this.participants,
      isConfession: isConfession ?? this.isConfession,
      revealStatus: revealStatus ?? this.revealStatus,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }

  factory ChatModel.fromMap(Map<String, dynamic> map) {
    DateTime parseTime(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val.runtimeType.toString().contains('Timestamp')) return val.toDate();
      return DateTime.now();
    }

    return ChatModel(
      id: map['id'] ?? '',
      otherUserId: map['otherUserId'] ?? '',
      otherUserName: map['otherUserName'] ?? '',
      otherUserAvatar: map['otherUserAvatar'],
      otherUserIsOnline: map['otherUserIsOnline'] ?? false,
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: parseTime(map['lastMessageTime']),
      unreadCount: map['unreadCount'] ?? 0,
      isExpired: map['isExpired'] ?? false,
      expiresIn: map['expiresIn'] != null ? Duration(milliseconds: map['expiresIn']) : null,
      status: map['status'] ?? 'accepted',
      requestSenderId: map['requestSenderId'],
      participants: List<String>.from(map['participants'] ?? []),
      isConfession: map['isConfession'] ?? false,
      revealStatus: map['revealStatus'],
      acceptedAt: map['acceptedAt'] != null ? parseTime(map['acceptedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'otherUserId': otherUserId,
      'otherUserName': otherUserName,
      'otherUserAvatar': otherUserAvatar,
      'otherUserIsOnline': otherUserIsOnline,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime.millisecondsSinceEpoch,
      'unreadCount': unreadCount,
      'isExpired': isExpired,
      'expiresIn': expiresIn?.inMilliseconds,
      'status': status,
      'requestSenderId': requestSenderId,
      'participants': participants,
      'isConfession': isConfession,
      'revealStatus': revealStatus,
      'acceptedAt': acceptedAt?.millisecondsSinceEpoch,
    };
  }
}
