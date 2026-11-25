import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:situationship/core/models/user_model.dart';
import 'package:situationship/core/theme/app_theme.dart';
import 'package:situationship/core/ai/vibe_matrix_matcher.dart';
import 'package:situationship/features/verification/presentation/widgets/s_badge_widget.dart';

class CupidProfileCard extends StatefulWidget {
  final CupidMatchResult match;
  final Function(UserModel) onLike;
  final Function(UserModel) onSuperLike;

  const CupidProfileCard({
    super.key,
    required this.match,
    required this.onLike,
    required this.onSuperLike,
  });

  @override
  State<CupidProfileCard> createState() => _CupidProfileCardState();
}

class _CupidProfileCardState extends State<CupidProfileCard> {
  bool _liked = false;
  bool _superLiked = false;
  int _activePhotoIndex = 0;

  @override
  Widget build(BuildContext context) {
    final candidate = widget.match.candidate;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final photos = candidate.photos.isNotEmpty
        ? candidate.photos
        : (candidate.avatarUrl != null ? [candidate.avatarUrl!] : <String>[]);

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 14, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141824) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? const Color(0xFF262E44)
              : Colors.black.withValues(alpha: 0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. Photo Preview with Compatibility Badge & Dots ────────────────
            SizedBox(
              height: 240,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Photo Carousel
                  if (photos.isNotEmpty)
                    PageView.builder(
                      itemCount: photos.length,
                      onPageChanged: (idx) => setState(() => _activePhotoIndex = idx),
                      itemBuilder: (context, idx) {
                        return CachedNetworkImage(
                          imageUrl: photos[idx],
                          fit: BoxFit.cover,
                          memCacheWidth: 600,
                          memCacheHeight: 600,
                          maxWidthDiskCache: 1200,
                          maxHeightDiskCache: 1200,
                          errorWidget: (_, __, ___) => _buildPlaceholderAvatar(candidate),
                        );
                      },
                    )
                  else
                    _buildPlaceholderAvatar(candidate),

                  // Top Gradient Shadow
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 60,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Top Compatibility Badge
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF5277), Color(0xFFFF3366)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF5277).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite_rounded, color: Colors.white, size: 11),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.match.compatibilityScore}% Vibe Match',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Gradient
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 80,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.85),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Name, Age & Verified in Photo
                  Positioned(
                    bottom: 10,
                    left: 12,
                    right: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${candidate.name}, ${candidate.age}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (candidate.isVerified) ...[
                              const SizedBox(width: 4),
                              const SBadgeWidget(size: 14),
                            ],
                          ],
                        ),
                        if (candidate.location != null && candidate.location!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, color: Colors.white70, size: 11),
                              const SizedBox(width: 3),
                              Text(
                                candidate.location!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Photo dots indicator if multiple photos
                  if (photos.length > 1)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Row(
                        children: List.generate(photos.length, (i) {
                          return Container(
                            margin: const EdgeInsets.only(left: 3),
                            width: i == _activePhotoIndex ? 12 : 5,
                            height: 4,
                            decoration: BoxDecoration(
                              color: i == _activePhotoIndex ? Colors.white : Colors.white38,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),

            // ── 2. Why You Match & Highlights ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Highlight traits pills
                  if (widget.match.highlightTraits.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: widget.match.highlightTraits.map((trait) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E2538)
                                : const Color(0xFFF0EDF8),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF2E3852)
                                  : Colors.black.withValues(alpha: 0.08),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            trait,
                            style: TextStyle(
                              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 8),

                  // Concierge explanation
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1F30) : const Color(0xFFF8F7FC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      widget.match.rationale.detailedExplanation,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Icebreaker hint
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 11,
                        color: Color(0xFFFF5277),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          widget.match.rationale.icebreakerSuggestion,
                          style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: isDark ? Colors.white54 : AppTheme.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ── 3. Interactive Action Buttons ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // View Profile
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        context.push('/profile/view/${candidate.id}');
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                          width: 0.9,
                        ),
                      ),
                      child: Text(
                        'View Profile',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Like Button
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _liked = true);
                      widget.onLike(candidate);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _liked
                            ? const Color(0xFFFF5277)
                            : (isDark ? const Color(0xFF1E2538) : const Color(0xFFFCE7F3)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFF5277).withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 18,
                          color: _liked ? Colors.white : const Color(0xFFFF5277),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Super Like Button
                  InkWell(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      setState(() => _superLiked = true);
                      widget.onSuperLike(candidate);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _superLiked
                            ? const Color(0xFFFFB800)
                            : (isDark ? const Color(0xFF242018) : const Color(0xFFFEF3C7)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFFB800).withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.bolt_rounded,
                          size: 19,
                          color: _superLiked ? Colors.black : const Color(0xFFFFB800),
                        ),
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

  Widget _buildPlaceholderAvatar(UserModel candidate) {
    return Container(
      color: const Color(0xFF1B2030),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_rounded, size: 54, color: Colors.white38),
            const SizedBox(height: 6),
            Text(
              candidate.name,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
