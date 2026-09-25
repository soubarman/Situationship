import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../../../core/models/post_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_palette.dart';
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
  bool? _localIsJoinedPlan;
  List<String>? _localParticipants;

  void _handleJoinPlan(String title, List<String> currentParticipants) {
    final uid = _currentUserId;
    if (uid.isEmpty) return;
    HapticFeedback.mediumImpact();
    final updated = [
      ...currentParticipants.where((id) => id != uid),
      uid,
    ];
    setState(() {
      _localIsJoinedPlan = true;
      _localParticipants = updated;
    });
    ref.read(postsProvider.notifier).joinPlan(widget.post.id, uid);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("You're in for $title! 🎉"),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ref.read(appPaletteProvider).primary,
        action: SnackBarAction(
          label: "Who's In",
          textColor: Colors.white,
          onPressed: () {
            _showPlanParticipantsSheet(
              context,
              Theme.of(context).brightness == Brightness.dark,
              title,
              updated,
              true,
            );
          },
        ),
      ),
    );
  }

  void _handleLeavePlan(String title, List<String> currentParticipants) {
    final uid = _currentUserId;
    if (uid.isEmpty) return;
    HapticFeedback.lightImpact();
    final updated = currentParticipants.where((id) => id != uid).toList();
    setState(() {
      _localIsJoinedPlan = false;
      _localParticipants = updated;
    });
    ref.read(postsProvider.notifier).leavePlan(widget.post.id, uid);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Left the plan"),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ref.read(appPaletteProvider).primary,
      ),
    );
  }
  final GlobalKey<PopupMenuButtonState<String>> _reactKey = GlobalKey();
  OverlayEntry? _reactionOverlayEntry;
  VideoPlayerController? _voiceCtrl;
  bool _isVoicePlaying = false;
  bool _isVoiceLoading = false;

  bool? _localIsFollowing;

  Future<void> _handleFollowToggle(bool isCurrentlyFollowing) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser.id == widget.post.userId) return;
    HapticFeedback.lightImpact();
    setState(() {
      _localIsFollowing = !isCurrentlyFollowing;
    });
    try {
      await ref.read(socialProvider.notifier).toggleFollow(
        currentUserId: currentUser.id,
        targetUserId: widget.post.userId,
        isCurrentlyFollowing: isCurrentlyFollowing,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _localIsFollowing = isCurrentlyFollowing;
        });
      }
      debugPrint('Follow toggle error: $e');
    }
  }

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
    final uid = ref.read(currentUserProvider).id;
    if (uid.isNotEmpty) return uid;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
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
    final palette = ref.watch(appPaletteProvider);
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

    // Watch live plan participants from Firestore
    final liveParticipantsAsync = ref.watch(livePlanParticipantsProvider(widget.post.id));
    final liveParticipants = liveParticipantsAsync.asData?.value ?? widget.post.planParticipants;
    final effectiveParticipants = _localParticipants ?? liveParticipants;
    final isJoinedPlan = _localIsJoinedPlan ?? effectiveParticipants.contains(_currentUserId);

    final currentUser = ref.watch(currentUserProvider);
    final isFollowing = _localIsFollowing ?? currentUser.following.contains(widget.post.userId);
    final displayLocation = widget.post.location ??
        (widget.post.caption.contains('Where:')
            ? RegExp(r'Where:\s*(.+)').firstMatch(widget.post.caption)?.group(1)?.trim()
            : null);
    final hasPlan = widget.post.caption.contains('Plan:') ||
        widget.post.caption.contains('🗓️ Plan');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? palette.surfaceTint : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? palette.primary.withOpacity(0.20) : const Color(0xFFE8E4F2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: palette.primary.withOpacity(isDark ? 0.06 : 0.03),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(
            isDark,
            palette,
            displayName,
            displayAvatar,
            liveAuthor.asData?.value?.isVerified ?? widget.post.isUserVerified,
            isFollowing,
            displayLocation,
          ),
          if (widget.post.mood != null && widget.post.imageUrl != null)
            _buildMoodBadge(isDark, palette),
          _buildCaptionAndPlan(isDark, palette, effectiveParticipants, isJoinedPlan),
          if (!hasPlan && widget.post.imageUrl != null) _buildImage(),
          if (widget.post.imageUrl == null &&
              widget.post.mood != null &&
              (widget.post.caption.isEmpty ||
                  widget.post.caption == widget.post.mood))
            _buildMoodHero(isDark, palette),
          _buildActions(isDark, palette, isLiked, myReaction, liveLikes, liveReactions),
          if (widget.post.voiceUrl != null && widget.post.voiceUrl!.trim().isNotEmpty)
            _buildVoicePlayer(isDark, palette),
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

  Widget _buildVoicePlayer(bool isDark, AppPalette palette) {
    final currentPos = _voiceCtrl?.value.position.inMilliseconds.toDouble() ?? 0.0;
    final totalDuration = _voiceCtrl?.value.duration.inMilliseconds.toDouble() ?? 45000.0;
    final progress = (totalDuration > 0) ? (currentPos / totalDuration).clamp(0.0, 1.0) : 0.0;

    String durationText = '0:45';
    if (_voiceCtrl != null && _voiceCtrl!.value.isInitialized) {
      final pos = _voiceCtrl!.value.position;
      final dur = _voiceCtrl!.value.duration;
      final displayTime = _isVoicePlaying ? pos : dur;
      final m = displayTime.inMinutes.remainder(60).toString().padLeft(1, '0');
      final s = displayTime.inSeconds.remainder(60).toString().padLeft(2, '0');
      durationText = '$m:$s';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? palette.backgroundTint.withOpacity(0.85) : const Color(0xFFF3F1FA),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark ? palette.primary.withOpacity(0.25) : Colors.black12,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggleVoicePlay,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: palette.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
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
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _EqualizerWaveform(
                  progress: progress,
                  isDark: isDark,
                  isPlaying: _isVoicePlaying,
                  availableWidth: constraints.maxWidth,
                  activeColor: palette.primary,
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Voice Note',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                durationText,
                style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? const Color(0xFF9E9AB7) : Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? palette.surfaceTint : Colors.black.withOpacity(0.06),
            ),
            child: Icon(
              Icons.more_horiz_rounded,
              size: 16,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedBadge(AppPalette palette) {
    return Container(
      width: 17,
      height: 17,
      margin: const EdgeInsets.only(left: 6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.verifiedBadgeBg,
      ),
      child: Center(
        child: Icon(
          palette.verifiedIcon,
          color: palette.verifiedIconColor,
          size: 11,
        ),
      ),
    );
  }

  Widget _buildFollowButton(bool isDark, bool isFollowing, AppPalette palette) {
    if (widget.post.userId == _currentUserId) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => _handleFollowToggle(isFollowing),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          gradient: isFollowing ? null : palette.primaryGradient,
          color: isFollowing
              ? (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05))
              : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isFollowing
              ? null
              : [
                  BoxShadow(
                    color: palette.primary.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
          border: isFollowing
              ? Border.all(
                  color: isDark ? Colors.white24 : Colors.black12,
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isFollowing) ...[
              const Icon(Icons.add_rounded, color: Colors.white, size: 13),
              const SizedBox(width: 2),
            ],
            Text(
              isFollowing ? 'Following' : 'Follow',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    bool isDark,
    AppPalette palette,
    String displayName,
    String displayAvatar,
    bool isVerified,
    bool isFollowing,
    String? displayLocation,
  ) {
    final boostStatus = ref.watch(contentBoostStatusProvider(widget.post.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => ProfileChoiceSheet.navigateToProfile(context, ref, widget.post.userId),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? palette.primary.withOpacity(0.3) : Colors.black12,
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: displayAvatar,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  memCacheWidth: 200,
                  errorWidget: (context, url, error) => Container(
                    color: isDark ? Colors.white10 : Colors.black12,
                    child: const Icon(Icons.person, color: Colors.white54, size: 24),
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
                    Flexible(
                      child: GestureDetector(
                        onTap: () => ProfileChoiceSheet.navigateToProfile(context, ref, widget.post.userId),
                        child: Text(
                          displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: isDark ? Colors.white : const Color(0xFF131127),
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (isVerified) _buildVerifiedBadge(palette),
                    _buildFollowButton(isDark, isFollowing, palette),
                    if (widget.post.isPinned) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.push_pin_rounded,
                        size: 13,
                        color: palette.primary,
                      ),
                    ],
                    if (boostStatus != null) ...[
                      const SizedBox(width: 6),
                      BoostBadge(isPremium: boostStatus.boostTier == 'premium'),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      _formatTimeAgo(widget.post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFF9E9AB7) : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text('•', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF6B658A) : Colors.black38)),
                    const SizedBox(width: 5),
                    Icon(
                      widget.post.privacy == 'private'
                          ? Icons.lock_outline_rounded
                          : (widget.post.privacy == 'connections' ? Icons.people_outline_rounded : Icons.public_rounded),
                      size: 13,
                      color: isDark ? const Color(0xFF9E9AB7) : Colors.black54,
                    ),
                    if (displayLocation != null && displayLocation.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Text('•', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF6B658A) : Colors.black38)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          displayLocation,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF9E9AB7) : Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (widget.post.isEdited) ...[
                      const SizedBox(width: 5),
                      Text('•', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF6B658A) : Colors.black38)),
                      const SizedBox(width: 5),
                      Text(
                        'Edited',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? const Color(0xFF6B658A) : Colors.black38,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (widget.post.communityId != null && widget.post.communityName != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => context.push('/community/${widget.post.communityId}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.primary.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: palette.primary.withOpacity(0.25), width: 0.8),
                          ),
                          child: Text(
                            widget.post.communityName!,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 9.5,
                              color: palette.primary,
                            ),
                          ),
                        ),
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
              if (widget.post.userId == _currentUserId)
                GestureDetector(
                  onTap: () => BoostScreen.show(context, widget.post),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, color: Colors.white, size: 12),
                        SizedBox(width: 2),
                        Text(
                          'Boost',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () => _showPostOptionsSheet(context, isDark, palette),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? palette.backgroundTint.withOpacity(0.85) : Colors.black.withOpacity(0.05),
                    border: Border.all(
                      color: isDark ? palette.primary.withOpacity(0.18) : Colors.black.withOpacity(0.05),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    color: isDark ? Colors.white.withOpacity(0.85) : Colors.black87,
                    size: 19,
                  ),
                ),
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
    AppPalette palette,
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
    final displayLikes = reactionCount > 0 ? reactionCount : widget.post.likes.length;
    final displayComments = widget.post.commentCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        children: [
          // React Button - directly opens animated reactions
          Builder(
            builder: (buttonContext) {
              final hasReacted = myReaction != null;
              final isLikedOnly = !hasReacted && isLiked;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  _reactBtnController.forward(from: 0);
                  _showReactionPopup(buttonContext, isDark);
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedBuilder(
                  animation: _reactBtnScale,
                  builder: (_, child) => Transform.scale(
                    scale: _reactBtnScale.value,
                    child: child,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasReacted)
                        _buildEmojiImage(myReaction!, size: 22)
                      else if (isLikedOnly)
                        Icon(
                          Icons.favorite_rounded,
                          color: palette.primary,
                          size: 22,
                        )
                      else
                        Icon(
                          Icons.add_reaction_outlined,
                          color: isDark ? Colors.white.withOpacity(0.75) : Colors.black54,
                          size: 22,
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (displayLikes > 0) {
                            showModalBottomSheet(
                              context: context,
                              useRootNavigator: true,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => _LikesSheet(post: widget.post),
                            );
                          } else {
                            _showReactionPopup(buttonContext, isDark);
                          }
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          displayLikes > 0 ? _formatCount(displayLikes) : 'React',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: (hasReacted || isLikedOnly)
                                ? (isDark ? Colors.white : palette.primary)
                                : (isDark ? Colors.white.withOpacity(0.9) : Colors.black87),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(width: 24),

          // Comment Button
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
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: isDark ? Colors.white.withOpacity(0.75) : Colors.black54,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _formatCount(displayComments),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 24),

          // Share Button
          GestureDetector(
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
            behavior: HitTestBehavior.opaque,
            child: Transform.rotate(
              angle: -0.3,
              child: Icon(
                Icons.send_rounded,
                color: isDark ? Colors.white.withOpacity(0.75) : Colors.black54,
                size: 21,
              ),
            ),
          ),

          const Spacer(),

          // Bookmark Button
          GestureDetector(
            onTap: _toggleBookmark,
            behavior: HitTestBehavior.opaque,
            child: Icon(
              _isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: _isBookmarked
                  ? palette.primary
                  : (isDark ? Colors.white.withOpacity(0.75) : Colors.black54),
              size: 22,
            ),
          ),
        ],
      ),
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
        const popupWidth = 330.0;
        double leftPosition = offset.dx - (popupWidth - size.width) / 2;
        leftPosition = leftPosition.clamp(10.0, (screenWidth - (popupWidth + 10.0)).clamp(10.0, screenWidth));
        final double topPosition = (offset.dy - 76 < 60)
            ? offset.dy + size.height + 10
            : offset.dy - 76;

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
              top: topPosition,
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
                          color: AppTheme.primaryBlue.withOpacity(0.12),
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
                      children: ['🔥', '❤️', '💀', '🫶', '😭', '🤩', '👀'].asMap().entries.map((entry) {
                        final i = entry.key;
                        final emoji = entry.value;
                        // Staggered entrance using delayed TweenAnimationBuilder
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 180 + i * 35),
                          curve: Curves.easeOutBack,
                          builder: (context, v, child) => Transform.translate(
                            offset: Offset(0, 8 * (1 - v)),
                            child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
                          ),
                          child: _ReactionItem(
                            emoji: emoji,
                            label: const {
                              '🔥': 'Fire',
                              '❤️': 'Love',
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

  Widget _buildCaptionAndPlan(bool isDark, AppPalette palette, List<String> participants, bool isJoinedPlan) {
    final caption = widget.post.caption;

    String? planTitle, planTime, planLocation, planDescription;
    final captionLines = <String>[];

    for (final rawLine in caption.split(RegExp(r'\r?\n'))) {
      final stripped = rawLine.trim();
      if (stripped.isEmpty) continue;

      final planIdx   = stripped.indexOf('Plan:');
      final timeIdx   = stripped.indexOf('Time:');
      final whereIdx  = stripped.indexOf('Where:');
      final descIdx   = stripped.indexOf('Desc:');
      final aboutIdx  = stripped.indexOf('About:');

      if (planIdx != -1 && planTitle == null) {
        planTitle = stripped.substring(planIdx + 5).trim();
      } else if (timeIdx != -1 && planTime == null) {
        planTime = stripped.substring(timeIdx + 5).trim();
      } else if (whereIdx != -1 && planLocation == null) {
        planLocation = stripped.substring(whereIdx + 6).trim();
      } else if (descIdx != -1 && planDescription == null) {
        planDescription = stripped.substring(descIdx + 5).trim();
      } else if (aboutIdx != -1 && planDescription == null) {
        planDescription = stripped.substring(aboutIdx + 6).trim();
      } else {
        captionLines.add(stripped);
      }
    }

    String mainCaption = '';
    if (captionLines.isNotEmpty) {
      mainCaption = captionLines.first;
      if (captionLines.length > 1 && planDescription == null) {
        planDescription = captionLines.sublist(1).join('\n');
      }
    }

    final isLongCaption = mainCaption.length > 120;
    final displayCaption = isLongCaption && !_isExpanded
        ? '${mainCaption.substring(0, 120)}...'
        : mainCaption;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mainCaption.isNotEmpty && mainCaption != widget.post.mood)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: GestureDetector(
              onTap: () {
                if (isLongCaption) setState(() => _isExpanded = !_isExpanded);
              },
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: displayCaption,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w400,
                        color: isDark ? Colors.white.withOpacity(0.95) : const Color(0xFF131127),
                        height: 1.45,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (isLongCaption)
                      TextSpan(
                        text: _isExpanded ? ' See less' : ' See more',
                        style: TextStyle(
                          fontSize: 14.5,
                          color: palette.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (planTitle != null)
          _buildPlanCard(isDark, palette, planTitle, planTime, planLocation, planDescription, participants, isJoinedPlan),
      ],
    );
  }

  Widget _buildPlanCard(
    bool isDark,
    AppPalette palette,
    String title,
    String? time,
    String? location,
    String? description,
    List<String> participants,
    bool isJoinedPlan,
  ) {
    final displayDesc = (description != null && description.isNotEmpty)
        ? description
        : "Let's watch the sky and talk about life.";
    final displayTime = (time != null && time.isNotEmpty) ? time : 'Today 7:00 PM';
    final displayLoc = (location != null && location.isNotEmpty)
        ? location
        : (widget.post.location ?? 'Earth');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Color.lerp(palette.surfaceTint, palette.primary, 0.14)!,
                  Color.lerp(palette.backgroundTint, palette.secondary, 0.08)!,
                ]
              : [
                  Color.lerp(Colors.white, palette.primary, 0.06)!,
                  Color.lerp(Colors.white, palette.secondary, 0.04)!,
                ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? palette.primary.withOpacity(0.32)
              : palette.primary.withOpacity(0.18),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withOpacity(isDark ? 0.20 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Thumbnail + Details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlanThumbnail(
                  imageUrl: widget.post.imageUrl,
                  onTap: () {
                    if (widget.post.imageUrl != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FullScreenImageViewer(
                            imageUrl: widget.post.imageUrl!,
                            heroTag: '${widget.post.id}_plan_thumb',
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 15,
                            color: palette.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'PLAN',
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF1A1035),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayDesc,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? const Color(0xFF9E9AB7) : Colors.black54,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Bottom row: Time, Location, I'm In button, Participants
            Wrap(
              spacing: 6,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Chips group (Time & Location)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Time chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? palette.backgroundTint.withOpacity(0.85)
                            : Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? palette.primary.withOpacity(0.25)
                              : palette.primary.withOpacity(0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: palette.accent.withOpacity(0.20),
                            ),
                            child: Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: palette.accent,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            displayTime,
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF1A1035),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Location chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? palette.backgroundTint.withOpacity(0.85)
                            : Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? palette.secondary.withOpacity(0.25)
                              : palette.secondary.withOpacity(0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: palette.secondary.withOpacity(0.20),
                            ),
                            child: Icon(
                              Icons.location_on_rounded,
                              size: 13,
                              color: palette.secondary,
                            ),
                          ),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: Text(
                              displayLoc,
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF1A1035),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Right group: "I'm In" / "Joined ✓" button + Participants
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (!isJoinedPlan) {
                          _handleJoinPlan(title, participants);
                        } else {
                          // Already joined! Open sheet to see who is in
                          HapticFeedback.lightImpact();
                          _showPlanParticipantsSheet(
                            context,
                            isDark,
                            title,
                            participants,
                            true,
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5.5),
                        decoration: BoxDecoration(
                          gradient: isJoinedPlan
                              ? null
                              : palette.primaryGradient,
                          color: isJoinedPlan
                              ? (isDark ? palette.primary.withOpacity(0.20) : palette.primary.withOpacity(0.12))
                              : null,
                          borderRadius: BorderRadius.circular(20),
                          border: isJoinedPlan
                              ? Border.all(color: palette.primary, width: 1.2)
                              : null,
                          boxShadow: isJoinedPlan
                              ? null
                              : [
                                  BoxShadow(
                                    color: palette.primary.withOpacity(0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isJoinedPlan) ...[
                              Icon(Icons.check_rounded, size: 13, color: isDark ? Colors.white : palette.primary),
                              const SizedBox(width: 3),
                            ],
                            Text(
                              isJoinedPlan ? "Joined" : "I'm In",
                              style: TextStyle(
                                color: isJoinedPlan
                                    ? (isDark ? Colors.white : palette.primary)
                                    : Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Real overlapping participant avatars & tap to see who's in
                    _buildParticipantAvatars(isDark, palette, participants, title, isJoinedPlan),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantAvatars(
    bool isDark,
    AppPalette palette,
    List<String> participants,
    String planTitle,
    bool isJoined,
  ) {
    if (participants.isEmpty) {
      return GestureDetector(
        onTap: () => _showPlanParticipantsSheet(
          context,
          isDark,
          planTitle,
          participants,
          isJoined,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? palette.primary.withOpacity(0.25) : palette.primary.withOpacity(0.15),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 13,
                color: isDark ? palette.accent : palette.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '0 in • See list',
                style: TextStyle(
                  color: isDark ? Colors.white70 : palette.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final displayUserIds = participants.take(3).toList();
    final stackWidth = 22.0 + (displayUserIds.length - 1) * 12.0;

    return GestureDetector(
      onTap: () => _showPlanParticipantsSheet(
        context,
        isDark,
        planTitle,
        participants,
        isJoined,
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: stackWidth,
              height: 22,
              child: Stack(
                children: List.generate(displayUserIds.length, (idx) {
                  return Positioned(
                    left: idx * 12.0,
                    child: _PlanParticipantAvatar(
                      userId: displayUserIds[idx],
                      isDark: isDark,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '${participants.length} in',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF131127),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlanParticipantsSheet(
    BuildContext context,
    bool isDark,
    String planTitle,
    List<String> participants,
    bool isJoined,
  ) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlanParticipantsSheet(
        postId: widget.post.id,
        planTitle: planTitle,
        initialParticipants: participants,
        isDark: isDark,
        initialIsJoined: isJoined,
        onJoin: () => _handleJoinPlan(planTitle, participants),
        onLeave: () => _handleLeavePlan(planTitle, participants),
      ),
    );
  }



  // Mood-only posts get a gradient hero card instead of a blank image slot
  Widget _buildMoodHero(bool isDark, AppPalette palette) {
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
            palette.primary.withOpacity(isDark ? 0.22 : 0.1),
            palette.secondary.withOpacity(isDark ? 0.22 : 0.1),
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
              color: palette.primary,
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
                    Icon(Icons.music_note_rounded, color: palette.primary, size: 16),
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

  Widget _buildMoodBadge(bool isDark, AppPalette palette) {
    final mood = widget.post.mood!;
    final parts = mood.split(' ');
    final emoji = parts.first;
    final label = parts.skip(1).join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
        decoration: BoxDecoration(
          color: palette.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: palette.primary.withOpacity(0.35),
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
                color: palette.primary,
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

  void _showPostOptionsSheet(BuildContext context, bool isDark, AppPalette palette) {
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
            color: isDark ? palette.surfaceTint : Colors.white,
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
                  leading: Icon(Icons.edit_outlined, color: palette.primary),
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
                        backgroundColor: palette.primary,
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
                    _showPrivacySelectorSheet(context, isDark, palette);
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
                  leading: Icon(Icons.bookmark_outline, color: palette.primary),
                  title: const Text('Save Post', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Save to folders (Reflective, Energetic, Chill)'),
                  onTap: () {
                    Navigator.pop(context);
                    _showSaveToCategoryDialog(context, isDark, palette);
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

  void _showPrivacySelectorSheet(BuildContext context, bool isDark, AppPalette palette) {
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
                color: isDark ? palette.surfaceTint : Colors.white,
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
                    activeColor: palette.primary,
                    onChanged: (val) => setModalState(() => selected = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Connections Only'),
                    value: 'connections',
                    groupValue: selected,
                    activeColor: palette.primary,
                    onChanged: (val) => setModalState(() => selected = val!),
                  ),
                  RadioListTile<String>(
                    title: const Text('Private (Only me)'),
                    value: 'private',
                    groupValue: selected,
                    activeColor: palette.primary,
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
                            backgroundColor: palette.primary,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.primary,
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

  void _showSaveToCategoryDialog(BuildContext context, bool isDark, AppPalette palette) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? palette.surfaceTint : Colors.white,
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
              child: Text('Send Interest', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
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
              Icon(Icons.check_circle, color: AppTheme.success, size: 54),
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

class _HypeItSheet extends ConsumerWidget {
  final PostModel post;
  const _HypeItSheet({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = ref.watch(appPaletteProvider);

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
            backgroundColor: palette.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }

    final bgColor = isDark ? palette.surfaceTint : Colors.white;
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
                  gradient: palette.primaryGradient,
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
                  backgroundColor: palette.primary,
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
                  backgroundColor: AppTheme.primaryBlue,
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
                  backgroundColor: AppTheme.primaryBlue,
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
              shaderCallback: (bounds) => LinearGradient(
                colors: [AppTheme.primaryBlue, Color(0xFFF59E0B)],
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

class _EqualizerWaveform extends StatelessWidget {
  final double progress;
  final bool isDark;
  final bool isPlaying;
  final double? availableWidth;
  final Color? activeColor;

  const _EqualizerWaveform({
    required this.progress,
    required this.isDark,
    required this.isPlaying,
    this.availableWidth,
    this.activeColor,
  });

  static const List<double> barHeights = [
    5, 8, 14, 10, 16, 22, 18, 13, 8, 15, 21, 16, 11, 7, 13, 19, 15, 9, 17, 21, 14, 8, 4
  ];

  @override
  Widget build(BuildContext context) {
    int count = barHeights.length;
    if (availableWidth != null && availableWidth! > 0) {
      final maxBars = (availableWidth! / 4.6).floor();
      if (maxBars < count && maxBars > 4) {
        count = maxBars;
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(count, (index) {
        final barHeight = barHeights[index % barHeights.length];
        final barProgress = (index + 1) / count;
        final isFilled = progress >= barProgress;

        return Container(
          width: 2.2,
          height: barHeight,
          margin: const EdgeInsets.symmetric(horizontal: 1.1),
          decoration: BoxDecoration(
            color: isFilled
                ? (activeColor ?? const Color(0xFFFF2A85))
                : (isDark ? const Color(0xFF8B82B2) : const Color(0xFFB5ADC8)),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

class _PlanThumbnail extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback? onTap;

  const _PlanThumbnail({this.imageUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 76,
          height: 76,
          child: (imageUrl != null && imageUrl!.startsWith('http'))
              ? CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _buildSunsetArt(),
                )
              : _buildSunsetArt(),
        ),
      ),
    );
  }

  Widget _buildSunsetArt() {
    return Container(
      width: 76,
      height: 76,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF6B1D76), // deep twilight purple
            Color(0xFFB8236B), // rich magenta
            Color(0xFFFF5252), // coral crimson
            Color(0xFFFF9F43), // golden sunrise
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft ambient sun glow
          Positioned(
            bottom: 12,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFEAA7).withOpacity(0.55),
                    const Color(0xFFFF9F43).withOpacity(0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Setting sun
          Positioned(
            bottom: 16,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Colors.white,
                    Color(0xFFFFF7C2),
                    Color(0xFFFFC048),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFC048).withOpacity(0.65),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          // Silhouette mountain background
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _MountainClipper(),
              child: Container(
                height: 22,
                color: const Color(0xFF1E1038),
              ),
            ),
          ),
          // Silhouette foreground hills
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _ForegroundRidgeClipper(),
              child: Container(
                height: 12,
                color: const Color(0xFF110722),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MountainClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, size.height * 0.6);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.1, size.width * 0.5, size.height * 0.55);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.85, size.width, size.height * 0.3);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ForegroundRidgeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.35, size.height * 0.7, size.width * 0.65, size.height * 0.2);
    path.lineTo(size.width, size.height * 0.5);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _PlanParticipantAvatar extends ConsumerWidget {
  final String userId;
  final bool isDark;

  const _PlanParticipantAvatar({required this.userId, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(appPaletteProvider);
    final currentUid = ref.watch(currentUserProvider).id.isNotEmpty
        ? ref.watch(currentUserProvider).id
        : (FirebaseAuth.instance.currentUser?.uid ?? '');
    final userAsync = (userId == currentUid)
        ? AsyncValue.data(ref.watch(currentUserProvider))
        : ref.watch(otherUserProvider(userId));

    final user = userAsync.valueOrNull;
    final avatarUrl = user?.avatarUrl;
    final name = user?.name ?? 'User';

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? palette.surfaceTint : Colors.white,
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: (avatarUrl != null && avatarUrl.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: avatarUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallbackAvatar(name, palette),
              )
            : _fallbackAvatar(name, palette),
      ),
    );
  }

  Widget _fallbackAvatar(String name, AppPalette palette) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: palette.primary,
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PlanParticipantsSheet extends ConsumerWidget {
  final String postId;
  final String planTitle;
  final List<String> initialParticipants;
  final bool isDark;
  final bool initialIsJoined;
  final VoidCallback onJoin;
  final VoidCallback onLeave;

  const _PlanParticipantsSheet({
    required this.postId,
    required this.planTitle,
    required this.initialParticipants,
    required this.isDark,
    required this.initialIsJoined,
    required this.onJoin,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(appPaletteProvider);
    final currentUid = ref.watch(currentUserProvider).id.isNotEmpty
        ? ref.watch(currentUserProvider).id
        : (FirebaseAuth.instance.currentUser?.uid ?? '');

    // Watch live participants from Firestore for instant real-time synchronization
    final liveParticipantsAsync = ref.watch(livePlanParticipantsProvider(postId));
    final liveList = liveParticipantsAsync.asData?.value;
    final participants = (liveList != null && liveList.isNotEmpty)
        ? liveList
        : initialParticipants;
    final isJoined = (currentUid.isNotEmpty && participants.contains(currentUid)) || initialIsJoined;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.70,
      ),
      decoration: BoxDecoration(
        color: isDark ? palette.surfaceTint : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: isDark ? palette.primary.withOpacity(0.25) : const Color(0xFFE8E4F2),
          width: 1,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.primary.withOpacity(0.15),
                    ),
                    child: Icon(
                      Icons.celebration_rounded,
                      color: palette.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Who\'s In for $planTitle',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : const Color(0xFF131127),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${participants.length} ${participants.length == 1 ? 'person has' : 'people have'} joined',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? const Color(0xFF9E9AB7) : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            // Participants list or empty state
            if (participants.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.groups_rounded,
                      size: 46,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No one has joined yet!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF131127),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Be the first to join this plan and start the vibe.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: participants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final userId = participants[index];
                    final isMe = currentUid.isNotEmpty && userId == currentUid;
                    final userAsync = isMe
                        ? AsyncValue.data(ref.watch(currentUserProvider))
                        : ref.watch(otherUserProvider(userId));

                    final user = userAsync.valueOrNull;
                    final rawName = user?.name.trim() ?? '';
                    final name = isMe
                        ? (rawName.isNotEmpty ? '$rawName (You)' : 'You (You)')
                        : (rawName.isNotEmpty ? rawName : 'Member');
                    final avatarUrl = user?.avatarUrl;
                    final isVerified = user?.isVerified ?? false;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? palette.backgroundTint : const Color(0xFFF7F5FC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              ProfileChoiceSheet.navigateToProfile(context, ref, userId);
                            },
                            child: CircleAvatar(
                              radius: 20,
                              backgroundColor: palette.primary,
                              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                  ? CachedNetworkImageProvider(avatarUrl)
                                  : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? Colors.white : const Color(0xFF131127),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isVerified) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.verified_rounded, size: 15, color: palette.primary),
                                    ],
                                  ],
                                ),
                                if (user?.bio != null && user!.bio!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    user.bio!,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark ? const Color(0xFF9E9AB7) : Colors.black54,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              ProfileChoiceSheet.navigateToProfile(context, ref, userId);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                              isMe ? 'My Profile' : 'View',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // Bottom action: Join or Leave
            if (isJoined)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: palette.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "You're in for this plan",
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        onLeave();
                      },
                      child: const Text(
                        'Leave Plan',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      onJoin();
                    },
                    icon: const Icon(Icons.celebration_rounded, color: Colors.white, size: 18),
                    label: const Text(
                      "I'm In! 🚀",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: palette.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

