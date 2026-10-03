import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../providers/app_state_provider.dart';
import '../providers/shared_prefs_provider.dart';

enum ThemeVibe {
  auto,
  female, // Girl Mode (Pink)
  male,   // Boy Mode (Blue)
}

class AppPalette {
  final String id;
  final String displayName;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color backgroundTint;
  final Color surfaceTint;
  
  // Streak / Coin Pill
  final Color streakBg;
  final Color streakBorder;
  final Color streakContentColor;

  // Verified Badge
  final Color verifiedBadgeBg;
  final Color verifiedIconColor;
  final IconData verifiedIcon;

  // Gradients
  final LinearGradient primaryGradient;
  final LinearGradient navPillGradient;
  final LinearGradient logoGradient;

  const AppPalette({
    required this.id,
    required this.displayName,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.backgroundTint,
    required this.surfaceTint,
    required this.streakBg,
    required this.streakBorder,
    required this.streakContentColor,
    required this.verifiedBadgeBg,
    required this.verifiedIconColor,
    required this.verifiedIcon,
    required this.primaryGradient,
    required this.navPillGradient,
    required this.logoGradient,
  });

  // ─── 🌸 Girl Mode (Pink) ───────────────────────────────────────────────────
  static const female = AppPalette(
    id: 'female',
    displayName: 'Girl Mode (Pink)',
    primary: Color(0xFFFF5277),        // Vibrant signature coral pink
    secondary: Color(0xFFD63B6E),      // Deep berry pink
    accent: Color(0xFFFF7E9E),         // Warm blush pink accent
    backgroundTint: Color(0xFF140B16), // Deep plum-obsidian
    surfaceTint: Color(0xFF1E1022),    // Muted purple-rose surface
    streakBg: Color(0xFF1C0F1F),
    streakBorder: Color(0xFFFF5277),
    streakContentColor: Color(0xFFFF7E9E),
    verifiedBadgeBg: Color(0xFFFF5277),
    verifiedIconColor: Colors.white,
    verifiedIcon: Icons.check_rounded,
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF5277), Color(0xFFD63B6E)],
    ),
    navPillGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF5277), Color(0xFFE03868)],
    ),
    logoGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFF5277),
        Color(0xFFFF7597),
        Color(0xFFFFE0EA),
        Color(0xFFFF7597),
        Color(0xFFFF5277),
      ],
      stops: [0.0, 0.28, 0.55, 0.82, 1.0],
    ),
  );

  // ─── ⚡ Boy Mode (Sapphire & Electric Blue) ─────────────────────────────────
  static const male = AppPalette(
    id: 'male',
    displayName: 'Boy Mode (Blue)',
    primary: Color(0xFF2D6FD4),        // Electric sapphire blue
    secondary: Color(0xFF48AADB),      // Soft steel blue
    accent: Color(0xFF6AC2E8),         // Bright ice blue accent
    backgroundTint: Color(0xFF080F1F), // Deep navy-obsidian
    surfaceTint: Color(0xFF0F1D38),    // Muted navy surface
    streakBg: Color(0xFF0A172E),
    streakBorder: Color(0xFF48AADB),
    streakContentColor: Color(0xFF6AC2E8),
    verifiedBadgeBg: Color(0xFF2D6FD4),
    verifiedIconColor: Colors.white,
    verifiedIcon: Icons.verified_user_rounded,
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2D6FD4), Color(0xFF48AADB)],
    ),
    navPillGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2D6FD4), Color(0xFF3A8FCC)],
    ),
    logoGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF2D6FD4),
        Color(0xFF6AC2E8),
        Color(0xFFDCEEFA),
        Color(0xFF48AADB),
        Color(0xFF1E5BB8),
      ],
      stops: [0.0, 0.28, 0.55, 0.82, 1.0],
    ),
  );

  // Backwards compatibility alias
  static const cyber = male;
}

// ─── State Notifier for Theme Vibe Selection ─────────────────────────────────

class ThemeVibeNotifier extends StateNotifier<ThemeVibe> {
  final SharedPreferences? _prefs;
  static const _key = 'user_theme_vibe';

  ThemeVibeNotifier(this._prefs) : super(ThemeVibe.auto) {
    _loadVibe();
  }

  void _loadVibe() {
    final prefs = _prefs;
    if (prefs == null) return;
    final saved = prefs.getString(_key);
    if (saved != null) {
      state = ThemeVibe.values.firstWhere(
        (v) => v.name == saved,
        orElse: () => ThemeVibe.auto,
      );
    }
  }

  Future<void> setVibe(ThemeVibe vibe) async {
    state = vibe;
    await _prefs?.setString(_key, vibe.name);
  }
}

final themeVibeProvider = StateNotifierProvider<ThemeVibeNotifier, ThemeVibe>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeVibeNotifier(prefs);
});

// ─── Active Palette Provider (Dynamic based on Gender or Override) ───────────

final appPaletteProvider = Provider<AppPalette>((ref) {
  final vibe = ref.watch(themeVibeProvider);

  // Manual override takes precedence if not set to auto
  if (vibe == ThemeVibe.female) return AppPalette.female;
  if (vibe == ThemeVibe.male) return AppPalette.male;

  // Otherwise, automatically derive from current user's registered gender:
  final user = ref.watch(currentUserProvider);
  if (user.isFemale) return AppPalette.female;
  if (user.isMale) return AppPalette.male;

  // Default fallback for guest or other: Blue for boys
  return AppPalette.male;
});
