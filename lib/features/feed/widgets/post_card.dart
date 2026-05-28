import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import '../../../core/models/post_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../core/models/comment_model.dart';
import '../screens/comments_screen.dart';
import '../screens/edit_post_screen.dart';

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
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _heartScale;
  bool _showHeart = false;
  bool _isExpanded = false;
  bool _isBookmarked = false;
  final GlobalKey<PopupMenuButtonState<String>> _reactKey = GlobalKey();
  OverlayEntry? _reactionOverlayEntry;

  @override
  void initState() {
    super.initState();
    // Initialize animation controller
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
    _loadBookmarkStatus();
  }

  @override
  void dispose() {
    _hideReactionPopup();
    _heartController.dispose();
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

  bool get _isLiked => widget.post.likes.contains(_currentUserId) || widget.post.reactions.containsKey(_currentUserId);

  String? get _myReaction => widget.post.reactions[_currentUserId];

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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkSurface.withOpacity(0.85)
            : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDark, displayName, displayAvatar),
            if (widget.post.caption.isNotEmpty && widget.post.caption != widget.post.mood)
              _buildCaption(isDark),
            if (widget.post.imageUrl != null) _buildImage(),
            if (widget.post.imageUrl == null && widget.post.mood != null &&
                (widget.post.caption.isEmpty || widget.post.caption == widget.post.mood))
              _buildMoodHero(isDark),
            _buildActions(isDark),
            if (widget.post.commentCount > 0)
              _buildRecentComment(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, String displayName, String displayAvatar) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => context.push('/profile/view/${widget.post.userId}'),
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
                child: Image.network(
                  displayAvatar,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, __) => Container(
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
                              onTap: () => context.push('/profile/view/${widget.post.userId}'),
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: isDark ? Colors.white : Colors.black87,
                                  letterSpacing: -0.2,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (widget.post.isUserVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, color: AppTheme.primaryBlue, size: 15),
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
          IconButton(
            icon: Icon(Icons.more_horiz, color: isDark ? Colors.white70 : Colors.black54),
            onPressed: () => _showPostOptionsSheet(context, isDark),
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
            margin: const EdgeInsets.symmetric(horizontal: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: double.infinity,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: widget.post.imageUrl != null
                      ? Image.network(
                          widget.post.imageUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: progress.expectedTotalBytes != null
                                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                      : null,
                                  strokeWidth: 2,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: const Center(child: Icon(Icons.image_rounded, size: 48)),
                        ),
                ),
              ),
            ),
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

  Widget _buildActions(bool isDark) {
    final Set<String> uniqueReactors = {
      ...widget.post.likes,
      ...widget.post.reactions.keys,
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
                if (reactionCount > 0) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: () {
                      final Set<String> activeEmojis = {};
                      if (widget.post.likes.isNotEmpty) {
                        activeEmojis.add('👍');
                      }
                      activeEmojis.addAll(widget.post.reactions.values);
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
          child: Divider(height: 1, color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
        ),
        // Buttons Row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (buttonContext) {
                    Widget reactionWidget;
                    Color? reactionColor;
                    String reactionLabel = 'Like';

                    if (_myReaction != null) {
                      if (_myReaction == '👍') {
                        reactionLabel = 'Like';
                        reactionWidget = const Icon(Icons.thumb_up, size: 18, color: AppTheme.primaryBlue);
                        reactionColor = AppTheme.primaryBlue;
                      } else if (_myReaction == '❤️') {
                        reactionLabel = 'Love';
                        reactionWidget = const Icon(Icons.favorite, size: 18, color: Colors.red);
                        reactionColor = Colors.red;
                      } else {
                        if (_myReaction == '😆') {
                          reactionLabel = 'Haha';
                          reactionColor = Colors.amber[800];
                        } else if (_myReaction == '😮') {
                          reactionLabel = 'Wow';
                          reactionColor = Colors.amber[800];
                        } else if (_myReaction == '😢') {
                          reactionLabel = 'Sad';
                          reactionColor = Colors.amber[800];
                        } else if (_myReaction == '😡') {
                          reactionLabel = 'Angry';
                          reactionColor = Colors.deepOrange;
                        } else {
                          reactionLabel = 'Like';
                          reactionColor = Colors.orange;
                        }
                        reactionWidget = Icon(Icons.thumb_up, size: 18, color: reactionColor);
                      }
                    } else if (_isLiked) {
                      reactionWidget = const Icon(Icons.thumb_up, size: 18, color: AppTheme.primaryBlue);
                      reactionColor = AppTheme.primaryBlue;
                      reactionLabel = 'Like';
                    } else {
                      reactionWidget = Icon(Icons.thumb_up_alt_outlined, size: 18, color: isDark ? Colors.white70 : Colors.black54);
                    }

                    return InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showReactionPopup(buttonContext, isDark);
                      },
                      borderRadius: BorderRadius.circular(16),
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
                    );
                  }
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
                child: _FbActionButton(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  isDark: isDark,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      useRootNavigator: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _ShareSheet(post: widget.post),
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
                      backgroundImage: NetworkImage(
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
                                    child: Image.network(
                                      comment.text,
                                      fit: BoxFit.cover,
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
        double leftPosition = offset.dx - (300 - size.width) / 2;
        // Clamp to prevent overlay going off-screen
        leftPosition = leftPosition.clamp(12.0, screenWidth - 312.0);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  _hideReactionPopup();
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: leftPosition,
              top: offset.dy - 65,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkSurface.withOpacity(0.98) : Colors.white.withOpacity(0.98),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black12,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: ['👍', '❤️', '😆', '😮', '😢', '😡'].map((emoji) {
                      return _ReactionItem(
                        emoji: emoji,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          if (emoji == '👍') {
                            widget.onLike();
                          } else {
                            ref.read(postsProvider.notifier).reactToPost(
                              widget.post.id,
                              _currentUserId,
                              emoji,
                            );
                          }
                          _hideReactionPopup();
                        },
                      );
                    }).toList(),
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
    final isLongCaption = caption.length > 100;
    final displayCaption = isLongCaption && !_isExpanded ? '${caption.substring(0, 100)}...' : caption;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
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
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
                  height: 1.4,
                ),
              ),
              if (isLongCaption)
                TextSpan(
                  text: _isExpanded ? ' See less' : ' See more',
                  style: TextStyle(
                    fontSize: 14.5,
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
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

class _ShareSheet extends StatelessWidget {
  final PostModel post;
  const _ShareSheet({required this.post});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Future<void> copyLink() async {
      final postUrl = 'https://situationship.app/post/${post.id}';
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Link copied: $postUrl')),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.success,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44, height: 5,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const Text('Share Post', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          // Send in Chat
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('💬', style: TextStyle(fontSize: 22)),
              ),
              title: const Text('Send in Chat', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Select a conversation to share'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
          ),
          // Copy Link
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('📋', style: TextStyle(fontSize: 22)),
              ),
              title: const Text('Copy Link', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: copyLink,
            ),
          ),
          // Share to Twitter
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('🐦', style: TextStyle(fontSize: 22)),
              ),
              title: const Text('Share to Twitter', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Twitter integration coming soon'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
          ),
          // Share to Instagram
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('📸', style: TextStyle(fontSize: 22)),
              ),
              title: const Text('Share to Instagram', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Instagram integration coming soon'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
          ),
          // More Options
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text('📲', style: TextStyle(fontSize: 22)),
              ),
              title: const Text('More Options', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('More sharing options coming soon'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
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

class _ReactionItem extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;

  const _ReactionItem({required this.emoji, required this.onTap});

  @override
  State<_ReactionItem> createState() => _ReactionItemState();
}

class _ReactionItemState extends State<_ReactionItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.identity()..scale(_isHovered ? 1.25 : 1.0),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: _buildEmojiImage(widget.emoji, size: 28),
        ),
      ),
    );
  }
}

Widget _buildEmojiImage(String emoji, {double size = 20}) {
  try {
    final runes = emoji.runes.toList();
    final cleanRunes = runes.where((r) => r != 0xFE0F).toList();
    final hex = cleanRunes.map((r) => r.toRadixString(16)).join('-');
    
    return Image.network(
      'https://cdnjs.cloudflare.com/ajax/libs/twemoji/14.0.2/72x72/$hex.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Text(
        emoji,
        style: TextStyle(
          fontSize: size,
          fontFamilyFallback: const ['Apple Color Emoji', 'Segoe UI Emoji', 'Noto Color Emoji', 'Android Emoji'],
        ),
      ),
    );
  } catch (_) {
    return Text(
      emoji,
      style: TextStyle(
        fontSize: size,
        fontFamilyFallback: const ['Apple Color Emoji', 'Segoe UI Emoji', 'Noto Color Emoji', 'Android Emoji'],
      ),
    );
  }
}
