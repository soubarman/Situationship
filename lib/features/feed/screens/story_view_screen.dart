import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';

class StoryViewScreen extends ConsumerStatefulWidget {
  final String userId;
  final String? initialName;
  final String? initialAvatar;

  const StoryViewScreen({
    super.key,
    required this.userId,
    this.initialName,
    this.initialAvatar,
  });

  @override
  ConsumerState<StoryViewScreen> createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends ConsumerState<StoryViewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  int _currentIndex = 0;
  List<Map<String, dynamic>> _stories = [];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _nextStory();
        }
      });

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStories());
  }

  void _loadStories() {
    final allStories = ref.read(storiesStreamProvider).asData?.value ?? [];
    final userStories =
        allStories.where((s) => s['userId'] == widget.userId).toList();

    if (userStories.isEmpty) {
      if (mounted) context.pop();
      return;
    }

    setState(() => _stories = userStories);
    _startTimer();
  }

  void _startTimer() {
    _progressController.reset();
    _progressController.forward();
  }

  void _nextStory() {
    if (_currentIndex < _stories.length - 1) {
      setState(() => _currentIndex++);
      _startTimer();
    } else {
      if (mounted) context.pop();
    }
  }

  void _prevStory() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _startTimer();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (_stories.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                widget.initialName ?? 'Loading...',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    final story = _stories[_currentIndex];
    final userName = story['userName'] ?? widget.initialName ?? 'User';
    final userAvatar = story['userAvatar'] as String?;
    final imageUrl = story['imageUrl'] as String?;
    final caption = story['caption'] as String? ?? '';
    final createdAt = story['createdAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(story['createdAt'] as int)
        : DateTime.now();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          if (details.localPosition.dx < size.width / 2) {
            _prevStory();
          } else {
            _nextStory();
          }
        },
        onLongPressStart: (_) => _progressController.stop(),
        onLongPressEnd: (_) => _progressController.forward(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background image ──────────────────────────────────────────
            if (imageUrl != null)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: Icon(Icons.broken_image_rounded,
                        color: Colors.white38, size: 80),
                  ),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryBlue, AppTheme.accentPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Text('✨', style: TextStyle(fontSize: 80)),
                ),
              ),

            // ── Top gradient overlay ──────────────────────────────────────
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xBB000000), Colors.transparent],
                  ),
                ),
              ),
            ),

            // ── Bottom gradient overlay ───────────────────────────────────
            if (caption.isNotEmpty)
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 160,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xBB000000), Colors.transparent],
                    ),
                  ),
                ),
              ),

            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Progress bars ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Row(
                      children: List.generate(_stories.length, (i) {
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: i < _currentIndex
                                  // Completed segments — full white bar
                                  ? const LinearProgressIndicator(
                                      value: 1.0,
                                      backgroundColor: Colors.white30,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                      minHeight: 3,
                                    )
                                  : i == _currentIndex
                                      // Active segment — animated
                                      ? AnimatedBuilder(
                                          animation: _progressController,
                                          builder: (_, __) =>
                                              LinearProgressIndicator(
                                            value: _progressController.value,
                                            backgroundColor: Colors.white30,
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                    Color>(Colors.white),
                                            minHeight: 3,
                                          ),
                                        )
                                      // Future segments — empty
                                      : const LinearProgressIndicator(
                                          value: 0.0,
                                          backgroundColor: Colors.white30,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                          minHeight: 3,
                                        ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Header ───────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 2),
                            image: userAvatar != null
                                ? DecorationImage(
                                    image: NetworkImage(userAvatar),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: userAvatar == null
                              ? const Center(
                                  child: Text('😊',
                                      style: TextStyle(fontSize: 20)))
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                _timeAgo(createdAt),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 28),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // ── Caption ──────────────────────────────────────────────
                  if (caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Text(
                        caption,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 8)
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
}
