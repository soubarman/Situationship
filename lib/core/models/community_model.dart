class CommunityModel {
  final String id;
  final String name;
  final String tag; // e.g. "Interest", "Creative", "Social", "Lifestyle"
  final String imageUrl;
  final int memberCount;
  final List<String> memberAvatars;
  final String description;
  final String createdBy;
  final bool isOnlyAdminApproved;
  final List<String> pendingApprovals;

  const CommunityModel({
    required this.id,
    required this.name,
    required this.tag,
    required this.imageUrl,
    required this.memberCount,
    this.memberAvatars = const [],
    this.description = '',
    this.createdBy = '',
    this.isOnlyAdminApproved = false,
    this.pendingApprovals = const [],
  });

  factory CommunityModel.fromMap(Map<String, dynamic> map) {
    return CommunityModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      tag: map['tag'] ?? 'Interest',
      imageUrl: map['imageUrl'] ?? '',
      memberCount: map['memberCount'] ?? 0,
      memberAvatars: List<String>.from(map['memberAvatars'] ?? []),
      description: map['description'] ?? '',
      createdBy: map['createdBy'] ?? '',
      isOnlyAdminApproved: map['isOnlyAdminApproved'] ?? false,
      pendingApprovals: List<String>.from(map['pendingApprovals'] ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'tag': tag,
        'imageUrl': imageUrl,
        'memberCount': memberCount,
        'memberAvatars': memberAvatars,
        'description': description,
        'createdBy': createdBy,
        'isOnlyAdminApproved': isOnlyAdminApproved,
        'pendingApprovals': pendingApprovals,
      };

  CommunityModel copyWith({
    String? id,
    String? name,
    String? tag,
    String? imageUrl,
    int? memberCount,
    List<String>? memberAvatars,
    String? description,
    String? createdBy,
    bool? isOnlyAdminApproved,
    List<String>? pendingApprovals,
  }) {
    return CommunityModel(
      id: id ?? this.id,
      name: name ?? this.name,
      tag: tag ?? this.tag,
      imageUrl: imageUrl ?? this.imageUrl,
      memberCount: memberCount ?? this.memberCount,
      memberAvatars: memberAvatars ?? this.memberAvatars,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      isOnlyAdminApproved: isOnlyAdminApproved ?? this.isOnlyAdminApproved,
      pendingApprovals: pendingApprovals ?? this.pendingApprovals,
    );
  }

  static List<CommunityModel> get defaults => [
        const CommunityModel(
          id: 'anime-addicts',
          name: 'Anime Addicts',
          tag: 'Interest',
          imageUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=400',
          memberCount: 0,
        ),
        const CommunityModel(
          id: 'art-soul',
          name: 'Art & Soul',
          tag: 'Creative',
          imageUrl: 'https://images.unsplash.com/photo-1460661419201-fd4cecdf8a8b?w=400',
          memberCount: 0,
        ),
        const CommunityModel(
          id: 'late-night-vibes',
          name: 'Late Night Vibes',
          tag: 'Social',
          imageUrl: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?w=400',
          memberCount: 0,
        ),
        const CommunityModel(
          id: 'foodies-unite',
          name: 'Foodies Unite',
          tag: 'Lifestyle',
          imageUrl: 'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400',
          memberCount: 0,
        ),
        const CommunityModel(
          id: 'bookworm-club',
          name: 'Bookworm Club',
          tag: 'Interest',
          imageUrl: 'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=400',
          memberCount: 0,
        ),
        const CommunityModel(
          id: 'music-souls',
          name: 'Music Souls',
          tag: 'Creative',
          imageUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=400',
          memberCount: 0,
        ),
      ];
}
