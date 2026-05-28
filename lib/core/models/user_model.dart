class UserModel {
  final String id;
  final String name;
  final String email;
  final int age;
  final String? bio;
  final String? location;
  final String? avatarUrl;
  final List<String> interests;
  final List<String> photos;
  final bool isVerified;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? zodiacSign;
  final List<String> followers;
  final List<String> following;
  final List<String> likedBy;
  final List<String> matches;
  final int postCount;
  final int coins;
  final List<String> joinedCommunities;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.age,
    this.bio,
    this.location,
    this.avatarUrl,
    this.interests = const [],
    this.photos = const [],
    this.isVerified = false,
    this.isOnline = false,
    this.lastSeen,
    this.zodiacSign,
    this.followers = const [],
    this.following = const [],
    this.likedBy = const [],
    this.matches = const [],
    this.postCount = 0,
    this.coins = 100,
    this.joinedCommunities = const [],
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      age: map['age'] ?? 18,
      bio: map['bio'],
      location: map['location'],
      avatarUrl: map['avatarUrl'],
      interests: List<String>.from(map['interests'] ?? []),
      photos: List<String>.from(map['photos'] ?? []),
      isVerified: map['isVerified'] ?? false,
      isOnline: map['isOnline'] ?? false,
      lastSeen: map['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastSeen'])
          : null,
      zodiacSign: map['zodiacSign'],
      followers: List<String>.from(map['followers'] ?? []),
      following: List<String>.from(map['following'] ?? []),
      likedBy: List<String>.from(map['likedBy'] ?? []),
      matches: List<String>.from(map['matches'] ?? []),
      postCount: map['postCount'] ?? 0,
      coins: map['coins'] ?? 100,
      joinedCommunities: List<String>.from(map['joinedCommunities'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'age': age,
      'bio': bio,
      'location': location,
      'avatarUrl': avatarUrl,
      'interests': interests,
      'photos': photos,
      'isVerified': isVerified,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
      'zodiacSign': zodiacSign,
      'followers': followers,
      'following': following,
      'likedBy': likedBy,
      'matches': matches,
      'postCount': postCount,
      'coins': coins,
      'joinedCommunities': joinedCommunities,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    int? age,
    String? bio,
    String? location,
    String? avatarUrl,
    List<String>? interests,
    List<String>? photos,
    bool? isVerified,
    bool? isOnline,
    DateTime? lastSeen,
    String? zodiacSign,
    List<String>? followers,
    List<String>? following,
    List<String>? likedBy,
    List<String>? matches,
    int? postCount,
    int? coins,
    List<String>? joinedCommunities,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      age: age ?? this.age,
      bio: bio ?? this.bio,
      location: location ?? this.location,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      interests: interests ?? this.interests,
      photos: photos ?? this.photos,
      isVerified: isVerified ?? this.isVerified,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      zodiacSign: zodiacSign ?? this.zodiacSign,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      likedBy: likedBy ?? this.likedBy,
      matches: matches ?? this.matches,
      postCount: postCount ?? this.postCount,
      coins: coins ?? this.coins,
      joinedCommunities: joinedCommunities ?? this.joinedCommunities,
    );
  }

  static UserModel get currentUser => const UserModel(
        id: '',
        name: '',
        email: '',
        age: 18,
        bio: '',
        location: '',
        avatarUrl: null,
        interests: [],
        photos: [],
        isVerified: false,
        isOnline: true,
        postCount: 0,
        coins: 100,
        joinedCommunities: [],
      );
}
