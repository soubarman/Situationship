import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';

// ─── Vibe helpers ─────────────────────────────────────────────────────────────

const _vibeLabels = [
  'Soft Chaos',
  'Golden Hour',
  'Quiet Storm',
  'Warm Chaos',
  'Soft Rebel',
  'Night Owl',
];
const _vibeColors = [
  Color(0xFFB8A9FF),
  Color(0xFFFBBF24),
  Color(0xFF6ECBF5),
  Color(0xFFFF8EC8),
  Color(0xFF7EEECB),
  Color(0xFFF87171),
];

String _vibeFor(UserModel u) =>
    _vibeLabels[u.id.hashCode.abs() % _vibeLabels.length];
Color _vibeColorFor(UserModel u) =>
    _vibeColors[u.id.hashCode.abs() % _vibeColors.length];

int _matchPercent(UserModel me, UserModel other) {
  final mySet = me.interests.toSet();
  final theirSet = other.interests.toSet();
  final shared = mySet.intersection(theirSet).length;
  final total = max(mySet.union(theirSet).length, 1);
  final base = 55 + (other.id.hashCode.abs() % 25);
  final bonus = ((shared / total) * 30).round();
  return (base + bonus).clamp(55, 99);
}

// ─────────────────────────────────────────────────────────────────────────────

class NearlySoulsTab extends ConsumerStatefulWidget {
  final List<UserModel> users;
  final Future<void> Function(UserModel liked, {UserModel? pairedWith}) onLike;

  const NearlySoulsTab({
    super.key,
    required this.users,
    required this.onLike,
  });

  @override
  ConsumerState<NearlySoulsTab> createState() => _NearlySoulsTabState();
}

class _NearlySoulsTabState extends ConsumerState<NearlySoulsTab> {
  bool _isGrid = true;
  final Set<String> _likedIds = {};

  void _toggleView() {
    HapticFeedback.selectionClick();
    setState(() => _isGrid = !_isGrid);
  }

  void _like(UserModel user) {
    if (_likedIds.contains(user.id)) return;
    HapticFeedback.mediumImpact();
    setState(() => _likedIds.add(user.id));
    widget.onLike(user);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);

    if (widget.users.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return Column(
      children: [
        // ── Header row ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 14, 10),
          child: Row(
            children: [
              Text(
                'High-vibe matches near you',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.5)
                      : AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // Grid / list toggle
              GestureDetector(
                onTap: _toggleView,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.08),
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    _isGrid
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                    size: 18,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.7)
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Grid or list ───────────────────────────────────────────────────
        Expanded(
          child: _isGrid
              ? _buildGrid(currentUser)
              : _buildList(currentUser, isDark),
        ),
      ],
    );
  }

  Widget _buildGrid(UserModel currentUser) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.68,
      ),
      itemCount: widget.users.length,
      itemBuilder: (context, index) {
        final user = widget.users[index];
        final matchPct = _matchPercent(currentUser, user);
        final isLiked = _likedIds.contains(user.id);
        return _GridCard(
          user: user,
          matchPct: matchPct,
          isLiked: isLiked,
          onTap: () => context.push('/profile/view/${user.id}'),
          onLike: () => _like(user),
        );
      },
    );
  }

  Widget _buildList(UserModel currentUser, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: widget.users.length,
      itemBuilder: (context, index) {
        final user = widget.users[index];
        final matchPct = _matchPercent(currentUser, user);
        final isLiked = _likedIds.contains(user.id);
        return _ListCard(
          user: user,
          matchPct: matchPct,
          isLiked: isLiked,
          isDark: isDark,
          onTap: () => context.push('/profile/view/${user.id}'),
          onLike: () => _like(user),
        );
      },
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
              color: AppTheme.primaryGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_alt_rounded,
                color: AppTheme.primaryGreen, size: 48),
          ),
          const SizedBox(height: 20),
          Text(
            'No souls nearby yet 🌙',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first in your area!\nExpand your match distance.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.5)
                  : AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grid Card ────────────────────────────────────────────────────────────────

class _GridCard extends StatelessWidget {
  final UserModel user;
  final int matchPct;
  final bool isLiked;
  final VoidCallback onTap;
  final VoidCallback onLike;

  const _GridCard({
    required this.user,
    required this.matchPct,
    required this.isLiked,
    required this.onTap,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final vibe = _vibeFor(user);
    final vibeColor = _vibeColorFor(user);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo
            CachedNetworkImage(
              imageUrl:
                  user.avatarUrl ?? 'https://i.pravatar.cc/400?u=${user.id}',
              fit: BoxFit.cover,
              memCacheWidth: 500,
              placeholder: (_, __) => Container(
                color: const Color(0xFF1C2232),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryBlue,
                    strokeWidth: 2,
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFF1C2232),
                child: const Icon(Icons.person_rounded,
                    size: 40, color: Colors.white30),
              ),
            ),

            // Gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    stops: const [0.45, 1.0],
                  ),
                ),
              ),
            ),

            // Match % badge (top right)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$matchPct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ),

            // Name, age, vibe + heart button at bottom
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${user.name}, ${user.age}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: vibeColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: vibeColor.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            vibe,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: vibeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Heart button
                  GestureDetector(
                    onTap: onLike,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLiked
                            ? AppTheme.primaryBlue.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.15),
                        border: Border.all(
                          color: isLiked
                              ? AppTheme.primaryBlue
                              : Colors.white.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── List Card ────────────────────────────────────────────────────────────────

class _ListCard extends StatelessWidget {
  final UserModel user;
  final int matchPct;
  final bool isLiked;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onLike;

  const _ListCard({
    required this.user,
    required this.matchPct,
    required this.isLiked,
    required this.isDark,
    required this.onTap,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final vibe = _vibeFor(user);
    final vibeColor = _vibeColorFor(user);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.8,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Photo
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl:
                    user.avatarUrl ?? 'https://i.pravatar.cc/400?u=${user.id}',
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                memCacheWidth: 192,
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${user.name}, ${user.age}',
                    style: TextStyle(
                      color: isDark ? Colors.white : AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: vibeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: vibeColor.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      vibe,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: vibeColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Match % + heart
            Column(
              children: [
                Text(
                  '$matchPct%',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.8)
                        : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onLike,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isLiked
                          ? AppTheme.primaryBlue.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.1),
                      border: Border.all(
                        color: isLiked
                            ? AppTheme.primaryBlue
                            : Colors.white.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
