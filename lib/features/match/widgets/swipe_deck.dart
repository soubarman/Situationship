import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/services/like_service.dart';
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
      duration: const Duration(milliseconds: 280),
    );

    _swipeController.addListener(() {
      if (!_isDragging && _swipeController.isAnimating) {
        setState(() {
          final t = const Interval(0.0, 1.0, curve: Curves.easeOutCubic).transform(_swipeController.value);
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
      _history.add(_currentIndex);
      
      if (_currentIndex < widget.users.length) {
        final user = widget.users[_currentIndex];
        if (dxOffset > 0) {
          widget.onSwipeRight?.call(user);
        } else {
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
    _swipeEndOffset = Offset(isLike ? 450.0 : -450.0, 40.0);
    _swipeStartAngle = 0.0;
    _swipeEndAngle = isLike ? 0.30 : -0.30;

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
      _rotationAngle = -0.15;
    });

    _swipeStartOffset = const Offset(0, -400);
    _swipeEndOffset = Offset.zero;
    _swipeStartAngle = -0.15;
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

    final double screenWidth = MediaQuery.of(context).size.width;
    final double rotationAngle = _rotationAngle;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxH = constraints.maxHeight;
        final double cardH = (maxH - 110).clamp(280.0, 520.0);
        final double cardW = (cardH * 0.72).clamp(240.0, 380.0);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Cards Stack
            Expanded(
              child: Center(
                child: SizedBox(
                  height: cardH,
                  width: cardW,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1. Next card behind the active one
                      if (nextCardUser != null)
                        Positioned.fill(
                          child: Transform.scale(
                            scale: 0.94,
                            child: Transform.translate(
                              offset: const Offset(0, 16),
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
                              _rotationAngle = (_dragOffset.dx / screenWidth) * 0.40;
                            });
                          },
                          onPanEnd: (details) {
                            setState(() {
                              _isDragging = false;
                            });

                            if (_dragOffset.dy < -110 && _dragOffset.dx.abs() < 80) {
                              _triggerSuperLike();
                            } else if (_dragOffset.dx.abs() > 110) {
                              final double velocity = details.velocity.pixelsPerSecond.dx;
                              final double targetX = _dragOffset.dx > 0 
                                  ? max(450.0, _dragOffset.dx + velocity * 0.2)
                                  : min(-450.0, _dragOffset.dx + velocity * 0.2);

                              _swipeStartOffset = _dragOffset;
                              _swipeEndOffset = Offset(targetX, _dragOffset.dy);
                              _swipeStartAngle = _rotationAngle;
                              _swipeEndAngle = _dragOffset.dx > 0 ? 0.30 : -0.30;

                              _swipeController.reset();
                              _swipeController.forward();
                            } else {
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

                                  // Directional Overlay Badges
                                  if (_dragOffset.dx > 20)
                                    Positioned(
                                      top: 36,
                                      left: 24,
                                      child: Transform.rotate(
                                        angle: -0.15,
                                        child: _buildSwipeDirectionTag(
                                          label: 'LIKE 💖',
                                          color: AppTheme.primaryPink,
                                        ),
                                      ),
                                    ),
                                  if (_dragOffset.dx < -20)
                                    Positioned(
                                      top: 36,
                                      right: 24,
                                      child: Transform.rotate(
                                        angle: 0.15,
                                        child: _buildSwipeDirectionTag(
                                          label: 'PASS ✕',
                                          color: DesignTokens.error,
                                        ),
                                      ),
                                    ),
                                  if (_dragOffset.dy < -40 && _dragOffset.dx.abs() < 80)
                                    Positioned(
                                      top: 40,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: _buildSwipeDirectionTag(
                                          label: 'SUPER LIKE ★',
                                          color: DesignTokens.purple,
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
              ),
            ),

            const SizedBox(height: 14),

            // Precision Tactile Action Deck
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Rewind Button
                  _buildDeckButton(
                    icon: Icons.replay_rounded,
                    iconColor: Colors.amber,
                    backgroundColor: DesignTokens.obsidianCard,
                    borderColor: Colors.amber.withValues(alpha: 0.25),
                    size: 44,
                    onTap: _triggerRewind,
                    isEnabled: _history.isNotEmpty,
                    badgeCount: _history.isNotEmpty ? _history.length : null,
                  ),
                  const SizedBox(width: 14),

                  // 2. NOPE (Pass) Button
                  _buildDeckButton(
                    icon: Icons.close_rounded,
                    iconColor: DesignTokens.error,
                    backgroundColor: DesignTokens.obsidianCard,
                    borderColor: DesignTokens.error.withValues(alpha: 0.3),
                    size: 54,
                    onTap: () => _triggerSwipeButton(false),
                    isEnabled: true,
                  ),
                  const SizedBox(width: 14),

                  // 3. SUPER LIKE Button
                  _buildDeckButton(
                    icon: Icons.star_rounded,
                    iconColor: DesignTokens.purple,
                    backgroundColor: DesignTokens.obsidianCard,
                    borderColor: DesignTokens.purple.withValues(alpha: 0.35),
                    size: 50,
                    onTap: _triggerSuperLike,
                    isEnabled: true,
                  ),
                  const SizedBox(width: 14),

                  // 4. LIKE Button (Hero Button with vibrant glow)
                  _buildDeckButton(
                    icon: Icons.favorite_rounded,
                    iconColor: Colors.white,
                    gradient: AppTheme.primaryGradient,
                    glowColor: AppTheme.primaryPink,
                    size: 64,
                    onTap: () => _triggerSwipeButton(true),
                    isEnabled: true,
                  ),
                  const SizedBox(width: 14),

                  // 5. CONFESSION / SECRET CHAT Button
                  _buildDeckButton(
                    icon: Icons.lock_outline_rounded,
                    iconColor: AppTheme.primaryBlue,
                    backgroundColor: DesignTokens.obsidianCard,
                    borderColor: AppTheme.primaryBlue.withValues(alpha: 0.3),
                    size: 50,
                    onTap: _showConfessionBottomSheet,
                    isEnabled: true,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeckButton({
    required IconData icon,
    required Color iconColor,
    Color? backgroundColor,
    Color? borderColor,
    Gradient? gradient,
    Color? glowColor,
    required double size,
    required VoidCallback onTap,
    required bool isEnabled,
    int? badgeCount,
  }) {
    return GestureDetector(
      onTap: isEnabled
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: isEnabled ? 1.0 : 0.35,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gradient == null ? (backgroundColor ?? DesignTokens.obsidianCard) : null,
                gradient: gradient,
                border: borderColor != null ? Border.all(color: borderColor, width: 1.2) : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                  if (glowColor != null)
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: iconColor,
                  size: size * 0.46,
                ),
              ),
            ),
            if (badgeCount != null && badgeCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeDirectionTag({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: DesignTokens.obsidianBase.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        border: Border.all(color: color, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 16,
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      height: 480,
      width: 340,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: DesignTokens.obsidianCard,
        borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
        boxShadow: DesignTokens.cardShadow(),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.radar_rounded,
              color: AppTheme.primaryBlue,
              size: 44,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Radar Cleared! 💫',
            style: DesignTokens.headingMedium(color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            'You\'ve seen everyone nearby. Expand your radius filter or check back later!',
            textAlign: TextAlign.center,
            style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary),
          ),
          const SizedBox(height: 28),
          // Gradient reload button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _currentIndex = 0;
                _history.clear();
              });
              ref.read(matchQueueProvider.notifier).reset();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryPink.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Scan Again 🚀',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
        decoration: BoxDecoration(
          color: DesignTokens.obsidianElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.lock_rounded, size: 20, color: DesignTokens.purple),
                const SizedBox(width: 8),
                Text(
                  'Confess to ${targetUser.name}',
                  style: DesignTokens.titleMedium(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 4,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: 'Type your anonymous secret confession... ${targetUser.name} won\'t know who sent it! 🤫',
                hintStyle: DesignTokens.bodyMedium(color: DesignTokens.textMuted),
                filled: true,
                fillColor: DesignTokens.obsidianInput,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              style: DesignTokens.bodyMedium(color: Colors.white),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('Cost:', style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary)),
                    const SizedBox(width: 6),
                    Text('🪙 10', style: DesignTokens.labelBold(color: Colors.amber)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _sendAnonymousConfession(controller.text, targetUser, sheetContext),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Send Secret🔒'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DesignTokens.purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusFull)),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
      final chatId = LikeService.getCanonicalChatId(currentUser.id, targetUser.id);

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
        backgroundColor: DesignTokens.obsidianModal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusXl)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: DesignTokens.purple.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.lock_rounded, size: 32, color: DesignTokens.purple),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Confession Locked! 🤫',
              style: DesignTokens.headingMedium(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Your confession has been delivered anonymously to $targetName\'s inbox!',
              textAlign: TextAlign.center,
              style: DesignTokens.bodyMedium(color: DesignTokens.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: DesignTokens.purple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusFull)),
              ),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}
