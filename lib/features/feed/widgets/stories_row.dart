import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/user_model.dart';
import '../screens/feed_screen.dart';

class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storiesStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 110,
      child: storiesAsync.when(
        data: (stories) {
          final uniqueUsers = <String, Map<String, dynamic>>{};
          for (var s in stories) {
            uniqueUsers[s['userId']] = s;
          }
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          final currentUser = ref.watch(currentUserProvider);
          final isFollowingOnly = ref.watch(storiesFilterProvider);
          
          // Separate other users stories from current user's
          final otherUsersStories = uniqueUsers.values
              .where((s) {
                if (s['userId'] == currentUserId) return false;
                if (isFollowingOnly && !currentUser.following.contains(s['userId'])) return false;
                return true;
              })
              .toList();

          return Stack(
            children: [
              ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 16, right: 80), // extra padding for the filter button
                itemCount: otherUsersStories.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final hasStory = currentUserId != null && uniqueUsers.containsKey(currentUserId);
                    return _buildAddStory(context, isDark, currentUser, hasStory);
                  }
                  
                  final story = otherUsersStories[index - 1];
                  return _StoryItem(
                    userId: story['userId'],
                    userName: story['userName'],
                    avatarUrl: story['userAvatar'],
                    isDark: isDark,
                  );
                },
              ),
              Positioned(
                right: 16,
                top: 20,
                child: GestureDetector(
                  onTap: () => ref.read(storiesFilterProvider.notifier).state = !isFollowingOnly,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isFollowingOnly ? Icons.group_rounded : Icons.public_rounded,
                              size: 16,
                              color: isFollowingOnly ? AppTheme.primaryBlue : (isDark ? Colors.white70 : Colors.black54),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isFollowingOnly ? 'Following' : 'All',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isFollowingOnly ? AppTheme.primaryBlue : (isDark ? Colors.white70 : Colors.black54),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) {
          debugPrint('Stories Error: $err');
          return Center(
            child: Icon(
              Icons.error_outline_rounded,
              color: AppTheme.error.withOpacity(0.5),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddStory(BuildContext context, bool isDark, UserModel user, bool hasStory) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: () {
                  if (hasStory) {
                    context.push(
                      '/story/view/${user.id}',
                      extra: {'userName': user.name, 'userAvatar': user.avatarUrl},
                    );
                  } else {
                    context.push('/story/create');
                  }
                },
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasStory ? AppTheme.primaryGradient : null,
                    border: Border.all(
                      color: hasStory ? Colors.transparent : (isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
                      width: 1.5,
                    ),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? AppTheme.darkBg : Colors.white,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: isDark ? AppTheme.darkCard : const Color(0xFFF3F6FF),
                      backgroundImage: (user.avatarUrl != null) 
                          ? CachedNetworkImageProvider(user.avatarUrl!, maxWidth: 150, maxHeight: 150) 
                          : null,
                      child: (user.avatarUrl == null) 
                          ? Text('✨', style: TextStyle(fontSize: 24, color: isDark ? Colors.white30 : Colors.black26))
                          : null,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => context.push('/story/create'),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: isDark ? AppTheme.darkBg : Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryBlue.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your Story',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryItem extends ConsumerStatefulWidget {
  final String userId;
  final String userName;   // fallback snapshot
  final String? avatarUrl; // fallback snapshot
  final bool isDark;

  const _StoryItem({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    required this.isDark,
  });

  @override
  ConsumerState<_StoryItem> createState() => _StoryItemState();
}

class _StoryItemState extends ConsumerState<_StoryItem> {

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Live-watch the story author's profile for up-to-date name/avatar.
    final liveAuthor = ref.watch(otherUserProvider(widget.userId));
    final displayName = liveAuthor.asData?.value?.name ?? widget.userName;
    final displayAvatar = liveAuthor.asData?.value?.avatarUrl
        ?? widget.avatarUrl
        ?? 'https://i.pravatar.cc/100?u=${widget.userId}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => context.push(
              '/story/view/${widget.userId}',
              extra: {'userName': displayName, 'userAvatar': displayAvatar},
            ),
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(2.5),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isDark ? AppTheme.darkBg : Colors.white,
                ),
                padding: const EdgeInsets.all(2),
                child: CircleAvatar(
                  radius: 30,
                  backgroundImage: CachedNetworkImageProvider(displayAvatar, maxWidth: 150, maxHeight: 150),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 70,
            child: Text(
              displayName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.isDark ? Colors.white70 : AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

