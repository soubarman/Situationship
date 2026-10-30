import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/models/user_model.dart';
import '../../core/services/coin_service.dart';

/// Modern romantic dating app paywall BottomSheet for Direct Messaging ("Say Hi").
class SayHiPremiumModal extends ConsumerStatefulWidget {
  final UserModel targetUser;
  final UserModel currentUser;
  final VoidCallback onUnlocked;

  const SayHiPremiumModal({
    super.key,
    required this.targetUser,
    required this.currentUser,
    required this.onUnlocked,
  });

  static void show({
    required BuildContext context,
    required UserModel targetUser,
    required UserModel currentUser,
    required VoidCallback onUnlocked,
  }) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      isScrollControlled: true,
      builder: (ctx) => SayHiPremiumModal(
        targetUser: targetUser,
        currentUser: currentUser,
        onUnlocked: onUnlocked,
      ),
    );
  }

  @override
  ConsumerState<SayHiPremiumModal> createState() => _SayHiPremiumModalState();
}

class _SayHiPremiumModalState extends ConsumerState<SayHiPremiumModal> {
  bool _isPurchasing = false;

  Future<void> _subscribeAndConnect() async {
    if (_isPurchasing) return;
    setState(() => _isPurchasing = true);
    HapticFeedback.mediumImpact();

    try {
      await CoinService.activateSubscription(
        userId: widget.currentUser.id,
        duration: const Duration(days: 30),
        phoneUnlockQuota: 10,
      );

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Text('👑', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'VIP Activated! Say Hi to ${widget.targetUser.name.split(" ").first} ✨',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );

      widget.onUnlocked();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPurchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subscription failed: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildAvatar(String? url, String name, {required List<Color> ringColors, bool isOnline = false}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: ringColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: ringColors.first.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2.5),
          child: ClipOval(
            child: url != null && url.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: 180,
                    placeholder: (_, __) => Container(color: const Color(0xFF1E1638)),
                    errorWidget: (_, __, ___) => _buildFallbackInitial(name),
                  )
                : _buildFallbackInitial(name),
          ),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF0F0C1E), width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xFF10B981),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFallbackInitial(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF3366), Color(0xFFFF8E53)],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildPerkItem({
    required String icon,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3366).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF3366).withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;
    final targetFirstName = widget.targetUser.name.split(' ').first;

    return Container(
      constraints: BoxConstraints(maxHeight: screenH * 0.90),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F0C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: const Color(0xFFFF3366).withValues(alpha: isDark ? 0.35 : 0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF3366).withValues(alpha: 0.25),
            blurRadius: 40,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset > 0 ? bottomInset + 12 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Romantic Match Connector Visual: You ──💖── Target User
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAvatar(
                    widget.currentUser.avatarUrl,
                    widget.currentUser.name,
                    ringColors: const [Color(0xFF6366F1), Color(0xFF9333EA)],
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF3366), Color(0xFFFF8E53)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF3366).withValues(alpha: 0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Say Hi', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 13),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildAvatar(
                    widget.targetUser.avatarUrl,
                    widget.targetUser.name,
                    ringColors: const [Color(0xFFFF3366), Color(0xFFFF8E53)],
                    isOnline: widget.targetUser.isActuallyActive,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // VIP Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.45),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFB300), size: 14),
                    SizedBox(width: 5),
                    Text(
                      'SITUATIONSHIP VIP EXCLUSIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Color(0xFFFFB300),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Headline
              Text(
                'Say Hi to $targetFirstName directly ✨',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),

              // Subtitle
              Text(
                'Skip the mutual match waitlist! Situationship VIP lets you break the ice and slide straight into $targetFirstName\'s inbox right now.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 18),

              // Dating VIP Perks
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  children: [
                    _buildPerkItem(
                      icon: '💬',
                      title: 'Direct Messaging (Say Hi)',
                      desc: 'Send instant messages to anyone nearby without waiting for a match',
                      isDark: isDark,
                    ),
                    _buildPerkItem(
                      icon: '🚀',
                      title: 'Top-of-Inbox Priority',
                      desc: 'Your chat is highlighted and pinned right at the top of her inbox',
                      isDark: isDark,
                    ),
                    _buildPerkItem(
                      icon: '👁️',
                      title: 'See Who Liked & Visited You',
                      desc: 'Instantly unblur secret admirers and incoming likes',
                      isDark: isDark,
                    ),
                    _buildPerkItem(
                      icon: '📞',
                      title: '10 Free Phone & Social Unlocks',
                      desc: 'Directly exchange personal contacts whenever chemistry sparks',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Plan & Pricing Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF26123D), const Color(0xFF1E0E33)]
                        : [const Color(0xFFFFF1F4), const Color(0xFFFFE6EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFFF3366).withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    const Text('⭐', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Situationship VIP',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF3366),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'SAVE 50%',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Just ₹6.6/day • Cancel anytime',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹199',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: isDark ? const Color(0xFFFFB300) : const Color(0xFFFF3366),
                          ),
                        ),
                        Text(
                          '/month',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white54 : const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Main CTA Button
              GestureDetector(
                onTap: _isPurchasing ? null : _subscribeAndConnect,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF3366), Color(0xFFFF6584), Color(0xFFFF8E53)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF3366).withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isPurchasing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Get VIP & Message $targetFirstName 👑',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Secondary Wallet Link
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context, rootNavigator: true).pop();
                  context.push('/wallet');
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Explore All Plans in Wallet ➔',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6584),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // Dismiss Button
              TextButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                child: Text(
                  'Maybe Later',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
