import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/image_with_fallback.dart';
import '../../../core/models/community_model.dart';
import '../../../core/models/post_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../feed/widgets/quick_post_box.dart';
import '../../feed/widgets/post_card.dart';

class CommunityDetailScreen extends ConsumerStatefulWidget {
  final String communityId;

  const CommunityDetailScreen({
    super.key,
    required this.communityId,
  });

  @override
  ConsumerState<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen> {
  String _activeTab = 'feed'; // 'feed' or 'chat' (discord style!)
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _openCreatePost(BuildContext context, CommunityModel community) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: QuickPostBox(
            communityId: widget.communityId,
            communityName: community.name,
          ),
        ),
      ),
    );
  }

  Widget _buildCreatePostCard(
    BuildContext context,
    CommunityModel community,
    UserModel currentUser,
    AppPalette palette,
    bool isDark,
  ) {
    final avatar = (currentUser.avatarUrl != null && currentUser.avatarUrl!.isNotEmpty)
        ? currentUser.avatarUrl!
        : 'https://i.pravatar.cc/100?u=${currentUser.id}';

    return GestureDetector(
      onTap: () => _openCreatePost(context, community),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141724) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(avatar),
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Share something in ${community.name}...',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: palette.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 5),
                  Text(
                    'Post',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
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

  void _handleJoinToggle(
    UserModel currentUser,
    CommunityModel community,
    bool isJoined,
    bool isPending,
    AppPalette palette,
  ) {
    if (currentUser.id.isEmpty) return;
    try {
      ref.read(socialProvider.notifier).toggleCommunityJoin(
        currentUserId: currentUser.id,
        communityId: community.id,
        isCurrentlyJoined: isJoined,
        isOnlyAdminApproved: community.isOnlyAdminApproved,
        pendingApprovals: community.pendingApprovals,
      );

      final message = isJoined
          ? 'Left ${community.name}'
          : (isPending
              ? 'Cancelled join request for ${community.name}'
              : (community.isOnlyAdminApproved
                  ? 'Join request sent! 📨'
                  : 'Joined ${community.name}! 🎉'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isJoined ? Colors.grey[800] : palette.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = ref.watch(appPaletteProvider);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: isActive ? palette.primaryGradient : null,
          color: isActive ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: palette.primary.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
                fontSize: 13.5,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatRoom(CommunityModel community, UserModel currentUser) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messagesAsync = ref.watch(communityMessagesStreamProvider(widget.communityId));

    return Container(
      height: 520,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          // Discord channel style header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.tag_rounded, color: AppTheme.primaryBlue, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#general-discussion',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'Vibe with everyone in ${community.name}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.white54 : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

            // Messages list
            Expanded(
              child: messagesAsync.when(
                data: (messages) {
                  if (messages.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('💬', style: TextStyle(fontSize: 40)),
                          const SizedBox(height: 12),
                          Text(
                            'Welcome to #general-discussion!',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Be the first to say hello!',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.white54 : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _chatScrollController,
                    reverse: true, // Newest at bottom
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final senderId = msg['senderId'] ?? '';
                      final isMe = senderId == currentUser.id;
                      final senderName = msg['senderName'] ?? 'User';
                      final senderAvatar = msg['senderAvatar'] ?? 'https://i.pravatar.cc/100?u=$senderId';
                      final text = msg['text'] ?? '';
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            if (!isMe) ...[
                              GestureDetector(
                                onTap: () => context.push('/profile/view/$senderId'),
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundImage: NetworkImage(senderAvatar),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (!isMe)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4, bottom: 3),
                                      child: Text(
                                        senderName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      gradient: isMe ? AppTheme.primaryGradient : null,
                                      color: isMe ? null : (isDark ? Colors.white.withOpacity(0.08) : Colors.white),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                                        bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(isDark ? 0.05 : 0.02),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ],
                                    ),
                                    child: Text(
                                      text,
                                      style: TextStyle(
                                        color: isMe ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 10),
                              CircleAvatar(
                                radius: 18,
                                backgroundImage: NetworkImage(senderAvatar),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
              ),
            ),

            // Message Composer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Message #general-discussion...',
                        filled: true,
                        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendChatMessage(currentUser),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => _sendChatMessage(currentUser),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    void _sendChatMessage(UserModel currentUser) {
      final text = _chatController.text.trim();
      if (text.isEmpty) return;
      
      _chatController.clear();
      sendCommunityMessage(
        communityId: widget.communityId,
        senderId: currentUser.id,
        senderName: currentUser.name,
        senderAvatar: currentUser.avatarUrl,
        text: text,
      );
      
      // Auto scroll to bottom
      Future.delayed(const Duration(milliseconds: 80), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = ref.watch(appPaletteProvider);
    final currentUser = ref.watch(currentUserProvider);
    final communitiesAsync = ref.watch(communitiesProvider);
    final communities = communitiesAsync.valueOrNull;

    if (communities == null) {
      if (communitiesAsync.hasError) {
        return Scaffold(body: Center(child: Text('Error: ${communitiesAsync.error}')));
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final community = communities.firstWhere(
      (c) => c.id == widget.communityId,
      orElse: () => CommunityModel.defaults.first,
    );

    final isJoined = currentUser.joinedCommunities.contains(widget.communityId);
    final isPending = community.pendingApprovals.contains(currentUser.id);
    final postsAsync = ref.watch(communityPostsStreamProvider(widget.communityId));

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      floatingActionButton: isJoined && _activeTab == 'feed'
          ? FloatingActionButton.extended(
              onPressed: () => _openCreatePost(context, community),
              backgroundColor: palette.primary,
              icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
              label: const Text(
                'Post',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          // ─── Flexible Banner Header ─────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: isDark ? AppTheme.darkSurface : Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => context.pop(),
            ),
            actions: [
              if (currentUser.id == community.createdBy)
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 24),
                  tooltip: 'Community Settings',
                  onPressed: () => _showEditCommunitySheet(context, community),
                ),
            ],
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final top = constraints.biggest.height;
                final isCollapsed = top <= (kToolbarHeight + MediaQuery.of(context).padding.top + 20);
                return FlexibleSpaceBar(
                  centerTitle: true,
                  title: isCollapsed
                      ? Text(
                          community.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  background: Stack(
                fit: StackFit.expand,
                children: [
                  ImageWithFallback(imageUrl: community.imageUrl, fit: BoxFit.cover),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.4),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.8),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            community.tag,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          community.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.people_alt, color: Colors.white70, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${community.memberAvatars.isEmpty ? 1 : community.memberAvatars.length} members',
                              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            if (community.isOnlyAdminApproved) ...[
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.orange.withOpacity(0.4), width: 1),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock_outline, color: Colors.orange, size: 11),
                                    SizedBox(width: 3),
                                    Text(
                                      'Private',
                                      style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),

          // ─── Community Detail and Subreddit Feed Content ────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Join Button or Member Status
                  if (!isJoined)
                    ElevatedButton.icon(
                      onPressed: currentUser.id.isEmpty
                          ? null
                          : () {
                              _handleJoinToggle(currentUser, community, isJoined, isPending, palette);
                            },
                      icon: Icon(
                        isPending ? Icons.hourglass_empty_rounded : Icons.group_add_rounded,
                        size: 20,
                      ),
                      label: Text(
                        currentUser.id.isEmpty
                            ? 'Loading...'
                            : (isPending ? 'Request Pending' : 'Join Community'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isPending ? Colors.orange.withOpacity(0.15) : palette.primary,
                        foregroundColor: isPending ? Colors.orange : Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: isPending ? const BorderSide(color: Colors.orange, width: 1.5) : BorderSide.none,
                        ),
                      ),
                    )
                  else
                    // Joined Member Status Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141724) : Colors.black.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.check_rounded, color: AppTheme.primaryGreen, size: 14),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Joined as Member',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              _handleJoinToggle(currentUser, community, isJoined, isPending, palette);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent.withOpacity(0.85),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Leave',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 28),

                  // About Section
                  const Text(
                    'About',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    community.description.isEmpty
                        ? 'Welcome to ${community.name}! A place to connect, share, and vibe with people who share your interests. Join the conversation and start posting.'
                        : community.description,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : AppTheme.textSecondary,
                      fontSize: 14.5,
                      height: 1.5,
                    ),
                  ),

                  // Members Section
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Members',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      if (!community.isOnlyAdminApproved || isJoined)
                        TextButton(
                          onPressed: () => _showMembersSheet(context, community),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryBlue,
                            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          child: const Text('View All'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (community.isOnlyAdminApproved && !isJoined)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, color: Colors.orange[400], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Members list is private. Join this community to see other members.',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 52,
                      child: FutureBuilder<QuerySnapshot>(
                        future: firestoreProvider
                            .collection('users')
                            .where(FieldPath.documentId, whereIn: community.memberAvatars.isEmpty ? [''] : community.memberAvatars.take(10).toList())
                            .get(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final usersDocs = snapshot.data!.docs;
                          return ListView.builder(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: usersDocs.length,
                            itemBuilder: (context, index) {
                              final userData = usersDocs[index].data() as Map<String, dynamic>;
                              final memberId = usersDocs[index].id;
                              final avatarUrl = userData['avatarUrl'];
                              final isAdmin = memberId == community.createdBy;

                              return GestureDetector(
                                onTap: () => context.push('/profile/view/$memberId'),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 12),
                                  child: Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundImage: NetworkImage(
                                          avatarUrl ?? 'https://i.pravatar.cc/150?u=$memberId',
                                        ),
                                      ),
                                      if (isAdmin)
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                              color: Colors.amber,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.star,
                                              size: 8,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),

                  // Admin Moderation Panel (Pending Requests)
                  if (currentUser.id == community.createdBy && community.pendingApprovals.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(0.2),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.admin_panel_settings_rounded, color: AppTheme.primaryBlue, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                'Pending Member Requests (${community.pendingApprovals.length})',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: community.pendingApprovals.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final pendingUserId = community.pendingApprovals[index];
                              return FutureBuilder<DocumentSnapshot>(
                                future: firestoreProvider.collection('users').doc(pendingUserId).get(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) return const SizedBox.shrink();
                                  final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                                  final userName = userData['name'] ?? 'User';
                                  final userAvatar = userData['avatarUrl'] ?? 'https://i.pravatar.cc/100?u=$pendingUserId';
                                  
                                  return Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundImage: NetworkImage(userAvatar),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          userName,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                                        ),
                                      ),
                                      // Approve Button
                                      IconButton(
                                        icon: Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 26),
                                        onPressed: () async {
                                          final batch = firestoreProvider.batch();
                                          batch.update(firestoreProvider.collection('communities').doc(widget.communityId), {
                                            'pendingApprovals': FieldValue.arrayRemove([pendingUserId]),
                                            'memberAvatars': FieldValue.arrayUnion([pendingUserId]),
                                            'memberCount': FieldValue.increment(1),
                                          });
                                          batch.set(firestoreProvider.collection('users').doc(pendingUserId), {
                                            'joinedCommunities': FieldValue.arrayUnion([widget.communityId])
                                          }, SetOptions(merge: true));
                                          await batch.commit();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Approved $userName!')),
                                          );
                                        },
                                      ),
                                      // Decline Button
                                      IconButton(
                                        icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 26),
                                        onPressed: () async {
                                          await firestoreProvider.collection('communities').doc(widget.communityId).update({
                                            'pendingApprovals': FieldValue.arrayRemove([pendingUserId]),
                                          });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Declined request from $userName.')),
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Tab Selector (Posts Feed vs Discord Chat Room)
                  if (isJoined) ...[
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF141724) : Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTabButton(
                              label: 'Feed',
                              icon: Icons.dynamic_feed_rounded,
                              isActive: _activeTab == 'feed',
                              onTap: () => setState(() => _activeTab = 'feed'),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _buildTabButton(
                              label: 'Chat Room',
                              icon: Icons.chat_bubble_outline_rounded,
                              isActive: _activeTab == 'chat',
                              onTap: () => setState(() => _activeTab = 'chat'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Feed Tab Contents
                  if (_activeTab == 'feed' || !isJoined) ...[
                    // Private Lock or Post Feed
                    if (!isJoined)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 54,
                                color: AppTheme.textSecondary.withOpacity(0.25),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'This community\'s posts are private.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isPending
                                    ? 'Your join request is pending approval. You will see posts once approved!'
                                    : 'Join ${community.name} to view the feed and share your vibe!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // Sleek Create Post Prompt Card (Opens QuickPostBox sheet)
                      _buildCreatePostCard(
                        context,
                        community,
                        currentUser,
                        palette,
                        isDark,
                      ),
                      const SizedBox(height: 14),

                      // Post Feed Stream
                      postsAsync.when(
                        data: (posts) {
                          if (posts.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 40),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: palette.primary.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.forum_outlined,
                                        size: 40,
                                        color: palette.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No posts yet in ${community.name}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Be the first to share a post and start the vibe!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    ElevatedButton.icon(
                                      onPressed: () => _openCreatePost(context, community),
                                      icon: const Icon(Icons.add_rounded, size: 18),
                                      label: const Text('Create First Post', style: TextStyle(fontWeight: FontWeight.w800)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: palette.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(bottom: 90),
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: posts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final post = posts[index];
                              return PostCard(
                                post: post,
                                onLike: () => ref
                                    .read(postsProvider.notifier)
                                    .toggleLike(post.id, currentUser.id),
                              );
                            },
                          );
                        },
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (err, stack) => Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'Error loading feed: $err',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    // Chat Room Tab Contents (Discord Chat Room)
                    _buildChatRoom(community, currentUser),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMembersSheet(BuildContext context, CommunityModel community) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  // Handle indicator
                  Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Community Members (${community.memberAvatars.length})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<QuerySnapshot>(
                      future: firestoreProvider
                          .collection('users')
                          .where(FieldPath.documentId, whereIn: community.memberAvatars.isEmpty ? [''] : community.memberAvatars.take(30).toList())
                          .get(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text('No members found'));
                        }
                        final usersDocs = snapshot.data!.docs;
                        return ListView.builder(
                          controller: scrollController,
                          itemCount: usersDocs.length,
                          itemBuilder: (context, index) {
                            final userData = usersDocs[index].data() as Map<String, dynamic>;
                            final memberId = usersDocs[index].id;
                            final name = userData['name'] ?? 'Viber';
                            final avatarUrl = userData['avatarUrl'];
                            final bio = userData['bio'] ?? userData['headline'] ?? 'Vibing in Situationship ✨';
                            final isAdmin = memberId == community.createdBy;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundImage: NetworkImage(
                                        avatarUrl ?? 'https://i.pravatar.cc/150?u=$memberId',
                                      ),
                                    ),
                                    if (isAdmin)
                                      Positioned(
                                        right: -2,
                                        bottom: -2,
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: const BoxDecoration(
                                            color: Colors.amber,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.star,
                                            size: 10,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                    ),
                                    if (isAdmin) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '👑 ADMIN',
                                              style: TextStyle(
                                                color: Colors.amber,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    bio,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                    ),
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  context.push('/profile/view/$memberId');
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showEditCommunitySheet(BuildContext context, CommunityModel community) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nameController = TextEditingController(text: community.name);
    final tagController = TextEditingController(text: community.tag);
    final descriptionController = TextEditingController(text: community.description);
    final imageUrlController = TextEditingController(text: community.imageUrl);
    XFile? pickedImageFile;
    bool isOnlyAdminApproved = community.isOnlyAdminApproved;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle indicator
                    Center(
                      child: Container(
                        width: 38,
                        height: 5,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Community Settings ⚙️',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Cover Photo Header Box
                    const Text('Community Cover Photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: isSaving ? null : () async {
                        try {
                          final picked = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 85,
                            maxWidth: 1080,
                          );
                          if (picked != null) {
                            setSheetState(() {
                              pickedImageFile = picked;
                            });
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error picking image: $e')),
                          );
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        height: 140,
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkCard : Colors.grey[200],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.primaryBlue.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: pickedImageFile != null
                                  ? (kIsWeb
                                      ? Image.network(pickedImageFile!.path, fit: BoxFit.cover, width: double.infinity)
                                      : Image.file(File(pickedImageFile!.path), fit: BoxFit.cover, width: double.infinity))
                                  : ImageWithFallback(imageUrl: imageUrlController.text.trim(), fit: BoxFit.cover),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
                                    SizedBox(height: 4),
                                    Text(
                                      'Change Photo',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Name Field
                    const Text('Community Name', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        hintText: 'e.g. Gamer Vibers',
                        filled: true,
                        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tag Field
                    const Text('Tag / Handle', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tagController,
                      enabled: !isSaving,
                      decoration: InputDecoration(
                        hintText: 'e.g. gaming',
                        filled: true,
                        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description Field
                    const Text('Description', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      enabled: !isSaving,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Describe your community...',
                        filled: true,
                        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Privacy Options Container
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? AppTheme.darkBorder : Colors.black.withOpacity(0.05)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Private (Admin Approval Required)',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'New members will require your approval before joining and viewing posts.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch.adaptive(
                            value: isOnlyAdminApproved,
                            activeColor: AppTheme.primaryBlue,
                            onChanged: isSaving ? null : (val) {
                              setSheetState(() {
                                isOnlyAdminApproved = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    isSaving
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : ElevatedButton(
                            onPressed: () async {
                              setSheetState(() {
                                isSaving = true;
                              });

                              try {
                                String finalImageUrl = imageUrlController.text.trim();
                                if (pickedImageFile != null) {
                                  final storageRef = FirebaseStorage.instance.ref('communities/${community.id}.jpg');
                                  if (kIsWeb) {
                                    final bytes = await pickedImageFile!.readAsBytes();
                                    await storageRef.putData(bytes);
                                  } else {
                                    await storageRef.putFile(File(pickedImageFile!.path));
                                  }
                                  finalImageUrl = await storageRef.getDownloadURL();
                                }

                                await firestoreProvider.collection('communities').doc(community.id).update({
                                  'name': nameController.text.trim(),
                                  'tag': tagController.text.trim().toUpperCase(),
                                  'imageUrl': finalImageUrl,
                                  'description': descriptionController.text.trim(),
                                  'isOnlyAdminApproved': isOnlyAdminApproved,
                                });

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Community updated successfully! 🚀'),
                                      backgroundColor: AppTheme.success,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error updating: $e'),
                                      backgroundColor: Colors.red[700],
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                              } finally {
                                setSheetState(() {
                                  isSaving = false;
                                });
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Save Changes',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                          ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
