import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_model.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/app_state_provider.dart';
import '../../../core/providers/firestore_provider.dart';
import '../../../core/utils/heart_queue_engine.dart';

// ─── Vibe helpers ────────────────────────────────────────────────────────────

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
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  bool _isRevealed = false;
  String? _lastReaction; // 'too_hot' | 'crushing' | 'dm_me'
  bool _isSending = false;
  bool _pendingAdvance = false;

  late AnimationController _revealController;
  late Animation<double> _revealAnim;
  late AnimationController _ambientPulseCtrl;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _revealAnim = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );

    _ambientPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _revealController.dispose();
    _ambientPulseCtrl.dispose();
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

      // 2. Like if it's "too_hot" or "crushing"
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

    // Advance after reveal delay (unless it was dm_me)
    if (reaction != 'dm_me') {
      Future.delayed(const Duration(milliseconds: 1600), () {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isShort = constraints.maxHeight < 690;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                // ── Seductive Header Pill Bar ──────────────────────────────
                _buildHeader(matchPct, isDark),

                // ── Luxury Velvet Mystery Card ─────────────────────────────
                Expanded(
                  child: _buildSoulCard(
                    target,
                    currentUser,
                    vibe,
                    vibeColor,
                    isDark,
                    isShort,
                  ),
                ),

                SizedBox(height: isShort ? 10 : 16),

                // ── Unified 4-Action Command Console ───────────────────────
                _buildActionConsole(isDark, isShort),

                SizedBox(height: isShort ? 4 : 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Header: Ethereal Aura Bar ─────────────────────────────────────────────

  Widget _buildHeader(int matchPct, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Row(
        children: [
          // Ethereal Soul Mode Capsule
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF2E93).withValues(alpha: isDark ? 0.22 : 0.12),
                  const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.26 : 0.14),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFF2E93).withValues(alpha: isDark ? 0.45 : 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFF2E93),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFFFF2E93),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'SOUL FREQUENCY',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: Color(0xFFFF2E93),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Feel first · Face unlocks on reaction',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          // Chemistry Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF007A).withValues(alpha: isDark ? 0.22 : 0.12),
                  const Color(0xFF7928CA).withValues(alpha: isDark ? 0.26 : 0.14),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFF007A).withValues(alpha: isDark ? 0.45 : 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF007A).withValues(alpha: isDark ? 0.2 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 13,
                  color: Color(0xFFFF007A),
                ),
                const SizedBox(width: 4),
                Text(
                  '$matchPct% Match',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Center: Seductive Soul Mystery Card ───────────────────────────────────

  Widget _buildSoulCard(
    UserModel target,
    UserModel currentUser,
    String vibe,
    Color vibeColor,
    bool isDark,
    bool isShort,
  ) {
    return AnimatedBuilder(
      animation: _ambientPulseCtrl,
      builder: (context, _) {
        final pulse = _ambientPulseCtrl.value;
        final glowSpread = pulse * 4.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              color: const Color(0xFF0F0C1E),
              border: Border.all(
                color: Color.lerp(
                  vibeColor.withValues(alpha: 0.35),
                  const Color(0xFFFF2E93).withValues(alpha: 0.55),
                  pulse,
                )!,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: vibeColor.withValues(alpha: 0.25 + 0.12 * pulse),
                  blurRadius: 28 + glowSpread,
                  spreadRadius: -2,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Background image with animated blur
                  AnimatedBuilder(
                    animation: _revealAnim,
                    builder: (context, _) {
                      final blurVal = (18 * (1 - _revealAnim.value)).clamp(0.0, 18.0);
                      return ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: blurVal, sigmaY: blurVal),
                        child: CachedNetworkImage(
                          imageUrl: target.avatarUrl ??
                              'https://i.pravatar.cc/600?u=${target.id}',
                          fit: BoxFit.cover,
                          memCacheWidth: 800,
                          placeholder: (_, __) => Container(
                            color: const Color(0xFF161328),
                            child: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFFF2E93),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [vibeColor, const Color(0xFF120E29)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                target.name.isNotEmpty ? target.name[0] : '?',
                                style: const TextStyle(fontSize: 64, color: Colors.white70),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // 2. Warm Velvet Vignette Overlay
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.35, 0.68, 1.0],
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            const Color(0xFF1B0F2A).withValues(alpha: 0.25),
                            const Color(0xFF0C071A).withValues(alpha: 0.8),
                            const Color(0xFF080514).withValues(alpha: 0.96),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 3. Mysterious Hologram Veil Seal (When not revealed)
                  if (!_isRevealed)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: isShort ? 180 : 210,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Mystic Hologram Crystal Orb
                            Container(
                              width: isShort ? 72 : 82,
                              height: isShort ? 72 : 82,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(0xFFFF2E93).withValues(alpha: 0.35),
                                    const Color(0xFF180F33).withValues(alpha: 0.85),
                                  ],
                                ),
                                border: Border.all(
                                  color: Color.lerp(
                                    const Color(0xFFFF2E93),
                                    const Color(0xFF00F5D4),
                                    pulse,
                                  )!.withValues(alpha: 0.65),
                                  width: 1.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF2E93).withValues(
                                      alpha: 0.35 + 0.15 * pulse,
                                    ),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Colors.white,
                                  size: isShort ? 32 : 38,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Seductive Badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4.5,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFFFF2E93).withValues(alpha: 0.25),
                                    const Color(0xFF7928CA).withValues(alpha: 0.35),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1,
                                ),
                              ),
                              child: const Text(
                                'SECRET AURA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11.5,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap any reaction below to unveil her gaze ✨',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 4. Soul Profile Floating Glass Island (Bottom)
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 14,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          padding: EdgeInsets.all(isShort ? 12 : 15),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D0A1C).withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Row 1: Vibe Tag & Identity
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: vibeColor.withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: vibeColor.withValues(alpha: 0.55),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      vibe,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.3,
                                        color: vibeColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _isRevealed
                                          ? '${target.name}, ${target.age}'
                                          : 'Mystery Soul · ${target.age}',
                                      style: TextStyle(
                                        fontSize: isShort ? 18 : 21,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: isShort ? 8 : 10),

                              // Row 2: Editorial Soul Prompt
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: vibeColor.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.format_quote_rounded,
                                          size: 15,
                                          color: vibeColor.withValues(alpha: 0.95),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "I'LL FALL FOR YOU IF...",
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.8,
                                            color: vibeColor.withValues(alpha: 0.95),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _quoteText(target),
                                      style: TextStyle(
                                        fontSize: isShort ? 12.5 : 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.95),
                                        fontStyle: FontStyle.italic,
                                        height: 1.35,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),

                              // Row 3: Passions
                              if (target.interests.isNotEmpty) ...[
                                SizedBox(height: isShort ? 8 : 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: target.interests
                                      .take(3)
                                      .map((i) => _InterestChip(label: i))
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 5. Celebration Reaction Bloom
                  if (_isRevealed && _lastReaction != null)
                    AnimatedBuilder(
                      animation: _revealAnim,
                      builder: (context, _) => Positioned(
                        top: 28,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Opacity(
                            opacity: (1 - _revealAnim.value).clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: 0.8 + _revealAnim.value * 0.6,
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.6),
                                  border: Border.all(
                                    color: const Color(0xFFFF2E93).withValues(alpha: 0.7),
                                    width: 2.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFF2E93).withValues(alpha: 0.6),
                                      blurRadius: 32,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _reactionEmoji(_lastReaction!),
                                  style: const TextStyle(fontSize: 48),
                                ),
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
        );
      },
    );
  }

  // ─── Unified 4-Action Command Console ──────────────────────────────────────

  Widget _buildActionConsole(bool isDark, bool isShort) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: isShort ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF100C22) : Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 1. Pass Action (Circular Ghost Button)
            _ActionOrbButton(
              icon: Icons.close_rounded,
              label: 'PASS',
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
              bgColor: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9),
              borderColor: isDark ? Colors.white12 : Colors.black12,
              onTap: _skip,
              isShort: isShort,
            ),

            // 2. Too Hot Action (Warm Sunset Flame)
            _ActionOrbButton(
              emoji: '🔥',
              label: 'TOO HOT',
              themeGradient: const [Color(0xFFFF416C), Color(0xFFFF4B2B)],
              isLoading: _isSending && _lastReaction == 'too_hot',
              onTap: () => _react('too_hot'),
              isShort: isShort,
            ),

            // 3. Crushing Action (Hero Rose Heartpiece)
            _ActionOrbButton(
              emoji: '💖',
              label: 'CRUSHING',
              isMain: true,
              themeGradient: const [Color(0xFFFF007A), Color(0xFF7928CA)],
              isLoading: _isSending && _lastReaction == 'crushing',
              onTap: () => _react('crushing'),
              isShort: isShort,
            ),

            // 4. Secret DM Action (Electric Cyan Whisper)
            _ActionOrbButton(
              emoji: '💬',
              label: 'SECRET DM',
              badgeText: '🪙 10',
              themeGradient: const [Color(0xFF00F5D4), Color(0xFF6366F1)],
              isLoading: _isSending && _lastReaction == 'dm_me',
              onTap: () => _react('dm_me'),
              isShort: isShort,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Secret DM Confession Sheet ───────────────────────────────────────────

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
          24,
          20,
          24,
          MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF100D22) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00F5D4), Color(0xFF6366F1)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secret Soul DM',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        '100% Anonymous whisper to their inbox',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
                    'Whisper something intoxicating... they won\'t know who sent it! 🤫',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white30 : Colors.black38,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Cost: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Colors.amber,
                        ),
                      ),
                      Text(
                        '🪙 10 Coins',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      _sendConfession(controller.text, targetUser, sheetContext),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text(
                    'Send Secret 🔒',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    elevation: 4,
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
    String text,
    UserModel targetUser,
    BuildContext sheetContext,
  ) async {
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

      if (sheetContext.mounted) Navigator.pop(sheetContext);
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF007A).withValues(alpha: 0.18),
                    const Color(0xFF7928CA).withValues(alpha: 0.22),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFF007A).withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF007A).withValues(alpha: 0.25),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFFFF007A),
                size: 48,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'All Souls Explored! ✨',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : const Color(0xFF111827),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have connected with all frequencies in this orbit. Check back soon for new mysterious faces.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _reactionEmoji(String reaction) {
    return switch (reaction) {
      'too_hot' => '🔥',
      'crushing' => '💖',
      'dm_me' => '💬',
      _ => '✨',
    };
  }
}

// ─── Luxury Action Orb Button ────────────────────────────────────────────────

class _ActionOrbButton extends StatefulWidget {
  final String? emoji;
  final IconData? icon;
  final String label;
  final String? badgeText;
  final List<Color>? themeGradient;
  final Color? color;
  final Color? bgColor;
  final Color? borderColor;
  final bool isLoading;
  final VoidCallback onTap;
  final bool isMain;
  final bool isShort;

  const _ActionOrbButton({
    this.emoji,
    this.icon,
    required this.label,
    this.badgeText,
    this.themeGradient,
    this.color,
    this.bgColor,
    this.borderColor,
    this.isLoading = false,
    required this.onTap,
    this.isMain = false,
    this.isShort = false,
  });

  @override
  State<_ActionOrbButton> createState() => _ActionOrbButtonState();
}

class _ActionOrbButtonState extends State<_ActionOrbButton>
    with TickerProviderStateMixin {
  late AnimationController _idleCtrl;
  late AnimationController _tapCtrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.82)
            .chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.82, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(_tapCtrl);
  }

  @override
  void dispose() {
    _idleCtrl.dispose();
    _tapCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.isLoading) return;
    HapticFeedback.heavyImpact();
    _tapCtrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final orbSize = widget.isMain
        ? (widget.isShort ? 54.0 : 60.0)
        : (widget.isShort ? 44.0 : 48.0);
    final emojiSize = widget.isMain
        ? (widget.isShort ? 28.0 : 32.0)
        : (widget.isShort ? 20.0 : 22.0);

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scale,
            child: AnimatedBuilder(
              animation: _idleCtrl,
              builder: (context, _) {
                final t = _idleCtrl.value;
                double idleScale = 1.0;
                double idleRot = 0.0;
                double idleOffsetY = 0.0;

                if (widget.isMain) {
                  final beat = math.sin(t * 2 * math.pi);
                  idleScale = 1.0 + (beat > 0.3 ? (beat - 0.3) * 0.18 : 0.0);
                } else if (widget.emoji == '🔥') {
                  idleScale = 1.0 + 0.05 * math.sin(t * 2 * math.pi);
                  idleRot = 0.04 * math.sin(t * 4 * math.pi);
                } else if (widget.emoji == '💬') {
                  idleOffsetY = -3.0 * math.sin(t * 2 * math.pi);
                }

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Glowing Orb Body
                    Container(
                      width: orbSize,
                      height: orbSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.bgColor,
                        gradient: widget.themeGradient != null
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  widget.themeGradient![0].withValues(alpha: 0.3),
                                  widget.themeGradient![1].withValues(alpha: 0.18),
                                ],
                              )
                            : null,
                        border: Border.all(
                          color: widget.borderColor ??
                              (widget.themeGradient != null
                                  ? widget.themeGradient![0].withValues(alpha: 0.55)
                                  : Colors.white24),
                          width: widget.isMain ? 1.8 : 1.2,
                        ),
                        boxShadow: widget.themeGradient != null
                            ? [
                                BoxShadow(
                                  color: widget.themeGradient![0].withValues(
                                    alpha: widget.isMain ? 0.4 : 0.22,
                                  ),
                                  blurRadius: widget.isMain ? 16 : 10,
                                  spreadRadius: 0,
                                ),
                              ]
                            : null,
                      ),
                      child: widget.isLoading
                          ? const Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Center(
                              child: widget.icon != null
                                  ? Icon(
                                      widget.icon,
                                      size: widget.isShort ? 20 : 22,
                                      color: widget.color ?? Colors.white,
                                    )
                                  : Transform.translate(
                                      offset: Offset(0, idleOffsetY),
                                      child: Transform.rotate(
                                        angle: idleRot,
                                        child: Transform.scale(
                                          scale: idleScale,
                                          child: Text(
                                            widget.emoji ?? '',
                                            style: TextStyle(
                                              fontSize: emojiSize,
                                              height: 1.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                    ),

                    // Micro Coin / Badge
                    if (widget.badgeText != null)
                      Positioned(
                        top: -4,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4.5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131024),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.6),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            widget.badgeText!,
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 5),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.isShort ? 8.5 : 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: widget.isMain
                  ? const Color(0xFFFF2E93)
                  : (widget.color ?? Colors.white70),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

// ─── Match % & Quote helpers ──────────────────────────────────────────────────

final _soulTabEngine = HeartQueueEngine();

int _matchPercent(UserModel me, UserModel other) {
  return _soulTabEngine.scoreProfile(currentUser: me, candidate: other).displayScore;
}

String _quoteText(UserModel u) {
  final bio = u.bio?.trim();
  if (bio != null && bio.isNotEmpty) return bio;
  if (u.interests.isNotEmpty) {
    return u.interests.take(2).join(' & ');
  }
  return 'Honestly just vibing rn ✨';
}
