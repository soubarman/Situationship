import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/design_tokens.dart';
import '../../features/boost/providers/boost_provider.dart';

final currentIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  static const List<_NavItem> _items = [
    _NavItem(icon: Icons.home_outlined,        activeIcon: Icons.home_rounded,         label: 'Home',     path: '/feed'),
    _NavItem(icon: Icons.favorite_outline,     activeIcon: Icons.favorite_rounded,     label: 'Matches',  path: '/match'),
    _NavItem(icon: Icons.chat_bubble_outline,  activeIcon: Icons.chat_bubble_rounded,  label: 'Chat',     path: '/chats'),
    _NavItem(icon: Icons.group_outlined,       activeIcon: Icons.group_rounded,        label: 'People',   path: '/communities'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(boostNotificationListenerProvider);

    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final location = GoRouterState.of(context).matchedLocation;
    final palette  = ref.watch(appPaletteProvider);

    int currentIndex = 0;
    if (location.startsWith('/match')) {
      currentIndex = 1;
    } else if (location.startsWith('/chats')) {
      currentIndex = 2;
    } else if (location.startsWith('/communities')) {
      currentIndex = 3;
    }

    final safeBottom = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && currentIndex != 0) {
          context.go('/feed');
        }
      },
      child: Scaffold(
        extendBody: true,
        body: child,
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 10 + safeBottom),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: isDark
                      ? DesignTokens.obsidianElevated.withValues(alpha: 0.94)
                      : Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: palette.primary.withValues(alpha: isDark ? 0.12 : 0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(_items.length, (i) {
                      return _NavBarItem(
                        item: _items[i],
                        isSelected: currentIndex == i,
                        isDark: isDark,
                        hasDot: i == 2, // chat alert dot
                        palette: palette,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.go(_items[i].path);
                        },
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.path});
}

class _NavBarItem extends StatefulWidget {
  final _NavItem item;
  final bool isSelected;
  final bool isDark;
  final bool hasDot;
  final AppPalette palette;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.item,
    required this.isSelected,
    required this.isDark,
    this.hasDot = false,
    required this.palette,
    required this.onTap,
  });

  @override
  State<_NavBarItem> createState() => _NavBarItemState();
}

class _NavBarItemState extends State<_NavBarItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: DesignTokens.durationFast,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.90)
        .animate(CurvedAnimation(parent: _ctrl, curve: DesignTokens.curveSpring));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.isSelected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: AnimatedBuilder(
          animation: _scale,
          builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: DesignTokens.curveSpring,
            padding: EdgeInsets.symmetric(horizontal: sel ? 16 : 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: sel ? widget.palette.navPillGradient : null,
              color: sel
                  ? null
                  : (_isHovered ? Colors.white.withValues(alpha: 0.08) : Colors.transparent),
              borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
              boxShadow: sel
                  ? [
                      BoxShadow(
                        color: widget.palette.primary.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      sel ? widget.item.activeIcon : widget.item.icon,
                      size: 20,
                      color: sel
                          ? Colors.white
                          : (widget.isDark
                              ? (_isHovered
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.45))
                              : AppTheme.textTertiary),
                    ),
                    if (widget.hasDot && !sel)
                      Positioned(
                        top: -2,
                        right: -3,
                        child: Container(
                          width: 6.5,
                          height: 6.5,
                          decoration: BoxDecoration(
                            color: widget.palette.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: widget.palette.primary.withValues(alpha: 0.9),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (sel) ...[
                  const SizedBox(width: 7),
                  Text(
                    widget.item.label,
                    style: DesignTokens.labelBold(color: Colors.white).copyWith(
                      fontSize: 12.5,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
