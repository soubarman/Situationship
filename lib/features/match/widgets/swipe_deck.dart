import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import 'swipe_card.dart';

class SwipeDeck extends ConsumerStatefulWidget {
  final List<UserModel> users;
  final double? deviceLat;
  final double? deviceLon;
  final Function(UserModel user)? onSwipeLeft;
  final Function(UserModel user)? onSwipeRight;

  const SwipeDeck({
    super.key,
    required this.users,
    this.deviceLat,
    this.deviceLon,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  @override
  ConsumerState<SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends ConsumerState<SwipeDeck> with SingleTickerProviderStateMixin {
  late AnimationController _swipeController;

  int _currentIndex = 0;
  Offset _dragOffset = Offset.zero;
  double _rotationAngle = 0.0;
  bool _isDragging = false;
  bool _isSuperLikeActive = false;
  
  // History stack for the premium Rewind feature!
  final List<int> _history = [];

  Offset _swipeStartOffset = Offset.zero;
  Offset _swipeEndOffset = Offset.zero;
  double _swipeStartAngle = 0.0;
  double _swipeEndAngle = 0.0;

  @override
  void initState() {
    super.initState();
    _swipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _swipeController.addListener(() {
      if (!_isDragging && _swipeController.isAnimating) {
        setState(() {
          final t = const Interval(0.0, 1.0, curve: Curves.easeOutBack).transform(_swipeController.value);
          _dragOffset = Offset.lerp(_swipeStartOffset, _swipeEndOffset, t)!;
          _rotationAngle = _swipeStartAngle + (_swipeEndAngle - _swipeStartAngle) * t;
        });
      }
    });

    _swipeController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finalizeSwipe(_dragOffset.dx);
      }
    });
  }

  @override
  void dispose() {
    _swipeController.dispose();
    super.dispose();
  }

  void _finalizeSwipe(double dxOffset) {
    if (dxOffset.abs() > 100) {
      // Completed swipe! Push current index to history, advance, and reset drag
      _history.add(_currentIndex);
      
      if (_currentIndex < widget.users.length) {
        final user = widget.users[_currentIndex];
        if (dxOffset > 0) {
          // Swipe Right (Like)
          widget.onSwipeRight?.call(user);

          // Trigger mock match screen 35% of the time!
          if (_isSuperLikeActive || Random().nextDouble() < 0.35) {
            _isSuperLikeActive = false; // Reset flag
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                context.push('/match/success', extra: {
                  'matchedUser': {
                    'name': user.name,
                    'avatarUrl': user.avatarUrl ?? 'https://i.pravatar.cc/400?u=${user.id}',
                    'chatId': 'chat_match_${user.id}',
                  }
                });
              }
            });
          }
        } else {
          // Swipe Left (Nope)
          widget.onSwipeLeft?.call(user);
        }
      }

      setState(() {
        _currentIndex++;
        _dragOffset = Offset.zero;
        _rotationAngle = 0.0;
        _swipeStartOffset = Offset.zero;
        _swipeEndOffset = Offset.zero;
        _swipeStartAngle = 0.0;
        _swipeEndAngle = 0.0;
      });
    } else {
      // Snapped back
      setState(() {
        _dragOffset = Offset.zero;
        _rotationAngle = 0.0;
        _swipeStartOffset = Offset.zero;
        _swipeEndOffset = Offset.zero;
        _swipeStartAngle = 0.0;
        _swipeEndAngle = 0.0;
      });
    }
    _swipeController.reset();
  }

  void _triggerSwipeButton(bool isLike) {
    if (_currentIndex >= widget.users.length || _swipeController.isAnimating) return;

    _swipeStartOffset = Offset.zero;
    _swipeEndOffset = Offset(isLike ? 450.0 : -450.0, 50.0);
    _swipeStartAngle = 0.0;
    _swipeEndAngle = isLike ? 0.35 : -0.35;

    _swipeController.reset();
    _swipeController.forward();
  }

  void _triggerRewind() {
    if (_history.isEmpty || _swipeController.isAnimating) return;

    final previousIndex = _history.removeLast();
    setState(() {
      _currentIndex = previousIndex;
      _isDragging = false;
      _dragOffset = const Offset(0, -400);
      _rotationAngle = -0.2;
    });

    _swipeStartOffset = const Offset(0, -400);
    _swipeEndOffset = Offset.zero;
    _swipeStartAngle = -0.2;
    _swipeEndAngle = 0.0;

    _swipeController.reset();
    _swipeController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_currentIndex >= widget.users.length) {
      return Center(
        child: _buildEmptyState(isDark),
      );
    }

    final currentCardUser = widget.users[_currentIndex];
    
    // Background card (next user)
    UserModel? nextCardUser;
    if (_currentIndex + 1 < widget.users.length) {
      nextCardUser = widget.users[_currentIndex + 1];
    }

    // Drag calculations
    final double screenWidth = MediaQuery.of(context).size.width;
    final double rotationAngle = _rotationAngle;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cards Stack
          SizedBox(
            height: 520,
            width: 350,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Next card behind the active one (scaled & styled for 3D stack effect)
                if (nextCardUser != null)
                  Positioned.fill(
                    child: Transform.scale(
                      scale: 0.93,
                      child: Transform.translate(
                        offset: const Offset(0, 15),
                        child: SwipeCard(
                          user: nextCardUser,
                          isBackground: true,
                          deviceLat: widget.deviceLat,
                          deviceLon: widget.deviceLon,
                        ),
                      ),
                    ),
                  ),

                // 2. Active top card (draggable with rotation and direction overlays)
                Positioned.fill(
                  child: GestureDetector(
                    onPanStart: (_) {
                      _swipeController.stop();
                      setState(() {
                        _isDragging = true;
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _dragOffset += details.delta;
                        _rotationAngle = (_dragOffset.dx / screenWidth) * 0.45;
                      });
                    },
                    onPanEnd: (details) {
                      setState(() {
                        _isDragging = false;
                      });

                      // Trigger swipe if drag threshold is met (120px)
                      if (_dragOffset.dx.abs() > 120) {
                        final double velocity = details.velocity.pixelsPerSecond.dx;
                        final double targetX = _dragOffset.dx > 0 
                            ? max(450.0, _dragOffset.dx + velocity * 0.2)
                            : min(-450.0, _dragOffset.dx + velocity * 0.2);

                        _swipeStartOffset = _dragOffset;
                        _swipeEndOffset = Offset(targetX, _dragOffset.dy);
                        _swipeStartAngle = _rotationAngle;
                        _swipeEndAngle = _dragOffset.dx > 0 ? 0.35 : -0.35;

                        _swipeController.reset();
                        _swipeController.forward();
                      } else {
                        // Snap back
                        _swipeStartOffset = _dragOffset;
                        _swipeEndOffset = Offset.zero;
                        _swipeStartAngle = _rotationAngle;
                        _swipeEndAngle = 0.0;

                        _swipeController.reset();
                        _swipeController.forward();
                      }
                    },
                    child: Transform.translate(
                      offset: _dragOffset,
                      child: Transform.rotate(
                        angle: rotationAngle,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SwipeCard(
                              user: currentCardUser,
                              isBackground: false,
                              deviceLat: widget.deviceLat,
                              deviceLon: widget.deviceLon,
                            ),

                            // Dynamic translucent swipe overlays
                            if (_dragOffset.dx > 20)
                              Positioned(
                                top: 40,
                                left: 30,
                                child: Transform.rotate(
                                  angle: -0.15,
                                  child: _buildSwipeDirectionTag(
                                    label: 'LIKE 💖',
                                    color: AppTheme.success,
                                  ),
                                ),
                              ),
                            if (_dragOffset.dx < -20)
                              Positioned(
                                top: 40,
                                right: 30,
                                child: Transform.rotate(
                                  angle: 0.15,
                                  child: _buildSwipeDirectionTag(
                                    label: 'NOPE 💔',
                                    color: AppTheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Frosted glass swiper guide banner to occupy the layout gap!
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.06),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.05 : 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Swipe Right to Vibe • Left to Skip',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white70 : AppTheme.textSecondary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Glassmorphic Action Buttons Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. Rewind Button
              _buildRoundActionButton(
                icon: Icons.undo_rounded,
                iconColor: Colors.amber,
                borderColor: Colors.amber.withOpacity(0.3),
                glowColor: Colors.amber,
                onTap: _triggerRewind,
                isEnabled: _history.isNotEmpty,
                isSmall: true,
              ),
              const SizedBox(width: 15),

              // 2. NOPE Button
              _buildRoundActionButton(
                icon: Icons.close_rounded,
                iconColor: AppTheme.error,
                borderColor: AppTheme.error.withOpacity(0.3),
                glowColor: AppTheme.error,
                onTap: () => _triggerSwipeButton(false),
                isEnabled: true,
              ),
              const SizedBox(width: 15),

              // 3. SUPER LIKE Button (Instant Match!)
              _buildRoundActionButton(
                icon: Icons.star_rounded,
                iconColor: AppTheme.primaryBlue,
                borderColor: AppTheme.primaryBlue.withOpacity(0.3),
                glowColor: AppTheme.primaryBlue,
                onTap: _triggerSuperLike,
                isEnabled: true,
                isMedium: true,
              ),
              const SizedBox(width: 15),

              // 4. ANONYMOUS CONFESSION Button
              _buildRoundActionButton(
                icon: Icons.lock_rounded,
                iconColor: AppTheme.accentPurple,
                borderColor: AppTheme.accentPurple.withOpacity(0.3),
                glowColor: AppTheme.accentPurple,
                onTap: _showConfessionBottomSheet,
                isEnabled: true,
                isMedium: true,
              ),
              const SizedBox(width: 15),

              // 5. LIKE Button
              _buildRoundActionButton(
                icon: Icons.favorite_rounded,
                iconColor: AppTheme.primaryGreen,
                borderColor: AppTheme.primaryGreen.withOpacity(0.3),
                glowColor: AppTheme.primaryGreen,
                onTap: () => _triggerSwipeButton(true),
                isEnabled: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeDirectionTag({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 16,
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildRoundActionButton({
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
    required Color glowColor,
    required VoidCallback onTap,
    required bool isEnabled,
    bool isSmall = false,
    bool isMedium = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double size = isSmall ? 46 : (isMedium ? 54 : 66);
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isEnabled ? 1.0 : 0.3,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.85),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.07),
              width: 1.5,
            ),
            boxShadow: [
              if (isEnabled) ...[
                BoxShadow(
                  color: glowColor.withOpacity(isDark ? 0.15 : 0.22),
                  blurRadius: 16,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.15 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ],
          ),
          child: Center(
            child: Icon(
              icon,
              color: iconColor,
              size: isSmall ? 20 : (isMedium ? 24 : 28),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      height: 520,
      width: 350,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.explore_rounded,
              color: AppTheme.primaryBlue,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Radar Cleared! 💫',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No more souls in your radius. Expand your filter range or check back later!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white70 : AppTheme.textSecondary,
              fontSize: 14.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          // Gradient reload button
          GestureDetector(
            onTap: () {
              setState(() {
                _currentIndex = 0;
                _history.clear();
              });
              ref.read(matchQueueProvider.notifier).reset();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Radar Scan 🚀',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  void _triggerSuperLike() {
    if (_currentIndex >= widget.users.length || _swipeController.isAnimating) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _isSuperLikeActive = true;
    });
    _triggerSwipeButton(true);
  }

  void _showConfessionBottomSheet() {
    if (_currentIndex >= widget.users.length) return;
    final targetUser = widget.users[_currentIndex];
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.lock_rounded, size: 20, color: AppTheme.accentPurple),
                const SizedBox(width: 8),
                Text(
                  'Confess Anonymously to ${targetUser.name}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 4,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: 'Type your secret confession here... ${targetUser.name} won\'t know who sent it! 🤫',
                hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Cost:', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                    const SizedBox(width: 6),
                    const Text('🪙 10', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.amber)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _sendAnonymousConfession(controller.text, targetUser, sheetContext),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Send Secret🔒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _sendAnonymousConfession(String text, UserModel targetUser, BuildContext sheetContext) async {
    final confession = text.trim();
    if (confession.isEmpty) return;

    final currentUser = ref.read(currentUserProvider);
    final displayedCoins = currentUser.coins;

    if (displayedCoins < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough coins! 🪙 Need 10 coins to confess.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    try {
      final db = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );
      final chatId = 'chat_${currentUser.id}_${targetUser.id}';

      // Ensure chat exists
      final chatDoc = await db.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) {
        await db.collection('chats').doc(chatId).set({
          'id': chatId,
          'participants': [currentUser.id, targetUser.id],
          'otherUserId': targetUser.id,
          'otherUserName': targetUser.name,
          'otherUserAvatar': targetUser.avatarUrl,
          'otherUserIsOnline': false,
          'lastMessage': 'Received an anonymous confession! 🤫🔒',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCount': 1,
          'isExpired': false,
          'status': 'requested',
          'requestSenderId': currentUser.id,
          'senderId': currentUser.id,
          'senderName': currentUser.name,
          'senderAvatar': currentUser.avatarUrl,
          'receiverId': targetUser.id,
          'receiverName': targetUser.name,
          'receiverAvatar': targetUser.avatarUrl,
          'isConfession': true,
          'revealStatus': null,
        });
      } else {
        await db.collection('chats').doc(chatId).update({
          'lastMessage': 'Received an anonymous confession! 🤫🔒',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'isConfession': true,
        });
      }

      // Add anonymous confession to message subcollection!
      final messageId = db.collection('chats').doc(chatId).collection('messages').doc().id;
      await db.collection('chats').doc(chatId).collection('messages').doc(messageId).set({
        'id': messageId,
        'senderId': 'anonymous',
        'text': '🤫 Locked Confession: "$confession"',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isRead': false,
        'type': 'text',
      });

      // Deduct coins
      await db.collection('users').doc(currentUser.id).update({
        'coins': FieldValue.increment(-10),
      });

      if (mounted) {
        Navigator.pop(sheetContext);
        _showConfessionSuccessDialog(targetUser.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Confession failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _showConfessionSuccessDialog(String targetName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: AppTheme.accentPurple.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentPurple.withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🤫 Confession Locked! 🤫', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 16),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.accentPurple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.lock_rounded, size: 36, color: AppTheme.accentPurple),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your confession has been delivered anonymously to $targetName\'s inbox!',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
