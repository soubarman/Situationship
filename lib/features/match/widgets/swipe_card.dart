import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/location_helper.dart';

/// Signature Discovery Profile Card for Situationship.
/// Features multi-photo touch cycling with segmented story indicators,
/// cinematic multi-stop scrim, tactile info drawer, and high-fashion editorial typography.
class SwipeCard extends ConsumerStatefulWidget {
  final UserModel user;
  final bool isBackground;
  final double? deviceLat;
  final double? deviceLon;

  const SwipeCard({
    super.key,
    required this.user,
    required this.isBackground,
    this.deviceLat,
    this.deviceLon,
  });

  @override
  ConsumerState<SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends ConsumerState<SwipeCard> {
  int _currentPhotoIndex = 0;

  List<String> get _photoList {
    if (widget.user.photos.isNotEmpty) {
      return widget.user.photos;
    }
    if (widget.user.avatarUrl != null && widget.user.avatarUrl!.isNotEmpty) {
      return [widget.user.avatarUrl!];
    }
    return ['https://i.pravatar.cc/800?u=${widget.user.id}'];
  }

  void _nextPhoto() {
    if (_photoList.length <= 1) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentPhotoIndex = (_currentPhotoIndex + 1) % _photoList.length;
    });
  }

  void _prevPhoto() {
    if (_photoList.length <= 1) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentPhotoIndex = (_currentPhotoIndex - 1 + _photoList.length) % _photoList.length;
    });
  }

  void _openDetailsSheet(BuildContext context, int distance) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProfileDetailsModal(
        user: widget.user,
        distanceKm: distance,
        photos: _photoList,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);

    final distance = LocationHelper.getDistanceKm(
      lat1: widget.deviceLat,
      lon1: widget.deviceLon,
      loc1: currentUser.location,
      loc2: widget.user.location,
      id1: currentUser.id,
      id2: widget.user.id,
    );

    final photos = _photoList;
    final activePhotoUrl = (_currentPhotoIndex < photos.length)
        ? photos[_currentPhotoIndex]
        : photos.first;

    return Container(
      decoration: BoxDecoration(
        color: DesignTokens.obsidianCard,
        borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
        border: Border.all(
          color: Colors.white.withValues(alpha: widget.isBackground ? 0.04 : 0.12),
          width: 1.0,
        ),
        boxShadow: widget.isBackground
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : DesignTokens.cardShadow(glowColor: AppTheme.primaryPink),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Full-Bleed Photograph ─────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: CachedNetworkImage(
                key: ValueKey(activePhotoUrl),
                imageUrl: activePhotoUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                memCacheWidth: 800,
                placeholder: (context, url) => Container(
                  color: DesignTokens.obsidianElevated,
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white24,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: DesignTokens.obsidianElevated,
                  child: const Center(
                    child: Icon(Icons.person_rounded, size: 64, color: Colors.white24),
                  ),
                ),
              ),
            ),

            // ── 2. Tap Touch Zones for Multi-Photo Cycling ─────────────────
            if (!widget.isBackground && photos.length > 1)
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _prevPhoto,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _nextPhoto,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),

            // ── 3. Background Dimming Layer for Stack Depth ────────────────
            if (widget.isBackground)
              Container(
                color: Colors.black.withValues(alpha: 0.40),
              ),

            // ── 4. Cinematic Multi-Stop Scrim ──────────────────────────────
            if (!widget.isBackground)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.82),
                          DesignTokens.obsidianBase,
                        ],
                        stops: const [0.0, 0.20, 0.52, 0.80, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

            // ── 5. Segmented Story / Photo Progress Indicators ─────────────
            if (!widget.isBackground && photos.length > 1)
              Positioned(
                top: 12,
                left: 14,
                right: 14,
                child: Row(
                  children: List.generate(photos.length, (idx) {
                    final isCurrent = idx == _currentPhotoIndex;
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),

            // ── 6. Active Card Foreground Overlay & Metadata ───────────────
            if (!widget.isBackground)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 26, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Badges Row
                      Row(
                        children: [
                          // Distance Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.near_me_rounded, size: 12, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  '$distance km away',
                                  style: DesignTokens.microBadge(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // Info Button
                          GestureDetector(
                            onTap: () => _openDetailsSheet(context, distance),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  width: 1.0,
                                ),
                              ),
                              child: const Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Name, Age & Verified
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              widget.user.name,
                              style: DesignTokens.headingLarge(color: Colors.white).copyWith(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.user.age}',
                            style: DesignTokens.headingLarge(color: Colors.white70).copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          if (widget.user.isVerified) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF38BDF8), Color(0xFF6366F1)],
                                ),
                                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_rounded, size: 11, color: Colors.white),
                                  SizedBox(width: 3),
                                  Text(
                                    'VERIFIED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Location & Intent Row
                      Row(
                        children: [
                          if (widget.user.location != null && widget.user.location!.isNotEmpty) ...[
                            Icon(Icons.location_on_rounded, size: 14, color: AppTheme.primaryPink),
                            const SizedBox(width: 4),
                            Text(
                              widget.user.location!,
                              style: DesignTokens.bodyMedium(color: Colors.white70),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (widget.user.relationshipIntent != null && widget.user.relationshipIntent!.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('✨', style: TextStyle(fontSize: 10)),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.user.relationshipIntent!,
                                    style: DesignTokens.microBadge(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),

                      // Bio snippet
                      if (widget.user.bio != null && widget.user.bio!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.user.bio!,
                          style: DesignTokens.bodyMedium(color: Colors.white.withValues(alpha: 0.88)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      // Interest tags
                      if (widget.user.interests.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.user.interests.take(3).map((interest) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                interest,
                                style: DesignTokens.microBadge(color: Colors.white),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Detailed profile modal bottom sheet
class _ProfileDetailsModal extends StatelessWidget {
  final UserModel user;
  final int distanceKm;
  final List<String> photos;

  const _ProfileDetailsModal({
    required this.user,
    required this.distanceKm,
    required this.photos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: DesignTokens.obsidianModal,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(DesignTokens.radius2xl)),
        border: Border.all(color: DesignTokens.hairline),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: CachedNetworkImageProvider(photos.first),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${user.name}, ${user.age}',
                                style: DesignTokens.headingLarge(color: Colors.white),
                              ),
                              if (user.isVerified) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF38BDF8)),
                              ],
                            ],
                          ),
                          Text(
                            '$distanceKm km away • ${user.location ?? "Nearby"}',
                            style: DesignTokens.bodyMedium(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Bio
                if (user.bio != null && user.bio!.isNotEmpty) ...[
                  Text('About', style: DesignTokens.titleMedium(color: Colors.white)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: DesignTokens.obsidianElevated,
                      borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                      border: Border.all(color: DesignTokens.hairline),
                    ),
                    child: Text(
                      user.bio!,
                      style: DesignTokens.bodyLarge(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Intent & Zodiac
                if (user.relationshipIntent != null || user.zodiacSign != null) ...[
                  Row(
                    children: [
                      if (user.relationshipIntent != null)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: DesignTokens.obsidianElevated,
                              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                              border: Border.all(color: DesignTokens.hairline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Looking for', style: DesignTokens.microBadge(color: Colors.white54)),
                                const SizedBox(height: 4),
                                Text(user.relationshipIntent!, style: DesignTokens.titleMedium(color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      if (user.relationshipIntent != null && user.zodiacSign != null)
                        const SizedBox(width: 10),
                      if (user.zodiacSign != null)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: DesignTokens.obsidianElevated,
                              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                              border: Border.all(color: DesignTokens.hairline),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Zodiac', style: DesignTokens.microBadge(color: Colors.white54)),
                                const SizedBox(height: 4),
                                Text(user.zodiacSign!, style: DesignTokens.titleMedium(color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],

                // Interests
                if (user.interests.isNotEmpty) ...[
                  Text('Interests & Passions', style: DesignTokens.titleMedium(color: Colors.white)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: user.interests.map((interest) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: DesignTokens.obsidianElevated,
                          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                          border: Border.all(color: DesignTokens.hairline),
                        ),
                        child: Text(
                          interest,
                          style: DesignTokens.bodyMedium(color: Colors.white),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                ],

                // Photos Grid
                if (photos.length > 1) ...[
                  Text('Photos', style: DesignTokens.titleMedium(color: Colors.white)),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: photos.length,
                    itemBuilder: (context, idx) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                        child: CachedNetworkImage(
                          imageUrl: photos[idx],
                          fit: BoxFit.cover,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
