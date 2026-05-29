import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/user_model.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/models/post_model.dart';
import '../../feed/widgets/post_card.dart';
class UserDetailScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  int _activeTab = 0;
  double _sliderValue = 0.0;
  bool _isRequesting = false;
  bool _isConfessionActive = false;
  double _confessSwipeValue = 0.0;
  final _confessionController = TextEditingController();
  bool _isSendingConfession = false;
  int? _overriddenCoins;

  @override
  void dispose() {
    _confessionController.dispose();
    super.dispose();
  }

  void _handleFollow(UserModel currentUser, UserModel targetUser, bool isFollowing) async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(socialProvider.notifier).toggleFollow(
        currentUserId: currentUser.id,
        targetUserId: targetUser.id,
        isCurrentlyFollowing: isFollowing,
      );
      if (mounted) {
        _showSuccess(isFollowing ? 'Unfollowed ${targetUser.name}' : 'Now following ${targetUser.name}!');
      }
    } catch (e) {
      if (mounted) _showError('Could not update follow. Check Firebase Rules!');
    }
  }

  void _showGiftDialog(UserModel currentUser, UserModel targetUser) {
    final displayedCoins = _overriddenCoins ?? currentUser.coins;
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppTheme.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),
            Text('Send a Gift to ${targetUser.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('You have 🪙 $displayedCoins coins', style: const TextStyle(color: AppTheme.textSecondary)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildGiftOption(context, '🌹', 'Rose', 10, currentUser, targetUser),
                _buildGiftOption(context, '💍', 'Ring', 50, currentUser, targetUser),
                _buildGiftOption(context, '👑', 'Crown', 100, currentUser, targetUser),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildGiftOption(BuildContext context, String emoji, String name, int cost, UserModel currentUser, UserModel targetUser) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _sendGift(currentUser, targetUser, name, cost);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('🪙 $cost', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  void _sendGift(UserModel currentUser, UserModel targetUser, String giftName, int cost) async {
    final displayedCoins = _overriddenCoins ?? currentUser.coins;
    if (displayedCoins < cost) {
      _showError('Not enough coins for $giftName!');
      return;
    }

    // Instantly reflect coin deduction in UI!
    setState(() {
      _overriddenCoins = displayedCoins - cost;
    });

    try {
      final db = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );
      
      final batch = db.batch();
      batch.update(db.collection('users').doc(currentUser.id), {
        'coins': FieldValue.increment(-cost),
      });
      batch.update(db.collection('users').doc(targetUser.id), {
        'coins': FieldValue.increment(cost),
      });

      await batch.commit();

      // Send Notification!
      await sendNotification(
        userId: targetUser.id,
        senderId: currentUser.id,
        senderName: currentUser.name,
        senderAvatar: currentUser.avatarUrl,
        type: 'gift',
        title: 'New Gift received! 🎁',
        body: '${currentUser.name} sent you a $giftName!',
      );

      if (mounted) {
        _showSuccess('Sent $giftName to ${targetUser.name}! 🎁');
      }
    } catch (e) {
      // Revert if failed!
      setState(() {
        _overriddenCoins = displayedCoins;
      });
      if (mounted) _showError('Gift failed. Check Firebase Rules!');
    }
  }

  void _handleChatRequest(UserModel currentUser, UserModel targetUser) async {
    if (_isRequesting) return;

    final displayedCoins = _overriddenCoins ?? currentUser.coins;
    if (displayedCoins < 10) {
      _showError('Not enough coins! 🪙 Need 10 coins to chat.');
      setState(() => _sliderValue = 0);
      return;
    }

    // Instantly reflect coin deduction locally!
    setState(() {
      _overriddenCoins = displayedCoins - 10;
      _isRequesting = true;
    });

    try {
      final db = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );
      final chatId = 'chat_${currentUser.id}_${targetUser.id}';

      await db.collection('chats').doc(chatId).set({
        'id': chatId,
        'participants': [currentUser.id, targetUser.id],
        'otherUserId': targetUser.id,
        'otherUserName': targetUser.name,
        'otherUserAvatar': targetUser.avatarUrl,
        'otherUserIsOnline': false,
        'lastMessage': 'Chat request sent! 💫',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount': 0,
        'isExpired': false,
        'status': 'requested',
        'requestSenderId': currentUser.id,
        'senderId': currentUser.id,
        'senderName': currentUser.name,
        'senderAvatar': currentUser.avatarUrl,
        'receiverId': targetUser.id,
        'receiverName': targetUser.name,
        'receiverAvatar': targetUser.avatarUrl,
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Request timed out. Check your internet.'),
      );

      // Deduct coins
      await db.collection('users').doc(currentUser.id).update({
        'coins': FieldValue.increment(-10),
      }).timeout(const Duration(seconds: 5), onTimeout: () {});

      // Send Notification!
      await sendNotification(
        userId: targetUser.id,
        senderId: currentUser.id,
        senderName: currentUser.name,
        senderAvatar: currentUser.avatarUrl,
        type: 'chat_request',
        title: 'New Chat Request! 💖',
        body: '${currentUser.name} wants to chat with you!',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat request sent! 💫'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 3),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) context.go('/chats');
      }
    } catch (e) {
      // Revert if failed!
      setState(() {
        _overriddenCoins = displayedCoins;
      });
      if (mounted) _showError('Error: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
          _sliderValue = 0;
        });
      }
    }
  }

  void _cancelChatRequest(UserModel currentUser, ChatModel chat) async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Do you want to cancel this chat request? Your 10 coins will be refunded immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel Request', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final displayedCoins = _overriddenCoins ?? currentUser.coins;

    // Instantly refund coins in the UI!
    setState(() {
      _overriddenCoins = displayedCoins + 10;
    });

    try {
      final db = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );

      final batch = db.batch();
      batch.delete(db.collection('chats').doc(chat.id));
      batch.update(db.collection('users').doc(currentUser.id), {
        'coins': FieldValue.increment(10),
      });

      await batch.commit();
      _showSuccess('Request cancelled & 10 coins refunded immediately! 🪙');
    } catch (e) {
      // Revert if failed!
      setState(() {
        _overriddenCoins = displayedCoins;
      });
      _showError('Failed to cancel request: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _sendConfession(UserModel currentUser, UserModel targetUser) async {
    final confession = _confessionController.text.trim();
    if (confession.isEmpty) {
      _showError('Type something to confess first! 💭');
      return;
    }

    setState(() => _isSendingConfession = true);

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

      // Send Notification!
      await sendNotification(
        userId: targetUser.id,
        senderId: currentUser.id,
        senderName: 'Someone anonymous',
        senderAvatar: 'https://ui-avatars.com/api/?name=%3F&background=2C3E50&color=fff&rounded=true',
        type: 'confession',
        title: 'New Anonymous Confession! 🤫🔒',
        body: 'Someone left a locked confession on your profile!',
      );

      _confessionController.clear();
      setState(() {
        _isSendingConfession = false;
        _isConfessionActive = false;
        _confessSwipeValue = 0.0;
      });

      _showConfessionSuccessModal(targetUser.name);
    } catch (e) {
      setState(() => _isSendingConfession = false);
      _showError('Confession failed: $e');
    }
  }

  void _showConfessionSuccessModal(String targetName) {
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

  void _dismissConfession() {
    HapticFeedback.selectionClick();
    setState(() {
      _isConfessionActive = false;
      _confessSwipeValue = 0.0;
      _confessionController.clear();
    });
    _showSuccess('Confession dismissed. No messages were sent.');
  }

  Widget _buildConfessSwipeBar(bool isDark) {
    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.0 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded, size: 16, color: AppTheme.accentPurple.withOpacity(0.7)),
                const SizedBox(width: 8),
                const Text(
                  'Swipe right to confess... 🤫',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 56,
                thumbShape: _CustomConfessThumbShape(),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
              ),
              child: Slider(
                value: _confessSwipeValue,
                onChanged: (v) {
                  setState(() => _confessSwipeValue = v);
                  if (v > 0.9) {
                    HapticFeedback.heavyImpact();
                    setState(() {
                      _isConfessionActive = true;
                      _confessSwipeValue = 0.0;
                    });
                  }
                },
                onChangeEnd: (v) {
                  if (v < 0.9) {
                    setState(() => _confessSwipeValue = 0);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveConfessionComposer(UserModel currentUser, UserModel targetUser, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.accentPurple.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentPurple.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 18, color: AppTheme.accentPurple),
              const SizedBox(width: 8),
              const Text(
                'Anonymous Confession',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.accentPurple, fontSize: 14),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _dismissConfession,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confessionController,
            maxLines: 3,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: 'Type your secret confession here... Target won\'t know who sent it! 🤫',
              hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              counterText: '',
            ),
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                onPressed: _isSendingConfession ? null : () => _sendConfession(currentUser, targetUser),
                icon: _isSendingConfession 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Send anonymously 🔒', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPurple,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoodAndChipsSection(UserModel user, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.05 : 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                'Vibe & Mood',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Current mood statement card with premium left glow border
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark 
                    ? [Colors.white.withOpacity(0.06), Colors.white.withOpacity(0.02)]
                    : [const Color(0xFFECFDF5), const Color(0xFFF0FDF4)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white12 : const Color(0xFFD1FAE5),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Text('🔥', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT MOOD',
                        style: TextStyle(
                          color: const Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manifesting beautiful connections and late-night talks ✨',
                        style: TextStyle(
                          color: isDark ? Colors.white.withOpacity(0.9) : Colors.green.shade900,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Feeling tag & traits chips
          const Text(
            'Feeling Tags & Traits',
            style: TextStyle(fontWeight: FontWeight.w900, color: AppTheme.textSecondary, fontSize: 13, letterSpacing: -0.1),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFeelingTagChip('♓ Pisces', AppTheme.primaryBlue, isDark),
              _buildFeelingTagChip('💫 Dreamer', AppTheme.accentPink, isDark),
              ...user.interests.map((interest) => _buildFeelingTagChip(interest, Colors.teal, isDark)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeelingTagChip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(isDark ? 0.35 : 0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isDark ? 0 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? color.withOpacity(0.95) : color,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    );
  }

  Widget _buildBackgroundOrbs(bool isDark) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Orb 1: Pinkish-violet top left
          Positioned(
            top: -120,
            left: -120,
            width: 360,
            height: 360,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFCE7F3).withOpacity(isDark ? 0.08 : 0.5),
              ),
            ),
          ),
          // Orb 2: Indigo-blue middle right
          Positioned(
            top: 300,
            right: -100,
            width: 340,
            height: 340,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE0E7FF).withOpacity(isDark ? 0.06 : 0.45),
              ),
            ),
          ),
          // Orb 3: Violet bottom left
          Positioned(
            bottom: 120,
            left: -100,
            width: 320,
            height: 320,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEDE9FE).withOpacity(isDark ? 0.07 : 0.45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(otherUserProvider(widget.userId));
    final currentUser = ref.watch(currentUserProvider);
    final chats = ref.watch(chatsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return userAsync.when(
      data: (user) {
        if (user == null) {
          return const Scaffold(body: Center(child: Text('User not found 😢')));
        }

        final isFollowing = currentUser.following.contains(user.id);
        // Check if a chat already exists between these two users
        final existingChat = chats.where((c) =>
          c.participants.contains(currentUser.id) &&
          c.participants.contains(user.id)
        ).firstOrNull;

        return Scaffold(
          backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
          body: Stack(
            children: [
              _buildBackgroundOrbs(isDark),
              SafeArea(
                top: true,
                bottom: false,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildMainProfileImage(user, currentUser, isDark, context),
                      const SizedBox(height: 20),
                      _buildMoodAndChipsSection(user, isDark),
                      const SizedBox(height: 24),
                      _buildReactionButtons(isDark, currentUser, user, isFollowing),
                      const SizedBox(height: 24),
                      _isConfessionActive
                          ? _buildActiveConfessionComposer(currentUser, user, isDark)
                          : _buildConfessSwipeBar(isDark),
                      const SizedBox(height: 24),
                      _buildSlideToChat(currentUser, user, existingChat: existingChat),
                      const SizedBox(height: 24),
                      _buildActionButtons(currentUser, user, isFollowing, isDark),
                      const SizedBox(height: 24),
                      _buildTabbedSections(user, isDark),
                      const SizedBox(height: 24),
                      _buildBottomActions(isDark),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _buildCoinBadge(int coins, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            '$coins',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: Colors.amber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainProfileImage(UserModel user, UserModel currentUser, bool isDark, BuildContext context) {
    return Container(
      width: double.infinity,
      height: 440,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: Image.network(
              user.avatarUrl ?? 'https://i.pravatar.cc/600',
              fit: BoxFit.cover,
            ),
          ),
          // Gradient
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.4),
                  Colors.transparent,
                  Colors.black.withOpacity(0.9),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
          // Top Actions (Back Button & Coins)
          Positioned(
            top: 16,
            left: 16,
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🪙', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    '${_overriddenCoins ?? currentUser.coins}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.amber),
                  ),
                ],
              ),
            ),
          ),
          // Content
          Positioned(
            bottom: 32,
            left: 28,
            right: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: user.isOnline ? const Color(0xFF10B981) : Colors.amber,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (user.isOnline ? const Color(0xFF10B981) : Colors.amber).withOpacity(0.5),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      user.isOnline ? 'Active Now' : 'Last active 5m ago',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        shadows: const [
                          Shadow(color: Colors.black45, blurRadius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${user.name}, ${user.age}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildOverlayTag('🎨 Feeling creative', AppTheme.accentPink),
                    _buildOverlayTag('Creative', Colors.white.withOpacity(0.2)),
                    _buildOverlayTag('Introvert', Colors.white.withOpacity(0.2)),
                  ],
                ),
                const SizedBox(height: 20),
                _buildOverlayTag('📍 5 miles away', Colors.white.withOpacity(0.2), isLocation: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayTag(String text, Color color, {bool isLocation = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isLocation ? 16 : 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: isLocation ? Border.all(color: Colors.white.withOpacity(0.3)) : null,
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildReactionButtons(bool isDark, UserModel currentUser, UserModel targetUser, bool isFollowing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildReactionItem('🥶', 'Cold!', const Color(0xFFE0F2FE), isDark, () => _handleReaction('🥶', currentUser, targetUser, isFollowing)),
        const SizedBox(width: 20),
        _buildReactionItem('🤌', 'Chief Kiss', const Color(0xFFFEF3C7), isDark, () => _handleReaction('🤌', currentUser, targetUser, isFollowing), isLarge: true),
        const SizedBox(width: 20),
        _buildReactionItem('😘', 'Love!', const Color(0xFFFEE2E2), isDark, () => _handleReaction('😘', currentUser, targetUser, isFollowing)),
      ],
    );
  }

  Widget _buildReactionItem(String emoji, String label, Color bg, bool isDark, VoidCallback onTap, {bool isLarge = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          _buildCircleEmoji(emoji, bg, isDark, isLarge: isLarge),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  void _handleReaction(String emoji, UserModel currentUser, UserModel targetUser, bool isFollowing) async {
    try {
      final db = FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default',
      );
      final chatId = 'chat_${currentUser.id}_${targetUser.id}';

      // 1. Check if chat request already exists
      final chatDoc = await db.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) {
        // Create the chat request!
        await db.collection('chats').doc(chatId).set({
          'id': chatId,
          'participants': [currentUser.id, targetUser.id],
          'otherUserId': targetUser.id,
          'otherUserName': targetUser.name,
          'otherUserAvatar': targetUser.avatarUrl,
          'otherUserIsOnline': false,
          'lastMessage': 'Sent a reaction: $emoji ✨',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCount': 0,
          'isExpired': false,
          'status': 'requested',
          'requestSenderId': currentUser.id,
          'senderId': currentUser.id,
          'senderName': currentUser.name,
          'senderAvatar': currentUser.avatarUrl,
          'receiverId': targetUser.id,
          'receiverName': targetUser.name,
          'receiverAvatar': targetUser.avatarUrl,
        });
      } else {
        // Just update last message
        await db.collection('chats').doc(chatId).update({
          'lastMessage': 'Sent a reaction: $emoji ✨',
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
      }

      // 2. Add message to chat subcollection
      final messageId = db.collection('chats').doc(chatId).collection('messages').doc().id;
      await db.collection('chats').doc(chatId).collection('messages').doc(messageId).set({
        'id': messageId,
        'senderId': currentUser.id,
        'text': 'Sent a reaction: $emoji ✨',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isRead': false,
        'type': 'text',
      });

      // 3. Send Notification!
      await sendNotification(
        userId: targetUser.id,
        senderId: currentUser.id,
        senderName: currentUser.name,
        senderAvatar: currentUser.avatarUrl,
        type: 'reaction',
        title: 'New Reaction! 💖',
        body: '${currentUser.name} sent you a $emoji reaction!',
      );

      if (mounted) {
        _showReactionSuccess(emoji, targetUser.name);
      }
    } catch (e) {
      _showError('Reaction error: $e');
    }
  }

  void _showReactionSuccess(String emoji, String targetName) {
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
              color: AppTheme.primaryBlue.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('✨ Reaction Sent! ✨', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 16),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 36)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'You sent a "$emoji" reaction to $targetName!',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Awesome', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleEmoji(String emoji, Color bg, bool isDark, {bool isLarge = false}) {
    final size = isLarge ? 54.0 : 44.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? bg.withOpacity(0.1) : bg,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          emoji,
          style: TextStyle(fontSize: isLarge ? 24 : 18),
        ),
      ),
    );
  }

  Widget _buildSlideToChat(UserModel currentUser, UserModel targetUser, {ChatModel? existingChat}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (existingChat != null) {
      if (existingChat.status == 'accepted') {
        return _buildStatusBanner('Chat Request Accepted! 💬', AppTheme.primaryBlue, isDark, () {
          context.go('/chats/${existingChat.id}', extra: {
            'otherUserId': targetUser.id,
            'name': targetUser.name,
            'avatarUrl': targetUser.avatarUrl,
            'isOnline': targetUser.isOnline,
            'isConfession': existingChat.isConfession,
          });
        });
      } else if (existingChat.status == 'requested') {
        if (existingChat.requestSenderId == currentUser.id) {
          return _buildStatusBanner('Request Pending ⏳ (Tap to Cancel)', Colors.amber, isDark, () => _cancelChatRequest(currentUser, existingChat));
        } else {
          return _buildStatusBanner('They requested to chat! 💖', Colors.pinkAccent, isDark, () {
            context.go('/chats'); // Go to chats page to accept
          });
        }
      }
    }

    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.06),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.0 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Slide to Request Chat',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(width: 8),
                Text('🪙 10', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.amber, fontSize: 14)),
              ],
            ),
          ),
          Positioned.fill(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 56,
                thumbShape: _CustomThumbShape(),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
              ),
              child: Slider(
                value: _sliderValue,
                onChanged: _isRequesting ? null : (v) {
                  setState(() => _sliderValue = v);
                  if (v > 0.9) {
                    _handleChatRequest(currentUser, targetUser);
                  }
                },
                onChangeEnd: (v) {
                  if (v < 0.9) {
                    setState(() => _sliderValue = 0);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(String text, Color color, bool isDark, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withOpacity(isDark ? 0.35 : 0.2), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(isDark ? 0.1 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isDark ? color.withOpacity(0.9) : color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(UserModel currentUser, UserModel targetUser, bool isFollowing, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildMainActionButton(
              label: isFollowing ? 'Following' : 'Follow',
              icon: isFollowing ? Icons.check_circle_rounded : Icons.person_add_rounded,
              onTap: () => _handleFollow(currentUser, targetUser, isFollowing),
              isActive: isFollowing,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: _buildMainActionButton(
              label: 'Gift',
              icon: Icons.card_giftcard_rounded,
              onTap: () => _showGiftDialog(currentUser, targetUser),
              isAccent: true,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
    bool isAccent = false,
    required bool isDark,
  }) {
    // Elegant dynamic decoration based on states
    final hasGradient = !isActive; // Follow and Gift have beautiful gradients by default!
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: hasGradient
              ? (isAccent
                  ? const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : AppTheme.primaryGradient)
              : null,
          color: !hasGradient
              ? (isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0))
              : null,
          border: Border.all(
            color: isActive
                ? (isDark ? Colors.white24 : Colors.black12)
                : (isAccent ? const Color(0xFFF59E0B).withOpacity(0.3) : AppTheme.primaryBlue.withOpacity(0.3)),
            width: 1.5,
          ),
          boxShadow: [
            if (hasGradient)
              BoxShadow(
                color: (isAccent ? const Color(0xFFF59E0B) : AppTheme.primaryBlue).withOpacity(0.24),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isActive
                  ? (isDark ? Colors.white70 : AppTheme.textSecondary)
                  : Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? (isDark ? Colors.white.withOpacity(0.9) : AppTheme.textSecondary)
                    : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required IconData icon,
    required String label,
    required String subLabel,
    required VoidCallback onTap,
    bool isAccent = false,
    bool isActive = false,
    required bool isDark,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 60,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primaryBlue : (isDark ? AppTheme.darkCard : Colors.white),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isAccent ? const Color(0xFFFFB300) : (isActive ? Colors.transparent : const Color(0xFFE2E8F0)),
                width: 2,
              ),
              boxShadow: [
                if (isActive)
                  BoxShadow(
                    color: AppTheme.primaryBlue.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon, 
                  size: 20, 
                  color: isActive ? Colors.white : (isAccent ? const Color(0xFFFFB300) : (isDark ? Colors.white70 : Colors.black)),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w900, 
                    fontSize: 15,
                    color: isActive ? Colors.white : (isDark ? Colors.white : Colors.black),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subLabel,
          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildAboutCard(UserModel user, bool isDark) {
    return Container(
      key: const ValueKey(0),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.05 : 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'About ${user.name}',
                style: const TextStyle(
                  color: AppTheme.accentPink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              const Text('✨', style: TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            user.bio ?? 'Exploring art, seeking genuine vibes, and always open to deep conversations. Let\'s see where our situationship takes us! ☕🔮',
            style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF334155),
              fontSize: 14.5,
              height: 1.55,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabbedSections(UserModel user, bool isDark) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          height: 52,
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.02),
              width: 1,
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                _buildTabHeader(0, '👤 About', isDark),
                _buildTabHeader(1, '🧬 Compatibility', isDark),
                _buildTabHeader(2, '🎯 Looking For', isDark),
                _buildTabHeader(3, '✍️ Posts', isDark),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _activeTab == 0
              ? _buildAboutCard(user, isDark)
              : _activeTab == 1
                  ? _buildCompatibilityCard(user, isDark)
                  : _activeTab == 2
                      ? _buildLookingForCard(user, isDark)
                      : _buildPostsList(user, isDark),
        ),
      ],
    );
  }

  Widget _buildTabHeader(int index, String title, bool isDark) {
    final isActive = _activeTab == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeTab = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? AppTheme.primaryBlue.withOpacity(0.2) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isActive && !isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: isActive
                  ? AppTheme.primaryBlue
                  : (isDark ? Colors.white54 : AppTheme.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompatibilityCard(UserModel user, bool isDark) {
    return Container(
      key: const ValueKey(1),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.05 : 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧬', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'Compatibility Vibe',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '92% Match',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildCompatibilitySectionHeader('Things in Common [Matches: 4]', Icons.people_outline_rounded, Colors.blue),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCompatibilityTag('🎨 Art lovers', Colors.blue, isDark),
              _buildCompatibilityTag('🌙 Night owls', Colors.blue, isDark),
              _buildCompatibilityTag('☕ Coffee addicts', Colors.blue, isDark),
              _buildCompatibilityTag('🎵 Indie music', Colors.blue, isDark),
            ],
          ),
          const SizedBox(height: 20),
          _buildCompatibilitySectionHeader('Both Active Between', Icons.access_time_rounded, Colors.orange),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCompatibilityTag('⏰ 10PM - 2AM', Colors.orange, isDark),
              _buildCompatibilityTag('📅 Weekends', Colors.orange, isDark),
            ],
          ),
          const SizedBox(height: 20),
          _buildCompatibilitySectionHeader('Both Love', Icons.favorite_border_rounded, Colors.pink),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildCompatibilityTag('🍔 Late night food', Colors.pink, isDark),
              _buildCompatibilityTag('🚗 Drives', Colors.pink, isDark),
              _buildCompatibilityTag('🎬 Films', Colors.pink, isDark),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, thickness: 0.5),
          const SizedBox(height: 20),
          Text(
            'Compatibility Breakdown',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 16),
          _buildCompatibilityProgressRow('Energy', 0.85, Colors.purple),
          const SizedBox(height: 12),
          _buildCompatibilityProgressRow('Communication', 0.92, Colors.teal),
          const SizedBox(height: 12),
          _buildCompatibilityProgressRow('Lifestyle', 0.78, Colors.amber),
        ],
      ),
    );
  }

  Widget _buildCompatibilitySectionHeader(String label, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textSecondary, fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _buildCompatibilityTag(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(isDark ? 0.3 : 0.15)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? color.withOpacity(0.9) : color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildCompatibilityProgressRow(String label, double value, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
            ),
            const Spacer(),
            Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildLookingForCard(UserModel user, bool isDark) {
    return Container(
      key: const ValueKey(2),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.65),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.05 : 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎯', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                'Looking For',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.accentPink.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.accentPink.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite_rounded, color: AppTheme.accentPink, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Long-term relationship open to short-term connection. Seeking someone to explore food spots, art galleries, and share playlist discoveries. ☕🎵',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4, color: AppTheme.accentPink),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsList(UserModel user, bool isDark) {
    final streamPosts = ref.watch(postsStreamProvider).asData?.value ?? [];
    final localPosts = ref.watch(postsProvider);
    
    final List<PostModel> posts = [];
    final Set<String> seenIds = {};
    for (var p in [...localPosts, ...streamPosts]) {
      if (!seenIds.contains(p.id) && p.userId == user.id) {
        posts.add(p);
        seenIds.add(p.id);
      }
    }
    posts.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    if (posts.isEmpty) {
      return Container(
        key: const ValueKey(2),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: const Center(
          child: Text('No posts yet 📸', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
        ),
      );
    }

    return Container(
      key: const ValueKey(2),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          // Assuming we have access to PostCard here. Since we are in UserDetailScreen, we might need to import it.
          return PostCard(
            post: post,
            onLike: () => ref.read(postsProvider.notifier).toggleLike(post.id, ref.read(currentUserProvider).id),
          );
        },
      ),
    );
  }

  Widget _buildBottomActions(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildTextAction(Icons.share_rounded, 'Share Profile', isDark),
          const SizedBox(width: 24),
          Container(width: 1, height: 18, color: isDark ? Colors.white10 : Colors.black12),
          const SizedBox(width: 24),
          _buildTextAction(Icons.flag_rounded, 'Report', isDark),
        ],
      ),
    );
  }

  Widget _buildTextAction(IconData icon, String label, bool isDark) {
    return GestureDetector(
      onTap: () => _showSuccess('$label coming soon! ✨'),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isDark ? Colors.white38 : Colors.black45),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black45, 
              fontSize: 14, 
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(44, 44);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw white circle thumb (radius 22)
    canvas.drawCircle(center, 22, paint);

    // Draw icon inside
    const icon = Icons.send_rounded;
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: icon.fontFamily,
          color: AppTheme.accentPink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
  }
}

class _CustomConfessThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(44, 44);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw white circle thumb (radius 22)
    canvas.drawCircle(center, 22, paint);

    // Draw lock open icon inside
    const icon = Icons.lock_open_rounded;
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: icon.fontFamily,
          color: AppTheme.accentPurple,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
  }
}
