import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/user_model.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/theme/app_palette.dart';
import 'notifications_sheet.dart';
import 'situationship_logo.dart';

/// Unified Header component that matches the exact Situationship layout:
/// - Left: Situationship™ Logo or Screen Title
/// - Right: Coin Pill (🪙 coins), Action Button (Filter or Search), Bell (with unread badge), and Profile Avatar
class SituationshipHeaderBar extends ConsumerWidget {
  final Widget? titleWidget;
  final String? titleText;
  final VoidCallback? onFilterTap;
  final VoidCallback? onSearchTap;
  final Widget? searchBarWidget;
  final bool showLogo;
  final bool showCoins;
  final bool showNotifications;
  final bool showSearch;
  final bool showProfileAvatar;
  final EdgeInsetsGeometry padding;

  const SituationshipHeaderBar({
    super.key,
    this.titleWidget,
    this.titleText,
    this.onFilterTap,
    this.onSearchTap,
    this.searchBarWidget,
    this.showLogo = true,
    this.showCoins = true,
    this.showNotifications = true,
    this.showSearch = true,
    this.showProfileAvatar = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);
    final palette = ref.watch(appPaletteProvider);
    final coins = currentUser.coins;

    if (searchBarWidget != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: searchBarWidget!,
      );
    }

    // Left side: Logo or Title
    Widget leftWidget;
    if (showLogo) {
      leftWidget = SituationshipLogo(
        fontSize: 22,
        isDark: isDark,
        showTrademark: true,
      );
    } else if (titleWidget != null) {
      leftWidget = titleWidget!;
    } else {
      leftWidget = Text(
        titleText ?? '',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      );
    }

    // Right side actions cluster
    final List<Widget> actions = [];

    // 1. Coin Balance Pill
    if (showCoins) {
      actions.add(_buildCoinPill(context, coins, isDark, palette));
    }

    // 2. Filter Button (if onFilterTap is passed, it comes before Bell as in Matches tab)
    if (onFilterTap != null) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 7));
      actions.add(_buildHeaderIconButton(
        context: context,
        icon: Icons.tune_rounded,
        isDark: isDark,
        onTap: onFilterTap!,
      ));
    }

    // 3. Notification Bell
    if (showNotifications) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 7));
      actions.add(_buildNotificationBell(context, currentUser, ref, isDark, palette));
    }

    // 4. Search Button (if showSearch is true and not in filter mode)
    if (showSearch && onFilterTap == null) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 7));
      actions.add(_buildHeaderIconButton(
        context: context,
        icon: Icons.search_rounded,
        isDark: isDark,
        onTap: onSearchTap ?? () => context.push('/search'),
      ));
    }

    // 5. User Profile Avatar
    if (showProfileAvatar) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 7));
      actions.add(_buildProfileAvatar(context, currentUser, isDark, palette));
    }

    return Padding(
      padding: padding,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: Title or Logo
            Flexible(
              child: leftWidget,
            ),
            const SizedBox(width: 8),
            // Right: Actions Cluster
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }

  // ── Coin Balance Pill ───────────────────────────────────────────────────────

  Widget _buildCoinPill(
    BuildContext context,
    int coins,
    bool isDark,
    AppPalette palette,
  ) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/wallet');
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B150A) : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFFB800),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFB800).withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '🪙',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 4.5),
            Text(
              '$coins',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFFD54F),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Notification Bell (Real Unread Count) ──────────────────────────────────

  Widget _buildNotificationBell(
    BuildContext context,
    UserModel currentUser,
    WidgetRef ref,
    bool isDark,
    AppPalette palette,
  ) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final notifications = notificationsAsync.asData?.value ?? [];
    final unreadCount = notifications.where((n) => !n.isRead).length;
    final hasUnread = unreadCount > 0;
    final displayCount = unreadCount >= 10 ? '9+' : '$unreadCount';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildHeaderIconButton(
          context: context,
          icon: hasUnread ? Icons.notifications_rounded : Icons.notifications_none_rounded,
          isDark: isDark,
          onTap: () {
            HapticFeedback.lightImpact();
            showNotificationsSheet(context, currentUser, ref);
          },
        ),
        if (hasUnread)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              decoration: BoxDecoration(
                color: palette.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF090C15) : Colors.white,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.primary.withValues(alpha: 0.6),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  displayCount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Header Icon Button ─────────────────────────────────────────────────────

  Widget _buildHeaderIconButton({
    required BuildContext context,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark ? const Color(0xFF161026).withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.04),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: Icon(
            icon,
            size: 17,
            color: isDark ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  // ── User Profile Avatar ────────────────────────────────────────────────────

  Widget _buildProfileAvatar(
    BuildContext context,
    UserModel currentUser,
    bool isDark,
    AppPalette palette,
  ) {
    final avatarUrl = currentUser.avatarUrl;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/profile');
      },
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: palette.primaryGradient,
          boxShadow: [
            BoxShadow(
              color: palette.primary.withValues(alpha: 0.35),
              blurRadius: 6,
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.5),
        child: ClipOval(
          child: Container(
            color: isDark ? const Color(0xFF161026) : Colors.white,
            child: avatarUrl != null && avatarUrl.isNotEmpty
                ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    width: 31,
                    height: 31,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person_rounded,
                      size: 17,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  )
                : Icon(
                    Icons.person_rounded,
                    size: 17,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
          ),
        ),
      ),
    );
  }
}
