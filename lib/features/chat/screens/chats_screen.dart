import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../shared/widgets/background_orbs.dart';
import '../../verification/presentation/widgets/s_badge_widget.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _tabAnimController;
  late AnimationController _headerAnimController;
  late Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerFade = CurvedAnimation(
      parent: _headerAnimController,
      curve: Curves.easeOut,
    );
    _headerAnimController.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tabAnimController.dispose();
    _headerAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final acceptedChats = chats.where((c) => c.status == 'accepted' && !c.isConfession).toList();
    final requestedChats = chats.where((c) => c.status == 'requested' && !c.isConfession).toList();
    final confessionChats = chats.where((c) => c.isConfession).toList();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF0F4FF),
      body: Stack(
        children: [
          const BackgroundOrbs(),
          RefreshIndicator(
            onRefresh: () async {
              await Future.delayed(const Duration(milliseconds: 500));
            },
            color: AppTheme.primaryBlue,
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                _buildSliverAppBar(context, isDark),
                SliverToBoxAdapter(child: _buildTabBar(isDark)),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildChatList(acceptedChats, isDark, ref),
                  _buildChatList(requestedChats, isDark, ref, isRequest: true),
                  _buildConfessionsList(confessionChats, isDark, ref),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, bool isDark) {
    final currentUser = ref.watch(currentUserProvider);
    return SliverAppBar(
      floating: true,
      snap: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      expandedHeight: 72,
      flexibleSpace: FlexibleSpaceBar(
        background: FadeTransition(
          opacity: _headerFade,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 12,
              16,
              8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [AppTheme.primaryBlue, AppTheme.accentPurple, AppTheme.accentPink],
                    ).createShader(bounds),
                    child: const Text(
                      'Chats ✨',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Search button
                _GlassIconButton(
                  isDark: isDark,
                  icon: Icons.search_rounded,
                  onTap: () {},
                ),
                const SizedBox(width: 8),
                // Avatar
                GestureDetector(
                  onTap: () => context.push('/profile'),
                  child: _StoryRingAvatar(
                    avatarUrl: currentUser.avatarUrl,
                    isOnline: true,
                    radius: 20,
                    showRing: true,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.9),
                width: 1,
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                gradient: AppTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.white54 : AppTheme.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              tabs: const [
                Tab(text: 'Messages'),
                Tab(text: 'Requests'),
                Tab(text: 'Confessions'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatList(List<ChatModel> chats, bool isDark, WidgetRef ref, {bool isRequest = false}) {
    if (chats.isEmpty) {
      return _AnimatedEmptyState(
        emoji: isRequest ? '📪' : '💬',
        title: isRequest ? 'No pending requests' : 'No messages yet',
        subtitle: isRequest
            ? 'People you connect with will show here'
            : 'Start a conversation from Discover!',
        isDark: isDark,
      );
    }

    final activeChats = chats.where((c) => !c.isExpired).toList();
    final expiredChats = chats.where((c) => c.isExpired).toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (!isRequest) _buildOnlineRow(context, activeChats, ref, isDark),
        if (activeChats.isNotEmpty) ...[
          _SectionHeader(label: isRequest ? 'Pending' : 'Active', isDark: isDark),
          ...activeChats.asMap().entries.map((entry) => _AnimatedChatTile(
                chat: entry.value,
                isRequest: isRequest,
                index: entry.key,
              )),
        ],
        if (expiredChats.isNotEmpty) ...[
          _SectionHeader(label: 'Expired', isDark: isDark),
          ...expiredChats.asMap().entries.map((entry) => _AnimatedChatTile(
                chat: entry.value,
                isExpired: true,
                isRequest: isRequest,
                index: entry.key,
              )),
        ],
        SizedBox(height: MediaQuery.of(context).padding.bottom + 120),
      ],
    );
  }

  Widget _buildOnlineRow(BuildContext context, List<ChatModel> activeChats, WidgetRef ref, bool isDark) {
    if (activeChats.isEmpty) return const SizedBox.shrink();
    final onlineChats = activeChats.where((c) => c.otherUserIsOnline).toList();
    if (onlineChats.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppTheme.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.success.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'ONLINE NOW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white54 : AppTheme.textTertiary,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: onlineChats.length,
            itemBuilder: (context, index) {
              final chat = onlineChats[index];
              final otherUser = ref.watch(otherUserProvider(chat.otherUserId)).valueOrNull;
              final isVerified = otherUser?.isVerified ?? false;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: GestureDetector(
                  onTap: () {
                    ref.read(chatsProvider.notifier).markRead(chat.id);
                    context.push('/chats/${chat.id}', extra: {
                      'name': chat.otherUserName,
                      'avatarUrl': chat.otherUserAvatar,
                      'isOnline': chat.otherUserIsOnline,
                    });
                  },
                  child: Column(
                    children: [
                      _StoryRingAvatar(
                        avatarUrl: chat.otherUserAvatar,
                        name: chat.otherUserName,
                        isOnline: chat.otherUserIsOnline,
                        radius: 28,
                        showRing: true,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 60,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                chat.otherUserName,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isVerified) ...[
                              const SizedBox(width: 2),
                              const SBadgeWidget(size: 10, showTooltip: false),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildConfessionsList(List<ChatModel> chats, bool isDark, WidgetRef ref) {
    if (chats.isEmpty) {
      return _AnimatedEmptyState(
        emoji: '🎭',
        title: 'Secret Inbox',
        subtitle: 'Chat anonymously. You can request them to reveal their identity!',
        isDark: isDark,
      );
    }

    final activeChats = chats.where((c) => !c.isExpired).toList();
    final expiredChats = chats.where((c) => c.isExpired).toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (activeChats.isNotEmpty) ...[
          _SectionHeader(label: 'Secret Messages', isDark: isDark),
          ...activeChats.asMap().entries.map((entry) => _AnimatedChatTile(
                chat: entry.value,
                isConfessionView: true,
                index: entry.key,
              )),
        ],
        if (expiredChats.isNotEmpty) ...[
          _SectionHeader(label: 'Expired Secret Messages', isDark: isDark),
          ...expiredChats.asMap().entries.map((entry) => _AnimatedChatTile(
                chat: entry.value,
                isExpired: true,
                isConfessionView: true,
                index: entry.key,
              )),
        ],
        SizedBox(height: MediaQuery.of(context).padding.bottom + 120),
      ],
    );
  }
}

// ─── Story Ring Avatar ──────────────────────────────────────────────────────

class _StoryRingAvatar extends StatefulWidget {
  final String? avatarUrl;
  final String? name;
  final bool isOnline;
  final double radius;
  final bool showRing;
  final bool isDark;

  const _StoryRingAvatar({
    this.avatarUrl,
    this.name,
    required this.isOnline,
    required this.radius,
    required this.showRing,
    required this.isDark,
  });

  @override
  State<_StoryRingAvatar> createState() => _StoryRingAvatarState();
}

class _StoryRingAvatarState extends State<_StoryRingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulse = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isOnline) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.radius * 2;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isOnline && widget.showRing ? _pulse.value : 1.0,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow ring for online
              if (widget.isOnline && widget.showRing)
                Container(
                  width: size + 8,
                  height: size + 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(
                      colors: [
                        AppTheme.primaryBlue,
                        AppTheme.accentPurple,
                        AppTheme.accentPink,
                        AppTheme.primaryBlue,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              // White spacer
              if (widget.isOnline && widget.showRing)
                Container(
                  width: size + 4,
                  height: size + 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isDark ? AppTheme.darkBg : Colors.white,
                  ),
                ),
              // Avatar
              CircleAvatar(
                radius: widget.radius,
                backgroundImage: widget.avatarUrl != null
                    ? NetworkImage(widget.avatarUrl!)
                    : null,
                backgroundColor: widget.isDark
                    ? AppTheme.darkCard
                    : const Color(0xFFE0E8FF),
                child: widget.avatarUrl == null
                    ? Text(
                        (widget.name?.isNotEmpty == true)
                            ? widget.name![0].toUpperCase()
                            : '😎',
                        style: TextStyle(
                          fontSize: widget.radius * 0.8,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              // Online dot
              if (widget.isOnline)
                Positioned(
                  right: widget.showRing ? 6 : 2,
                  bottom: widget.showRing ? 6 : 2,
                  child: Container(
                    width: widget.radius * 0.45,
                    height: widget.radius * 0.45,
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isDark ? AppTheme.darkBg : Colors.white,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.success.withValues(alpha: 0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Animated Chat Tile ─────────────────────────────────────────────────────

class _AnimatedChatTile extends StatefulWidget {
  final ChatModel chat;
  final bool isExpired;
  final bool isRequest;
  final bool isConfessionView;
  final int index;

  const _AnimatedChatTile({
    required this.chat,
    this.isExpired = false,
    this.isRequest = false,
    this.isConfessionView = false,
    required this.index,
  });

  @override
  State<_AnimatedChatTile> createState() => _AnimatedChatTileState();
}

class _AnimatedChatTileState extends State<_AnimatedChatTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 450 + (widget.index * 60).clamp(0, 360)),
    );
    _slide = Tween<double>(begin: 40.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slide.value),
          child: Opacity(
            opacity: _fade.value,
            child: child,
          ),
        );
      },
      child: _ChatTile(
        chat: widget.chat,
        isExpired: widget.isExpired,
        isRequest: widget.isRequest,
        isConfessionView: widget.isConfessionView,
      ),
    );
  }
}

// ─── Chat Tile ──────────────────────────────────────────────────────────────

class _ChatTile extends ConsumerStatefulWidget {
  final ChatModel chat;
  final bool isExpired;
  final bool isRequest;
  final bool isConfessionView;

  const _ChatTile({
    required this.chat,
    this.isExpired = false,
    this.isRequest = false,
    this.isConfessionView = false,
  });

  @override
  ConsumerState<_ChatTile> createState() => _ChatTileState();
}

class _ChatTileState extends ConsumerState<_ChatTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherUser = ref.watch(otherUserProvider(widget.chat.otherUserId)).valueOrNull;
    final isVerified = !widget.isConfessionView && (otherUser?.isVerified ?? false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr = timeago.format(widget.chat.lastMessageTime, allowFromNow: true);
    final currentUser = ref.watch(currentUserProvider);
    final isSentByMe = widget.chat.requestSenderId == currentUser.id;
    final hasUnread = widget.chat.unreadCount > 0;

    final isAnonymous = widget.chat.otherUserAvatar == 'anonymous_mask';

    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        if (!widget.isExpired && !widget.isRequest) {
          ref.read(chatsProvider.notifier).markRead(widget.chat.id);
          context.push(
            '/chats/${widget.chat.id}',
            extra: {
              'name': widget.chat.otherUserName,
              'avatarUrl': widget.chat.otherUserAvatar,
              'isOnline': widget.chat.otherUserIsOnline,
            },
          );
        }
      },
      onTapCancel: () => _pressController.reverse(),
      child: AnimatedBuilder(
        animation: _pressScale,
        builder: (context, child) => Transform.scale(
          scale: _pressScale.value,
          child: child,
        ),
        child: Opacity(
          opacity: widget.isExpired ? 0.5 : 1.0,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: hasUnread ? 0.07 : 0.04)
                        : Colors.white.withValues(alpha: hasUnread ? 0.92 : 0.78),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: hasUnread
                          ? AppTheme.primaryBlue.withValues(alpha: 0.35)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.85)),
                      width: hasUnread ? 1.2 : 0.8,
                    ),
                    boxShadow: [
                      if (hasUnread)
                        BoxShadow(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        )
                      else
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // ── Avatar ──────────────────────────────────────────
                      if (isAnonymous)
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [const Color(0xFF6B21A8), const Color(0xFF4C1D95)]
                                  : [const Color(0xFFC084FC), const Color(0xFF818CF8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text('🎭', style: TextStyle(fontSize: 24)),
                          ),
                        )
                      else
                        _StoryRingAvatar(
                          avatarUrl: widget.chat.otherUserAvatar,
                          name: widget.chat.otherUserName,
                          isOnline: widget.chat.otherUserIsOnline && !widget.isExpired,
                          radius: 26,
                          showRing: widget.chat.otherUserIsOnline && !widget.isExpired,
                          isDark: isDark,
                        ),
                      const SizedBox(width: 12),
                      // ── Content ─────────────────────────────────────────
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          widget.chat.otherUserName,
                                          style: TextStyle(
                                            fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isVerified) ...[
                                        const SizedBox(width: 4),
                                        const SBadgeWidget(size: 14, showTooltip: false),
                                      ],
                                    ],
                                  ),
                                ),
                                if (!widget.isRequest)
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: hasUnread
                                          ? AppTheme.primaryBlue
                                          : AppTheme.textTertiary,
                                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.isRequest
                                            ? (isSentByMe
                                                ? 'Waiting for response...'
                                                : 'Wants to start a conversation ✨')
                                            : widget.chat.lastMessage,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: hasUnread
                                              ? (isDark ? Colors.white : AppTheme.textPrimary)
                                              : AppTheme.textTertiary,
                                          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (widget.isConfessionView) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                AppTheme.primaryBlue.withValues(alpha: 0.15),
                                                AppTheme.accentPurple.withValues(alpha: 0.1),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.lock_outline_rounded,
                                                size: 11,
                                                color: AppTheme.primaryBlue,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                'Tap to chat securely',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppTheme.primaryBlue,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Accept button for requests
                                if (widget.isRequest && !isSentByMe) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: AppTheme.primaryGradient,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          ref.read(chatsProvider.notifier).updateChatStatus(widget.chat.id, 'accepted');
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                          child: Text(
                                            'Accept',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ]
                                // Unread badge
                                else if (hasUnread && !widget.isConfessionView) ...[
                                  const SizedBox(width: 8),
                                  _UnreadBadge(count: widget.chat.unreadCount),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Unread Badge ───────────────────────────────────────────────────────────

class _UnreadBadge extends StatefulWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  State<_UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<_UnreadBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            widget.count > 99 ? '99+' : widget.count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section Header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool isDark;
  const _SectionHeader({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white38 : AppTheme.textTertiary,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Glass Icon Button ───────────────────────────────────────────────────────

class _GlassIconButton extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.isDark,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.9),
                width: 0.8,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isDark ? Colors.white70 : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Animated Empty State ────────────────────────────────────────────────────

class _AnimatedEmptyState extends StatefulWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool isDark;

  const _AnimatedEmptyState({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  @override
  State<_AnimatedEmptyState> createState() => _AnimatedEmptyStateState();
}

class _AnimatedEmptyStateState extends State<_AnimatedEmptyState>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _fadeController;
  late Animation<double> _float;
  late Animation<double> _fade;
  late Animation<double> _sparkle;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _float = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _sparkle = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _floatController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _float.value),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow aura
                      Opacity(
                        opacity: _sparkle.value * 0.5,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppTheme.primaryBlue.withValues(alpha: 0.4),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Emoji
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : AppTheme.primaryBlue.withValues(alpha: 0.1),
                          border: Border.all(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : AppTheme.primaryBlue.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            widget.emoji,
                            style: const TextStyle(fontSize: 36),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppTheme.primaryBlue, AppTheme.accentPurple],
              ).createShader(bounds),
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: widget.isDark ? Colors.white38 : AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Floating sparkles
            AnimatedBuilder(
              animation: _floatController,
              builder: (context, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final delay = i / 3;
                    final val = sin((_floatController.value + delay) * pi);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Opacity(
                        opacity: (val * 0.5 + 0.5).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, val * -6),
                          child: Text(
                            ['✨', '💫', '⭐'][i],
                            style: TextStyle(fontSize: 14 + (val * 4)),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
