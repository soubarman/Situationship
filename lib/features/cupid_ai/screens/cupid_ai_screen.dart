import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:situationship/core/theme/app_palette.dart';
import '../providers/cupid_ai_provider.dart';
import '../widgets/cupid_profile_card.dart';

class CupidAIScreen extends ConsumerStatefulWidget {
  const CupidAIScreen({super.key});

  @override
  ConsumerState<CupidAIScreen> createState() => _CupidAIScreenState();
}

class _CupidAIScreenState extends ConsumerState<CupidAIScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _handleSend([String? presetText]) {
    final query = presetText ?? _textController.text;
    if (query.trim().isEmpty) return;

    HapticFeedback.lightImpact();
    ref.read(cupidAIProvider.notifier).sendMessage(query);
    if (presetText == null) {
      _textController.clear();
    }
    _scrollToBottom();
  }

  IconData _iconForChip(String chip) {
    final lower = chip.toLowerCase();
    if (lower.contains('art')) return Icons.palette_outlined;
    if (lower.contains('music') || lower.contains('indie') || lower.contains('vinyl')) {
      return Icons.music_note_rounded;
    }
    if (lower.contains('coffee') || lower.contains('book')) return Icons.local_cafe_outlined;
    if (lower.contains('night')) return Icons.nightlight_round;
    if (lower.contains('trip') || lower.contains('road')) return Icons.explore_outlined;
    if (lower.contains('connection') || lower.contains('relationship')) {
      return Icons.favorite_border_rounded;
    }
    if (lower.contains('smok')) return Icons.smoke_free_rounded;
    return Icons.auto_awesome_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cupidAIProvider);
    final palette = ref.watch(appPaletteProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen(cupidAIProvider, (_, __) => _scrollToBottom());

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0F17) : const Color(0xFFF8F7FC),
      body: SafeArea(
        child: Column(
          children: [
            // ── 1. Top Header ──────────────────────────────────────────────
            _buildHeader(isDark, palette, state),

            // ── 2. Chat Stream ─────────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: state.messages.length,
                itemBuilder: (context, index) {
                  final msg = state.messages[index];
                  return _buildMessageItem(msg, isDark, palette);
                },
              ),
            ),

            // ── 3. Quick Suggestion Chips (Minimalist Vector Pills) ────────
            if (!state.isThinking) _buildQuickChips(state.suggestedChips, isDark, palette),

            // ── 4. Unified Input Capsule ───────────────────────────────────
            _buildInputBar(isDark, palette),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, AppPalette palette, CupidAIState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10131E) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF1F2638) : Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 4),

          // Luxury Medallion Avatar with Soft Aura
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final glowAlpha = 0.25 + (_pulseController.value * 0.25);
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [const Color(0xFF2E1934), const Color(0xFF171124)]
                        : [const Color(0xFFFFEEF3), const Color(0xFFF3E8FF)],
                  ),
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: glowAlpha),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.favorite_rounded,
                    color: palette.primary,
                    size: 20,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),

          // Title & Live Concierge Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Cupid Concierge',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state.isOfflineReady ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.isOfflineReady ? '100% On-Device AI • Offline' : 'On-Device AI Engine',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Clear Chat Button
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
            tooltip: 'Clear Chat',
            onPressed: () {
              ref.read(cupidAIProvider.notifier).clearChat();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(CupidChatMessage msg, bool isDark, AppPalette palette) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 8, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: palette.primaryGradient,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: palette.primary.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            msg.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      );
    }

    // Cupid Concierge Response Card
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8, right: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151926) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(
                color: isDark ? const Color(0xFF242C3F) : Colors.black.withValues(alpha: 0.08),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subtle Concierge Signature Row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite_rounded,
                      size: 11,
                      color: palette.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'CUPID CONCIERGE',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: palette.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Message Text or Thinking Indicator
                msg.isThinking
                    ? _buildThinkingIndicator(isDark, palette)
                    : Text(
                        msg.text,
                        style: TextStyle(
                          color: isDark ? Colors.white.withValues(alpha: 0.94) : Colors.black87,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
              ],
            ),
          ),

          // If matches exist, embed horizontal profile cards carousel
          if (msg.matches.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 420,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 4),
                itemCount: msg.matches.length,
                itemBuilder: (context, idx) {
                  final match = msg.matches[idx];
                  return CupidProfileCard(
                    match: match,
                    onLike: (user) => ref.read(cupidAIProvider.notifier).handleLike(user),
                    onSuperLike: (user) => ref.read(cupidAIProvider.notifier).handleSuperLike(user),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThinkingIndicator(bool isDark, AppPalette palette) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(palette.primary),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Consulting Cupid Concierge...',
          style: TextStyle(
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickChips(List<String> chips, bool isDark, AppPalette palette) {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        itemBuilder: (context, index) {
          final chip = chips[index];
          final icon = _iconForChip(chip);

          return GestureDetector(
            onTap: () => _handleSend(chip),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161A26) : const Color(0xFFF3F0FA),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF262E44) : Colors.black.withValues(alpha: 0.08),
                  width: 0.9,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: palette.primary),
                  const SizedBox(width: 6),
                  Text(
                    chip,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar(bool isDark, AppPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF10131E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1F2638) : Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161A26) : const Color(0xFFF3F0FA),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark ? const Color(0xFF252D42) : Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 20,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'Ask Cupid (e.g. loves art & indie gigs)...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Embedded Send Pill
            GestureDetector(
              onTap: () => _handleSend(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: palette.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: palette.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
