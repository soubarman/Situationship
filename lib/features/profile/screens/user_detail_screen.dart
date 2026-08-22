import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/models/user_model.dart';
import '../../../core/models/chat_model.dart';
import '../../../core/models/post_model.dart';
import '../../feed/widgets/post_card.dart';
import '../../../core/utils/location_helper.dart';
import '../../verification/presentation/widgets/s_badge_widget.dart';
import '../../../shared/widgets/background_orbs.dart';
import '../../wallet/widgets/coin_gate_sheet.dart';
import '../../../core/providers/access_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../shared/widgets/profile_choice_sheet.dart';

class UserDetailScreen extends ConsumerStatefulWidget {
  final String userId;
  const UserDetailScreen({super.key, required this.userId});

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen>
    with TickerProviderStateMixin {
  int _activeTab = 0;
  double _sliderValue = 0.0;
  bool _isRequesting = false;
  bool _isConfessionActive = false;
  double _confessSwipeValue = 0.0;
  final _confessionController = TextEditingController();
  bool _isSendingConfession = false;
  int? _overriddenCoins;

  double? _deviceLat;
  double? _deviceLon;
  bool _hasAskedChoice = false;

  // Animation controllers
  late final AnimationController _shimmerAnim;
  late final AnimationController _storyRingAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _fetchDeviceLocation();

    // Shimmer/pulse for confess bar
    _shimmerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    // Spinning ring for Takes thumbnails
    _storyRingAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Pulse for lock icon
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _shimmerAnim, curve: Curves.easeInOut),
    );
  }

  bool _viewRecorded = false;

  Future<void> _recordProfileView(UserModel currentUser) async {
    try {


      if (currentUser.id == widget.userId) return; // don't record own view
      
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final viewId = '${currentUser.id}_${widget.userId}';
      
      await db.collection('profile_views').doc(viewId).set({
        'id': viewId,
        'viewerId': currentUser.id,
        'viewerName': currentUser.name,
        'viewerAvatar': currentUser.avatarUrl,
        'targetId': widget.userId,
        'viewedAt': timestamp,
      });
      
      debugPrint('✅ SUCCESS: Profile view recorded for target ${widget.userId}');
    } catch (e) {
      debugPrint('❌ Failed to record profile view: $e');
    }
  }

  Future<void> _fetchDeviceLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 4),
      );

      if (mounted) {
        setState(() {
          _deviceLat = position.latitude;
          _deviceLon = position.longitude;
        });
      }
    } catch (e) {
      debugPrint('Failed to get location in details: $e');
    }
  }

  @override
  void dispose() {
    _shimmerAnim.dispose();
    _storyRingAnim.dispose();
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
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
      
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
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
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
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');

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
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
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

  Widget _buildConfessSwipeBar(UserModel currentUser, UserModel targetUser, bool isDark) {
    final progress = _confessSwipeValue;
    final trackBg = isDark ? const Color(0xFF1A1033) : const Color(0xFFF0E6FF);
    const glowColor = Color(0xFF9333EA);
    final labelColor = isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF5B21B6);
    final isIdle = progress < 0.05;

    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (context, child) {
        final t = _shimmerAnim.value;
        final pulse = 0.5 + 0.5 * (1 - (2 * t - 1).abs());
        final pulseScale = 0.92 + 0.16 * pulse;
        final glowOpacity = (isDark ? 0.25 : 0.12) + 0.2 * pulse;
        final shimmerPos = -0.4 + t * 1.8;

        return Container(
          height: 62,
          decoration: BoxDecoration(
            color: trackBg,
            borderRadius: BorderRadius.circular(31),
            border: Border.all(
              color: glowColor.withOpacity(isDark ? 0.55 : 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(glowOpacity),
                blurRadius: 22,
                spreadRadius: isIdle ? 2 : 0,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(31),
            child: Stack(
              children: [
                // Drag-fill track
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            glowColor.withOpacity(0.38),
                            glowColor.withOpacity(0.15),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Sweeping shimmer (idle only)
                if (isIdle)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment(shimmerPos * 2 - 1, 0),
                      widthFactor: 0.28,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              (isDark ? Colors.white : glowColor).withOpacity(0.13),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // Label: pulsing lock + text + chevrons
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: isIdle ? pulseScale : 1.0,
                        child: Icon(
                          progress > 0.6
                              ? Icons.lock_open_rounded
                              : Icons.lock_outline_rounded,
                          size: 18,
                          color: labelColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        progress > 0.15
                            ? (progress > 0.6 ? 'Almost there... 🔥' : 'Keep going...')
                            : 'Swipe right to confess 🤫',
                        style: TextStyle(
                          color: labelColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (isIdle) ...[const SizedBox(width: 8), _AnimatedChevrons(color: labelColor, animValue: t)],
                    ],
                  ),
                ),

                // Invisible slider on top
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 62,
                      thumbShape: _CustomConfessThumbShape(isDark: isDark),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _confessSwipeValue,
                      onChanged: (v) {
                        setState(() => _confessSwipeValue = v);
                        if (v > 0.88) {
                          HapticFeedback.heavyImpact();
                          setState(() => _confessSwipeValue = 0.0);
                          _openConfessionBottomSheet(currentUser, targetUser, isDark);
                        }
                      },
                      onChangeEnd: (v) {
                        if (v < 0.88) setState(() => _confessSwipeValue = 0);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openConfessionBottomSheet(UserModel currentUser, UserModel targetUser, bool isDark) {
    _confessionController.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final sheetBg = isDark ? const Color(0xFF0F0C1D) : Colors.white;
            final textCol = isDark ? Colors.white : const Color(0xFF1A1033);
            final hintCol = isDark ? Colors.white.withOpacity(0.4) : const Color(0xFF8B7CB8);
            final inputBg = isDark ? const Color(0xFF1B1730) : const Color(0xFFF7F3FF);
            final borderCol = isDark ? const Color(0xFF3D2E6B) : const Color(0xFFE0D4FF);
            final charCount = _confessionController.text.length;
            final charColor = charCount > 170
                ? const Color(0xFFEF4444)
                : charCount > 130
                    ? const Color(0xFFF59E0B)
                    : hintCol;

            return Container(
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9333EA).withOpacity(0.25),
                    blurRadius: 40,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Gradient banner header
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF3B0764), const Color(0xFF1E0A3C)]
                            : [const Color(0xFFF5F0FF), const Color(0xFFEDE9FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    padding: const EdgeInsets.fromLTRB(22, 14, 12, 18),
                    child: Column(
                      children: [
                        // Drag handle
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white30 : const Color(0xFFB39DDB),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF9333EA), Color(0xFFC084FC)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF9333EA).withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.lock_rounded, size: 24, color: Colors.white),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Anonymous Confession',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: isDark ? Colors.white : const Color(0xFF3B0764),
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${targetUser.name} won\'t know who sent this 🤫',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? const Color(0xFFC084FC) : const Color(0xFF7C3AED),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.07),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black54),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Body
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20, 20, 20,
                      MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Text field
                        Container(
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: borderCol, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _confessionController,
                                autofocus: true,
                                maxLines: 5,
                                maxLength: 200,
                                onChanged: (_) => setModalState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'Write your secret for ${targetUser.name}... 💭',
                                  hintStyle: TextStyle(color: hintCol, fontSize: 14.5, height: 1.5),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                  counterText: '',
                                ),
                                style: TextStyle(
                                  fontSize: 15.5,
                                  height: 1.55,
                                  color: textCol,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '✍️ Be honest, it\'s anonymous',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: hintCol,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '$charCount/200',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: charColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Send button
                        GestureDetector(
                          onTap: _isSendingConfession
                              ? null
                              : () {
                                  final text = _confessionController.text.trim();
                                  if (text.isEmpty) {
                                    _showError('Type something to confess first! 💭');
                                    return;
                                  }
                                  setModalState(() {});
                                  Navigator.pop(context);
                                  _sendConfession(currentUser, targetUser);
                                },
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: _isSendingConfession
                                  ? null
                                  : const LinearGradient(
                                      colors: [Color(0xFF7C3AED), Color(0xFFC084FC)],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                              color: _isSendingConfession
                                  ? (isDark ? Colors.white12 : Colors.black12)
                                  : null,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: _isSendingConfession
                                  ? []
                                  : [
                                      BoxShadow(
                                        color: const Color(0xFF9333EA).withOpacity(0.45),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isSendingConfession)
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  const Icon(Icons.lock_rounded, size: 20, color: Colors.white),
                                const SizedBox(width: 10),
                                Text(
                                  _isSendingConfession ? 'Sending...' : 'Send Anonymously 🔒',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Colors.white,
                                    letterSpacing: -0.2,
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
            );
          },
        );
      },
    );
  }



  Widget _buildMoodAndChipsSection(UserModel user, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.55),
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

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    if (!_viewRecorded && currentUser.id.isNotEmpty && currentUser.id != '1') {
      _viewRecorded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recordProfileView(currentUser);
      });
    }
    final userAsync = ref.watch(otherUserProvider(widget.userId));
    final chats = ref.watch(chatsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return userAsync.when(
      data: (user) {
        if (user == null) {
          return const Scaffold(body: Center(child: Text('User not found 😢')));
        }

        final isFollowing = currentUser.following.contains(user.id);
        final existingChat = chats.where((c) =>
          c.participants.contains(currentUser.id) &&
          c.participants.contains(user.id)
        ).firstOrNull;

        return Scaffold(
          backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF8FAFC),
          body: Stack(
            children: [
              const BackgroundOrbs(),
              // Main scrollable content
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // Full-bleed hero (no margin, edge-to-edge)
                  SliverToBoxAdapter(
                    child: _buildHeroSection(user, currentUser, isDark, context),
                  ),

                  // Info card that slides up over the photo, containing all bottom sections
                  SliverToBoxAdapter(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.45),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                            border: Border(
                              top: BorderSide(
                                color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.8),
                                width: 1.2,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildInfoCard(user, currentUser, existingChat, isFollowing, isDark),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                child: _buildConfessSwipeBar(currentUser, user, isDark),
                              ),

                              _buildAboutMeChips(user, isDark),
                              _buildTabbedSections(user, currentUser, isDark),
                              const SizedBox(height: 130),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Floating reaction bar at bottom
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: _buildFloatingReactions(currentUser, user, isFollowing, isDark),
              ),
            ],
          ),
        );
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  int _calculateCompatibilityScore(UserModel currentUser, UserModel user) {
    int baseScore = 55;
    final u1Int = currentUser.interests.map((e) => e.toLowerCase()).toSet();
    final u2Int = user.interests.map((e) => e.toLowerCase()).toSet();
    final common = u1Int.intersection(u2Int).toList();
    
    // Hash determinism
    int combinedHash = (currentUser.id.hashCode ^ user.id.hashCode).abs();
    
    baseScore += (combinedHash % 25);
    baseScore += (common.length * 5);
    if (baseScore > 98) baseScore = 98;
    return baseScore;
  }

  // ─── HERO PHOTO (full bleed) ────────────────────────────────────────────────
  Widget _buildHeroSection(UserModel user, UserModel currentUser, bool isDark, BuildContext context) {
    final distance = LocationHelper.getDistanceKm(
      lat1: _deviceLat, lon1: _deviceLon,
      loc1: currentUser.location, loc2: user.location,
      id1: currentUser.id, id2: user.id,
    );
    final screenH = MediaQuery.of(context).size.height;

    int compatibilityScore = _calculateCompatibilityScore(currentUser, user);

    return SizedBox(
      height: screenH * 0.64,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Photo
          Image.network(
            user.avatarUrl ?? 'https://i.pravatar.cc/600',
            fit: BoxFit.cover,
          ),

          // Bottom scrim
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.25),
                    Colors.black.withOpacity(0.88),
                  ],
                  stops: const [0.0, 0.45, 0.7, 1.0],
                ),
              ),
            ),
          ),

          // Top bar: back + options
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildGlassIconBtn(Icons.arrow_back_ios_new_rounded, () => context.pop()),
                    if (user.id == currentUser.id)
                      GestureDetector(
                        onTap: () => ProfileChoiceSheet.show(context, currentUser, isDark),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF9333EA), Color(0xFFFF3CAC)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF9333EA).withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.remove_red_eye_rounded, size: 14, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Preview Mode 👁️',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.swap_vert_rounded, size: 15, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    PopupMenuButton<String>(
                      color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      offset: const Offset(0, 50),
                      onSelected: (value) {
                        if (value == 'switch') {
                          ProfileChoiceSheet.show(context, currentUser, isDark);
                        } else if (value == 'share') {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Profile link copied! ✨'), behavior: SnackBarBehavior.floating),
                          );
                        } else if (value == 'report') {
                          _showReportUserSheet(context, isDark);
                        }
                      },
                      itemBuilder: (context) => [
                        if (user.id == currentUser.id)
                          PopupMenuItem(
                            value: 'switch',
                            child: Row(
                              children: [
                                const Icon(Icons.tune_rounded, size: 20, color: Color(0xFF9333EA)),
                                const SizedBox(width: 12),
                                Text('Profile Options', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share_rounded, size: 20, color: isDark ? Colors.white : Colors.black87),
                              const SizedBox(width: 12),
                              Text('Share Profile', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'report',
                          child: Row(
                            children: [
                              const Icon(Icons.flag_rounded, size: 20, color: Colors.redAccent),
                              const SizedBox(width: 12),
                              const Text('Report User', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                      child: _buildGlassIconBtn(Icons.more_vert_rounded, null),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom overlay: name, status, mini stats
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Badges (moved here)
                  Row(
                    children: [
                      _buildGlassPill('🤝 $compatibilityScore% Match', accent: const Color(0xFFB06EF5)),
                      const SizedBox(width: 8),
                      _buildGlassPill('📍 $distance km', accent: const Color(0xFF4FC3F7)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  
                  // Online indicator
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: user.isOnline ? const Color(0xFF22C55E) : Colors.grey.shade500,
                          shape: BoxShape.circle,
                          boxShadow: user.isOnline ? [
                            BoxShadow(color: const Color(0xFF22C55E).withOpacity(0.7), blurRadius: 6, spreadRadius: 2),
                          ] : [],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        user.isOnline ? 'Active now' : 'Offline',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Name + age
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '${user.name}, ${user.age}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            height: 1.1,
                            shadows: [Shadow(color: Colors.black38, blurRadius: 12)],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isVerified) ...[
                        const SizedBox(width: 8),
                        const SBadgeWidget(size: 26),
                      ],
                    ],
                  ),
                  if ((user.location ?? '').isNotEmpty) ...
                  [
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          user.location ?? '',
                          style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── INFO CARD (slides up over photo) ───────────────────────────────────────
  Widget _buildInfoCard(UserModel user, UserModel currentUser, ChatModel? existingChat, bool isFollowing, bool isDark) {
    final chatLabel = existingChat?.status == 'accepted'
        ? 'Open Chat'
        : (existingChat?.status == 'requested' ? 'Pending…' : 'Message');

    return Container(
      margin: const EdgeInsets.only(top: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),

          // Stats row (followers, posts, mutual)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                _buildStatCell('${user.followers.length}', 'Followers', isDark),
                _buildStatDivider(isDark),
                _buildStatCell('${user.following.length}', 'Following', isDark),
                _buildStatDivider(isDark),
                _buildStatCell('${user.coins}', 'Aura 🪙', isDark),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Message button
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () {
                      if (existingChat != null && existingChat.status == 'accepted') {
                        context.pushNamed('chat-detail', pathParameters: {
                          'chatId': existingChat.id
                        }, extra: {
                          'otherUserId': user.id,
                          'name': user.name,
                          'avatarUrl': user.avatarUrl,
                          'isOnline': user.isOnline,
                          'isConfession': existingChat.isConfession,
                        });
                      } else if (existingChat != null && existingChat.status == 'requested') {
                        if (existingChat.requestSenderId == currentUser.id) _cancelChatRequest(currentUser, existingChat);
                      } else {
                        _handleChatRequest(currentUser, user);
                      }
                    },
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB06EF5), Color(0xFF7B2FBE)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(27),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF9B5DE5).withOpacity(0.45),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(chatLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Follow button
                GestureDetector(
                  onTap: () => _handleFollow(currentUser, user, isFollowing),
                  child: Container(
                    height: 54,
                    width: 54,
                    decoration: BoxDecoration(
                      color: isFollowing
                          ? (isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF1F0FF))
                          : const Color(0xFF9B5DE5).withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF9B5DE5).withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      isFollowing ? Icons.person_remove_rounded : Icons.person_add_alt_1_rounded,
                      color: isFollowing ? const Color(0xFF9B5DE5) : const Color(0xFF9B5DE5),
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Gift button
                GestureDetector(
                  onTap: () => _showGiftDialog(currentUser, user),
                  child: Container(
                    height: 54,
                    width: 54,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.amber.withOpacity(0.1) : Colors.amber.withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber.withOpacity(0.4), width: 1.5),
                    ),
                    child: const Center(
                      child: Text('🎁', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // User's active Takes section (appears above Bio)
          _buildUserTakesSection(user, isDark),

          // Bio + Phone in a unified section card
          if ((user.bio ?? '').isNotEmpty || (user.phoneNumber != null && user.phoneNumber!.isNotEmpty))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : const Color(0xFFE8E0FF),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.12 : 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((user.bio ?? '').isNotEmpty) ...
                    [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 3,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF9B5DE5), Color(0xFFFF5069)],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'About',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              user.bio!,
                              style: TextStyle(
                                fontSize: 15,
                                color: isDark ? Colors.white.withOpacity(0.88) : Colors.black.withOpacity(0.78),
                                height: 1.6,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (user.phoneNumber != null && user.phoneNumber!.trim().isNotEmpty)
                        Divider(
                          height: 1,
                          color: isDark ? Colors.white.withOpacity(0.07) : const Color(0xFFEDE8FF),
                          indent: 18,
                          endIndent: 18,
                        ),
                    ],
                    // Phone Section
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      child: _buildPhoneSection(user, currentUser, isDark),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildPhoneSection(UserModel targetUser, UserModel currentUser, bool isDark) {
    if (targetUser.phoneNumber == null || targetUser.phoneNumber!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final isSelf = targetUser.id == currentUser.id;
    final allowUnlock = targetUser.isPhonePublic; // repurposed from public to allow unlock
    final unlockKey = '${targetUser.id}_${targetUser.phoneVisibilityVersion}';
    final hasUnlocked = currentUser.unlockedUserPhones.contains(unlockKey) || 
                        (targetUser.phoneVisibilityVersion == 0 && currentUser.unlockedUserPhones.contains(targetUser.id));
    
    if (!isSelf && !allowUnlock && !hasUnlocked) {
      return const SizedBox.shrink();
    }

    final displayedPhone = (isSelf || hasUnlocked) ? targetUser.phoneNumber! : '••••• •••••';
        
    // Render as a flat row inside the parent card (no extra container)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(isDark ? 0.18 : 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_rounded, color: AppTheme.primaryBlue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PHONE NUMBER',
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  displayedPhone,
                  style: TextStyle(
                    color: isDark ? Colors.white.withOpacity(0.87) : Colors.black87,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          if (isSelf || hasUnlocked)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: targetUser.phoneNumber ?? ''));
                _showSuccess('Phone number copied!');
              },
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.copy_rounded, color: AppTheme.primaryBlue, size: 18),
              ),
            )
          else
            GestureDetector(
              onTap: () => _unlockPhone(targetUser, currentUser),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF6366F1)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_open_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Unlock',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
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

  Future<void> _unlockPhone(UserModel targetUser, UserModel currentUser) async {
    final allowed = await showCoinGate(context, ref, 'phone_unlock');
    if (!allowed) return;

    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
      
      final isFree = currentUser.hasActiveSubscription && currentUser.phoneUnlocksRemaining > 0;
      
      await db.runTransaction((tx) async {
        final userRef = db.collection('users').doc(currentUser.id);
        final snap = await tx.get(userRef);
        if (!snap.exists) return;
        
        final unlocked = List<String>.from(snap.data()?['unlockedUserPhones'] ?? []);
        final unlockKey = '${targetUser.id}_${targetUser.phoneVisibilityVersion}';
        if (!unlocked.contains(unlockKey)) {
          unlocked.add(unlockKey);
        }
        
        final updates = <String, dynamic>{
          'unlockedUserPhones': unlocked,
        };
        
        if (isFree) {
          updates['phoneUnlocksUsed'] = FieldValue.increment(1);
        }
        
        tx.update(userRef, updates);
      });
      
      _showSuccess('Phone number unlocked successfully! 🎉');
    } catch (e) {
      _showError('Unlock failed: $e');
    }
  }

  Widget _buildStatCell(String value, String label, bool isDark) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : Colors.black38,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider(bool isDark) {
    return Container(
      width: 1,
      height: 36,
      color: isDark ? Colors.white12 : Colors.black12,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildGlassPill(String text, {Color? accent}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.42),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accent?.withOpacity(0.6) ?? Colors.white.withOpacity(0.3),
              width: 1.2,
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassIconBtn(IconData icon, VoidCallback? onTap) {
    Widget child = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.38),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.22), width: 1.2),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
    
    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }

  Widget _buildAboutMeChips(UserModel user, bool isDark) {
    final chips = [
      '👩 Woman', '♋ Cancer', '🐱 Cat lover', '🍷 Social drinker',
      ...user.interests.take(5),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel('About Me', isDark),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: chips.map((c) => _buildPillChip(c, isDark)).toList(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label, bool isDark) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 18,
          margin: const EdgeInsets.only(right: 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF9B5DE5), Color(0xFFFF5069)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildPillChip(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.07) : const Color(0xFFF4F0FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFD9CCFF),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? Colors.white.withOpacity(0.88) : const Color(0xFF5E35B1),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildFloatingReactions(UserModel currentUser, UserModel user, bool isFollowing, bool isDark) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(56),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(56),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.9),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildReactionBtn('🥶', 'Cold!', const Color(0xFF6C3FC5), () => _handleReaction('🥶', currentUser, user, isFollowing), isDark),
                const SizedBox(width: 24),
                _buildReactionBtn('🤌', 'Chef Kiss', const Color(0xFFFF2A5F), () => _handleReaction('🤌', currentUser, user, isFollowing), isDark, isMain: true),
                const SizedBox(width: 24),
                _buildReactionBtn('😘', 'Love!', const Color(0xFFE91E8C), () => _handleReaction('😘', currentUser, user, isFollowing), isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReactionBtn(String emoji, String label, Color color, VoidCallback onTap, bool isDark, {bool isMain = false}) {
    final size = isMain ? 68.0 : 52.0;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: isMain ? LinearGradient(
                colors: [color.withOpacity(1), color.withRed(255)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ) : null,
              color: isMain ? null : color.withOpacity(isDark ? 0.25 : 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.5), width: 1.5),
              boxShadow: isMain ? [
                BoxShadow(color: color.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 6)),
              ] : [],
            ),
            child: Center(
              child: Text(emoji, style: TextStyle(fontSize: isMain ? 30 : 22)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
  void _handleReaction(String emoji, UserModel currentUser, UserModel targetUser, bool isFollowing) async {
    try {
      final db = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default');
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
        await db.collection('chats').doc(chatId).update({
          'lastMessage': 'Sent a reaction: $emoji ✨',
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
      }

      final messageId = db.collection('chats').doc(chatId).collection('messages').doc().id;
      await db.collection('chats').doc(chatId).collection('messages').doc(messageId).set({
        'id': messageId,
        'senderId': currentUser.id,
        'text': 'Sent a reaction: $emoji ✨',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isRead': false,
        'type': 'text',
      });

      if (mounted) {
        _showReactionSuccess(emoji, targetUser.name);
      }
    } catch (e) {
      if (mounted) _showError('Reaction error: $e');
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

  Widget _buildTabbedSections(UserModel user, UserModel currentUser, bool isDark) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          height: 52,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
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
                _buildTabHeader(0, '🧬 Compatibility', isDark),
                _buildTabHeader(1, '🎯 Looking For', isDark),
                _buildTabHeader(2, '✍️ Posts', isDark),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _activeTab == 0
              ? _buildCompatibilityCard(user, currentUser, isDark)
              : _activeTab == 1
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

  Widget _buildCompatibilityCard(UserModel user, UserModel currentUser, bool isDark) {
    // Advanced algorithm based on hash + interests
    int baseScore = _calculateCompatibilityScore(currentUser, user);
    final u1Int = currentUser.interests.map((e) => e.toLowerCase()).toSet();
    final u2Int = user.interests.map((e) => e.toLowerCase()).toSet();
    final common = u1Int.intersection(u2Int).toList();
    
    // Hash determinism
    int combinedHash = (currentUser.id.hashCode ^ user.id.hashCode).abs();
    
    // Sub-scores
    double energyScore = ((baseScore + (combinedHash % 15)) % 100) / 100.0;
    if (energyScore < 0.6) energyScore += 0.3;
    if (energyScore > 0.98) energyScore = 0.98;
    
    double commScore = ((baseScore + ((combinedHash >> 2) % 20)) % 100) / 100.0;
    if (commScore < 0.6) commScore += 0.3;
    if (commScore > 0.98) commScore = 0.98;
    
    double lifeScore = ((baseScore - ((combinedHash >> 3) % 15)) % 100) / 100.0;
    if (lifeScore < 0.6) lifeScore += 0.3;
    if (lifeScore > 0.98) lifeScore = 0.98;
    
    // Both active between logic
    final activeHours = [
      ['⏰ 10PM - 2AM', '📅 Weekends'],
      ['⏰ 6AM - 9AM', '📅 Weekdays'],
      ['⏰ 8PM - 11PM', '📅 Every day'],
      ['⏰ 1PM - 4PM', '📅 Weekends'],
      ['⏰ Late Night', '📅 Irregular'],
    ];
    final activeChoice = activeHours[combinedHash % activeHours.length];
    
    // Both love logic
    final loveChoices = [
      ['🍔 Late night food', '🚗 Drives', '🎬 Films'],
      ['☕ Coffee', '📚 Reading', '🌲 Hiking'],
      ['🍷 Wine', '🍝 Pasta', '🎨 Art'],
      ['🎮 Gaming', '🍕 Pizza', '🎧 Music'],
      ['✈️ Travel', '📸 Photography', '🌅 Sunsets'],
    ];
    final loveChoice = loveChoices[(combinedHash >> 1) % loveChoices.length];
    
    // Ensure we have some fake things in common if array is empty
    List<String> commonInterestsToDisplay = common.isNotEmpty 
        ? common.map((e) => '✨ ${e.substring(0, 1).toUpperCase()}${e.substring(1)}').toList()
        : ['🎵 Music', '🍔 Foodies', '✈️ Travel'];

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
                child: Text(
                  '$baseScore% Match',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildCompatibilitySectionHeader('Things in Common [Matches: ${commonInterestsToDisplay.length}]', Icons.people_outline_rounded, Colors.blue),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: commonInterestsToDisplay.map((e) => _buildCompatibilityTag(e, Colors.blue, isDark)).toList(),
          ),
          const SizedBox(height: 20),
          _buildCompatibilitySectionHeader('Both Active Between', Icons.access_time_rounded, Colors.orange),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: activeChoice.map((e) => _buildCompatibilityTag(e, Colors.orange, isDark)).toList(),
          ),
          const SizedBox(height: 20),
          _buildCompatibilitySectionHeader('Both Love', Icons.favorite_border_rounded, Colors.pink),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: loveChoice.map((e) => _buildCompatibilityTag(e, Colors.pink, isDark)).toList(),
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
          _buildCompatibilityProgressRow('Energy', energyScore, Colors.purple),
          const SizedBox(height: 12),
          _buildCompatibilityProgressRow('Communication', commScore, Colors.teal),
          const SizedBox(height: 12),
          _buildCompatibilityProgressRow('Lifestyle', lifeScore, Colors.amber),
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
    final streamPosts = ref.watch(postsPaginationProvider).asData?.value ?? [];
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
          _buildTextAction(Icons.flag_rounded, 'Report', isDark, onTap: () => _showReportUserSheet(context, isDark)),
        ],
      ),
    );
  }

  Widget _buildTextAction(IconData icon, String label, bool isDark, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap ?? () => _showSuccess('$label coming soon! ✨'),
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

  // ── Report User Bottom Sheet ─────────────────────────────────────
  void _showReportUserSheet(BuildContext context, bool isDark) {
    final reasons = [
      'Fake profile',
      'Harassment or bullying',
      'Spam',
      'Inappropriate content',
      'Hate speech',
      'Underage user',
      'Other',
    ];
    String selectedReason = reasons.first;
    final detailsController = TextEditingController();

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return Container(
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Report User', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Select a reason:', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 14)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: reasons.map((r) {
                    final selected = r == selectedReason;
                    return GestureDetector(
                      onTap: () => setState(() => selectedReason = r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? AppTheme.primaryBlue : (isDark ? Colors.white10 : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? AppTheme.primaryBlue : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          r,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: detailsController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Additional details (optional)...',
                    hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                    filled: true,
                    fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _submitUserReport(selectedReason, detailsController.text, isDark);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Submit Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _submitUserReport(String reason, String details, bool isDark) async {
    final currentUser = ref.read(userDataStreamProvider).asData?.value;
    if (currentUser == null) return;
    try {
      final docId = firestoreProvider.collection('reports').doc().id;
      await firestoreProvider.collection('reports').doc(docId).set({
        'id': docId,
        'type': 'user',
        'reportedUserId': widget.userId,
        'reportedBy': currentUser.id,
        'reporterName': currentUser.name,
        'reason': reason,
        'details': details,
        'status': 'open',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'resolvedAt': null,
        'adminNote': null,
      });
    } catch (e) {
      debugPrint('[Report] Failed to save: $e');
    }
    if (!mounted) return;
    // Confirmation bottom sheet
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 56),
            const SizedBox(height: 16),
            const Text('Report Submitted', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Thank you for keeping our community safe. We will review this report and notify you of the outcome.',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTakesSection(UserModel user, bool isDark) {
    final userTakesAsync = ref.watch(userTakesProvider(user.id));

    return userTakesAsync.when(
      data: (takes) {
        if (takes.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _storyRingAnim,
                      builder: (_, __) => Transform.rotate(
                        angle: _storyRingAnim.value * 2 * 3.14159,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF3CAC), Color(0xFFFF8C42)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF3CAC).withOpacity(0.4),
                                blurRadius: 12,
                                spreadRadius: 1,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.bolt_rounded, size: 15, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Takes',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black87,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF3CAC), Color(0xFFFF8C42)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${takes.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Thumbnails list
              SizedBox(
                height: 130,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: takes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final take = takes[index];

                    return GestureDetector(
                      onTap: () {
                        context.pushNamed(
                          'take-view',
                          pathParameters: {'userId': user.id},
                          extra: {
                            'userName': user.name,
                            'userAvatar': user.avatarUrl,
                          },
                        );
                      },
                      child: AnimatedBuilder(
                        animation: _storyRingAnim,
                        builder: (_, __) {
                          return SizedBox(
                            width: 90,
                            height: 130,
                            child: CustomPaint(
                              painter: _SpinningRingPainter(
                                angle: _storyRingAnim.value * 2 * 3.14159,
                                radius: 20,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(3.5),
                                child: _buildTakeThumbnail(take: take, user: user, isDark: isDark),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildTakeThumbnail({
    required Map<String, dynamic> take,
    required UserModel user,
    required bool isDark,
  }) {
    final rawImg = (take['imageUrl'] as String?) ?? (take['thumbnailUrl'] as String?) ?? (take['mediaUrl'] as String?);
    final rawVid = (take['videoUrl'] as String?);
    final String mediaUrl = (rawImg != null && rawImg.isNotEmpty)
        ? rawImg
        : (rawVid != null && rawVid.isNotEmpty)
            ? rawVid
            : (user.avatarUrl ?? '');

    final bool isVideo = (rawVid != null && rawVid.isNotEmpty) || (take['isVideo'] as bool? ?? false);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16.5),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Blurred background image (image/video frame/avatar is visible blurred under glass)
          if (mediaUrl.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
              child: Transform.scale(
                scale: 1.2, // Slightly scaled up so blur edges fill container smoothly
                child: Image.network(
                  mediaUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _takePlaceholder(isDark, user),
                ),
              ),
            )
          else
            _takePlaceholder(isDark, user),

          // 2. Soft dark gradient scrim
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.1),
                  Colors.black.withOpacity(0.55),
                ],
              ),
            ),
          ),

          // 3. Glowing center play/eye icon badge
          Center(
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.28),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withOpacity(0.7),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF3CAC).withOpacity(0.5),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                isVideo ? Icons.play_arrow_rounded : Icons.visibility_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),

          // 4. Top-right mini "TAKE" pill
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVideo ? Icons.videocam_rounded : Icons.photo_camera_rounded,
                    color: Colors.white70,
                    size: 9,
                  ),
                  const SizedBox(width: 3),
                  const Text(
                    'TAKE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
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

  Widget _takePlaceholder(bool isDark, UserModel user) {
    final avatar = user.avatarUrl ?? '';
    return Stack(
      fit: StackFit.expand,
      children: [
        if (avatar.isNotEmpty)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 7.0, sigmaY: 7.0),
            child: Transform.scale(
              scale: 1.25,
              child: Image.network(avatar, fit: BoxFit.cover),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF3B0764), const Color(0xFF1E1B4B)]
                    : [const Color(0xFFE9D5FF), const Color(0xFFC084FC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Animated chevrons for confess swipe bar ─────────────────────────────────
class _AnimatedChevrons extends StatelessWidget {
  final Color color;
  final double animValue; // 0..1 looping
  const _AnimatedChevrons({required this.color, required this.animValue});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        // Each chevron lags behind the previous by 0.15
        final phase = (animValue - i * 0.18).clamp(0.0, 1.0);
        final opacity = 0.3 + 0.7 * (0.5 + 0.5 * (1 - (2 * phase - 1).abs()));
        final offset = 3.0 * (0.5 + 0.5 * (1 - (2 * phase - 1).abs()));
        return Transform.translate(
          offset: Offset(offset, 0),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: color.withOpacity(opacity),
          ),
        );
      }),
    );
  }
}

// ─── Spinning gradient ring painter for Takes thumbnails ─────────────────────
class _SpinningRingPainter extends CustomPainter {
  final double angle;
  final double radius;
  const _SpinningRingPainter({required this.angle, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Background (dark gap between ring and content)
    final bgPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawRRect(rrect, bgPaint);

    // Rotating gradient ring
    final gradient = SweepGradient(
      startAngle: angle,
      endAngle: angle + 3.14159 * 2,
      colors: const [
        Color(0xFFFF3CAC),
        Color(0xFFFF8C42),
        Color(0xFFFFE44D),
        Color(0xFF7C3AED),
        Color(0xFFFF3CAC),
      ],
      stops: const [0.0, 0.3, 0.55, 0.8, 1.0],
    );

    final ringPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(rrect, ringPaint);
  }

  @override
  bool shouldRepaint(_SpinningRingPainter old) => old.angle != angle;
}


class _CustomConfessThumbShape extends SliderComponentShape {



  final bool isDark;
  _CustomConfessThumbShape({this.isDark = false});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(46, 46);

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
    
    // Drop shadow
    final shadowPaint = Paint()
      ..color = const Color(0xFF9333EA).withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center + const Offset(0, 3), 22, shadowPaint);

    // Gradient circle background
    final rect = Rect.fromCircle(center: center, radius: 23);
    final gradientPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF9333EA), Color(0xFFC084FC)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawCircle(center, 23, gradientPaint);

    // Inner white circle
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 19, innerPaint);

    // Lock open icon inside
    const icon = Icons.lock_open_rounded;
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 20,
          fontFamily: icon.fontFamily,
          color: const Color(0xFF9333EA),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
  }
}

