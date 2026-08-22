import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/app_state_provider.dart';

class ProfileChoiceSheet extends StatelessWidget {
  final UserModel user;
  final bool isDark;

  const ProfileChoiceSheet({
    super.key,
    required this.user,
    required this.isDark,
  });

  static Future<void> show(BuildContext context, UserModel user, bool isDark) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => ProfileChoiceSheet(user: user, isDark: isDark),
    );
  }

  static void navigateToProfile(BuildContext context, WidgetRef ref, String targetUserId) {
    final currentUser = ref.read(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (targetUserId.isNotEmpty && targetUserId == currentUser.id) {
      ProfileChoiceSheet.show(context, currentUser, isDark);
    } else {
      context.push('/profile/view/$targetUserId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1B1726) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1B2E);
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top grab handle indicator
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Header avatar + title
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF3CAC), Color(0xFF7C3AED)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF3CAC).withOpacity(0.3),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(2),
                      child: ClipOval(
                        child: Image.network(
                          user.avatarUrl ?? 'https://i.pravatar.cc/150',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Profile 👤',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: textColor,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'How would you like to open your profile?',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: subColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // Option 1: Preview Public View
                _buildChoiceTile(
                  context: context,
                  title: 'View as Visitor (Public View)',
                  subtitle: 'See how others view your photos, bio, Takes, traits & confession bar',
                  icon: Icons.remove_red_eye_rounded,
                  iconGradient: const [Color(0xFF00C6FF), Color(0xFF0072FF)],
                  isPrimary: true,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/profile/view/${user.id}');
                  },
                ),

                const SizedBox(height: 12),

                // Option 2: My Profile (Default Section)
                _buildChoiceTile(
                  context: context,
                  title: 'My Profile (Default Section)',
                  subtitle: 'Your main profile with stats, bio, posts grid, visitors & options',
                  icon: Icons.person_rounded,
                  iconGradient: const [Color(0xFFFF3CAC), Color(0xFFFF8C42)],
                  isPrimary: false,
                  onTap: () {
                    Navigator.pop(context);
                    context.go('/profile');
                  },
                ),

                const SizedBox(height: 12),

                // Option 3: View Visitors
                _buildChoiceTile(
                  context: context,
                  title: 'Profile Visitors 👁️',
                  subtitle: 'See who recently viewed your profile and interacted with you',
                  icon: Icons.people_outline_rounded,
                  iconGradient: const [Color(0xFFA855F7), Color(0xFF6366F1)],
                  isPrimary: false,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/profile/visitors');
                  },
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> iconGradient,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    final tileBg = isDark
        ? (isPrimary ? const Color(0xFF2A1F40) : Colors.white.withOpacity(0.06))
        : (isPrimary ? const Color(0xFFF3E8FF) : Colors.black.withOpacity(0.04));

    final borderColor = isPrimary
        ? const Color(0xFF9333EA).withOpacity(0.55)
        : (isDark ? Colors.white.withOpacity(0.09) : Colors.black.withOpacity(0.06));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.3),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: const Color(0xFF9333EA).withOpacity(0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: iconGradient),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}
