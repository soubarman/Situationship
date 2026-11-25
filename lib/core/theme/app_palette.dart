import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../providers/app_state_provider.dart';
import '../providers/shared_prefs_provider.dart';

enum ThemeVibe {
  auto,
  female, // Girl Mode (Luminous Rose)
  male,   // Boy Mode (Electric Sapphire)
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

  // ─── 🌸 Girl Mode (Luminous Coral & Rose) ──────────────────────────────────
  static const female = AppPalette(
    id: 'female',
    displayName: 'Girl Mode (Rose)',
    primary: Color(0xFFFF3366),        // Luminous signature rose-coral
    secondary: Color(0xFFE11D48),      // Crimson rose
    accent: Color(0xFFFF6B8B),         // Soft blush luminescence
    backgroundTint: Color(0xFF0D0811), // Deep velvet obsidian with warm rose undertone
    surfaceTint: Color(0xFF160F1A),    // Elevated rose-obsidian surface
    streakBg: Color(0xFF1F1224),
    streakBorder: Color(0xFFFF3366),
    streakContentColor: Color(0xFFFF6B8B),
    verifiedBadgeBg: Color(0xFFFF3366),
    verifiedIconColor: Colors.white,
    verifiedIcon: Icons.check_rounded,
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF3366), Color(0xFFE11D48)],
    ),
    navPillGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF3366), Color(0xFFF43F5E)],
    ),
    logoGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFF3366),
        Color(0xFFFF6B8B),
        Color(0xFFFFF1F2),
        Color(0xFFFF6B8B),
        Color(0xFFFF3366),
      ],
      stops: [0.0, 0.28, 0.55, 0.82, 1.0],
    ),
  );

  // ─── ⚡ Boy Mode (Electric Sapphire & Azure) ────────────────────────────────
  static const male = AppPalette(
    id: 'male',
    displayName: 'Boy Mode (Sapphire)',
    primary: Color(0xFF2563EB),        // Electric cobalt/sapphire
    secondary: Color(0xFF0284C7),      // Vivid azure
    accent: Color(0xFF38BDF8),         // Sky neon accent
    backgroundTint: Color(0xFF070B14), // Deep velvet obsidian with marine undertone
    surfaceTint: Color(0xFF0F1726),    // Elevated oceanic obsidian surface
    streakBg: Color(0xFF0B192E),
    streakBorder: Color(0xFF0284C7),
    streakContentColor: Color(0xFF38BDF8),
    verifiedBadgeBg: Color(0xFF2563EB),
    verifiedIconColor: Colors.white,
    verifiedIcon: Icons.verified_user_rounded,
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2563EB), Color(0xFF0284C7)],
    ),
    navPillGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
    ),
    logoGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF2563EB),
        Color(0xFF38BDF8),
        Color(0xFFF0F9FF),
        Color(0xFF0284C7),
        Color(0xFF1D4ED8),
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
    if (saved == 'female') {
      state = ThemeVibe.female;
    } else if (saved == 'male') {
      state = ThemeVibe.male;
    } else {
      state = ThemeVibe.auto;
    }
  }

  Future<void> setVibe(ThemeVibe vibe) async {
    state = vibe;
    final prefs = _prefs;
    if (prefs == null) return;
    if (vibe == ThemeVibe.female) {
      await prefs.setString(_key, 'female');
    } else if (vibe == ThemeVibe.male) {
      await prefs.setString(_key, 'male');
    } else {
      await prefs.remove(_key);
    }
  }
}

final themeVibeProvider = StateNotifierProvider<ThemeVibeNotifier, ThemeVibe>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeVibeNotifier(prefs);
});

final appPaletteProvider = Provider<AppPalette>((ref) {
  final vibe = ref.watch(themeVibeProvider);
  if (vibe == ThemeVibe.female) return AppPalette.female;
  if (vibe == ThemeVibe.male) return AppPalette.male;

  final user = ref.watch(currentUserProvider);
  final gender = user.gender.toLowerCase().trim();
  if (gender == 'female' || gender == 'f' || gender == 'woman') {
    return AppPalette.female;
  }
  return AppPalette.male;
});
