import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/utils/location_helper.dart';
import '../../spotlight/widgets/spotlight_feed_section.dart';

// ─── Prompts and Vibes ────────────────────────────────────────────────────────

const _vibeLabels = [
  'Warm Current',
  'Soft Rebel',
  'Golden Hour',
  'Quiet Storm',
  'Soft Chaos',
  'Night Owl',
];

const _promptHeaders = [
  'PERFECT SUNDAY LOOKS LIKE...',
  "I'M ACTUALLY LOOKING FOR...",
  "I'LL FALL FOR YOU IF...",
  'THE WAY TO MY HEART IS...',
  'MY SIMPLE PLEASURES ARE...',
];

const _sampleQuotes = [
  '"Slow breakfast, no plans, someone who stays"',
  '"Someone who gets the quiet version of me"',
  '"Late night drives and unhinged playlists"',
  '"Deep talks at 2 AM over cold coffee"',
  '"Someone who laughs at all my bad jokes"',
];

String _vibeFor(UserModel u) =>
    _vibeLabels[u.id.hashCode.abs() % _vibeLabels.length];

String _promptHeaderFor(UserModel u) =>
    _promptHeaders[u.id.hashCode.abs() % _promptHeaders.length];

String _quoteFor(UserModel u) {
  final bio = u.bio?.trim();
  if (bio != null &&
      bio.isNotEmpty &&
      bio != 'Loading...' &&
      bio != 'User' &&
      bio.length > 5) {
    return '"$bio"';
  }
  if (u.interests.isNotEmpty) {
    return '"Loves ${u.interests.take(2).join(' & ')}"';
  }
  return _sampleQuotes[u.id.hashCode.abs() % _sampleQuotes.length];
}

int _matchPct(UserModel me, UserModel other) {
  final mySet = me.interests.toSet();
  final theirSet = other.interests.toSet();
  final shared = mySet.intersection(theirSet).length;
  final total = max(mySet.union(theirSet).length, 1);
  final base = 82 + (other.id.hashCode.abs() % 14);
  final bonus = ((shared / total) * 10).round();
  return (base + bonus).clamp(80, 98);
}

// ─────────────────────────────────────────────────────────────────────────────

class DiscoverTab extends ConsumerStatefulWidget {
  final List<UserModel> users;
  final double? deviceLat;
  final double? deviceLon;
  final Future<void> Function(UserModel liked, {UserModel? pairedWith}) onLike;
  final void Function(UserModel user) onSkip;

  const DiscoverTab({
    super.key,
    required this.users,
    this.deviceLat,
    this.deviceLon,
    required this.onLike,
    required this.onSkip,
  });

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab>
    with TickerProviderStateMixin {
  String? _chosenId;
  String _selectedFilter = 'Soft';

  late AnimationController _likeController;
  late AnimationController _entryController;
  late Animation<double> _entryFade;

  @override
  void initState() {
    super.initState();

    _likeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _entryFade =
        CurvedAnimation(parent: _entryController, curve: Curves.easeOut);

    _entryController.forward();
  }

  @override
  void dispose() {
    _likeController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  List<UserModel> get _pair {
    if (widget.users.isEmpty) return [];
    if (widget.users.length == 1) return [widget.users[0]];
    return [widget.users[0], widget.users[1]];
  }

  Future<void> _choose(UserModel chosen) async {
    if (_chosenId != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _chosenId = chosen.id);

    await _likeController.forward();

    // Find the other card in the pair (if any) — passed to onLike so
    // HeartQueue™ can track and restore it correctly on undo.
    final other = _pair.where((u) => u.id != chosen.id).firstOrNull;

    // Like chosen — HeartQueue™ handles pair tracking internally
    await widget.onLike(chosen, pairedWith: other);

    await Future.delayed(const Duration(milliseconds: 180));
    if (mounted) {
      _likeController.reset();
      _entryController.reset();
      setState(() => _chosenId = null);
      _entryController.forward();
    }
  }

  void _showOthers() {
    HapticFeedback.selectionClick();
    for (final u in _pair) {
      widget.onSkip(u);
    }
    _entryController.reset();
    setState(() => _chosenId = null);
    _entryController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pair = _pair;

    if (pair.isEmpty) return _buildEmptyState(isDark);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),

          // ── Subheader row: "Who are you feeling?" + "🌸 Soft ⌄" ───────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Who are you feeling?',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                    letterSpacing: -0.3,
                  ),
                ),
                _buildFilterDropdown(isDark),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // ── Center prompt text ─────────────────────────────────────────
          Center(
            child: Text(
              'Tap the one that hits different',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? const Color(0xFF6C7390) : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── 2 Side-by-Side Cards (Photo + Quote) ─────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FadeTransition(
              opacity: _entryFade,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Card
                  Expanded(
                    child: _ProfileMatchCard(
                      user: pair[0],
                      currentUser: currentUser,
                      isChosen: _chosenId == pair[0].id,
                      isOther: _chosenId != null && _chosenId != pair[0].id,
                      deviceLat: widget.deviceLat,
                      deviceLon: widget.deviceLon,
                      onTap: () => _choose(pair[0]),
                      onViewProfile: () =>
                          context.push('/profile/view/${pair[0].id}'),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Right Card
                  Expanded(
                    child: pair.length > 1
                        ? _ProfileMatchCard(
                            user: pair[1],
                            currentUser: currentUser,
                            isChosen: _chosenId == pair[1].id,
                            isOther:
                                _chosenId != null && _chosenId != pair[1].id,
                            deviceLat: widget.deviceLat,
                            deviceLon: widget.deviceLon,
                            onTap: () => _choose(pair[1]),
                            onViewProfile: () =>
                                context.push('/profile/view/${pair[1].id}'),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ── Bottom "Show me others ➔" Button ────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showOthers,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F75FF), Color(0xFF8B5CF6)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F75FF).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Show me others',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 19,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // ── Spotlight Section (Synced with Feed page) ──────────────────
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: SpotlightFeedSection(),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(bool isDark) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = val);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E1738) : Colors.white,
      offset: const Offset(0, 36),
      itemBuilder: (ctx) => [
        _buildPopupItem('Soft', '🌸', isDark),
        _buildPopupItem('Rebel', '⚡', isDark),
        _buildPopupItem('Chaos', '🔥', isDark),
        _buildPopupItem('Chill', '✨', isDark),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1D1730) : const Color(0xFFEDE9FE),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : const Color(0xFFDDD6FE),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌸', style: TextStyle(fontSize: 12.5)),
            const SizedBox(width: 5),
            Text(
              _selectedFilter,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF6D28D9),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isDark ? Colors.white70 : const Color(0xFF6D28D9),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String label, String emoji, bool isDark) {
    return PopupMenuItem<String>(
      value: label,
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF111827),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF4F75FF).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              color: Color(0xFF4F75FF),
              size: 48,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'All caught up! 💫',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No more souls in your radius.\nCheck back soon or expand filters!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.5),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Individual Side-by-Side Match Card (Photo + Prompt Card) ────────────────

class _ProfileMatchCard extends StatelessWidget {
  final UserModel user;
  final UserModel currentUser;
  final bool isChosen;
  final bool isOther;
  final double? deviceLat;
  final double? deviceLon;
  final VoidCallback onTap;
  final VoidCallback onViewProfile;

  const _ProfileMatchCard({
    required this.user,
    required this.currentUser,
    required this.isChosen,
    required this.isOther,
    this.deviceLat,
    this.deviceLon,
    required this.onTap,
    required this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final vibe = _vibeFor(user);
    final promptHeader = _promptHeaderFor(user);
    final quoteText = _quoteFor(user);
    final matchPct = _matchPct(currentUser, user);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final distance = LocationHelper.getDistanceKm(
      lat1: deviceLat,
      lon1: deviceLon,
      loc1: currentUser.location,
      loc2: user.location,
      id1: currentUser.id,
      id2: user.id,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isOther ? null : onTap,
      onLongPress: onViewProfile,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: isOther ? 0.35 : 1.0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          scale: isChosen ? 1.02 : (isOther ? 0.97 : 1.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Upper Photo Card ────────────────────────────────────────
              AspectRatio(
                aspectRatio: 0.82,
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: isDark ? const Color(0xFF141026) : Colors.white,
                    border: isChosen
                        ? Border.all(color: const Color(0xFF8B5CF6), width: 2.5)
                        : Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 1,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: isChosen
                            ? const Color(0xFF8B5CF6).withValues(alpha: 0.45)
                            : (isDark
                                ? Colors.black.withValues(alpha: 0.35)
                                : Colors.black.withValues(alpha: 0.06)),
                        blurRadius: isChosen ? 20 : 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Photo
                      CachedNetworkImage(
                        imageUrl: user.avatarUrl ??
                            'https://i.pravatar.cc/600?u=${user.id}',
                        fit: BoxFit.cover,
                        memCacheWidth: 600,
                        placeholder: (_, __) => _placeholder(),
                        errorWidget: (_, __, ___) => _placeholder(),
                      ),

                      // Gradient at bottom of photo
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.05),
                                Colors.black.withValues(alpha: 0.88),
                              ],
                              stops: const [0.45, 0.65, 1.0],
                            ),
                          ),
                        ),
                      ),

                      // Match % Badge Top Right
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.60),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            '$matchPct%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),

                      // Bottom details on photo
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Name
                            Text(
                              user.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16.5,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),

                            const SizedBox(height: 1),

                            // Age · Distance
                            Text(
                              '${user.age} · $distance km',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),

                            const SizedBox(height: 5),

                            // Vibe Pill
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8.5, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2C204D)
                                    .withValues(alpha: 0.90),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF7E60CD)
                                      .withValues(alpha: 0.45),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                vibe,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFCBB7FF),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Chosen Heart Pulse
                      if (isChosen)
                        Positioned.fill(
                          child: Container(
                            color: const Color(0xFF4F75FF)
                                .withValues(alpha: 0.25),
                            child: const Center(
                              child: Icon(
                                Icons.favorite_rounded,
                                color: Colors.white,
                                size: 54,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 7),

              // ── Lower Prompt Card (Compact Fixed Height ~72px) ───────────
              Container(
                height: 72,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131024) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2E2652).withValues(alpha: 0.65)
                        : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Prompt header with quotation mark
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '"',
                          style: TextStyle(
                            color: Color(0xFF6C63FF),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            promptHeader,
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF6C63FF),
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 3),

                    // Quote content
                    Text(
                      quoteText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF15102A),
      child: const Center(
        child: Icon(Icons.person_rounded, size: 40, color: Colors.white24),
      ),
    );
  }
}
