import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../../../core/models/post_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../verification/presentation/widgets/s_badge_widget.dart';
import '../../../core/constants/app_constants.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../core/models/comment_model.dart';
import '../screens/comments_screen.dart';
import '../screens/edit_post_screen.dart';
import '../../../core/widgets/full_screen_image_viewer.dart';
import '../../boost/widgets/boost_badge.dart';
import '../../boost/screens/boost_screen.dart';
import '../../boost/providers/boost_provider.dart';
import '../../../shared/widgets/profile_choice_sheet.dart';
class PostCard extends ConsumerStatefulWidget {
  final PostModel post;
  final VoidCallback onLike;

  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
  });

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard>
    with TickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _heartScale;
  // Animation for the React button tap feedback
  late AnimationController _reactBtnController;
  late Animation<double> _reactBtnScale;
  bool _showHeart = false;
  bool _isExpanded = false;
  bool _isBookmarked = false;
  final GlobalKey<PopupMenuButtonState<String>> _reactKey = GlobalKey();
  OverlayEntry? _reactionOverlayEntry;
  VideoPlayerController? _voiceCtrl;
  bool _isVoicePlaying = false;
  bool _isVoiceLoading = false;

  @override
  void initState() {
    super.initState();
    // Heart double-tap animation
    _heartController = AnimationController(
      vsync: this,
      duration: AppDurations.heartAnimation,
    );
    _heartScale = TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_heartController);
    // React button tap bounce animation
    _reactBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _reactBtnScale = TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.35)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.35, end: 0.9)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.9, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(_reactBtnController);
    _loadBookmarkStatus();
  }

  @override
  void dispose() {
    _hideReactionPopup();
    _heartController.dispose();
    _reactBtnController.dispose();
    _voiceCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList('bookmarked_posts') ?? [];
    if (mounted) {
      setState(() {
        _isBookmarked = bookmarks.contains(widget.post.id);
      });
    }
  }

  Future<void> _toggleBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList('bookmarked_posts') ?? [];

    setState(() {
      _isBookmarked = !_isBookmarked;
    });

    if (_isBookmarked) {
      bookmarks.add(widget.post.id);
      await prefs.setStringList('bookmarked_posts', bookmarks);
      HapticFeedback.lightImpact();
    } else {
      bookmarks.remove(widget.post.id);
      await prefs.setStringList('bookmarked_posts', bookmarks);
      HapticFeedback.lightImpact();
    }
  }

  void _doubleTapLike() {
    HapticFeedback.mediumImpact();
    setState(() => _showHeart = true);
    _heartController.forward(from: 0);
    Future.delayed(AppDurations.heartAnimation, () {
      if (mounted) setState(() => _showHeart = false);
    });
    if (!widget.post.likes.contains(_currentUserId)) {
      widget.onLike();
    }
  }

  String get _currentUserId {
    return ref.read(currentUserProvider).id;
  }

  // Use liveReactions from Firestore stream; fall back to widget.post data while loading
  bool _isLikedFromLive(List<String> liveLikes, Map<String, String> liveReactions) {
    return liveLikes.contains(_currentUserId) || liveReactions.containsKey(_currentUserId);
  }

  String? _myReactionFromLive(Map<String, String> liveReactions) {
    return liveReactions[_currentUserId];
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final liveAuthor = ref.watch(otherUserProvider(widget.post.userId));
    final displayName = liveAuthor.asData?.value?.name ?? widget.post.userName;
    final displayAvatar = liveAuthor.asData?.value?.avatarUrl
        ?? widget.post.userAvatar
        ?? 'https://i.pravatar.cc/100?u=${widget.post.userId}';

    // Watch live reactions from Firestore for real-time updates
    final liveReactionsAsync = ref.watch(livePostReactionsProvider(widget.post.id));
    final liveLikes = liveReactionsAsync.asData?.value.likes ?? widget.post.likes;
    final liveReactions = liveReactionsAsync.asData?.value.reactions ?? widget.post.reactions;
    final isLiked = _isLikedFromLive(liveLikes, liveReactions);
    final myReaction = _myReactionFromLive(liveReactions);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1A1035).withOpacity(0.55)
              : Colors.white.withOpacity(0.45),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.15)
                : Colors.white.withOpacity(0.60),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.20 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDark, displayName, displayAvatar, liveAuthor.asData?.value?.isVerified ?? widget.post.isUserVerified),
            if (widget.post.mood != null && widget.post.imageUrl != null)
              _buildMoodBadge(isDark),
            if (widget.post.caption.isNotEmpty &&
                widget.post.caption != widget.post.mood)
              _buildCaption(isDark),
            if (widget.post.voiceUrl != null)
              _buildVoicePlayer(isDark),
            if (widget.post.imageUrl != null) _buildImage(),
            if (widget.post.imageUrl == null &&
                widget.post.mood != null &&
                (widget.post.caption.isEmpty ||
                    widget.post.caption == widget.post.mood))
              _buildMoodHero(isDark),
            _buildActions(isDark, isLiked, myReaction, liveLikes, liveReactions),
            if (widget.post.commentCount > 0)
              _buildRecentComment(isDark),
          ],
        ),
      );
  }

  Future<void> _toggleVoicePlay() async {
    final voiceUrl = widget.post.voiceUrl;
    if (voiceUrl == null) return;

    if (_voiceCtrl != null) {
      if (_voiceCtrl!.value.isPlaying) {
        await _voiceCtrl!.pause();
        setState(() => _isVoicePlaying = false);
      } else {
        await _voiceCtrl!.play();
        setState(() => _isVoicePlaying = true);
      }
    } else {
      setState(() {
        _isVoiceLoading = true;
      });
      try {
        final ctrl = VideoPlayerController.networkUrl(Uri.parse(voiceUrl));
        await ctrl.initialize();
        ctrl.setLooping(false);
        ctrl.addListener(() {
          if (mounted) {
            setState(() {
              _isVoicePlaying = ctrl.value.isPlaying;
            });
            if (ctrl.value.position >= ctrl.value.duration) {
              setState(() {
                _isVoicePlaying = false;
              });
              ctrl.seekTo(Duration.zero);
            }
          }
        });
        _voiceCtrl = ctrl;
        await _voiceCtrl!.play();
        setState(() {
          _isVoicePlaying = true;
          _isVoiceLoading = false;
        });
      } catch (e) {
        setState(() {
          _isVoiceLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play voice note: $e')),
        );
      }
    }
  }

  Widget _buildVoicePlayer(bool isDark) {
    final currentPos = _voiceCtrl?.value.position.inMilliseconds.toDouble() ?? 0.0;
    final totalDuration = _voiceCtrl?.value.duration.inMilliseconds.toDouble() ?? 100.0;
    final progress = (totalDuration > 0) ? (currentPos / totalDuration).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF231E3D) : const Color(0xFFF3F2F8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _toggleVoicePlay,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFD66B7C),
                ),
                child: _isVoiceLoading
                    ? const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isVoicePlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Voice Note',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD66B7C)),
                      minHeight: 4,
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

  Widget _buildHeader(bool isDark, String displayName, String displayAvatar, bool isVerified) {
    final boostStatus = ref.watch(contentBoostStatusProvider(widget.post.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => ProfileChoiceSheet.navigateToProfile(context, ref, widget.post.userId),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: displayAvatar,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  memCacheWidth: 132, // 3x physical pixels
                  memCacheHeight: 132,
                  errorWidget: (context, url, error) => Container(
                    width: 44,
                    height: 44,
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () => ProfileChoiceSheet.navigateToProfile(context, ref, widget.post.userId),
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: isDark ? Colors.white : const Color(0xFF1A1035),
                                  letterSpacing: -0.2,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const SBadgeWidget(size: 15, showTooltip: false),
                          ],
                          if (widget.post.isPinned) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryBlue.withOpacity(0.25),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.push_pin, size: 9, color: Colors.white),
                                  SizedBox(width: 2),
                                  Text(
                                    'PINNED',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (boostStatus != null) ...[
                            const SizedBox(width: 8),
                            BoostBadge(isPremium: boostStatus.boostTier == 'premium'),
                          ],
                        ],
                      ),
                    ),
                    if (widget.post.communityId != null && widget.post.communityName != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.play_arrow_rounded, size: 12, color: isDark ? Colors.white30 : Colors.black38),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => context.push('/community/${widget.post.communityId}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.post.communityName!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      _formatTimeAgo(widget.post.createdAt),
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 5),
                    Text('·', style: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : Colors.black38)),
                    const SizedBox(width: 5),
                    Icon(
                      widget.post.privacy == 'private'
                          ? Icons.lock_outline_rounded
                          : (widget.post.privacy == 'connections' ? Icons.people_outline_rounded : Icons.public_rounded),
                      size: 13,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    if (widget.post.isEdited) ...[
                      const SizedBox(width: 5),
                      Text('·', style: TextStyle(fontSize: 12, color: isDark ? Colors.white30 : Colors.black38)),
                      const SizedBox(width: 5),
                      Text(
                        'Edited',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white30 : Colors.black38, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Quick boost button — tap to boost or see boost status
              if (widget.post.userId == _currentUserId)
                GestureDetector(
                  onTap: () => BoostScreen.show(context, widget.post),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withOpacity(0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, color: Colors.white, size: 13),
                        SizedBox(width: 3),
                        Text(
                          'Boost',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(Icons.more_horiz, color: isDark ? Colors.white70 : Colors.black54),
                onPressed: () => _showPostOptionsSheet(context, isDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    return GestureDetector(
      onDoubleTap: _doubleTapLike,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: widget.post.imageUrl != null
                ? GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => FullScreenImageViewer(
                            imageUrl: widget.post.imageUrl!,
                            heroTag: '${widget.post.id}_image',
                          ),
                        ),
                      );
                    },
                    child: Hero(
                      tag: '${widget.post.id}_image',
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.75,
                        ),
                        child: CachedNetworkImage(
                          imageUrl: widget.post.imageUrl!,
                          fit: BoxFit.contain,
                          memCacheWidth: 800,
                          progressIndicatorBuilder: (context, url, progress) {
                            return SizedBox(
                              height: 300,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: progress.progress,
                                  strokeWidth: 2,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (widget.post.musicTrack != null)
            Positioned(
              bottom: 22,
              left: 22,
              right: 22,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.post.musicTrack!,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              widget.post.musicArtist ?? '',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Text('🎵', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
          if (_showHeart)
            AnimatedBuilder(
              animation: _heartScale,
              builder: (context, child) => Transform.scale(
                scale: _heartScale.value,
                child: child,
              ),
              child: const Icon(
                Icons.favorite_rounded,
                size: 100,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.black26, blurRadius: 20),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(
    bool isDark,
    bool isLiked,
    String? myReaction,
    List<String> liveLikes,
    Map<String, String> liveReactions,
  ) {
    final Set<String> uniqueReactors = {
      ...liveLikes,
      ...liveReactions.keys,
    };
    final int reactionCount = uniqueReactors.length;

    return Column(
      children: [
        // Stats Row
        if (reactionCount > 0 || widget.post.commentCount > 0 || widget.post.shareCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                if (reactionCount > 0)
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        useRootNavigator: true,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _LikesSheet(post: widget.post),
                      );
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: () {
                            final Set<String> activeEmojis = {};
                            if (liveLikes.isNotEmpty) {
                              activeEmojis.add('🔥'); // legacy likes show as 🔥
                            }
                            activeEmojis.addAll(liveReactions.values);
                            return activeEmojis.toList().take(3).map((emoji) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 2.0),
                                child: _buildEmojiImage(emoji, size: 16),
                              );
                            }).toList();
                          }(),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatCount(reactionCount),
                          style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (widget.post.commentCount > 0)
                  Text(
                    '${_formatCount(widget.post.commentCount)} comments',
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.w500),
                  ),
                if (widget.post.commentCount > 0 && widget.post.shareCount > 0)
                  Text(' · ', style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)),
                if (widget.post.shareCount > 0)
                  Text(
                    '${_formatCount(widget.post.shareCount)} shares',
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Divider(
            height: 1,
            color: isDark
                ? Colors.white.withOpacity(0.10)
                : Colors.black.withOpacity(0.08),
          ),
        ),
        // Buttons Row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (buttonContext) {
                    // Determine the displayed reaction emoji & label using LIVE data
                    Widget reactionWidget;
                    Color? reactionColor;
                    String reactionLabel = 'React';

                    const genZLabels = {
                      '🔥': 'Fire',
                      '💀': 'Dead 💀',
                      '🫶': 'Luv',
                      '😭': 'Crying',
                      '🤩': 'Obsessed',
                      '👀': 'No way',
                      '👍': 'Vibe',
                      '❤️': 'Luv',
                    };

                    if (myReaction != null) {
                      reactionLabel = genZLabels[myReaction] ?? 'React';
                      reactionColor = myReaction == '🔥'
                          ? Colors.deepOrange
                          : myReaction == '💀'
                              ? Colors.grey[700]
                              : myReaction == '🫶'
                                  ? const Color(0xFFFF3CAC)
                                  : myReaction == '😭'
                                      ? const Color(0xFF5B9BD5)
                                      : myReaction == '🤩'
                                          ? Colors.amber[800]
                                          : myReaction == '👀'
                                              ? Colors.teal
                                              : AppTheme.primaryBlue;
                      reactionWidget = _buildEmojiImage(myReaction, size: 20);
                    } else if (isLiked) {
                      reactionLabel = 'Fire';
                      reactionColor = Colors.deepOrange;
                      reactionWidget = _buildEmojiImage('🔥', size: 20);
                    } else {
                      reactionWidget = const Text('🤍', style: TextStyle(fontSize: 20));
                    }

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _reactBtnController.forward(from: 0);
                        _showReactionPopup(buttonContext, isDark);
                      },
                      child: AnimatedBuilder(
                        animation: _reactBtnScale,
                        builder: (_, child) => Transform.scale(
                          scale: _reactBtnScale.value,
                          child: child,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              reactionWidget,
                              const SizedBox(width: 6),
                              Text(
                                reactionLabel,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: reactionColor ?? (isDark ? Colors.white70 : Colors.black54),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _FbActionButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Comment',
                  isDark: isDark,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => CommentsSheet(
                        postId: widget.post.id,
                        postUserName: widget.post.userName,
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: _HypeItActionButton(
                  isDark: isDark,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    showModalBottomSheet(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _HypeItSheet(post: widget.post),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildRecentComment(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => CommentsSheet(
                  postId: widget.post.id,
                  postUserName: widget.post.userName,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
              child: Row(
                children: [
                  Text(
                    'View more comments',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded, size: 10, color: isDark ? Colors.white60 : Colors.black54),
                ],
              ),
            ),
          ),
          StreamBuilder(
            stream: firestoreProvider
                .collection('posts')
                .doc(widget.post.id)
                .collection('comments')
                .orderBy('createdAt', descending: true)
                .limit(1)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox.shrink();
              }
              final doc = snapshot.data!.docs.first;
              final comment = CommentModel.fromMap(doc.data() as Map<String, dynamic>);
              
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundImage: CachedNetworkImageProvider(
                        comment.userAvatar ?? 'https://i.pravatar.cc/100?u=${comment.userId}',
                      ),
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                comment.userName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: isDark ? Colors.white : AppTheme.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _formatTimeAgo(comment.createdAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white30 : Colors.black38,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          comment.text.startsWith('http')
                              ? Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  constraints: const BoxConstraints(maxWidth: 80, maxHeight: 80),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: CachedNetworkImage(
                                      imageUrl: comment.text,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 240,
                                      memCacheHeight: 240,
                                    ),
                                  ),
                                )
                              : Text(
                                  comment.text,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: isDark ? Colors.white.withOpacity(0.8) : Colors.black87,
                                    height: 1.3,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showReactionPopup(BuildContext buttonContext, bool isDark) {
    if (_reactionOverlayEntry != null) {
      _hideReactionPopup();
      return;
    }

    final renderBox = buttonContext.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _reactionOverlayEntry = OverlayEntry(
      builder: (context) {
        final screenWidth = MediaQuery.of(buttonContext).size.width;
        double leftPosition = offset.dx - (320 - size.width) / 2;
        // Clamp to prevent overlay going off-screen
        leftPosition = leftPosition.clamp(12.0, screenWidth - 332.0);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hideReactionPopup,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: leftPosition,
              top: offset.dy - 80,
              child: Material(
                color: Colors.transparent,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: 0.6 + 0.4 * value,
                      alignment: Alignment.bottomCenter,
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E2E).withOpacity(0.97)
                          : Colors.white.withOpacity(0.97),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.20),
                          blurRadius: 24,
                          spreadRadius: 2,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: const Color(0xFFFF3CAC).withOpacity(0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.12)
                            : Colors.black.withOpacity(0.07),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: ['🔥', '💀', '🫶', '😭', '🤩', '👀'].asMap().entries.map((entry) {
                        final i = entry.key;
                        final emoji = entry.value;
                        // Staggered entrance using delayed TweenAnimationBuilder
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 200 + i * 40),
                          curve: Curves.easeOutBack,
                          builder: (context, v, child) => Transform.translate(
                            offset: Offset(0, 8 * (1 - v)),
                            child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
                          ),
                          child: _ReactionItem(
                            emoji: emoji,
                            label: const {
                              '🔥': 'Fire',
                              '💀': 'Dead',
                              '🫶': 'Luv',
                              '😭': 'Crying',
                              '🤩': 'Obsessed',
                              '👀': 'No way',
                            }[emoji],
                            onTap: () {
                              HapticFeedback.lightImpact();
                              ref.read(postsProvider.notifier).reactToPost(
                                widget.post.id,
                                _currentUserId,
                                emoji,
                              );
                              _hideReactionPopup();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(buttonContext).insert(_reactionOverlayEntry!);
  }

  void _hideReactionPopup() {
    _reactionOverlayEntry?.remove();
    _reactionOverlayEntry = null;
  }

  Widget _buildCaption(bool isDark) {
    final caption = widget.post.caption;

    // ── Parse plan metadata from caption lines ─────────────────────────────
    // Strategy: scan every line. Lines that contain "Plan:", "Time:", "Where:"
    // are treated as plan metadata. All other non-empty lines form the user caption.
    // This approach is intentionally emoji-agnostic and newline-variant-agnostic.
    String? planTitle, planTime, planLocation;
    final captionLines = <String>[];

    for (final rawLine in caption.split(RegExp(r'\r?\n'))) {
      final stripped = rawLine.trim();
      if (stripped.isEmpty) continue; // skip blank lines

      final planIdx   = stripped.indexOf('Plan:');
      final timeIdx   = stripped.indexOf('Time:');
      final whereIdx  = stripped.indexOf('Where:');

      if (planIdx != -1 && planTitle == null) {
        planTitle = stripped.substring(planIdx + 5).trim();
      } else if (timeIdx != -1 && planTime == null) {
        planTime = stripped.substring(timeIdx + 5).trim();
      } else if (whereIdx != -1 && planLocation == null) {
        planLocation = stripped.substring(whereIdx + 6).trim();
      } else {
        captionLines.add(stripped);
      }
    }

    final mainCaption = captionLines.join('\n');
    final isLongCaption = mainCaption.length > 120;
    final displayCaption =
        isLongCaption && !_isExpanded ? '${mainCaption.substring(0, 120)}...' : mainCaption;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Regular caption text ─────────────────────────────────────────
          if (mainCaption.isNotEmpty)
            GestureDetector(
              onTap: () {
                if (isLongCaption) setState(() => _isExpanded = !_isExpanded);
              },
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: displayCaption,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                        height: 1.5,
                      ),
                    ),
                    if (isLongCaption)
                      TextSpan(
                        text: _isExpanded ? ' See less' : ' See more',
                        style: const TextStyle(
                          fontSize: 14.5,
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // ── Plan Card ────────────────────────────────────────────────────
          if (planTitle != null) ...[
            if (mainCaption.isNotEmpty) const SizedBox(height: 12),
            _buildPlanCard(isDark, planTitle, planTime, planLocation),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    bool isDark,
    String title,
    String? time,
    String? location,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1E2A4A),
                  const Color(0xFF251E4A),
                ]
              : [
                  const Color(0xFFEEF4FF),
                  const Color(0xFFF3EEFF),
                ],
        ),
        border: Border.all(
          color: isDark
              ? AppTheme.primaryBlue.withOpacity(0.25)
              : AppTheme.primaryBlue.withOpacity(0.20),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.12 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle shimmer circle in the top-right corner
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.accentPurple.withOpacity(isDark ? 0.18 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with icon + "Plan" label
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryBlue, AppTheme.accentPurple],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withOpacity(0.30),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    ShaderMask(
                      shaderCallback: (b) =>
                          AppTheme.primaryGradient.createShader(b),
                      child: const Text(
                        'PLAN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Plan title
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1035),
                    letterSpacing: -0.3,
                  ),
                ),

                // Time & Location rows
                if ((time != null && time.isNotEmpty) ||
                    (location != null && location.isNotEmpty)) ...[
                  const SizedBox(height: 12),
                  Container(
                    height: 0.8,
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.06),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (time != null && time.isNotEmpty)
                        _planDetail(
                          isDark: isDark,
                          icon: Icons.schedule_rounded,
                          iconColor: const Color(0xFF6ECBF5),
                          label: time,
                        ),
                      if (location != null && location.isNotEmpty)
                        _planDetail(
                          isDark: isDark,
                          icon: Icons.location_on_rounded,
                          iconColor: const Color(0xFFFF6B9D),
                          label: location,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planDetail({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 13, color: iconColor),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : const Color(0xFF3D3D5C),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }



  // Mood-only posts get a gradient hero card instead of a blank image slot
  Widget _buildMoodHero(bool isDark) {
    final mood = widget.post.mood!;
    final parts = mood.split(' ');
    final emoji = parts.first;
    final label = parts.skip(1).join(' ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44),
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withOpacity(isDark ? 0.22 : 0.1),
            AppTheme.primaryGreen.withOpacity(isDark ? 0.22 : 0.1),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildEmojiImage(emoji, size: 54),
          const SizedBox(height: 12),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryBlue,
              letterSpacing: 1.5,
            ),
          ),
          if (widget.post.musicTrack != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.music_note_rounded, color: AppTheme.primaryBlue, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${widget.post.musicTrack} - ${widget.post.musicArtist}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMoodBadge(bool isDark) {
    final mood = widget.post.mood!;
    final parts = mood.split(' ');
    final emoji = parts.first;
    final label = parts.skip(1).join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: AppTheme.primaryBlue.withOpacity(0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildEmojiImage(emoji, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  // ─── Custom Premium Dialog & Bottom Sheet Flows ───────────────────────

  void _showPostOptionsSheet(BuildContext context, bool isDark) {
    final isOwnPost = widget.post.userId == _currentUserId;
    // Plans always contain all three structured fields in the caption
    final caption = widget.post.caption;
    final isPlan = caption.contains('Plan:') && (caption.contains('Time:') || caption.contains('Where:'));

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              if (isOwnPost) ...[
                if (!isPlan)
                  ListTile(
                    leading: const Icon(Icons.bolt, color: Colors.amber),
                    title: const Text('Boost Post', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Get more visibility on campus or city'),
                    onTap: () {
                      Navigator.pop(context);
                      BoostScreen.show(context, widget.post);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: AppTheme.primaryBlue),
                  title: const Text('Edit Post', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Update caption, mood, music, or replace assets'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => EditPostScreen(post: widget.post)),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(widget.post.isPinned ? Icons.pin_drop : Icons.push_pin_outlined, color: Colors.amber),
                  title: Text(widget.post.isPinned ? 'Unpin Post' : 'Pin Post', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(widget.post.isPinned ? 'Remove from top of your profile' : 'Keep at the top of your profile'),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(postsProvider.notifier).togglePinPost(widget.post.id, !widget.post.isPinned);
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(widget.post.isPinned ? 'Post unpinned successfully!' : 'Post pinned successfully!'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppTheme.primaryBlue,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.music_note_outlined, color: Colors.teal),
                  title: const Text('Post Music', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Add or change attached sound track'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => EditPostScreen(post: widget.post)),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: Colors.purple),
                  title: const Text('Post Privacy', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Currently ${widget.post.privacy.toUpperCase()}'),
                  onTap: () {
                    Navigator.pop(context);
                    _showPrivacySelectorSheet(context, isDark);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.content_copy, color: Colors.grey),
                  title: const Text('Copy Post link', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () {
                    Navigator.pop(context);
                    Clipboard.setData(ClipboardData(text: 'https://situationship.app/post/${widget.post.id}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied to clipboard!')),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete Post', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmationDialog(context);
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.bookmark_outline, color: AppTheme.primaryBlue),
                  title: const Text('Save Post', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Save to folders (Reflective, Energetic, Chill)'),
                  onTap: () {
                    Navigator.pop(context);
                    _showSaveToCategoryDialog(context, isDark);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.favorite_outline, color: Colors.red),
                  title: const Text('Interested', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('costs 3 Aura • notifies @username directly'),
                  onTap: () {
                    Navigator.pop(context);
                    _showInterestConfirmationDialog(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block_outlined, color: Colors.orange),
                  title: const Text('Not Interested', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Preferences adjust algorithm feed'),
                  onTap: () {
                    Navigator.pop(context);
                    _showNotInterestedConfirmation(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.content_copy, color: Colors.grey),
                  title: const Text('Copy Post link', style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () {
                    Navigator.pop(context);
                    Clipboard.setData(ClipboardData(text: 'https://situationship.app/post/${widget.post.id}'));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied to clipboard!')),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.report_gmailerrorred, color: Colors.redAccent),
                  title: const Text('Report Post', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(context);
                    _showReportSheet(context, isDark);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showPrivacySelectorSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        String selected = widget.post.privacy;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Post Privacy Selector', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  RadioListTile<String>(
                    title: const Text('Public (Everyone)'),
                    value: 'public',
                    groupValue: selected,
                    activeColor: AppTheme.primaryBlue,
                    onChanged: (val) => setModalState(() => selected = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Connections Only'),
                    value: 'connections',
                    groupValue: selected,
                    activeColor: AppTheme.primaryBlue,
                    onChanged: (val) => setModalState(() => selected = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Private (Only me)'),
                    value: 'private',
                    groupValue: selected,
                    activeColor: AppTheme.primaryBlue,
                    onChanged: (val) => setModalState(() => selected = val!),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        ref.read(postsProvider.notifier).updatePostPrivacy(widget.post.id, selected);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Privacy updated to: ${selected.toUpperCase()}'),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Post?'),
          content: const Text(
            'Are you sure you want to permanently remove this post? '
            'You will lose all Aura/interactions and reactions associated with it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                ref.read(postsProvider.notifier).deletePost(widget.post.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Post permanently deleted')),
                );
              },
              child: const Text('Permanently Remove', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showSaveToCategoryDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
          title: const Text('Save to Folder', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Text('🤔', style: TextStyle(fontSize: 20)),
                title: const Text('Reflective Folder'),
                onTap: () => _confirmSaveCategory(context, 'Reflective'),
              ),
              ListTile(
                leading: const Text('🔥', style: TextStyle(fontSize: 20)),
                title: const Text('Energetic Folder'),
                onTap: () => _confirmSaveCategory(context, 'Energetic'),
              ),
              ListTile(
                leading: const Text('😎', style: TextStyle(fontSize: 20)),
                title: const Text('Chill Folder'),
                onTap: () => _confirmSaveCategory(context, 'Chill'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmSaveCategory(BuildContext context, String category) async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList('bookmarked_posts') ?? [];
    if (!bookmarks.contains(widget.post.id)) {
      bookmarks.add(widget.post.id);
      await prefs.setStringList('bookmarked_posts', bookmarks);
    }
    
    // Store localized category folder
    await prefs.setString('category_${widget.post.id}', category);
    
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved post inside "$category" Folder!'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }

  void _showInterestConfirmationDialog(BuildContext context) {
    final liveUser = ref.read(currentUserProvider);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Show Interest in ${widget.post.userName}?'),
          content: const Text(
            'Costs 3 Aura. This notifies them directly of your interest '
            'and plays a strong haptic confirmation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                if (liveUser.coins < 3) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Not enough Aura! Check matches page.')),
                  );
                  return;
                }

                // Deduct coins & notify
                try {
                  await firestoreProvider.collection('users').doc(_currentUserId).update({
                    'coins': FieldValue.increment(-3),
                  });
                  await sendNotification(
                    userId: widget.post.userId,
                    senderId: _currentUserId,
                    senderName: liveUser.name,
                    senderAvatar: liveUser.avatarUrl,
                    type: 'interest',
                    title: 'New Interest!',
                    body: '${liveUser.name} showed interest in your post!',
                  );
                  
                  HapticFeedback.vibrate();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Interest Sent successfully! (3 Aura deducted)'),
                      backgroundColor: AppTheme.success,
                    ),
                  );
                } catch (e) {
                  debugPrint('Failed to send interest: $e');
                }
              },
              child: const Text('Send Interest', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showNotInterestedConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Not Interested?'),
          content: const Text(
            'Confirming will hide this post from your feed and adjust '
            'preference algorithms accordingly.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _hidePostWithUndo();
              },
              child: const Text('Confirm', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _hidePostWithUndo() {
    ref.read(hiddenPostsProvider.notifier).update((state) => [...state, widget.post.id]);
    HapticFeedback.lightImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Post hidden. Adjusting algorithm...'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppTheme.primaryBlue,
          onPressed: () {
            ref.read(hiddenPostsProvider.notifier).update(
              (state) => state.where((id) => id != widget.post.id).toList(),
            );
          },
        ),
      ),
    );
  }

  void _showReportSheet(BuildContext context, bool isDark) {
    String selectedReason = 'Spam';
    final List<String> reasons = ['Spam', 'Harassment', 'Inappropriate content', 'Hate speech', 'Intellectual property violation'];
    final TextEditingController reportDetails = TextEditingController();

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Report Post', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('Help us understand what is going on with this post.'),
                  const SizedBox(height: 16),
                  ...reasons.map((reason) {
                    return RadioListTile<String>(
                      title: Text(reason),
                      value: reason,
                      groupValue: selectedReason,
                      activeColor: AppTheme.primaryBlue,
                      onChanged: (val) => setModalState(() => selectedReason = val!),
                    );
                  }),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reportDetails,
                    decoration: const InputDecoration(
                      hintText: 'Additional details (optional)...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _submitReportAndShowSubmitted(selectedReason, reportDetails.text, isDark);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Submit Report'),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  void _submitReportAndShowSubmitted(String reason, String details, bool isDark) async {
    // Write report doc
    try {
      final docId = firestoreProvider.collection('reports').doc().id;
      await firestoreProvider.collection('reports').doc(docId).set({
        'id': docId,
        'postId': widget.post.id,
        'reportedBy': _currentUserId,
        'reason': reason,
        'details': details,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('Failed to save report: $e');
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: AppTheme.success, size: 54),
              const SizedBox(height: 16),
              const Text('Report Submitted', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Thank you for reporting. We will review this post shortly. '
                'Would you like to hide this post in the meantime?',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _hidePostWithUndo();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Hide this post'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  final Color? iconColor;

  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withOpacity(0.04),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: iconColor ?? (isDark ? Colors.white70 : AppTheme.textSecondary),
        ),
      ),
    );
  }
}

class _HypeItSheet extends StatelessWidget {
  final PostModel post;
  const _HypeItSheet({required this.post});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Future<void> copyLink() async {
      final postUrl = 'https://situationship.app/post/${post.id}';
      await Clipboard.setData(ClipboardData(text: postUrl));
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(child: Text('Link copied! spread the chaos 🔥')),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFEF4444),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }

    final bgColor = isDark ? const Color(0xFF13111C) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1035);
    final subColor = isDark ? Colors.white60 : Colors.black54;
    final tileColor = isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF5F3FF);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 5,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF3CAC), Color(0xFFF59E0B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _buildEmojiImage('🔥', size: 26),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hype It Up! 🚀',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textColor),
                  ),
                  Text(
                    'Spread the vibe fr fr',
                    style: TextStyle(fontSize: 13, color: subColor),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Send in Chat
          _HypeTile(
            emoji: '💬',
            title: 'Slide into DMs',
            subtitle: 'Send it to your fav people',
            tileColor: tileColor,
            textColor: textColor,
            subColor: subColor,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Pick your situationship 👀'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF7C3AED),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Copy Link
          _HypeTile(
            emoji: '🔗',
            title: 'Copy Link',
            subtitle: 'Snatch the link & do ur thing',
            tileColor: tileColor,
            textColor: textColor,
            subColor: subColor,
            onTap: copyLink,
          ),
          const SizedBox(height: 8),
          // Share to X/Twitter
          _HypeTile(
            emoji: '🐦',
            title: 'Drop on X (Twitter)',
            subtitle: 'Let the timeline eat 🍽️',
            tileColor: tileColor,
            textColor: textColor,
            subColor: subColor,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('X integration dropping soon 👀'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Share to Instagram
          _HypeTile(
            emoji: '📸',
            title: 'Blast on Insta',
            subtitle: 'Stories, Reels, whatever slaps',
            tileColor: tileColor,
            textColor: textColor,
            subColor: subColor,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Instagram link-up coming soon ✨'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFFFF3CAC),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // More Options
          _HypeTile(
            emoji: '📲',
            title: 'More Ways to Hype',
            subtitle: 'WhatsApp, Snap, wherever u vibe',
            tileColor: tileColor,
            textColor: textColor,
            subColor: subColor,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('More share options comin fr 🔜'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF00C6FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _HypeTile extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color tileColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTap;

  const _HypeTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.tileColor,
    required this.textColor,
    required this.subColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _buildEmojiImage(emoji, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14.5, color: textColor)),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: subColor, height: 1.3)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: subColor),
          ],
        ),
      ),
    );
  }
}

class _FbActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool isDark;

  const _FbActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: color ?? (isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: color ?? (isDark ? Colors.white70 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HypeItActionButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool isDark;

  const _HypeItActionButton({required this.onTap, required this.isDark});

  @override
  State<_HypeItActionButton> createState() => _HypeItActionButtonState();
}

class _HypeItActionButtonState extends State<_HypeItActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                scale: _pulseAnim.value,
                child: child,
              ),
              child: _buildEmojiImage('🔥', size: 20),
            ),
            const SizedBox(width: 6),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFFF3CAC), Color(0xFFF59E0B)],
              ).createShader(bounds),
              child: Text(
                'Hype It',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: widget.isDark ? Colors.white : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionItem extends StatefulWidget {
  final String emoji;
  final String? label;
  final VoidCallback onTap;

  const _ReactionItem({required this.emoji, this.label, required this.onTap});

  @override
  State<_ReactionItem> createState() => _ReactionItemState();
}

class _ReactionItemState extends State<_ReactionItem>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isAnimating = false;
  late final AnimationController _bounceCtrl;
  late final Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _bounceAnim = TweenSequence([
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.55)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 35),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.55, end: 0.85)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 25),
      TweenSequenceItem(
          tween: Tween<double>(begin: 0.85, end: 1.05)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 40),
    ]).animate(_bounceCtrl);
    _bounceCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (mounted) setState(() => _isAnimating = false);
      }
    });
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  void _triggerBounce() {
    setState(() => _isAnimating = true);
    _bounceCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _triggerBounce();
      },
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _triggerBounce();
          // Small delay so animation is visible before onTap dismisses the popup
          Future.delayed(const Duration(milliseconds: 120), widget.onTap);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _bounceAnim,
              builder: (context, child) => Transform.scale(
                // Play animation on tap (mobile) AND hover (desktop)
                scale: (_isAnimating || _isHovered) ? _bounceAnim.value : 1.0,
                child: child,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _isHovered
                      ? Colors.white.withOpacity(0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildEmojiImage(widget.emoji, size: 32),
              ),
            ),
            if (widget.label != null)
              AnimatedOpacity(
                // Show label both on hover (desktop) and during tap animation (mobile)
                opacity: (_isHovered || _isAnimating) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 120),
                child: Text(
                  widget.label!,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LiveEmojiWidget extends StatefulWidget {
  final String emoji;
  final double size;
  final bool animateMotion;

  const LiveEmojiWidget({
    super.key,
    required this.emoji,
    this.size = 20,
    this.animateMotion = true,
  });

  @override
  State<LiveEmojiWidget> createState() => _LiveEmojiWidgetState();
}

class _LiveEmojiWidgetState extends State<LiveEmojiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionCtrl;

  @override
  void initState() {
    super.initState();
    _motionCtrl = AnimationController(
      vsync: this,
      duration: _getDurationForEmoji(widget.emoji),
    );
    if (widget.animateMotion) {
      _motionCtrl.repeat(reverse: true);
    }
  }

  Duration _getDurationForEmoji(String e) {
    if (e.contains('😭')) return const Duration(milliseconds: 350); // fast sobbing tremble
    if (e.contains('🔥')) return const Duration(milliseconds: 550); // burning flame pulse
    if (e.contains('💀')) return const Duration(milliseconds: 1300); // floaty ghost wobble
    if (e.contains('🫶') || e.contains('❤️')) return const Duration(milliseconds: 650); // heartbeat
    if (e.contains('👀')) return const Duration(milliseconds: 950); // side glance
    if (e.contains('🤩')) return const Duration(milliseconds: 750); // starburst shimmer
    return const Duration(milliseconds: 1100);
  }

  @override
  void dispose() {
    _motionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.emoji;
    Widget rawImage = _buildRawEmojiImage(e, size: widget.size);

    if (!widget.animateMotion) {
      return rawImage;
    }

    return AnimatedBuilder(
      animation: _motionCtrl,
      builder: (context, child) {
        final t = _motionCtrl.value;

        if (e.contains('😭')) {
          // Sobbing trembling shake (fast up & down vibration)
          final dy = (t < 0.5 ? (t * 2) : (2 - t * 2)) * 2.4 - 1.2;
          return Transform.translate(
            offset: Offset(0, dy),
            child: child,
          );
        } else if (e.contains('🔥')) {
          // Burning flame scale pulse & upward float
          final scale = 1.0 + 0.12 * t;
          final dy = -1.5 * t;
          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          );
        } else if (e.contains('💀')) {
          // Floaty ghost wobble (vertical float + rotational tilt)
          final dy = -3.5 * (0.5 - (t - 0.5).abs());
          final angle = (t - 0.5) * 0.14;
          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.rotate(
              angle: angle,
              child: child,
            ),
          );
        } else if (e.contains('👀')) {
          // Eye glance shift (horizontal translation)
          final dx = (t - 0.5) * 3.2;
          return Transform.translate(
            offset: Offset(dx, 0),
            child: child,
          );
        } else if (e.contains('🫶') || e.contains('❤️')) {
          // Heartbeat pulse rhythm
          final scale = 1.0 + 0.16 * (t < 0.35 ? t / 0.35 : (1.0 - t) / 0.65);
          return Transform.scale(
            scale: scale,
            child: child,
          );
        } else if (e.contains('🤩')) {
          // Starburst shimmer
          final scale = 1.0 + 0.10 * t;
          final angle = (t - 0.5) * 0.12;
          return Transform.rotate(
            angle: angle,
            child: Transform.scale(scale: scale, child: child),
          );
        }

        // Gentle breathing float default
        final dy = -1.8 * t;
        return Transform.translate(
          offset: Offset(0, dy),
          child: child,
        );
      },
      child: rawImage,
    );
  }
}

Widget _buildRawEmojiImage(String emoji, {required double size}) {
  try {
    final runes = emoji.runes.toList();
    final cleanRunes = runes.where((r) => r != 0xFE0F).toList();
    final hex = cleanRunes.map((r) => r.toRadixString(16)).join('-');

    // Noto Animated 3D GIF URL
    final notoGifUrl = 'https://fonts.gstatic.com/s/e/notoemoji/latest/$hex/512.gif';
    // Static Twemoji PNG fallback
    final twemojiUrl = 'https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/72x72/$hex.png';

    return Image.network(
      notoGifUrl,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Image.network(
        twemojiUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Text(
          emoji,
          style: TextStyle(
            fontSize: size,
            fontFamilyFallback: const [
              'Apple Color Emoji',
              'Segoe UI Emoji',
              'Noto Color Emoji',
              'Android Emoji'
            ],
          ),
        ),
      ),
    );
  } catch (_) {
    return Text(
      emoji,
      style: TextStyle(
        fontSize: size,
        fontFamilyFallback: const [
          'Apple Color Emoji',
          'Segoe UI Emoji',
          'Noto Color Emoji',
          'Android Emoji'
        ],
      ),
    );
  }
}

Widget _buildEmojiImage(String emoji, {double size = 20, bool animateMotion = true}) {
  return LiveEmojiWidget(emoji: emoji, size: size, animateMotion: animateMotion);
}

class _LikesSheet extends ConsumerStatefulWidget {
  final PostModel post;
  
  const _LikesSheet({required this.post});

  @override
  ConsumerState<_LikesSheet> createState() => _LikesSheetState();
}

class _LikesSheetState extends ConsumerState<_LikesSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<String> _tabs;
  late Map<String, List<String>> _reactionGroups;

  @override
  void initState() {
    super.initState();
    final allReactors = {...widget.post.likes, ...widget.post.reactions.keys}.toList();
    
    _reactionGroups = {'All': allReactors};
    
    for (var userId in allReactors) {
      String reaction = '🔥'; // default to fire for legacy likes
      if (widget.post.reactions.containsKey(userId)) {
         reaction = widget.post.reactions[userId]!;
      }
      _reactionGroups.putIfAbsent(reaction, () => []).add(userId);
    }
    
    _tabs = ['All'];
    final otherReactions = _reactionGroups.keys.where((k) => k != 'All').toList();
    otherReactions.sort((a, b) => _reactionGroups[b]!.length.compareTo(_reactionGroups[a]!.length));
    _tabs.addAll(otherReactions);
    
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getReactionForUser(String userId) {
    if (widget.post.reactions.containsKey(userId)) {
      return widget.post.reactions[userId]!;
    }
    return '🔥'; // fire as default
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              color: isDark ? AppTheme.darkBg.withOpacity(0.85) : Colors.white.withOpacity(0.9),
              child: Column(
                children: [
                  // Handle
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white30 : Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (_tabs.length > 1)
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicatorColor: AppTheme.primaryBlue,
                      labelColor: AppTheme.primaryBlue,
                      unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
                      dividerColor: Colors.transparent,
                      tabs: _tabs.map((tab) {
                        if (tab == 'All') {
                          return Tab(text: 'All ${_reactionGroups[tab]!.length}');
                        }
                        return Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildEmojiImage(tab, size: 16),
                              const SizedBox(width: 4),
                              Text('${_reactionGroups[tab]!.length}'),
                            ],
                          ),
                        );
                      }).toList(),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Likes & Reactions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: _tabs.map((tab) {
                        final userIds = _reactionGroups[tab]!;
                        return ListView.builder(
                          controller: controller,
                          itemCount: userIds.length,
                          itemBuilder: (context, index) {
                            final userId = userIds[index];
                            final userAsync = ref.watch(otherUserProvider(userId));
                            final userReaction = _getReactionForUser(userId);
                            
                            return userAsync.when(
                              data: (user) {
                                if (user == null) return const SizedBox.shrink();
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                  leading: Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundImage: CachedNetworkImageProvider(
                                          user.avatarUrl ?? 'https://i.pravatar.cc/100?u=$userId',
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isDark ? AppTheme.darkBg : Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          padding: const EdgeInsets.all(2),
                                          child: _buildEmojiImage(userReaction, size: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                  title: Text(
                                    user.name,
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '@${user.name.replaceAll(' ', '').toLowerCase()}',
                                    style: TextStyle(
                                      color: isDark ? Colors.white60 : Colors.black54,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    context.push('/profile/view/$userId');
                                  },
                                );
                              },
                              loading: () => const ListTile(
                                leading: CircleAvatar(child: CircularProgressIndicator()),
                                title: Text('Loading...'),
                              ),
                              error: (_, __) => const SizedBox.shrink(),
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
