// ignore_for_file: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import '../utils/ui_web_shim.dart' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';

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
  final Map<String, html.VideoElement> _videoElements = {};

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
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
      if (mounted) context.pop();
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
    _progressCtrl.dispose();
    for (final v in _videoElements.values) {
      v.pause();
      v.removeAttribute('src');
      v.load();
    }
    super.dispose();
  }

  void _registerVideo(String url, String viewId) {
    if (!_videoElements.containsKey(url)) {
      final video = html.VideoElement()
        ..src = url
        ..autoplay = true
        ..loop = true
        ..muted = _isMuted
        ..setAttribute('playsinline', 'true')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.transform = 'scaleX(-1)'; // mirror like camera

      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(
        viewId,
        (int viewId) => video,
      );
      _videoElements[url] = video;
    } else {
      _videoElements[url]!.muted = _isMuted;
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
    final likes = List<String>.from(take['likes'] ?? []);
    final isLiked = currentUid != null && likes.contains(currentUid);
    final isOwner = take['userId'] == currentUid;

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
            // ── Full screen image / video ──────────────────────────────────────────
            if (take['videoUrl'] != null) ...[
              Builder(builder: (context) {
                final vUrl = take['videoUrl'] as String;
                final viewId = 'video-view-$vUrl';
                _registerVideo(vUrl, viewId);
                return HtmlElementView(viewType: viewId);
              })
            ] else if (imageUrl != null) ...[
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(
                  color: Colors.black,
                  child: Center(child: CircularProgressIndicator(color: Colors.white38)),
                ),
                errorWidget: (_, __, ___) => const ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: Icon(Icons.broken_image_rounded,
                        color: Colors.white38, size: 80),
                  ),
                ),
              )
            ] else ...[
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryBlue, AppTheme.accentPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(child: Text('✨', style: TextStyle(fontSize: 80))),
              ),
            ],

            // ── Render Overlays ────────────────────────────────────────────────
            if (take['overlays'] != null)
              ...((take['overlays'] as Map<String, dynamic>).values.map((o) {
                final isText = o['isText'] == true;
                return Positioned(
                  left: o['dx'] as double,
                  top: o['dy'] as double,
                  child: Transform.scale(
                    scale: o['scale'] as double,
                    child: isText
                        ? Text(
                            o['content'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          )
                        : Text(
                            o['content'] as String,
                            style: const TextStyle(fontSize: 60),
                          ),
                  ),
                );
              })),

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
                              for (final v in _videoElements.values) {
                                v.muted = _isMuted;
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

                  // Progress bars
                  Positioned(
                    top: 52,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: List.generate(_takes.length, (i) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: i < _currentIndex
                                  ? const LinearProgressIndicator(
                                      value: 1.0,
                                      backgroundColor: Colors.white24,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(Colors.white),
                                      minHeight: 2,
                                    )
                                  : i == _currentIndex
                                      ? AnimatedBuilder(
                                          animation: _progressCtrl,
                                          builder: (_, __) => LinearProgressIndicator(
                                            value: _progressCtrl.value,
                                            backgroundColor: Colors.white24,
                                            valueColor:
                                                const AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                            minHeight: 2,
                                          ),
                                        )
                                      : const LinearProgressIndicator(
                                          value: 0.0,
                                          backgroundColor: Colors.white24,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(Colors.white),
                                          minHeight: 2,
                                        ),
                            ),
                          ),
                        );
                      }),
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
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.camera_alt_rounded,
                                    color: Colors.white70, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '${_takes.length} take back',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Sign in to record / Progress bar
                          Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Stack(
                              children: [
                                // Progress indicator
                                AnimatedBuilder(
                                  animation: _progressCtrl,
                                  builder: (_, __) => FractionallySizedBox(
                                    widthFactor: _progressCtrl.value,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            AppTheme.accentPurple,
                                            AppTheme.primaryBlue,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                    ),
                                  ),
                                ),
                                Center(
                                  child: GestureDetector(
                                    onTap: () {
                                      context.pop();
                                      context.push('/take/create');
                                    },
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.camera_alt_rounded,
                                            color: Colors.white70, size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Tap to record your take',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
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
