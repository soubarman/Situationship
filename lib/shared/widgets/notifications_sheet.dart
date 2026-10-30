import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/models/notification_model.dart';
import '../../core/models/user_model.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_theme.dart';

void showNotificationsSheet(BuildContext context, UserModel currentUser, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Consumer(
        builder: (context, ref, child) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final notificationsAsync = ref.watch(notificationsStreamProvider);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            markAllNotificationsAsRead(currentUser.id);
          });

          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF140F22).withValues(alpha: 0.92)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Notifications 🔔',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: isDark ? Colors.white : AppTheme.textPrimary,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Close',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      color: isDark ? Colors.white12 : Colors.black12,
                      height: 1,
                    ),
                    Expanded(
                      child: notificationsAsync.when(
                        data: (list) {
                          if (list.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('✨', style: TextStyle(fontSize: 48)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'All caught up!',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white60 : AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Reactions and chat requests will appear here.',
                                    style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = list[index];
                              return _NotificationTile(
                                item: item,
                                isDark: isDark,
                                onTap: () {
                                  Navigator.of(context, rootNavigator: true).pop();
                                  if (item.senderId.isNotEmpty) {
                                    context.push('/profile/view/${item.senderId}');
                                  }
                                },
                              );
                            },
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);
    final notificationsAsync = ref.watch(notificationsStreamProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (currentUser.id.isNotEmpty) {
        markAllNotificationsAsRead(currentUser.id);
      }
    });

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0713) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Notifications 🔔', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: notificationsAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('✨', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(
                    'All caught up!',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white60 : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Reactions and chat requests will appear here.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = list[index];
              return _NotificationTile(
                item: item,
                isDark: isDark,
                onTap: () {
                  if (item.senderId.isNotEmpty) {
                    context.push('/profile/view/${item.senderId}');
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

String _formatTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel item;
  final bool isDark;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSuperLike = item.type == 'superlike';
    final isLike = item.type == 'like' || item.type == 'reaction';
    final isGift = item.type == 'gift';
    final isConfession = item.type == 'confession';

    IconData icon;
    Color iconColor;
    Gradient? cardGradient;
    Border? cardBorder;

    if (isSuperLike) {
      icon = Icons.star_rounded;
      iconColor = const Color(0xFF00C9FF);
      cardGradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF002B49).withValues(alpha: 0.7),
                const Color(0xFF0F1B2B).withValues(alpha: 0.8),
              ]
            : [
                const Color(0xFFE0F7FF),
                const Color(0xFFF0FDF4),
              ],
      );
      cardBorder = Border.all(
        color: const Color(0xFF00C9FF).withValues(alpha: 0.6),
        width: 1.5,
      );
    } else if (isLike) {
      icon = Icons.favorite_rounded;
      iconColor = const Color(0xFFFF3366);
      cardBorder = Border.all(
        color: const Color(0xFFFF3366).withValues(alpha: isDark ? 0.35 : 0.22),
        width: 1.0,
      );
    } else if (isGift) {
      icon = Icons.card_giftcard_rounded;
      iconColor = Colors.amber;
      cardBorder = Border.all(
        color: Colors.amber.withValues(alpha: isDark ? 0.35 : 0.22),
        width: 1.0,
      );
    } else if (isConfession) {
      icon = Icons.lock_rounded;
      iconColor = const Color(0xFFC084FC);
      cardBorder = Border.all(
        color: const Color(0xFFC084FC).withValues(alpha: isDark ? 0.35 : 0.22),
        width: 1.0,
      );
    } else {
      icon = Icons.chat_bubble_rounded;
      iconColor = AppTheme.primaryBlue;
      cardBorder = Border.all(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        width: 1.0,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardGradient == null
              ? (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white)
              : null,
          gradient: cardGradient,
          borderRadius: BorderRadius.circular(18),
          border: cardBorder,
          boxShadow: isSuperLike
              ? [
                  BoxShadow(
                    color: const Color(0xFF00C9FF).withValues(alpha: 0.20),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender Avatar or Type Icon
            Stack(
              clipBehavior: Clip.none,
              children: [
                if (item.senderAvatar != null && item.senderAvatar!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: CachedNetworkImage(
                      imageUrl: item.senderAvatar!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        color: iconColor.withValues(alpha: 0.15),
                        child: Icon(icon, color: iconColor, size: 22),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),

                // Mini Badge on Avatar corner
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      color: iconColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF140F22) : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      isSuperLike ? Icons.star_rounded : icon,
                      color: isSuperLike ? Colors.black : Colors.white,
                      size: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (isSuperLike)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'VIP ⭐',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        _formatTime(item.createdAt),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.textTertiary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        isSuperLike ? 'View Profile ✨' : 'View Profile →',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSuperLike ? const Color(0xFF00C9FF) : AppTheme.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
