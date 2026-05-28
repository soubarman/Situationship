import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import 'package:timeago/timeago.dart' as timeago;

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter chats
    final acceptedChats = chats.where((c) => c.status == 'accepted').toList();
    final requestedChats = chats.where((c) => c.status == 'requested').toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          // Chats provider already listens to Firestore, so just trigger a refresh
          await Future.delayed(const Duration(milliseconds: 500));
        },
        color: AppTheme.primaryBlue,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            _buildAppBar(context, isDark),
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                height: 48,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: AppTheme.primaryGradient,
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppTheme.textSecondary,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  tabs: const [
                    Tab(text: 'Messages'),
                    Tab(text: 'Requests'),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildChatList(acceptedChats, isDark, ref),
              _buildChatList(requestedChats, isDark, ref, isRequest: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatList(List<ChatModel> chats, bool isDark, WidgetRef ref, {bool isRequest = false}) {
    if (chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isRequest ? '📪' : '💬',
              style: const TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 16),
            Text(
              isRequest ? 'No pending requests' : 'No messages yet',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isRequest ? 'People you requested will show here' : 'Start a conversation from Discover!',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    final activeChats = chats.where((c) => !c.isExpired).toList();
    final expiredChats = chats.where((c) => c.isExpired).toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (!isRequest) _buildOnlineRow(context, activeChats, ref),
        if (activeChats.isNotEmpty) ...[
          _sectionHeader(isRequest ? 'Pending' : 'Active', context),
          ...activeChats.map((chat) => _ChatTile(chat: chat, isRequest: isRequest)),
        ],
        if (expiredChats.isNotEmpty) ...[
          _sectionHeader('Expired', context),
          ...expiredChats.map((chat) => _ChatTile(chat: chat, isExpired: true, isRequest: isRequest)),
        ],
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: const Text(
        'Chats',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
      ),
      actions: [
        IconButton(
          onPressed: () {},
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.search_rounded, size: 20),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildOnlineRow(BuildContext context, List<ChatModel> activeChats, WidgetRef ref) {
    if (activeChats.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: activeChats.length,
        itemBuilder: (context, index) {
          final chat = activeChats[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GestureDetector(
              onTap: () {
                ref.read(chatsProvider.notifier).markRead(chat.id);
                context.go('/chats/${chat.id}', extra: {
                  'name': chat.otherUserName,
                  'avatarUrl': chat.otherUserAvatar,
                  'isOnline': chat.otherUserIsOnline,
                });
              },
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: NetworkImage(
                          chat.otherUserAvatar ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(chat.otherUserName)}',
                        ),
                      ),
                      if (chat.otherUserIsOnline)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 60,
                    child: Text(
                      chat.otherUserName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppTheme.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  final ChatModel chat;
  final bool isExpired;
  final bool isRequest;

  const _ChatTile({
    required this.chat,
    this.isExpired = false,
    this.isRequest = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeStr = timeago.format(chat.lastMessageTime, allowFromNow: true);
    final currentUser = ref.watch(currentUserProvider);
    final isSentByMe = chat.requestSenderId == currentUser.id;

    return GestureDetector(
      onTap: (isExpired || isRequest)
          ? null
          : () => context.go(
                '/chats/${chat.id}',
                extra: {
                  'name': chat.otherUserName,
                  'avatarUrl': chat.otherUserAvatar,
                  'isOnline': chat.otherUserIsOnline,
                },
              ),
      child: Opacity(
        opacity: isExpired ? 0.55 : 1.0,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage: NetworkImage(
                      chat.otherUserAvatar ?? 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(chat.otherUserName)}',
                    ),
                  ),
                  if (chat.otherUserIsOnline && !isExpired)
                    Positioned(
                      right: 1,
                      bottom: 1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          chat.otherUserName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const Spacer(),
                        if (!isRequest)
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: chat.unreadCount > 0 ? AppTheme.primaryBlue : AppTheme.textTertiary,
                              fontWeight: chat.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isRequest 
                                ? (isSentByMe ? "Waiting for response..." : "Wants to start a conversation with you") 
                                : chat.lastMessage,
                            style: TextStyle(
                              fontSize: 13,
                              color: chat.unreadCount > 0 ? Theme.of(context).textTheme.bodyLarge?.color : AppTheme.textTertiary,
                              fontWeight: chat.unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isRequest && !isSentByMe) ...[
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              ref.read(chatsProvider.notifier).updateChatStatus(chat.id, 'accepted');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: const Text('Accept', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ] else if (chat.unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                chat.unreadCount.toString(),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                              ),
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
        ),
      ),
    );
  }
}
