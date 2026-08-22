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
  final String? verifiedBadge;        // 'S' when verified
  final String? verificationStatus;   // 'pending' | 'approved' | 'rejected' | 'manual_review'
  final bool isOnline;
  final DateTime? lastSeen;
  final String? zodiacSign;
  final List<String> followers;
  final List<String> following;
  final List<String> likedBy;
  final List<String> matches;
  final List<String> dislikedUsers; // persisted unlikes — never re-shown
  final int postCount;
  final int coins;
  final List<String> joinedCommunities;
  final String? currentCityId;
  final String? homeCityId;
  final String? campusId;

  // ── Gender & Economy ──────────────────────────────────────────────────
  /// 'male' | 'female' | 'other'
  final String gender;

  // ── Contact Info & Unlocks ───────────────────────────────────────────
  final String? phoneNumber;
  final bool isPhonePublic;
  final int phoneVisibilityVersion;
  final List<String> unlockedUserPhones; // List of userIds whose phones this user unlocked
  final List<String> unlockedVisitors;   // List of visitor userIds this user unlocked (unblurred)

  // ── Subscription (male only) ──────────────────────────────────────────
  final bool isSubscribed;
  final DateTime? subscriptionExpiry;
  final int phoneUnlocksUsed;   // resets each billing period
  final int phoneUnlockQuota;  // 10 for ₹199 plan

  // ── Milestone tracking (female only) ─────────────────────────────────
  final int totalEarnedCoins;          // lifetime earned (never decreases)
  final List<String> claimedMilestones; // e.g. ['spark','glow']

  // ── Daily caps ────────────────────────────────────────────────────────
  final String? lastLoginDate;          // 'yyyy-MM-dd'
  final int dailyLoginStreak;
  final int conversationRewardsToday;   // resets daily, max 3

  // ── Moderation ────────────────────────────────────────────────────
  final bool isSuspended;               // true = blocked from using app
  final String? suspensionReason;       // shown to user on suspended screen
  final DateTime? suspendedUntil;       // null = permanent suspension

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
    this.verifiedBadge,
    this.verificationStatus,
    this.isOnline = false,
    this.lastSeen,
    this.zodiacSign,
    this.followers = const [],
    this.following = const [],
    this.likedBy = const [],
    this.matches = const [],
    this.dislikedUsers = const [],
    this.postCount = 0,
    this.coins = 0,
    this.joinedCommunities = const [],
    this.currentCityId,
    this.homeCityId,
    this.campusId,
    this.gender = 'other',
    this.phoneNumber,
    this.isPhonePublic = false,
    this.phoneVisibilityVersion = 0,
    this.unlockedUserPhones = const [],
    this.unlockedVisitors = const [],
    this.isSubscribed = false,
    this.subscriptionExpiry,
    this.phoneUnlocksUsed = 0,
    this.phoneUnlockQuota = 0,
    this.totalEarnedCoins = 0,
    this.claimedMilestones = const [],
    this.lastLoginDate,
    this.dailyLoginStreak = 0,
    this.conversationRewardsToday = 0,
    this.isSuspended = false,
    this.suspensionReason,
    this.suspendedUntil,
  });

  bool get isMale => gender == 'male';
  bool get isFemale => gender == 'female';
  bool get hasActiveSubscription =>
      isSubscribed &&
      subscriptionExpiry != null &&
      subscriptionExpiry!.isAfter(DateTime.now());
  int get phoneUnlocksRemaining =>
      (phoneUnlockQuota - phoneUnlocksUsed).clamp(0, 999);
  /// True if account is currently suspended (permanent or within time window)
  bool get isCurrentlySuspended =>
      isSuspended &&
      (suspendedUntil == null || suspendedUntil!.isAfter(DateTime.now()));

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
      verifiedBadge: map['verifiedBadge'],
      verificationStatus: map['verificationStatus'],
      isOnline: map['isOnline'] ?? false,
      lastSeen: map['lastSeen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastSeen'])
          : null,
      zodiacSign: map['zodiacSign'],
      followers: List<String>.from(map['followers'] ?? []),
      following: List<String>.from(map['following'] ?? []),
      likedBy: List<String>.from(map['likedBy'] ?? []),
      matches: List<String>.from(map['matches'] ?? []),
      dislikedUsers: List<String>.from(map['dislikedUsers'] ?? []),
      postCount: map['postCount'] ?? 0,
      coins: map['coins'] ?? 0,
      joinedCommunities: List<String>.from(map['joinedCommunities'] ?? []),
      currentCityId: map['currentCityId'],
      homeCityId: map['homeCityId'],
      campusId: map['campusId'],
      gender: map['gender'] ?? 'other',
      phoneNumber: map['phoneNumber'],
      isPhonePublic: map['isPhonePublic'] ?? false,
      phoneVisibilityVersion: map['phoneVisibilityVersion'] ?? 0,
      unlockedUserPhones: List<String>.from(map['unlockedUserPhones'] ?? []),
      unlockedVisitors: List<String>.from(map['unlockedVisitors'] ?? []),
      isSubscribed: map['isSubscribed'] ?? false,
      subscriptionExpiry: map['subscriptionExpiry'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['subscriptionExpiry'])
          : null,
      phoneUnlocksUsed: map['phoneUnlocksUsed'] ?? 0,
      phoneUnlockQuota: map['phoneUnlockQuota'] ?? 0,
      totalEarnedCoins: map['totalEarnedCoins'] ?? 0,
      claimedMilestones: List<String>.from(map['claimedMilestones'] ?? []),
      lastLoginDate: map['lastLoginDate'],
      dailyLoginStreak: map['dailyLoginStreak'] ?? 0,
      conversationRewardsToday: map['conversationRewardsToday'] ?? 0,
      isSuspended: map['isSuspended'] ?? false,
      suspensionReason: map['suspensionReason'],
      suspendedUntil: map['suspendedUntil'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['suspendedUntil'])
          : null,
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
      'verifiedBadge': verifiedBadge,
      'verificationStatus': verificationStatus,
      'isOnline': isOnline,
      'lastSeen': lastSeen?.millisecondsSinceEpoch,
      'zodiacSign': zodiacSign,
      'followers': followers,
      'following': following,
      'likedBy': likedBy,
      'matches': matches,
      'dislikedUsers': dislikedUsers,
      'postCount': postCount,
      'coins': coins,
      'joinedCommunities': joinedCommunities,
      'currentCityId': currentCityId,
      'homeCityId': homeCityId,
      'campusId': campusId,
      'gender': gender,
      'phoneNumber': phoneNumber,
      'isPhonePublic': isPhonePublic,
      'phoneVisibilityVersion': phoneVisibilityVersion,
      'unlockedUserPhones': unlockedUserPhones,
      'unlockedVisitors': unlockedVisitors,
      'isSubscribed': isSubscribed,
      'subscriptionExpiry': subscriptionExpiry?.millisecondsSinceEpoch,
      'phoneUnlocksUsed': phoneUnlocksUsed,
      'phoneUnlockQuota': phoneUnlockQuota,
      'totalEarnedCoins': totalEarnedCoins,
      'claimedMilestones': claimedMilestones,
      'lastLoginDate': lastLoginDate,
      'dailyLoginStreak': dailyLoginStreak,
      'conversationRewardsToday': conversationRewardsToday,
      'isSuspended': isSuspended,
      'suspensionReason': suspensionReason,
      'suspendedUntil': suspendedUntil?.millisecondsSinceEpoch,
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
    String? verifiedBadge,
    String? verificationStatus,
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
    String? currentCityId,
    String? homeCityId,
    String? campusId,
    String? gender,
    String? phoneNumber,
    bool? isPhonePublic,
    int? phoneVisibilityVersion,
    List<String>? unlockedUserPhones,
    List<String>? unlockedVisitors,
    bool? isSubscribed,
    DateTime? subscriptionExpiry,
    int? phoneUnlocksUsed,
    int? phoneUnlockQuota,
    int? totalEarnedCoins,
    List<String>? claimedMilestones,
    String? lastLoginDate,
    int? dailyLoginStreak,
    int? conversationRewardsToday,
    bool? isSuspended,
    String? suspensionReason,
    DateTime? suspendedUntil,
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
      verifiedBadge: verifiedBadge ?? this.verifiedBadge,
      verificationStatus: verificationStatus ?? this.verificationStatus,
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
      currentCityId: currentCityId ?? this.currentCityId,
      homeCityId: homeCityId ?? this.homeCityId,
      campusId: campusId ?? this.campusId,
      gender: gender ?? this.gender,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isPhonePublic: isPhonePublic ?? this.isPhonePublic,
      phoneVisibilityVersion: phoneVisibilityVersion ?? this.phoneVisibilityVersion,
      unlockedUserPhones: unlockedUserPhones ?? this.unlockedUserPhones,
      unlockedVisitors: unlockedVisitors ?? this.unlockedVisitors,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      subscriptionExpiry: subscriptionExpiry ?? this.subscriptionExpiry,
      phoneUnlocksUsed: phoneUnlocksUsed ?? this.phoneUnlocksUsed,
      phoneUnlockQuota: phoneUnlockQuota ?? this.phoneUnlockQuota,
      totalEarnedCoins: totalEarnedCoins ?? this.totalEarnedCoins,
      claimedMilestones: claimedMilestones ?? this.claimedMilestones,
      lastLoginDate: lastLoginDate ?? this.lastLoginDate,
      dailyLoginStreak: dailyLoginStreak ?? this.dailyLoginStreak,
      conversationRewardsToday: conversationRewardsToday ?? this.conversationRewardsToday,
      isSuspended: isSuspended ?? this.isSuspended,
      suspensionReason: suspensionReason ?? this.suspensionReason,
      suspendedUntil: suspendedUntil ?? this.suspendedUntil,
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
        coins: 0,
        joinedCommunities: [],
        currentCityId: null,
        homeCityId: null,
        campusId: null,
        gender: 'other',
        phoneNumber: null,
        unlockedUserPhones: [],
        unlockedVisitors: [],
      );
}

