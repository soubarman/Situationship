import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';

// ─── Vibe helpers (same as discover_tab) ─────────────────────────────────────

const _vibeLabels = [
  'Soft Chaos',
  'Golden Hour',
  'Quiet Storm',
  'Warm Chaos',
  'Soft Rebel',
  'Night Owl',
];
const _vibeColors = [
  Color(0xFFB8A9FF),
  Color(0xFFFBBF24),
  Color(0xFF6ECBF5),
  Color(0xFFFF8EC8),
  Color(0xFF7EEECB),
  Color(0xFFF87171),
];

String _vibeFor(UserModel u) =>
    _vibeLabels[u.id.hashCode.abs() % _vibeLabels.length];
Color _vibeColorFor(UserModel u) =>
    _vibeColors[u.id.hashCode.abs() % _vibeColors.length];

// ─────────────────────────────────────────────────────────────────────────────

class SoulModeTab extends ConsumerStatefulWidget {
  final List<UserModel> users;
  final Future<void> Function(UserModel liked, {UserModel? pairedWith}) onLike;
  final void Function(UserModel user) onSkip;
  /// Called from parent when undo fires, so we can step the card back.
  final VoidCallback? onUndoRequested;

  const SoulModeTab({
    super.key,
    required this.users,
    required this.onLike,
    required this.onSkip,
    this.onUndoRequested,
  });

  @override
  ConsumerState<SoulModeTab> createState() => SoulModeTabState();
}

class SoulModeTabState extends ConsumerState<SoulModeTab>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _isRevealed = false;
  String? _lastReaction; // 'too_hot' | 'crushing' | 'dm_me'
  bool _isSending = false;
  // Track whether we're in the 1.4s window after a reaction (before _advance)
  bool _pendingAdvance = false;

  late AnimationController _revealController;
  late Animation<double> _revealAnim;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _revealAnim = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  void stepBack() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _isRevealed = false;
        _lastReaction = null;
        _pendingAdvance = false;
      });
      _revealController.reset();
    }
  }

  UserModel? get _current =>
      _currentIndex < widget.users.length ? widget.users[_currentIndex] : null;

  void _advance() {
    if (!mounted) return;
    setState(() {
      _currentIndex++;
      _isRevealed = false;
      _lastReaction = null;
      _pendingAdvance = false;
    });
    _revealController.reset();
  }

  Future<void> _react(String reaction) async {
    final target = _current;
    if (target == null || _isSending) return;
    HapticFeedback.heavyImpact();

    setState(() {
      _isSending = true;
      _lastReaction = reaction;
      _isRevealed = true;
      _pendingAdvance = true;
    });
    _revealController.forward();

    final currentUser = ref.read(currentUserProvider);
    if (currentUser.id.isEmpty) return;

    try {
      // 1. Send Firestore notification to the target user
      final (title, body) = _notifContent(reaction, currentUser.name);
      await sendNotification(
        userId: target.id,
        senderId: currentUser.id,
        senderName: currentUser.name,
        senderAvatar: currentUser.avatarUrl,
        type: 'soul_reaction',
        title: title,
        body: body,
      );

      // 2. Like if it's "too hot" or "crushing" — delegate to parent which handles follow + match detection
      if (reaction == 'too_hot' || reaction == 'crushing') {
        await widget.onLike(target);
      }

      // 3. If "dm_me" → open anonymous confession sheet
      if (reaction == 'dm_me' && mounted) {
        _showConfessionSheet(target);
      }
    } catch (e) {
      debugPrint('[SoulMode] reaction error: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }

    // Advance after reveal delay (unless it was dm_me which has its own sheet)
    if (reaction != 'dm_me') {
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted && _pendingAdvance) _advance();
      });
    }
  }

  (String, String) _notifContent(String reaction, String senderName) {
    return switch (reaction) {
      'too_hot' => (
          'Someone thinks you\'re too hot 🔥',
          'Someone reacted to your vibe on Soul Mode',
        ),
      'crushing' => (
          'Someone is crushing on you 😍',
          'Someone reacted to your vibe on Soul Mode',
        ),
      'dm_me' => (
          'Someone wants to DM you 💬',
          'Someone sent you a secret message on Soul Mode',
        ),
      _ => ('New Soul Mode reaction', 'Someone reacted to your vibe'),
    };
  }

  void _skip() {
    final target = _current;
    if (target == null) return;
    HapticFeedback.selectionClick();
    widget.onSkip(target);
    _advance();
  }

  @override
  Widget build(BuildContext context) {
    final target = _current;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (target == null) {
      return _buildEmptyState(isDark);
    }

    final currentUser = ref.watch(currentUserProvider);
    final vibe = _vibeFor(target);
    final vibeColor = _vibeColorFor(target);
    final matchPct = _matchPercent(currentUser, target);

    return Column(
      children: [
        // ── Subtitle ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
          child: Row(
            children: [
              Text(
                'Feel first · face unlocks when you react',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.5)
                      : AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // Match % badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.08),
                      width: 0.8),
                ),
                child: Text(
                  '$matchPct%',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Soul Card ──────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: const Color(0xFF13152A),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Revealed or blurred photo
                    AnimatedBuilder(
                      animation: _revealAnim,
                      builder: (context, _) {
                        final blurVal = (14 * (1 - _revealAnim.value)).clamp(0.0, 14.0);
                        return ImageFiltered(
                          imageFilter:
                              ImageFilter.blur(sigmaX: blurVal, sigmaY: blurVal),
                          child: CachedNetworkImage(
                            imageUrl: target.avatarUrl ??
                                'https://i.pravatar.cc/400?u=${target.id}',
                            fit: BoxFit.cover,
                            memCacheWidth: 800,
                          ),
                        );
                      },
                    ),

                    // Dark overlay
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Lock icon — anchored to top half so it never overlaps the bottom content
                    if (!_isRevealed)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 160, // reserves space for bottom profile content
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.lock_rounded,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Face locked',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'React below to unlock',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Content at bottom
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Vibe + age row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: vibeColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: vibeColor.withValues(alpha: 0.4),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  vibe,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: vibeColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isRevealed ? '${target.name}, ${target.age}' : '???  ${target.age}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // Bio quote card
                          Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "I'LL FALL FOR YOU IF...",
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: vibeColor.withValues(alpha: 0.85),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _quoteText(target),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                    fontStyle: FontStyle.italic,
                                    height: 1.35,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Interest chips
                          if (target.interests.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: target.interests
                                  .take(3)
                                  .map((i) => _InterestChip(label: i))
                                  .toList(),
                            ),
                        ],
                      ),
                    ),

                    // Reaction overlay flash
                    if (_isRevealed && _lastReaction != null)
                      AnimatedBuilder(
                        animation: _revealAnim,
                        builder: (context, _) => Positioned(
                          top: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Opacity(
                              opacity:
                                  (1 - _revealAnim.value).clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: 0.8 + _revealAnim.value * 0.5,
                                child: Text(
                                  _reactionEmoji(_lastReaction!),
                                  style: const TextStyle(fontSize: 56),
                                ),
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
        ),

        const SizedBox(height: 16),

        // ── Reaction Buttons ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ReactionButton(
                emoji: '🥵',
                label: 'too hot',
                color: const Color(0xFFF87171),
                isLoading: _isSending && _lastReaction == 'too_hot',
                onTap: () => _react('too_hot'),
              ),
              _ReactionButton(
                emoji: '😍',
                label: 'crushing',
                color: const Color(0xFFFF8EC8),
                isLoading: _isSending && _lastReaction == 'crushing',
                onTap: () => _react('crushing'),
              ),
              _ReactionButton(
                emoji: '😊',
                label: 'Dm me',
                color: const Color(0xFF6ECBF5),
                isLoading: _isSending && _lastReaction == 'dm_me',
                onTap: () => _react('dm_me'),
              ),
            ],
          ),
        ),

        // ── Skip link ──────────────────────────────────────────────────────
        TextButton(
          onPressed: _skip,
          child: Text(
            'skip',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  void _showConfessionSheet(UserModel targetUser) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
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
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.lock_rounded,
                    size: 20, color: AppTheme.accentPurple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Send a secret DM via Soul Mode',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 4,
              maxLength: 200,
              decoration: InputDecoration(
                hintText:
                    'Type your anonymous message... they won\'t know who sent it! 🤫',
                hintStyle: TextStyle(
                    color: isDark ? Colors.white30 : Colors.black38,
                    fontSize: 13),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
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
                const Row(
                  children: [
                    Text('Cost:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary)),
                    SizedBox(width: 6),
                    Text('🪙 10',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.amber)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      _sendConfession(controller.text, targetUser, sheetContext),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Send Secret 🔒',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).then((_) => _advance());
  }

  Future<void> _sendConfession(
      String text, UserModel targetUser, BuildContext sheetContext) async {
    final confession = text.trim();
    if (confession.isEmpty) return;

    final currentUser = ref.read(currentUserProvider);
    if (currentUser.coins < 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not enough coins! 🪙 Need 10 coins to confess.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return;
    }

    try {
      final db = firestoreProvider;
      final chatId = 'chat_${currentUser.id}_${targetUser.id}';

      final chatDoc = await db.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) {
        await db.collection('chats').doc(chatId).set({
          'id': chatId,
          'participants': [currentUser.id, targetUser.id],
          'otherUserId': targetUser.id,
          'otherUserName': targetUser.name,
          'otherUserAvatar': targetUser.avatarUrl,
          'otherUserIsOnline': false,
          'lastMessage': 'Received an anonymous Soul Mode DM! 🤫🔒',
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
          'lastMessage': 'Received an anonymous Soul Mode DM! 🤫🔒',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'isConfession': true,
        });
      }

      final messageId =
          db.collection('chats').doc(chatId).collection('messages').doc().id;
      await db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .set({
        'id': messageId,
        'senderId': 'anonymous',
        'text': '🤫 Soul Mode DM: "$confession"',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isRead': false,
        'type': 'text',
      });

      await db.collection('users').doc(currentUser.id).update({
        'coins': FieldValue.increment(-10),
      });

      if (mounted) Navigator.pop(sheetContext);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Send failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppTheme.accentPurple.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_open_rounded,
                color: AppTheme.accentPurple, size: 48),
          ),
          const SizedBox(height: 20),
          Text(
            'All souls unlocked! ✨',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back soon for new faces.',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.5)
                  : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  String _reactionEmoji(String reaction) {
    return switch (reaction) {
      'too_hot' => '🥵',
      'crushing' => '😍',
      'dm_me' => '💬',
      _ => '✨',
    };
  }
}

// ─── Reaction Button ─────────────────────────────────────────────────────────

class _ReactionButton extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.emoji,
    required this.label,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: isLoading
                ? Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: color,
                      ),
                    ),
                  )
                : Center(
                    child: Text(emoji,
                        style: const TextStyle(fontSize: 30)),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Interest Chip ────────────────────────────────────────────────────────────

class _InterestChip extends StatelessWidget {
  final String label;
  const _InterestChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.18), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

// ─── Match % helper ────────────────────────────────────────────────────────────

int _matchPercent(UserModel me, UserModel other) {
  final mySet = me.interests.toSet();
  final theirSet = other.interests.toSet();
  final shared = mySet.intersection(theirSet).length;
  final total = (mySet.union(theirSet).length).clamp(1, 999);
  final base = 55 + (other.id.hashCode.abs() % 25);
  final bonus = ((shared / total) * 30).round();
  return (base + bonus).clamp(55, 99);
}

// ─── Bio quote helper ─────────────────────────────────────────────────────────

String _quoteText(UserModel u) {
  final bio = u.bio?.trim();
  if (bio != null && bio.isNotEmpty) return '"$bio"';
  if (u.interests.isNotEmpty) {
    return '"${u.interests.take(2).join(' & ')}"';
  }
  return '"Honestly just vibing rn ✨"';
}
