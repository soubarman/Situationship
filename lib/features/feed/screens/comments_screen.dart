import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/comment_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/widgets/full_screen_image_viewer.dart';
import 'package:intl/intl.dart';

class CommentsSheet extends ConsumerStatefulWidget {
  final String postId;
  final String postUserName;

  const CommentsSheet({
    super.key,
    required this.postId,
    required this.postUserName,
  });

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _commentController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitComment() {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final currentUser = ref.read(currentUserProvider);
    final comment = CommentModel(
      id: 'c_${DateTime.now().millisecondsSinceEpoch}',
      postId: widget.postId,
      userId: currentUser.id,
      userName: currentUser.name,
      userAvatar: currentUser.avatarUrl,
      text: text,
      createdAt: DateTime.now(),
    );

    ref.read(commentsProvider(widget.postId).notifier).addComment(comment);
    ref.read(postsProvider.notifier).incrementCommentCount(widget.postId);
    _commentController.clear();

    _scrollToBottom();
  }

  void _submitStickerComment(String stickerUrl) {
    final currentUser = ref.read(currentUserProvider);
    final comment = CommentModel(
      id: 'c_${DateTime.now().millisecondsSinceEpoch}',
      postId: widget.postId,
      userId: currentUser.id,
      userName: currentUser.name,
      userAvatar: currentUser.avatarUrl,
      text: stickerUrl,
      createdAt: DateTime.now(),
    );

    ref.read(commentsProvider(widget.postId).notifier).addComment(comment);
    ref.read(postsProvider.notifier).incrementCommentCount(widget.postId);

    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMediaPicker(int initialIndex) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _MediaPickerSheet(
          initialTabIndex: initialIndex,
          onSelectMedia: (url) {
            _submitStickerComment(url);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final comments = ref.watch(commentsProvider(widget.postId));
    final currentUser = ref.watch(currentUserProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                const Text('Comments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${comments.length}',
                    style: const TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: comments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('💬', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 8),
                        Text('No comments yet. Be the first to vibe! 🚀',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13.5)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      return _CommentTile(
                        comment: comments[index],
                        currentUserId: currentUser.id,
                        onLike: () => ref
                            .read(commentsProvider(widget.postId).notifier)
                            .toggleLike(comments[index].id, currentUser.id),
                        onDelete: comments[index].userId == currentUser.id
                            ? () {
                                ref.read(commentsProvider(widget.postId).notifier).deleteComment(comments[index].id);
                                ref.read(postsProvider.notifier).decrementCommentCount(widget.postId);
                              }
                            : null,
                      );
                    },
                  ),
          ),
          // Input Bar with GIF & Sticker triggers
          Container(
            padding: EdgeInsets.fromLTRB(
              14,
              10,
              14,
              10 + MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundImage: NetworkImage(
                      currentUser.avatarUrl ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(currentUser.name)}&size=100&background=6ECBF5&color=fff&rounded=true',
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Quick GIF picker button
                  GestureDetector(
                    onTap: () => _showMediaPicker(0), // 0 = GIFs
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('🎬', style: TextStyle(fontSize: 16)),
                          SizedBox(width: 3),
                          Text('GIF', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Quick Sticker picker button
                  GestureDetector(
                    onTap: () => _showMediaPicker(1), // 1 = Stickers
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('🏷️', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _commentController,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 13.5),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _submitComment(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _submitComment,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaPickerSheet extends StatefulWidget {
  final int initialTabIndex; // 0 = GIFs, 1 = Stickers
  final ValueChanged<String> onSelectMedia;

  const _MediaPickerSheet({
    required this.initialTabIndex,
    required this.onSelectMedia,
  });

  @override
  State<_MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<_MediaPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';

  static const List<Map<String, String>> _gifCategories = [
    {'label': '🔥 Hype', 'tag': 'hype'},
    {'label': '🤣 Memes', 'tag': 'memes'},
    {'label': '🫶 Love', 'tag': 'love'},
    {'label': '😭 Drama', 'tag': 'drama'},
    {'label': '💀 Shocked', 'tag': 'shocked'},
    {'label': '💃 Vibes', 'tag': 'vibes'},
    {'label': '☕ Tea', 'tag': 'tea'},
    {'label': '🐱 Cats', 'tag': 'cat'},
  ];

  // Huge library of curated GIFs
  static const List<Map<String, dynamic>> _allGifs = [
    {'url': 'https://media.giphy.com/media/GeimqsH0TLDt4tScGw/giphy.gif', 'tags': 'trending vibes cat dance hype'},
    {'url': 'https://media.giphy.com/media/13CoXDiaCcC2EA/giphy.gif', 'tags': 'trending hype flex dance'},
    {'url': 'https://media.giphy.com/media/zcCGB01oHmGBW/giphy.gif', 'tags': 'memes laugh side eye lol'},
    {'url': 'https://media.giphy.com/media/l3q2zVr6cu95nF6O4/giphy.gif', 'tags': 'memes laugh dying rofl'},
    {'url': 'https://media.giphy.com/media/kyLYXonQpkUsCxZIKH/giphy.gif', 'tags': 'memes laugh wheezing lol'},
    {'url': 'https://media.giphy.com/media/26hpK0lWh5usxL7cQ/giphy.gif', 'tags': 'love heart eyes flirt'},
    {'url': 'https://media.giphy.com/media/3oEjHV0z8S7EgXXRGU/giphy.gif', 'tags': 'love hug cute romantic'},
    {'url': 'https://media.giphy.com/media/l41YcMcc6t7wT2Psc/giphy.gif', 'tags': 'drama crying sad sob'},
    {'url': 'https://media.giphy.com/media/3o7TKoWXm3okO1kgHC/giphy.gif', 'tags': 'trending hype party confetti'},
    {'url': 'https://media.giphy.com/media/j3gsTkbBoFiwDf4oav/giphy.gif', 'tags': 'tea sipping drama gossip'},
    {'url': 'https://media.giphy.com/media/26tOZ42cXxDTdFlq8/giphy.gif', 'tags': 'tea popcorn drama watching'},
    {'url': 'https://media.giphy.com/media/hVTouqNmqhMmI/giphy.gif', 'tags': 'tea drama watching eyes'},
    {'url': 'https://media.giphy.com/media/5Govl69wYb6g0/giphy.gif', 'tags': 'love kiss heart flirt'},
    {'url': 'https://media.giphy.com/media/nbvFV5wGKVYu4/giphy.gif', 'tags': 'cat clap applause cute'},
    {'url': 'https://media.giphy.com/media/l0ExhcMhm6t7r56XC/giphy.gif', 'tags': 'cat dog happy dance cute'},
    {'url': 'https://media.giphy.com/media/3o7bu3XilJ5BOiSGic/giphy.gif', 'tags': 'drama sad tear crying'},
    {'url': 'https://media.giphy.com/media/cJMmZA5XY451m/giphy.gif', 'tags': 'shocked side eye awkward meme'},
    {'url': 'https://media.giphy.com/media/26n6WywJyhXMG4skM/giphy.gif', 'tags': 'shocked mind blown meme'},
    {'url': 'https://media.giphy.com/media/l3q2K5jinAlChoCLS/giphy.gif', 'tags': 'memes blinking guy shocked meme'},
    {'url': 'https://media.giphy.com/media/d2W7eZX5z62ziqdi/giphy.gif', 'tags': 'memes cat shocked lol'},
    {'url': 'https://media.giphy.com/media/3o7TKMf5HJHbks8g8M/giphy.gif', 'tags': 'memes laugh shocked lol'},
    {'url': 'https://media.giphy.com/media/l3vR85PnGsBwu1PFK/giphy.gif', 'tags': 'trending hype party fireworks'},
    {'url': 'https://media.giphy.com/media/26n6WwY0ZzkP3C78c/giphy.gif', 'tags': 'hype flex savage entrance'},
    {'url': 'https://media.giphy.com/media/xT0xeJpnrWC4XWblEk/giphy.gif', 'tags': 'hype flex superstar'},
  ];

  // Huge library of animated 3D stickers
  static const List<Map<String, dynamic>> _allStickers = [
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f525/512.gif', 'tags': 'reactions energy fire hype'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f62d/512.gif', 'tags': 'reactions drama crying sad'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f480/512.gif', 'tags': 'reactions memes skull dead'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f929/512.gif', 'tags': 'reactions energy starstruck hype'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f440/512.gif', 'tags': 'reactions tea eyes watching'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1faf6/512.gif', 'tags': 'love heart hands cute'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/2764_fe0f/512.gif', 'tags': 'love heart red beating'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f680/512.gif', 'tags': 'energy rocket hype fast'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f4af/512.gif', 'tags': 'energy 100 real hype'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f389/512.gif', 'tags': 'energy party popper celebrate'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f923/512.gif', 'tags': 'memes rofl laugh funny'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60d/512.gif', 'tags': 'love heart eyes cute'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f496/512.gif', 'tags': 'love sparkling heart cute'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f618/512.gif', 'tags': 'love kiss kissy cute'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f60e/512.gif', 'tags': 'energy cool sunglasses flex'},
    {'url': 'https://fonts.gstatic.com/s/e/notoemoji/latest/1f970/512.gif', 'tags': 'love smiling hearts romance'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterItems(List<Map<String, dynamic>> items) {
    return items.where((item) {
      final tags = (item['tags'] as String).toLowerCase();
      final queryMatch = _searchQuery.isEmpty || tags.contains(_searchQuery.toLowerCase());
      final catMatch = _selectedCategory == 'All' || tags.contains(_selectedCategory.toLowerCase());
      return queryMatch && catMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161029) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 42,
            height: 4.5,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // Tab bar & search header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark ? Colors.white70 : Colors.black54,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: '🎬 GIFs'),
                        Tab(text: '🎨 Stickers'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Search input bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 20, color: isDark ? Colors.white60 : Colors.black45),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: 'Search 100s of GIFs & stickers...',
                        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13.5),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      child: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.white60 : Colors.black45),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Category chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _CategoryChip(
                  label: '✨ All',
                  isSelected: _selectedCategory == 'All',
                  onTap: () => setState(() => _selectedCategory = 'All'),
                ),
                ..._gifCategories.map((c) => _CategoryChip(
                      label: c['label']!,
                      isSelected: _selectedCategory == c['tag'],
                      onTap: () => setState(() => _selectedCategory = c['tag']!),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGrid(_filterItems(_allGifs), isDark, isGif: true),
                _buildGrid(_filterItems(_allStickers), isDark, isGif: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Map<String, dynamic>> items, bool isDark, {required bool isGif}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(isGif ? '🎬' : '🎨', style: const TextStyle(fontSize: 38)),
            const SizedBox(height: 8),
            Text(
              'No results for "$_searchQuery"',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isGif ? 2 : 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: isGif ? 1.3 : 1.0,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final url = item['url'] as String;

        return _MediaItemTile(
          url: url,
          isDark: isDark,
          isGif: isGif,
          onTap: () {
            widget.onSelectMedia(url);
            Navigator.pop(context);
          },
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          gradient: isSelected ? AppTheme.primaryGradient : null,
          color: isSelected
              ? null
              : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MediaItemTile extends StatefulWidget {
  final String url;
  final bool isDark;
  final bool isGif;
  final VoidCallback onTap;

  const _MediaItemTile({
    required this.url,
    required this.isDark,
    required this.isGif,
    required this.onTap,
  });

  @override
  State<_MediaItemTile> createState() => _MediaItemTileState();
}

class _MediaItemTileState extends State<_MediaItemTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 160),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isHovered
                      ? AppTheme.primaryBlue
                      : (widget.isDark ? Colors.white12 : Colors.black12),
                  width: _isHovered ? 1.8 : 0.8,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    widget.url,
                    fit: widget.isGif ? BoxFit.cover : BoxFit.contain,
                    gaplessPlayback: true,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryBlue,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_rounded, size: 24, color: Colors.grey),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.isGif ? 'GIF' : 'STICKER',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  final CommentModel comment;
  final String currentUserId;
  final VoidCallback onLike;
  final VoidCallback? onDelete;

  const _CommentTile({
    required this.comment,
    required this.currentUserId,
    required this.onLike,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLiked = comment.likes.contains(currentUserId);
    final timeStr = DateFormat('MMM d · h:mm a').format(comment.createdAt);
    // Live-watch commenter's profile for up-to-date name/avatar.
    final liveAuthor = ref.watch(otherUserProvider(comment.userId));
    final displayName = liveAuthor.asData?.value?.name ?? comment.userName;
    final displayAvatar = liveAuthor.asData?.value?.avatarUrl
        ?? comment.userAvatar
        ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(comment.userName)}&size=100&background=6ECBF5&color=fff&rounded=true';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: NetworkImage(displayAvatar),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 6),
                    Text(timeStr, style: TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
                    if (onDelete != null) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Comment?'),
                              content: const Text('Are you sure you want to delete this comment?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    onDelete!();
                                  },
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Text(
                          'Delete',
                          style: TextStyle(
                            color: AppTheme.error,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                comment.text.startsWith('http')
                    ? GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FullScreenImageViewer(
                                imageUrl: comment.text,
                                heroTag: 'comment_${comment.id}',
                              ),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(top: 4),
                          constraints: const BoxConstraints(maxWidth: 160, maxHeight: 160),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.black12,
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  comment.text,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, err, stack) => const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('[Sticker/GIF Error]'),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.65),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    comment.text.contains('.gif') ? 'GIF' : 'STICKER',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Text(comment.text, style: const TextStyle(fontSize: 14, height: 1.4)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onLike,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
              child: Column(
                children: [
                  Icon(
                    isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    size: 16,
                    color: isLiked ? AppTheme.error : AppTheme.textTertiary,
                  ),
                  if (comment.likes.isNotEmpty)
                    Text(
                      '${comment.likes.length}',
                      style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

