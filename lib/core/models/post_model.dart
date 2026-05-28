class PostModel {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatar;
  final bool isUserVerified;
  final String? imageUrl;
  final String? videoUrl;
  final String caption;
  final List<String> likes;
  final int commentCount;
  final int shareCount;
  final DateTime createdAt;
  final List<String> tags;
  final String? location;
  final bool isReel;
  final String? mood; // e.g. "😎 Chill"
  final Map<String, String> reactions; // userId -> emoji
  final String? communityId;
  final String? communityName;
  
  // New Flow Fields
  final String? musicTrack;
  final String? musicArtist;
  final bool isPinned;
  final String privacy; // public, connections, private
  final bool isEdited;

  const PostModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.isUserVerified = false,
    this.imageUrl,
    this.videoUrl,
    required this.caption,
    this.likes = const [],
    this.commentCount = 0,
    this.shareCount = 0,
    required this.createdAt,
    this.tags = const [],
    this.location,
    this.isReel = false,
    this.mood,
    this.reactions = const {},
    this.communityId,
    this.communityName,
    this.musicTrack,
    this.musicArtist,
    this.isPinned = false,
    this.privacy = 'public',
    this.isEdited = false,
  });

  factory PostModel.fromMap(Map<String, dynamic> map) {
    return PostModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userAvatar: map['userAvatar'],
      isUserVerified: map['isUserVerified'] ?? false,
      imageUrl: map['imageUrl'],
      videoUrl: map['videoUrl'],
      caption: map['caption'] ?? '',
      likes: List<String>.from(map['likes'] ?? []),
      commentCount: map['commentCount'] ?? 0,
      shareCount: map['shareCount'] ?? 0,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
              : (map['createdAt'].toDate()))
          : DateTime.now(),
      tags: List<String>.from(map['tags'] ?? []),
      location: map['location'],
      isReel: map['isReel'] ?? false,
      mood: map['mood'],
      reactions: Map<String, String>.from(map['reactions'] ?? {}),
      communityId: map['communityId'],
      communityName: map['communityName'],
      musicTrack: map['musicTrack'],
      musicArtist: map['musicArtist'],
      isPinned: map['isPinned'] ?? false,
      privacy: map['privacy'] ?? 'public',
      isEdited: map['isEdited'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'isUserVerified': isUserVerified,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'caption': caption,
      'likes': likes,
      'commentCount': commentCount,
      'shareCount': shareCount,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'tags': tags,
      'location': location,
      'isReel': isReel,
      'mood': mood,
      'reactions': reactions,
      'communityId': communityId,
      'communityName': communityName,
      'musicTrack': musicTrack,
      'musicArtist': musicArtist,
      'isPinned': isPinned,
      'privacy': privacy,
      'isEdited': isEdited,
    };
  }

  PostModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatar,
    bool? isUserVerified,
    String? imageUrl,
    String? videoUrl,
    String? caption,
    List<String>? likes,
    int? commentCount,
    int? shareCount,
    DateTime? createdAt,
    List<String>? tags,
    String? location,
    bool? isReel,
    String? mood,
    Map<String, String>? reactions,
    String? communityId,
    String? communityName,
    String? musicTrack,
    String? musicArtist,
    bool? isPinned,
    String? privacy,
    bool? isEdited,
  }) {
    return PostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      isUserVerified: isUserVerified ?? this.isUserVerified,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      caption: caption ?? this.caption,
      likes: likes ?? this.likes,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      createdAt: createdAt ?? this.createdAt,
      tags: tags ?? this.tags,
      location: location ?? this.location,
      isReel: isReel ?? this.isReel,
      mood: mood ?? this.mood,
      reactions: reactions ?? this.reactions,
      communityId: communityId ?? this.communityId,
      communityName: communityName ?? this.communityName,
      musicTrack: musicTrack ?? this.musicTrack,
      musicArtist: musicArtist ?? this.musicArtist,
      isPinned: isPinned ?? this.isPinned,
      privacy: privacy ?? this.privacy,
      isEdited: isEdited ?? this.isEdited,
    );
  }
}
