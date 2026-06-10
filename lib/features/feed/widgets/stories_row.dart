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
                padding: const EdgeInsets.only(left: 16, right: 80),
                itemCount: otherUsersStories.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final myStory = currentUserId != null
                        ? uniqueUsers[currentUserId]
                        : null;
                    return _buildAddStory(context, isDark, currentUser, myStory);
                  }
                  
                  final story = otherUsersStories[index - 1];
                  return _StoryItem(
                    userId: story['userId'],
                    userName: story['userName'],
                    avatarUrl: story['userAvatar'],
                    storyImageUrl: story['imageUrl'],
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

  Widget _buildAddStory(BuildContext context, bool isDark, UserModel user, Map<String, dynamic>? myStory) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              if (myStory != null) {
                context.push(
                  '/take/view/${user.id}',
                  extra: {'userName': user.name, 'userAvatar': user.avatarUrl},
                );
              } else {
                context.push('/take/create');
              }
            },
            child: myStory == null 
              ? _BleedingWaveWidget(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22), // Modern squircle
                      color: isDark ? Colors.white.withOpacity(0.08) : AppTheme.accentPurple.withOpacity(0.1),
                      border: Border.all(
                        color: isDark ? Colors.white.withOpacity(0.15) : AppTheme.accentPurple.withOpacity(0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accentPurple.withOpacity(0.15),
                          blurRadius: 12,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // If we don't have a story, show a cool animated plus icon
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.accentPurple.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded, // Sparkle icon
                            color: AppTheme.accentPurple,
                            size: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22), // Modern squircle
                    gradient: AppTheme.primaryGradient,
                    border: Border.all(
                      color: Colors.transparent,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // If we have a story, show the image inside the squircle
                  if (myStory != null && myStory['imageUrl'] != null)
                    Container(
                      margin: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(19),
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(myStory['imageUrl']),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    
                  // If we don't have a story, show a cool animated plus icon
                  if (myStory == null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentPurple.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded, // Sparkle icon
                        color: AppTheme.accentPurple,
                        size: 24,
                      ),
                    ),
                    
                  // If we DO have a story, show a tiny plus badge on the corner
                  if (myStory != null)
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: GestureDetector(
                        onTap: () => context.push('/take/create'),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppTheme.accentPurple, AppTheme.accentPink],
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? AppTheme.darkBg : Colors.white,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                spreadRadius: 1,
                              )
                            ]
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            myStory != null ? 'Your Take' : 'New Take',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [AppTheme.accentPurple, AppTheme.accentPink],
                ).createShader(const Rect.fromLTWH(0.0, 0.0, 100.0, 20.0)),
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
  final String? storyImageUrl; // the actual take image
  final bool isDark;

  const _StoryItem({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.storyImageUrl,
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


class _BleedingWaveWidget extends StatefulWidget {
  final Widget child;
  const _BleedingWaveWidget({required this.child});

  @override
  State<_BleedingWaveWidget> createState() => _BleedingWaveWidgetState();
}

class _BleedingWaveWidgetState extends State<_BleedingWaveWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Transform.scale(
              scale: 1.0 + (_controller.value * 0.4), // Expands by 40%
              child: Opacity(
                opacity: (1.0 - _controller.value) * 0.4, // Fades out smoothly
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: AppTheme.accentPurple,
                  ),
                ),
              ),
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

