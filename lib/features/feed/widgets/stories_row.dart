import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/user_model.dart';
import '../screens/feed_screen.dart';
import 'package:flutter/foundation.dart';
import '../utils/ui_web_shim.dart' as ui_web;
import '../../../core/utils/web_stub.dart' if (dart.library.html) 'package:web/web.dart' as web;
import 'dart:math';

class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storiesStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 140,
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
                        
                    // If user has a story, show their own story instead of the "Drop a Take" button
                    if (myStory != null && currentUserId != null) {
                      return _StoryItem(
                        userId: currentUserId,
                        userName: currentUser.name,
                        avatarUrl: currentUser.avatarUrl,
                        storyImageUrl: myStory['imageUrl'],
                        createdAt: myStory['createdAt'] as int?,
                        isDark: isDark,
                      );
                    }
                    
                    // User has no story, show the Add Story button
                    return _buildAddStory(context, isDark, currentUser);
                  }
                  
                  final story = otherUsersStories[index - 1];
                  return _StoryItem(
                    userId: story['userId'],
                    userName: story['userName'],
                    avatarUrl: story['userAvatar'],
                    storyImageUrl: story['imageUrl'],
                    createdAt: story['createdAt'] as int?,
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

  Widget _buildAddStory(BuildContext context, bool isDark, UserModel user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              context.push('/take/create');
            },
            child: Container(
              width: 78,
              height: 98,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Color(0xFFE84855), Color(0xFFF9A03F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  color: Colors.black,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    const _LoopingVideoBackground(),
                    Container(color: Colors.black.withOpacity(0.2)),
                    Positioned(
                      top: 8, left: 8,
                      child: Row(
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFE84855), shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          const Text('REC', style: TextStyle(color: Color(0xFFE84855), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        ]
                      )
                    ),
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 26),
                          ),
                          Positioned(
                            right: -4, bottom: -4,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(color: const Color(0xFFFF2D55), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)),
                              child: const Icon(Icons.add_rounded, color: Colors.white, size: 14),
                            )
                          )
                        ]
                      )
                    ),
                    Positioned(
                      bottom: 12, left: 0, right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _bar(8), const SizedBox(width: 3), _bar(14), const SizedBox(width: 3),
                          _bar(10), const SizedBox(width: 3), _bar(16), const SizedBox(width: 3), _bar(12),
                        ]
                      )
                    )
                  ]
                )
              )
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Drop a ', style: TextStyle(color: Color(0xFFF9A03F))),
                TextSpan(text: 'Take', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
              ]
            ),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
  
  Widget _bar(double h) => Container(
    width: 3, height: h,
    decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(2)),
  );
}

class _StoryItem extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final String? storyImageUrl;
  final int? createdAt;
  final bool isDark;

  const _StoryItem({
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.storyImageUrl,
    this.createdAt,
    required this.isDark,
  });

  @override
  ConsumerState<_StoryItem> createState() => _StoryItemState();
}

class _StoryItemState extends ConsumerState<_StoryItem> {

  @override
  Widget build(BuildContext context) {
    // Live-watch the story author's profile for up-to-date name/avatar.
    final liveAuthor = ref.watch(otherUserProvider(widget.userId));
    final displayName = liveAuthor.asData?.value?.name ?? widget.userName;
    final displayAvatar = liveAuthor.asData?.value?.avatarUrl
        ?? widget.avatarUrl
        ?? 'https://i.pravatar.cc/100?u=${widget.userId}';

    bool isEnding = false;
    if (widget.createdAt != null) {
      final createdAtDate = DateTime.fromMillisecondsSinceEpoch(widget.createdAt!);
      final expiresAt = createdAtDate.add(const Duration(hours: 24));
      final remaining = expiresAt.difference(DateTime.now());
      isEnding = remaining.inHours < 2 && remaining.inSeconds > 0;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => context.push(
              '/story/view/${widget.userId}',
              extra: {'userName': displayName, 'userAvatar': displayAvatar},
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 78,
                  height: 98,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      colors: widget.userId.hashCode % 2 == 0 
                          ? [const Color(0xFFE84855), const Color(0xFFF9A03F)]
                          : [const Color(0xFFB138FF), const Color(0xFFFD297B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      color: widget.isDark ? AppTheme.darkBg : Colors.white,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: displayAvatar,
                          fit: BoxFit.cover,
                        ),
                          
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withOpacity(0.5)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // ENDING badge
                if (isEnding)
                  Positioned(
                    bottom: -6, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF2D55),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        child: const Text('ENDING', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      )
                    )
                  ),
                
                // Emoji badge
                Positioned(
                  top: -6, right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1.5),
                    ),
                    child: Text(
                      widget.userId.hashCode % 3 == 0 ? '🔥' : (widget.userId.hashCode % 2 == 0 ? '✨' : '💯'),
                      style: const TextStyle(fontSize: 10),
                    )
                  )
                )
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 78,
            child: Text(
              '@${displayName.toLowerCase().replaceAll(' ', '')}',
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

class _LoopingVideoBackground extends StatefulWidget {
  const _LoopingVideoBackground();

  @override
  State<_LoopingVideoBackground> createState() => _LoopingVideoBackgroundState();
}

class _LoopingVideoBackgroundState extends State<_LoopingVideoBackground> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  String? _webElementId;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webElementId = 'take_video_bg_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
      ui_web.platformViewRegistry.registerViewFactory(_webElementId!, (int viewId) {
        final video = web.HTMLVideoElement()
          ..autoplay = true
          ..loop = true
          ..muted = true
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.pointerEvents = 'none';
          
        video.setAttribute('playsinline', 'true');
        video.setAttribute('muted', 'true');
        video.setAttribute('autoplay', 'true');
        video.setAttribute('loop', 'true');
        
        video.src = 'assets/assets/take video/take_icon_video.mp4';
        
        return video;
      });
      _ready = true;
    } else {
      _ctrl = VideoPlayerController.asset('assets/take video/take_icon_video.mp4');
      _ctrl!.initialize().then((_) async {
        await _ctrl!.setVolume(0.0);
        await _ctrl!.setLooping(true);
        await _ctrl!.play();
        
        _ctrl!.addListener(() {
          if (_ctrl!.value.isInitialized && !_ctrl!.value.isPlaying) {
            final position = _ctrl!.value.position;
            final duration = _ctrl!.value.duration;
            if (position >= duration || (duration.inMilliseconds - position.inMilliseconds) < 50) {
              _ctrl!.seekTo(Duration.zero);
              _ctrl!.play();
            }
          }
        });
        
        if (mounted) setState(() => _ready = true);
      });
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    
    if (kIsWeb) {
      return SizedBox.expand(
        child: IgnorePointer(
          child: HtmlElementView(viewType: _webElementId!),
        ),
      );
    }
    
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _ctrl!.value.size.width,
          height: _ctrl!.value.size.height,
          child: VideoPlayer(_ctrl!),
        ),
      ),
    );
  }
}
