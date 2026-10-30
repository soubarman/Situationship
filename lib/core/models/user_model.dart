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
  final List<String> superLikedBy;
  final Map<String, String> superLikeNotes;
  final List<String> matches;
  final List<String> dislikedUsers; // persisted unlikes — never re-shown
  final int postCount;
  final int coins;
  final List<String> joinedCommunities;
  final String? currentCityId;
  final String? homeCityId;
  final String? campusId;

  // ── Gender, Dating Preference & Economy ─────────────────────────────
  /// 'male' | 'female' | 'other'
  final String gender;
  /// Target genders this user wants to date: ['female'], ['male'], ['other'], etc.
  final List<String> interestedIn;
  /// 'serious' | 'casual' | 'open' | 'friendship'
  final String? relationshipIntent;
  /// User IDs blocked by this user
  final List<String> blockedUsers;
  /// Whether user appears in matching/discovery pools
  final bool isDiscoverable;
  /// Explicit dealbreakers, e.g. ['smoking', 'drinking']
  final List<String> dealbreakers;

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
    this.superLikedBy = const [],
    this.superLikeNotes = const {},
    this.matches = const [],
    this.dislikedUsers = const [],
    this.postCount = 0,
    this.coins = 0,
    this.joinedCommunities = const [],
    this.currentCityId,
    this.homeCityId,
    this.campusId,
    this.gender = 'other',
    this.interestedIn = const [],
    this.relationshipIntent,
    this.blockedUsers = const [],
    this.isDiscoverable = true,
    this.dealbreakers = const [],
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

  bool get isMale => normalizedGender == 'male';
  bool get isFemale => normalizedGender == 'female';

  /// Normalized gender: 'male', 'female', or 'other'
  String get normalizedGender {
    final g = gender.trim().toLowerCase();
    if (g == 'man' || g == 'm') return 'male';
    if (g == 'woman' || g == 'w' || g == 'f') return 'female';
    if (g == 'other' || g == 'non-binary' || g == 'nonbinary' || g == 'nb') return 'other';
    return g.isNotEmpty ? g : 'other';
  }

  /// Effective dating preference.
  /// If not explicitly set, defaults reciprocally based on user's own gender:
  /// male -> ['female'], female -> ['male'], other -> ['male', 'female', 'other'].
  List<String> get effectiveInterestedIn {
    if (interestedIn.isNotEmpty) {
      final list = <String>[];
      for (final e in interestedIn) {
        final clean = e.trim().toLowerCase();
        if (clean == 'man' || clean == 'men' || clean == 'm' || clean == 'male') {
          list.add('male');
        } else if (clean == 'woman' || clean == 'women' || clean == 'w' || clean == 'f' || clean == 'female') {
          list.add('female');
        } else if (clean == 'other' || clean == 'non-binary' || clean == 'nonbinary' || clean == 'nb') {
          list.add('other');
        } else if (clean == 'all' || clean == 'everyone') {
          return const ['male', 'female', 'other'];
        } else if (clean.isNotEmpty) {
          list.add(clean);
        }
      }
      if (list.isNotEmpty) return list;
    }
    // Reciprocal product defaults:
    if (isMale) return const ['female'];
    if (isFemale) return const ['male'];
    return const ['male', 'female', 'other'];
  }

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

  /// True only when user has passed verification checks and is approved
  bool get isReallyVerified {
    if (!isVerified) return false;
    if (verificationStatus != null && verificationStatus != 'approved') return false;
    return true;
  }

  /// Effective last seen timestamp strictly from Firestore `lastSeen` or `lastLoginDate`.
  /// Returns null if user has no recorded presence in Firestore.
  DateTime? get effectiveLastSeen {
    if (lastSeen != null) return lastSeen;
    if (lastLoginDate != null) {
      final parsed = DateTime.tryParse(lastLoginDate!);
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Real-time active status: true ONLY if user is online in Firestore AND has sent a heartbeat within the last 5 minutes.
  bool get isActuallyActive {
    if (!isOnline) return false;
    if (lastSeen == null) return false;
    final diff = DateTime.now().difference(lastSeen!);
    return diff.inMinutes >= 0 && diff.inMinutes <= 5;
  }

  /// Strictly real human-friendly active status string:
  /// - 'Active now' if genuinely online right now (< 5m heartbeat)
  /// - 'Active X minutes/hours/days ago' from real Firestore timestamp
  /// - 'Offline' if no recent activity recorded in Firestore
  String get activeStatusText {
    if (isActuallyActive) return 'Active now';
    final seen = effectiveLastSeen;
    if (seen != null) {
      final diff = DateTime.now().difference(seen);
      if (diff.isNegative) return 'Active now';
      final minutes = diff.inMinutes;
      final hours = diff.inHours;
      final days = diff.inDays;

      if (minutes < 1) return 'Active just now';
      if (minutes < 60) {
        return 'Active $minutes ${minutes == 1 ? "minute" : "minutes"} ago';
      }
      if (hours < 24) {
        return 'Active $hours ${hours == 1 ? "hour" : "hours"} ago';
      }
      if (days < 30) {
        return 'Active $days ${days == 1 ? "day" : "days"} ago';
      }
      final months = (days / 30).floor();
      if (months < 12) {
        return 'Active $months ${months == 1 ? "month" : "months"} ago';
      }
      return 'Recently online';
    }
    return 'Recently online';
  }

  /// Strictly real compact active status string:
  /// - 'Active now', 'Xm ago', 'Xh ago', 'Xd ago', or 'Offline'
  String get activeStatusCompact {
    if (isActuallyActive) return 'Active now';
    final seen = effectiveLastSeen;
    if (seen != null) {
      final diff = DateTime.now().difference(seen);
      if (diff.isNegative) return 'Active now';
      final minutes = diff.inMinutes;
      final hours = diff.inHours;
      final days = diff.inDays;

      if (minutes < 1) return 'Just now';
      if (minutes < 60) return '${minutes}m ago';
      if (hours < 24) return '${hours}h ago';
      if (days < 30) return '${days}d ago';
      final months = (days / 30).floor();
      if (months < 12) return '${months}mo ago';
      return 'Recently';
    }
    return 'Recently';
  }

  /// True if account is flagged as a test, demo, or placeholder account
  bool get isDemoOrTestAccount {
    final lowerName = name.trim().toLowerCase();
    final lowerEmail = email.trim().toLowerCase();
    final lowerId = id.trim().toLowerCase();

    if (lowerId.contains('sample') || lowerId.contains('dummy') || lowerId.startsWith('mock_')) {
      return true;
    }

    if (lowerName.isEmpty ||
        lowerName == 'demo' ||
        lowerName.startsWith('demo ') ||
        lowerName.endsWith(' demo') ||
        lowerName.contains('demo user') ||
        lowerName == 'test' ||
        lowerName.startsWith('test ') ||
        lowerName.contains('test user') ||
        RegExp(r'^[0-9]+$').hasMatch(lowerName) ||
        lowerName == 'sample') {
      return true;
    }

    if (lowerEmail.contains('@sample.com') ||
        lowerEmail.contains('@test.com') ||
        lowerEmail.contains('@example.com') ||
        lowerEmail.startsWith('demo@')) {
      return true;
    }

    return false;
  }

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
      lastSeen: () {
        final val = map['lastSeen'];
        if (val == null) return null;
        if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
        if (val is DateTime) return val;
        if (val is String) return DateTime.tryParse(val);
        try {
          final dynamic dyn = val;
          if (dyn.toDate is Function) {
            return dyn.toDate() as DateTime;
          }
        } catch (_) {}
        return null;
      }(),
      zodiacSign: map['zodiacSign'],
      followers: List<String>.from(map['followers'] ?? []),
      following: List<String>.from(map['following'] ?? []),
      likedBy: List<String>.from(map['likedBy'] ?? []),
      superLikedBy: List<String>.from(map['superLikedBy'] ?? []),
      superLikeNotes: Map<String, String>.from(map['superLikeNotes'] ?? {}),
      matches: List<String>.from(map['matches'] ?? []),
      dislikedUsers: List<String>.from(map['dislikedUsers'] ?? []),
      postCount: map['postCount'] ?? 0,
      coins: map['coins'] ?? 0,
      joinedCommunities: List<String>.from(map['joinedCommunities'] ?? []),
      currentCityId: map['currentCityId'],
      homeCityId: map['homeCityId'],
      campusId: map['campusId'],
      gender: map['gender'] ?? 'other',
      interestedIn: List<String>.from(map['interestedIn'] ?? (map['datingPreference'] != null ? [map['datingPreference']] : [])),
      relationshipIntent: map['relationshipIntent'] ?? map['intent'],
      blockedUsers: List<String>.from(map['blockedUsers'] ?? []),
      isDiscoverable: map['isDiscoverable'] ?? true,
      dealbreakers: List<String>.from(map['dealbreakers'] ?? []),
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
      'superLikedBy': superLikedBy,
      'superLikeNotes': superLikeNotes,
      'matches': matches,
      'dislikedUsers': dislikedUsers,
      'postCount': postCount,
      'coins': coins,
      'joinedCommunities': joinedCommunities,
      'currentCityId': currentCityId,
      'homeCityId': homeCityId,
      'campusId': campusId,
      'gender': gender,
      'interestedIn': interestedIn,
      'relationshipIntent': relationshipIntent,
      'blockedUsers': blockedUsers,
      'isDiscoverable': isDiscoverable,
      'dealbreakers': dealbreakers,
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
    List<String>? superLikedBy,
    Map<String, String>? superLikeNotes,
    List<String>? matches,
    List<String>? dislikedUsers,
    int? postCount,
    int? coins,
    List<String>? joinedCommunities,
    String? currentCityId,
    String? homeCityId,
    String? campusId,
    String? gender,
    List<String>? interestedIn,
    String? relationshipIntent,
    List<String>? blockedUsers,
    bool? isDiscoverable,
    List<String>? dealbreakers,
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
      superLikedBy: superLikedBy ?? this.superLikedBy,
      superLikeNotes: superLikeNotes ?? this.superLikeNotes,
      matches: matches ?? this.matches,
      dislikedUsers: dislikedUsers ?? this.dislikedUsers,
      postCount: postCount ?? this.postCount,
      coins: coins ?? this.coins,
      joinedCommunities: joinedCommunities ?? this.joinedCommunities,
      currentCityId: currentCityId ?? this.currentCityId,
      homeCityId: homeCityId ?? this.homeCityId,
      campusId: campusId ?? this.campusId,
      gender: gender ?? this.gender,
      interestedIn: interestedIn ?? this.interestedIn,
      relationshipIntent: relationshipIntent ?? this.relationshipIntent,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      isDiscoverable: isDiscoverable ?? this.isDiscoverable,
      dealbreakers: dealbreakers ?? this.dealbreakers,
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
        interestedIn: [],
        relationshipIntent: null,
        blockedUsers: [],
        isDiscoverable: true,
        dealbreakers: [],
        phoneNumber: null,
        unlockedUserPhones: [],
        unlockedVisitors: [],
      );
}

