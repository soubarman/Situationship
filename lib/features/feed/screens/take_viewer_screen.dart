import '../../../core/utils/web_stub.dart' if (dart.library.html) 'package:web/web.dart' as web;
import '../utils/ui_web_shim.dart' as ui_web;
import 'dart:ui' show ImageFilter;
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
import '../../../core/theme/app_palette.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/utils/color_filters.dart';

final _db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

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
    with TickerProviderStateMixin {
  late AnimationController _progressCtrl;
  int _currentIndex = 0;
  List<Map<String, dynamic>> _takes = [];
  bool _isMuted = true;
  String _activeTab = 'For you';
  final _tabs = ['For you', 'Following', 'Nearby'];

  // Double-tap heart explosion animation
  late AnimationController _heartAnimCtrl;
  late Animation<double> _heartScale;
  late Animation<double> _heartOpacity;
  Offset? _doubleTapHeartPosition;

  // Live / Fading pulsing glow animation
  late AnimationController _pulseCtrl;
  late Animation<double> _glowPulse;

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

    _heartAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.35).chain(CurveTween(curve: Curves.easeOutBack)), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2).chain(CurveTween(curve: Curves.easeIn)), weight: 35),
    ]).animate(_heartAnimCtrl);
    _heartOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
    ]).animate(_heartAnimCtrl);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowPulse = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTakes());
  }

  void _loadTakes({String? tab}) {
    final activeTab = tab ?? _activeTab;
    final all = ref.read(storiesStreamProvider).asData?.value ?? [];
    List<Map<String, dynamic>> filtered = [];

    if (activeTab == 'For you') {
      filtered = all.where((s) => s['userId'] == widget.initialUserId).toList();
      if (filtered.isEmpty && all.isNotEmpty) filtered = all;
    } else if (activeTab == 'Following') {
      filtered = all.where((s) => s['userId'] == widget.initialUserId).toList();
      if (filtered.isEmpty && all.isNotEmpty) filtered = all;
    } else {
      // Nearby / Explore
      filtered = all.where((s) => s['userId'] == widget.initialUserId).toList();
      if (filtered.isEmpty && all.isNotEmpty) filtered = all;
    }

    if (filtered.isEmpty) {
      if (mounted) context.pop();
      return;
    }
    setState(() {
      _takes = filtered;
      _currentIndex = 0;
    });
    _startTimer();
  }

  void _switchTab(String tab) {
    if (_activeTab == tab) return;
    HapticFeedback.selectionClick();
    setState(() => _activeTab = tab);
    _loadTakes(tab: tab);
  }

  void _triggerDoubleTapHeart(Offset pos, String storyId) {
    HapticFeedback.heavyImpact();
    setState(() => _doubleTapHeartPosition = pos);
    _heartAnimCtrl.forward(from: 0.0);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && _takes.isNotEmpty) {
      final currentLikes = List<String>.from(_takes[_currentIndex]['likes'] ?? []);
      if (!currentLikes.contains(uid)) {
        _likeTake(storyId);
      }
    }
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
    _heartAnimCtrl.dispose();
    _pulseCtrl.dispose();
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
                      icon: Icon(Icons.send_rounded, color: AppTheme.accentPurple),
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
              color: color.withValues(alpha: 0.15),
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
    final palette = ref.watch(appPaletteProvider);

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
        decoration: BoxDecoration(
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
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: (details) {
          _triggerDoubleTapHeart(details.localPosition, storyId);
        },
        onTapUp: (details) {
          _progressCtrl.stop();
          final dx = details.localPosition.dx;
          if (dx < size.width * 0.35) {
            _prev();
          } else if (dx > size.width * 0.65) {
            _next();
          } else {
            if (_progressCtrl.isAnimating) {
              _progressCtrl.stop();
            } else {
              _progressCtrl.forward();
            }
          }
        },
        onLongPressStart: (_) => _progressCtrl.stop(),
        onLongPressEnd: (_) => _progressCtrl.forward(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media and text/emoji overlays
            mediaAndOverlays,

            // Cinematic Scrim: Top Gradient
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 220,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.82),
                        Colors.black.withValues(alpha: 0.35),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Cinematic Scrim: Bottom Gradient
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 380,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.94),
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Main UI Overlay
            SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Top Segmented Progress Bar
                  Positioned(
                    top: 6,
                    left: 12,
                    right: 12,
                    child: _buildTopSegmentedBars(),
                  ),

                  // Top Header Controls: Floating Back + Frosted Tab Capsule + Sound Toggle
                  Positioned(
                    top: 18,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        // Luxury Back Button
                        ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.12),
                              child: InkWell(
                                onTap: () => context.pop(),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      width: 1,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Floating Frosted Tab Capsule
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: _tabs.map((t) {
                                  final isSelected = _activeTab == t;
                                  return GestureDetector(
                                    onTap: () => _switchTab(t),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 220),
                                      curve: Curves.easeOutCubic,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withValues(alpha: 0.22)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.2),
                                                  blurRadius: 8,
                                                )
                                              ]
                                            : null,
                                      ),
                                      child: Text(
                                        t,
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : Colors.white.withValues(alpha: 0.65),
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Sound / Mute Frosted Pill
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Material(
                              color: Colors.white.withValues(alpha: 0.12),
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _isMuted = !_isMuted);
                                  for (final v in _webVideoElements.values) {
                                    v.muted = _isMuted;
                                  }
                                  for (final ctrl in _nativeVideoControllers.values) {
                                    ctrl.setVolume(_isMuted ? 0.0 : 1.0);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isMuted
                                            ? Icons.volume_off_rounded
                                            : Icons.volume_up_rounded,
                                        color: Colors.white,
                                        size: 15,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isMuted ? 'Muted' : 'Sound',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Fading Warning Badge at top center (if < 2 hours)
                  if (isFading)
                    Positioned(
                      top: 72,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFFFF2D55).withValues(alpha: 0.85),
                                    const Color(0xFFFF6A00).withValues(alpha: 0.85),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF2D55).withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.hourglass_bottom_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Fading in $remainingStr',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Right Side Floating Luxury Action Dock
                  Positioned(
                    right: 12,
                    bottom: 84,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Creator Profile Avatar with Iridescent Story Ring
                        GestureDetector(
                          onTap: () {
                            // User profile view or avatar tap
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      palette.primary,
                                      palette.accent,
                                      const Color(0xFFFF2D55),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: palette.primary.withValues(alpha: 0.4),
                                      blurRadius: 12,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(2.5),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: userAvatar != null && userAvatar.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: userAvatar,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => ColoredBox(
                                            color: Colors.grey.shade900,
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ),
                                          errorWidget: (_, __, ___) => const Center(
                                            child: Text('✨', style: TextStyle(fontSize: 20)),
                                          ),
                                        )
                                      : const Center(
                                          child: Text('✨', style: TextStyle(fontSize: 20)),
                                        ),
                                ),
                              ),
                              if (!isOwner)
                                Positioned(
                                  bottom: -1,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [Color(0xFFFF2D55), Color(0xFFFF5252)],
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.add_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Like Action Button
                        _luxuryActionBtn(
                          icon: isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          label: '${likes.length}',
                          iconColor: isLiked
                              ? const Color(0xFFFF2D55)
                              : Colors.white,
                          glowColor: isLiked
                              ? const Color(0xFFFF2D55).withValues(alpha: 0.5)
                              : null,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _likeTake(storyId);
                          },
                        ),

                        const SizedBox(height: 16),

                        // Comment Action Button
                        _luxuryActionBtn(
                          icon: Icons.chat_bubble_rounded,
                          label: '${take['commentCount'] ?? 0}',
                          iconColor: Colors.white,
                          onTap: () => _showCommentsBottomSheet(storyId),
                        ),

                        const SizedBox(height: 16),

                        // Confess / Whisper Button (Signature dating dynamic)
                        _luxuryActionBtn(
                          icon: Icons.local_fire_department_rounded,
                          label: 'Confess',
                          iconColor: const Color(0xFFFF416C),
                          glowColor: const Color(0xFFFF416C).withValues(alpha: 0.4),
                          badgeGradient: const LinearGradient(
                            colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                          ),
                          onTap: () => _showConfessBottomSheet(userName, userAvatar),
                        ),

                        const SizedBox(height: 16),

                        // Share Action Button
                        _luxuryActionBtn(
                          icon: Icons.send_rounded,
                          label: 'Share',
                          iconColor: Colors.white,
                          onTap: () => _showShareBottomSheet(),
                        ),

                        const SizedBox(height: 16),

                        // Take Studio (Camera) Button
                        _luxuryActionBtn(
                          icon: Icons.camera_alt_rounded,
                          label: 'Take',
                          iconColor: const Color(0xFF00E5FF),
                          glowColor: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                          onTap: () {
                            context.pop();
                            context.push('/take/create');
                          },
                        ),

                        const SizedBox(height: 16),

                        // More (Options & Delete)
                        _luxuryActionBtn(
                          icon: Icons.more_horiz_rounded,
                          label: '',
                          iconColor: Colors.white70,
                          onTap: () {
                            _progressCtrl.stop();
                            _showMoreOptionsMenu(storyId, isOwner);
                          },
                        ),
                      ],
                    ),
                  ),

                  // Bottom Creator Info & Modernized Story Card
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 80,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 12, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Creator Handle + Tag + Relative Time
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '@${userName.toLowerCase().replaceAll(' ', '')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    letterSpacing: -0.4,
                                    shadows: [
                                      Shadow(color: Colors.black87, blurRadius: 10),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // HOT TAKE Glass Pill (Replaces ugly emoji badges)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFF3366), Color(0xFFFF6B00)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF3366).withValues(alpha: 0.35),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.local_fire_department_rounded,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'HOT TAKE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 9.5,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              Text(
                                _timeAgo(createdAt),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  shadows: const [
                                    Shadow(color: Colors.black87, blurRadius: 8),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          if (caption.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              caption,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w400,
                                height: 1.35,
                                shadows: [
                                  Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 1)),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),

                          // Sleek Moment Counter Pill (Replaces the ugly brown "1 take back" badge)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.auto_awesome_rounded,
                                      color: Color(0xFFFFD700),
                                      size: 13,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Moment ${_currentIndex + 1} of ${_takes.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    if (_takes.length > 1) ...[
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.swipe_rounded,
                                        color: Colors.white60,
                                        size: 12,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Dynamic Live / Fading Status Row
                          Row(
                            children: [
                              // Pulsing status dot
                              AnimatedBuilder(
                                animation: _glowPulse,
                                builder: (context, child) {
                                  final dotColor = isFading
                                      ? const Color(0xFFFF2D55)
                                      : const Color(0xFF00FFB2);
                                  return Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: dotColor,
                                      boxShadow: [
                                        BoxShadow(
                                          color: dotColor.withValues(alpha: _glowPulse.value * 0.8),
                                          blurRadius: 6 * _glowPulse.value,
                                          spreadRadius: 1 * _glowPulse.value,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isFading ? 'Fading Soon' : 'Live Take',
                                style: TextStyle(
                                  color: isFading
                                      ? const Color(0xFFFF416C)
                                      : const Color(0xFF00FFB2),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                remainingStr,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          // Modern Gradient Lifetime Bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              height: 3.5,
                              width: double.infinity,
                              color: Colors.white.withValues(alpha: 0.15),
                              alignment: Alignment.centerLeft,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return Container(
                                    height: 3.5,
                                    width: constraints.maxWidth * progressVal.clamp(0.0, 1.0),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isFading
                                            ? [const Color(0xFFFF2D55), const Color(0xFFFF8A00)]
                                            : [palette.primary, palette.accent],
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Double Tap Bursting Heart Overlay
            if (_doubleTapHeartPosition != null)
              Positioned(
                left: _doubleTapHeartPosition!.dx - 50,
                top: _doubleTapHeartPosition!.dy - 50,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _heartAnimCtrl,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _heartOpacity.value.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: _heartScale.value,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF2D55).withValues(alpha: 0.6),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFFF2D55),
                              size: 80,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSegmentedBars() {
    if (_takes.isEmpty) return const SizedBox.shrink();
    return Row(
      children: List.generate(_takes.length, (index) {
        return Expanded(
          child: Container(
            height: 2.5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(2),
            ),
            child: index < _currentIndex
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                : index == _currentIndex
                    ? AnimatedBuilder(
                        animation: _progressCtrl,
                        builder: (context, child) {
                          return FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _progressCtrl.value.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        },
                      )
                    : const SizedBox.shrink(),
          ),
        );
      }),
    );
  }

  Widget _luxuryActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
    Color? glowColor,
    Gradient? badgeGradient,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.35),
                  border: Border.all(
                    color: glowColor ?? Colors.white.withValues(alpha: 0.16),
                    width: 1.2,
                  ),
                  boxShadow: glowColor != null
                      ? [
                          BoxShadow(
                            color: glowColor,
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 22,
                ),
              ),
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                shadows: const [
                  Shadow(
                    color: Colors.black87,
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showMoreOptionsMenu(String storyId, bool isOwner) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14141E).withValues(alpha: 0.92),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                if (isOwner)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
                    title: const Text('Delete Take', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _deleteTake(storyId);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.report_gmailerrorred_rounded, color: Colors.white70),
                  title: const Text('Report Take', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  onTap: () => Navigator.pop(ctx),
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: Colors.white70),
                  title: const Text('Share Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showShareBottomSheet();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      if (mounted) _progressCtrl.forward();
    });
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
