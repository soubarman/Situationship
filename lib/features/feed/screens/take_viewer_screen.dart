import '../../../core/utils/web_stub.dart' if (dart.library.html) 'package:web/web.dart' as web;
import '../utils/ui_web_shim.dart' as ui_web;
import 'dart:ui' as ui;
import 'dart:async';
import '../../../core/utils/js_interop_stub.dart' if (dart.library.js_interop) 'dart:js_interop';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/utils/color_filters.dart';

final _db = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'default',
);

// ─── TakeViewerScreen ──────────────────────────────────────────────────────────
// Full-screen TikTok-style viewer for takes/stories
class TakeViewerScreen extends ConsumerStatefulWidget {
  final String initialUserId;
  final String? initialName;
  final String? initialAvatar;

  const TakeViewerScreen({
    super.key,
    required this.initialUserId,
    this.initialName,
    this.initialAvatar,
  });

  @override
  ConsumerState<TakeViewerScreen> createState() => _TakeViewerScreenState();
}

class _TakeViewerScreenState extends ConsumerState<TakeViewerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressCtrl;
  int _currentIndex = 0;
  List<Map<String, dynamic>> _takes = [];
  bool _isMuted = true;
  String _activeTab = 'For you';
  final _tabs = ['For you', 'Following', 'Nearby'];

  // Web: keyed by URL
  final Map<String, web.HTMLVideoElement> _webVideoElements = {};
  // Native: keyed by URL
  final Map<String, VideoPlayerController> _nativeVideoControllers = {};
  
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (_takes.isEmpty) return;
          final isVideo = _takes[_currentIndex]['videoUrl'] != null;
          if (isVideo) {
            _startTimer();
          } else {
            _next();
          }
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTakes());
  }

  void _loadTakes() {
    final all = ref.read(storiesStreamProvider).asData?.value ?? [];
    final user = all.where((s) => s['userId'] == widget.initialUserId).toList();
    if (user.isEmpty) {
      if (mounted) context.pop();
      return;
    }
    setState(() => _takes = user);
    _startTimer();
  }

  void _startTimer() {
    _progressCtrl.reset();
    _progressCtrl.forward();
  }

  void _next() {
    if (_currentIndex < _takes.length - 1) {
      setState(() => _currentIndex++);
      _startTimer();
    } else {
      _startTimer();
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _startTimer();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _progressCtrl.dispose();
    // Dispose web elements
    for (final v in _webVideoElements.values) {
      v.pause();
      v.removeAttribute('src');
      v.load();
    }
    // Dispose native video controllers
    for (final ctrl in _nativeVideoControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _registerWebVideo(String url, String viewId, {bool mirrored = false, double trimStart = 0.0, double trimEnd = 0.0, String filter = 'Normal'}) {
    if (!_webVideoElements.containsKey(url)) {
      final video = web.HTMLVideoElement()
        ..src = url
        ..autoplay = true
        ..loop = true
        ..muted = _isMuted
        ..setAttribute('playsinline', 'true')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.transform = mirrored ? 'scaleX(-1)' : 'none'
        ..style.filter = AppColorFilters.getCssFilter(filter);

      video.addEventListener('timeupdate', ((web.Event _) {
        if (trimEnd > 0) {
          if (video.currentTime >= trimEnd) {
            video.currentTime = trimStart;
            video.play();
          }
        } else if (trimStart > 0 && video.currentTime < trimStart - 0.1) {
          video.currentTime = trimStart;
        }
      }).toJS);

      // Explicitly call play() — browser autoplay policy may block autoplay attr
      video.play();

      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewId,
        (int viewId) => video,
      );
      _webVideoElements[url] = video;
    } else {
      final video = _webVideoElements[url]!;
      video.muted = _isMuted;
      video.style.filter = AppColorFilters.getCssFilter(filter);
      // Ensure it's playing (e.g. after tab switch)
      video.play();
    }
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Future<void> _deleteTake(String storyId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Take?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
            'This take will be permanently deleted.',
            style: TextStyle(color: Colors.white60)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _db.collection('stories').doc(storyId).delete();
      if (mounted) {
        if (_takes.length <= 1) {
          context.pop();
        } else {
          setState(() {
            _takes.removeAt(_currentIndex);
            if (_currentIndex >= _takes.length) _currentIndex = _takes.length - 1;
          });
          _startTimer();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: AppTheme.error,
        ));
      }
    }
  }

  Future<void> _likeTake(String storyId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    // Optimistic UI update
    if (mounted) {
      setState(() {
        final currentLikes = List<String>.from(_takes[_currentIndex]['likes'] ?? []);
        if (currentLikes.contains(uid)) {
          currentLikes.remove(uid);
        } else {
          currentLikes.add(uid);
        }
        _takes[_currentIndex]['likes'] = currentLikes;
      });
    }

    try {
      final doc = _db.collection('stories').doc(storyId);
      final snap = await doc.get();
      if (!snap.exists) return;
      final likes = List<String>.from(snap.data()?['likes'] ?? []);
      if (likes.contains(uid)) {
        await doc.update({'likes': FieldValue.arrayRemove([uid])});
      } else {
        await doc.update({'likes': FieldValue.arrayUnion([uid])});
      }
    } catch (e) {
      debugPrint('Like error: $e');
    }
  }

  void _showCommentsBottomSheet(String storyId) {
    _progressCtrl.stop();
    final ctrl = TextEditingController();
    final currentUser = ref.read(currentUserProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.6,
          decoration: const BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Comments',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _db
                      .collection('stories')
                      .doc(storyId)
                      .collection('comments')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading comments.\nPlease check Firestore Rules.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.error),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(
                          child: Text('No comments yet. Be the first!',
                              style: TextStyle(color: Colors.white54)));
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: docs.length,
                      itemBuilder: (ctx, i) {
                        final data = docs[i].data() as Map<String, dynamic>;
                        final time = DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundImage: data['userAvatar'] != null
                                    ? CachedNetworkImageProvider(data['userAvatar'])
                                    : null,
                                child: data['userAvatar'] == null
                                    ? const Icon(Icons.person, size: 16)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(data['userName'] ?? 'User',
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(width: 8),
                                        Text(_timeAgo(time),
                                            style: const TextStyle(
                                                color: Colors.white38, fontSize: 10)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(data['text'] ?? '',
                                        style: const TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundImage: currentUser.avatarUrl != null
                          ? CachedNetworkImageProvider(currentUser.avatarUrl!)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Add a comment...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: AppTheme.darkBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: AppTheme.accentPurple),
                      onPressed: () async {
                        if (ctrl.text.trim().isEmpty) return;
                        final text = ctrl.text.trim();
                        ctrl.clear();
                        
                        // Optimistic update
                        if (mounted) {
                          setState(() {
                            _takes[_currentIndex]['commentCount'] = 
                                (_takes[_currentIndex]['commentCount'] ?? 0) + 1;
                          });
                        }

                        try {
                          await _db.collection('stories').doc(storyId).collection('comments').add({
                            'userId': currentUser.id,
                            'userName': currentUser.name,
                            'userAvatar': currentUser.avatarUrl,
                            'text': text,
                            'createdAt': DateTime.now().millisecondsSinceEpoch,
                          });
                          await _db.collection('stories').doc(storyId).update({
                            'commentCount': FieldValue.increment(1),
                          });
                        } catch (e) {
                          debugPrint('Comment error: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to comment: $e')),
                            );
                            // Revert optimistic update
                            setState(() {
                              final count = (_takes[_currentIndex]['commentCount'] ?? 1) - 1;
                              _takes[_currentIndex]['commentCount'] = count < 0 ? 0 : count;
                            });
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _progressCtrl.forward());
  }

  void _showConfessBottomSheet(String userName, String? userAvatar) {
    _progressCtrl.stop();
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: userAvatar != null
                        ? CachedNetworkImageProvider(userAvatar)
                        : null,
                    child: userAvatar == null ? const Icon(Icons.person) : null,
                  ),
                  const SizedBox(width: 12),
                  Text('Confess to $userName',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Type your confession here... 💜',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: AppTheme.darkBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentPink,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Confession sent! 💜'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('Send Confession',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _progressCtrl.forward());
  }

  void _showShareBottomSheet() {
    _progressCtrl.stop();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Text('Share Take',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _shareOption(Icons.link_rounded, 'Copy Link', Colors.blue, () async {
                  Navigator.pop(ctx);
                  final link = 'https://situatioship.netlify.app';
                  await Clipboard.setData(ClipboardData(text: link));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied to clipboard!')));
                  }
                }),
                _shareOption(Icons.message_rounded, 'Message', Colors.green, () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sent in message!')));
                }),
                _shareOption(Icons.camera_alt_rounded, 'Snapchat', Colors.yellow[700]!, () {
                  Navigator.pop(ctx);
                }),
                _shareOption(Icons.more_horiz_rounded, 'More', Colors.white54, () {
                  Navigator.pop(ctx);
                }),
              ],
            ),
          ],
        ),
      ),
    ).then((_) => _progressCtrl.forward());
  }

  Widget _shareOption(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (_takes.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(widget.initialName ?? 'Loading...',
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    final take = _takes[_currentIndex];
    final storyId = take['id'] as String? ?? '';
    final userName = take['userName'] ?? widget.initialName ?? 'User';
    final userAvatar = take['userAvatar'] as String?;
    final imageUrl = take['imageUrl'] as String?;
    final caption = take['caption'] as String? ?? '';
    final createdAt = take['createdAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(take['createdAt'] as int)
        : DateTime.now();
    
    // Fading Timer Logic
    final expiresAt = createdAt.add(const Duration(hours: 24));
    final remaining = expiresAt.difference(DateTime.now());
    final isFading = remaining.inHours < 2;
    
    String remainingStr;
    if (remaining.isNegative) {
      remainingStr = '0m 0s';
    } else if (remaining.inHours > 0) {
      final mins = remaining.inMinutes % 60;
      remainingStr = '${remaining.inHours}h ${mins}m';
    } else {
      final secs = remaining.inSeconds % 60;
      remainingStr = '${remaining.inMinutes}m ${secs}s';
    }
    
    final progressVal = remaining.inMilliseconds / const Duration(hours: 24).inMilliseconds;

    final likes = List<String>.from(take['likes'] ?? []);
    final isLiked = currentUid != null && likes.contains(currentUid);
    final isOwner = take['userId'] == currentUid;

    final cropAspectStr = take['cropAspect'] as String? ?? 'Original';
    final cropZoom = (take['cropZoom'] as num?)?.toDouble() ?? 1.0;
    final cropX = (take['cropX'] as num?)?.toDouble() ?? 0.0;
    final cropY = (take['cropY'] as num?)?.toDouble() ?? 0.0;

    double? cropRatioValue;
    switch (cropAspectStr) {
      case '1:1': cropRatioValue = 1.0; break;
      case '4:5': cropRatioValue = 4.0 / 5.0; break;
      case '9:16': cropRatioValue = 9.0 / 16.0; break;
      case '16:9': cropRatioValue = 16.0 / 9.0; break;
    }

    Widget mediaContent;
    if (take['videoUrl'] != null) {
      Widget videoPlayer;
      if (kIsWeb) {
        final vUrl     = take['videoUrl'] as String;
        final mirrored = take['mirrored'] as bool? ?? false;
        final tStart   = (take['trimStart'] as num?)?.toDouble() ?? 0.0;
        final tEnd     = (take['trimEnd'] as num?)?.toDouble() ?? 0.0;
        final filter   = take['filter'] as String? ?? 'Normal';
        final viewId   = 'video-view-$vUrl';
        _registerWebVideo(vUrl, viewId, mirrored: mirrored, trimStart: tStart, trimEnd: tEnd, filter: filter);
        videoPlayer = HtmlElementView(viewType: viewId);
      } else {
        videoPlayer = _NativeVideoPlayer(
          url:              take['videoUrl'] as String,
          isMuted:          _isMuted,
          mirrored:         take['mirrored'] as bool? ?? false,
          trimStart:        (take['trimStart'] as num?)?.toDouble() ?? 0.0,
          trimEnd:          (take['trimEnd'] as num?)?.toDouble() ?? 0.0,
          controllerCache:  _nativeVideoControllers,
        );
      }
      
      if (cropZoom != 1.0 || cropX != 0.0 || cropY != 0.0) {
        mediaContent = ClipRect(
          child: FractionalTranslation(
            translation: Offset(cropX, cropY),
            child: Transform.scale(
              scale: cropZoom,
              child: videoPlayer,
            ),
          ),
        );
      } else {
        mediaContent = videoPlayer;
      }
    } else if (imageUrl != null) {
      mediaContent = CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => const ColoredBox(
          color: Colors.black,
          child: Center(child: CircularProgressIndicator(color: Colors.white38)),
        ),
        errorWidget: (_, __, ___) => const ColoredBox(
          color: Colors.black87,
          child: Center(
            child: Icon(Icons.broken_image_rounded, color: Colors.white38, size: 80),
          ),
        ),
      );
    } else {
      mediaContent = Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryBlue, AppTheme.accentPurple],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(child: Text('✨', style: TextStyle(fontSize: 80))),
      );
    }

    final filter = take['filter'] as String? ?? 'Normal';
    if (filter != 'Normal') {
      mediaContent = ColorFiltered(
        colorFilter: ColorFilter.matrix(AppColorFilters.get(filter)),
        child: mediaContent,
      );
    }

    Widget mediaAndOverlays = Stack(
      fit: StackFit.expand,
      children: [
        mediaContent,
        if (take['overlays'] != null)
          ...((take['overlays'] as Map<String, dynamic>).values.map((o) {
            final isText = o['isText'] == true;
            final scale = (o['scale'] as num?)?.toDouble() ?? 1.0;
            final rotation = (o['rotation'] as num?)?.toDouble() ?? 0.0;
            final fontFamily = o['fontFamily'] as String? ?? 'Inter';
            final colorValue = o['color'] as int?;
            final color = colorValue != null ? Color(colorValue) : Colors.white;
            final hasBackground = o['hasBackground'] == true;

            Widget child = isText
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: hasBackground
                        ? BoxDecoration(
                            color: color == Colors.white || color == Colors.transparent 
                                ? Colors.black87 
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          )
                        : null,
                    child: Text(
                      o['content'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: hasBackground && color == Colors.white ? Colors.black : color,
                        shadows: hasBackground ? null : const [
                          Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))
                        ],
                        decoration: TextDecoration.none,
                      ),
                    ),
                  )
                : Text(
                    o['content'] as String,
                    style: const TextStyle(fontSize: 48, decoration: TextDecoration.none),
                  );

            return Positioned(
              left: (o['dx'] as num).toDouble(),
              top: (o['dy'] as num).toDouble(),
              child: Transform.scale(
                scale: scale,
                child: Transform.rotate(
                  angle: rotation,
                  child: child,
                ),
              ),
            );
          })),
      ],
    );

    if (cropRatioValue != null) {
      mediaAndOverlays = Center(
        child: AspectRatio(
          aspectRatio: cropRatioValue,
          child: ClipRect(child: mediaAndOverlays),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          _progressCtrl.stop();
          if (d.localPosition.dx < size.width / 2) {
            _prev();
          } else {
            _next();
          }
        },
        onLongPressStart: (_) => _progressCtrl.stop(),
        onLongPressEnd: (_) => _progressCtrl.forward(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            mediaAndOverlays,

            // ── Gradient overlays ─────────────────────────────────────────
            const Positioned(
              top: 0, left: 0, right: 0, height: 200,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
              ),
            ),
            const Positioned(
              bottom: 0, left: 0, right: 0, height: 300,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xDD000000), Colors.transparent],
                  ),
                ),
              ),
            ),

            // ── Main layout ───────────────────────────────────────────────
            SafeArea(
              child: Stack(
                children: [
                  // TOP: Back button + Tabs + Muted
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          // Back
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.chevron_left_rounded,
                                  color: Colors.white, size: 28),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Tabs
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: _tabs.map((t) {
                                final sel = _activeTab == t;
                                return GestureDetector(
                                  onTap: () => setState(() => _activeTab = t),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          t,
                                          style: TextStyle(
                                            color: sel ? Colors.white : Colors.white54,
                                            fontWeight: sel
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        if (sel)
                                          Container(
                                            width: 4,
                                            height: 4,
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          // Muted
                          GestureDetector(
                            onTap: () {
                              setState(() => _isMuted = !_isMuted);
                              // Web: update all registered HTML video elements
                              for (final v in _webVideoElements.values) {
                                v.muted = _isMuted;
                              }
                              // Native: update all video player controllers
                              for (final ctrl in _nativeVideoControllers.values) {
                                ctrl.setVolume(_isMuted ? 0.0 : 1.0);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isMuted
                                        ? Icons.volume_off_rounded
                                        : Icons.volume_up_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isMuted ? 'Muted' : 'Sound',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Fading Pill at top (if fading)
                  if (isFading)
                    Positioned(
                      top: 60,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC33149).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, color: Colors.white, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Fading in $remainingStr',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // RIGHT SIDE: Action buttons
                  Positioned(
                    right: 12,
                    bottom: 120,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // User avatar
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            image: userAvatar != null
                                ? DecorationImage(
                                    image: CachedNetworkImageProvider(userAvatar),
                                    fit: BoxFit.cover)
                                : null,
                          ),
                          child: userAvatar == null
                              ? const Center(
                                  child: Text('😊',
                                      style: TextStyle(fontSize: 22)))
                              : null,
                        ),
                        const SizedBox(height: 20),

                        // Like
                        _actionBtn(
                          icon: isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          label: '${likes.length}',
                          color: isLiked ? AppTheme.error : Colors.white,
                          onTap: () => _likeTake(storyId),
                        ),
                        const SizedBox(height: 20),

                        // Comment
                        _actionBtn(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: '${take['commentCount'] ?? 0}',
                          onTap: () => _showCommentsBottomSheet(storyId),
                        ),
                        const SizedBox(height: 20),

                        // Share
                        _actionBtn(
                          icon: Icons.reply_rounded,
                          label: 'Share',
                          onTap: () => _showShareBottomSheet(),
                        ),
                        const SizedBox(height: 20),

                        // Take back (retake)
                        _actionBtn(
                          icon: Icons.camera_alt_rounded,
                          label: 'Take',
                          onTap: () {
                            context.pop();
                            context.push('/take/create');
                          },
                        ),
                        const SizedBox(height: 20),

                        // Confess
                        _actionBtn(
                          icon: Icons.favorite_outline_rounded,
                          label: 'Confess',
                          color: AppTheme.accentPink,
                          onTap: () => _showConfessBottomSheet(userName, userAvatar),
                        ),
                        const SizedBox(height: 20),

                        // More (3 dots) — shows delete for own takes
                        _actionBtn(
                          icon: Icons.more_horiz_rounded,
                          label: '',
                          onTap: () {
                            _progressCtrl.stop();
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (ctx) => Container(
                                decoration: const BoxDecoration(
                                  color: AppTheme.darkCard,
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(24)),
                                ),
                                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 4,
                                      margin: const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    if (isOwner) ...[
                                      ListTile(
                                        leading: const Icon(Icons.delete_outline_rounded,
                                            color: AppTheme.error),
                                        title: const Text('Delete Take',
                                            style: TextStyle(color: AppTheme.error)),
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          _deleteTake(storyId);
                                        },
                                      ),
                                    ],
                                    ListTile(
                                      leading: const Icon(Icons.report_gmailerrorred_rounded,
                                          color: Colors.white54),
                                      title: const Text('Report',
                                          style: TextStyle(color: Colors.white70)),
                                      onTap: () => Navigator.pop(ctx),
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.share_rounded,
                                          color: Colors.white54),
                                      title: const Text('Share',
                                          style: TextStyle(color: Colors.white70)),
                                      onTap: () => Navigator.pop(ctx),
                                    ),
                                  ],
                                ),
                              ),
                            ).then((_) => _progressCtrl.forward());
                          },
                        ),
                      ],
                    ),
                  ),

                  // BOTTOM: Username + Caption + Progress bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 72,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Username
                          Row(
                            children: [
                              Text(
                                '@${userName.toLowerCase().replaceAll(' ', '')}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Emoji badges
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('🔥', style: TextStyle(fontSize: 12)),
                                    Text('⚡', style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _timeAgo(createdAt),
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                          if (caption.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              caption,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.4,
                                shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          // "1 take back" badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B2117), // dark brown
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFD67341)), // orange border
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.undo_rounded,
                                    color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  '${_takes.length} take back',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Fading/Live Text Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isFading ? 'Fading soon' : 'Live',
                                style: TextStyle(
                                  color: isFading ? const Color(0xFFFF2D55) : Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                remainingStr,
                                style: TextStyle(
                                  color: isFading ? const Color(0xFFFF2D55) : Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Progress Bar & Sign In Button
                          SizedBox(
                            height: 36, // height for the button to center on the line
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                // Thin line background
                                Container(
                                  height: 3,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                // Active line
                                Container(
                                  height: 3,
                                  width: MediaQuery.of(context).size.width * progressVal.clamp(0.0, 1.0),
                                  decoration: BoxDecoration(
                                    color: isFading ? const Color(0xFFFF2D55) : const Color(0xFF00E5FF),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  Widget _actionBtn({
    required IconData icon,
    required String label,
    Color color = Colors.white,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

// ─── Cross-platform Native Video Player Widget ─────────────────────────────────
// Used on Android / iOS to play video takes from a network URL.
// On Web, HtmlElementView + HTMLVideoElement is used instead.
class _NativeVideoPlayer extends StatefulWidget {
  final String url;
  final bool isMuted;
  final bool mirrored;
  final double trimStart;
  final double trimEnd;
  final Map<String, VideoPlayerController> controllerCache;

  const _NativeVideoPlayer({
    required this.url,
    required this.isMuted,
    required this.mirrored,
    this.trimStart = 0.0,
    this.trimEnd = 0.0,
    required this.controllerCache,
  });

  @override
  State<_NativeVideoPlayer> createState() => _NativeVideoPlayerState();
}

class _NativeVideoPlayerState extends State<_NativeVideoPlayer> {
  VideoPlayerController? _ctrl;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(_NativeVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _initPlayer();
    } else if (old.isMuted != widget.isMuted && _ctrl != null) {
      _ctrl!.setVolume(widget.isMuted ? 0.0 : 1.0);
    }
  }

  void _onTick() {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    
    final posMs = _ctrl!.value.position.inMilliseconds;
    final endMs = (widget.trimEnd * 1000).toInt();
    final startMs = (widget.trimStart * 1000).toInt();
    
    if (widget.trimEnd > 0) {
      if (posMs >= endMs) {
        _ctrl!.seekTo(Duration(milliseconds: startMs));
        if (!_ctrl!.value.isPlaying) _ctrl!.play();
      }
    } else if (widget.trimStart > 0 && posMs < startMs - 100) {
      _ctrl!.seekTo(Duration(milliseconds: startMs));
    }
  }

  Future<void> _initPlayer() async {
    if (mounted) setState(() { _loading = true; _hasError = false; });

    // Reuse cached controller if available
    if (widget.controllerCache.containsKey(widget.url)) {
      final cached = widget.controllerCache[widget.url]!;
      cached.removeListener(_onTick);
      cached.addListener(_onTick);
      await cached.setLooping(true);
      await cached.setVolume(widget.isMuted ? 0.0 : 1.0);
      
      if (widget.trimStart > 0) {
        final pos = cached.value.position.inMilliseconds;
        final startMs = (widget.trimStart * 1000).toInt();
        if (pos < startMs - 200 || (widget.trimEnd > 0 && pos > (widget.trimEnd * 1000).toInt())) {
          await cached.seekTo(Duration(milliseconds: startMs));
        }
      }
      
      if (!cached.value.isPlaying) await cached.play();
      if (mounted) setState(() { _ctrl = cached; _loading = false; });
      return;
    }

    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await ctrl.initialize();
      ctrl.addListener(_onTick);
      await ctrl.setLooping(true);   // ← loop forever
      await ctrl.setVolume(widget.isMuted ? 0.0 : 1.0);
      
      if (widget.trimStart > 0) {
        await ctrl.seekTo(Duration(milliseconds: (widget.trimStart * 1000).toInt()));
      }
      
      await ctrl.play();             // ← start immediately
      widget.controllerCache[widget.url] = ctrl;
      if (mounted) setState(() { _ctrl = ctrl; _loading = false; });
    } catch (e) {
      debugPrint('_NativeVideoPlayer error: $e');
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
        ),
      );
    }
    if (_hasError || _ctrl == null) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_rounded, color: Colors.white38, size: 64),
              SizedBox(height: 12),
              Text('Video unavailable',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width:  _ctrl!.value.size.width,
        height: _ctrl!.value.size.height,
        child: widget.mirrored
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..scale(-1.0, 1.0),
                child: VideoPlayer(_ctrl!),
              )
            : VideoPlayer(_ctrl!),
      ),
    );
  }
}
