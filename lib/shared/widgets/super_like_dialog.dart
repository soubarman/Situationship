import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/models/user_model.dart';

/// Modal bottom sheet allowing the sender to attach an optional romantic compliment / icebreaker note with their Super Like.
class SuperLikeDialog extends StatefulWidget {
  final UserModel targetUser;
  final UserModel currentUser;
  final Function(String? note) onConfirmed;

  const SuperLikeDialog({
    super.key,
    required this.targetUser,
    required this.currentUser,
    required this.onConfirmed,
  });

  static void show({
    required BuildContext context,
    required UserModel targetUser,
    required UserModel currentUser,
    required Function(String? note) onConfirmed,
  }) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      isScrollControlled: true,
      builder: (ctx) => SuperLikeDialog(
        targetUser: targetUser,
        currentUser: currentUser,
        onConfirmed: onConfirmed,
      ),
    );
  }

  @override
  State<SuperLikeDialog> createState() => _SuperLikeDialogState();
}

class _SuperLikeDialogState extends State<SuperLikeDialog> {
  final TextEditingController _noteController = TextEditingController();
  bool _isSending = false;

  final List<String> _quickCompliments = [
    'Loved your style & vibe! ✨',
    'Your smile is captivating 🥰',
    'We\'d look amazing together ☕',
    'Immaculate music taste 🎵',
    'Coffee date on me? ☕💫',
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_isSending) return;
    setState(() => _isSending = true);
    HapticFeedback.heavyImpact();

    final note = _noteController.text.trim();
    Navigator.of(context, rootNavigator: true).pop();
    widget.onConfirmed(note.isNotEmpty ? note : null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final firstName = widget.targetUser.name.split(' ').first;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0C101E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: const Color(0xFF00C9FF).withValues(alpha: isDark ? 0.45 : 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C9FF).withValues(alpha: 0.25),
            blurRadius: 36,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(22, 14, 22, bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Super Like Glowing Star Badge
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00C9FF).withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(3),
                    child: ClipOval(
                      child: widget.targetUser.avatarUrl != null && widget.targetUser.avatarUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: widget.targetUser.avatarUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Center(child: Icon(Icons.star_rounded, color: Colors.white, size: 36)),
                            )
                          : const Center(child: Icon(Icons.star_rounded, color: Colors.white, size: 36)),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Color(0xFF00C9FF),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0xFF00C9FF), blurRadius: 8, spreadRadius: 1),
                        ],
                      ),
                      child: const Icon(Icons.star_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C9FF).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF00C9FF).withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('⭐', style: TextStyle(fontSize: 12)),
                    SizedBox(width: 5),
                    Text(
                      '3X MATCH PRIORITY',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: Color(0xFF00C9FF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                'Super Like $firstName ⭐',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your profile will jump straight to the top of $firstName\'s deck with an exclusive glowing star! Add a sweet note to break the ice:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: isDark ? Colors.white70 : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),

              // Quick Compliment Chips
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Quick Icebreakers:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFF00C9FF) : const Color(0xFF0284C7),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickCompliments.map((comp) {
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _noteController.text = comp;
                      _noteController.selection = TextSelection.fromPosition(
                        TextPosition(offset: comp.length),
                      );
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6.5),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFBAE6FD),
                        ),
                      ),
                      child: Text(
                        comp,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF0369A1),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Custom Note Input
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF141A2D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF00C9FF).withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: TextField(
                  controller: _noteController,
                  maxLength: 100,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Write a sweet first impression... (optional)',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    border: InputBorder.none,
                    counterStyle: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Send Button
              GestureDetector(
                onTap: _submit,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C9FF), Color(0xFF0072FF)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00C9FF).withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Send Super Like to $firstName ⭐',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Cancel button
              TextButton(
                onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 12.5,
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
