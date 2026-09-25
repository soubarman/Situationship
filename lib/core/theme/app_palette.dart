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
  cyber,  // Cyber Lime / Lilac
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

  // ─── 🌸 Girl Mode (Soft Rose & Blush) ──────────────────────────────────────
  static const female = AppPalette(
    id: 'female',
    displayName: 'Girl Mode (Rose)',
    primary: Color(0xFFD64F84),        // Soft rose — elegant, not neon
    secondary: Color(0xFFB5476B),      // Dusky mauve-rose
    accent: Color(0xFFE8729A),         // Warm blush accent
    backgroundTint: Color(0xFF150C18), // Deep plum-black
    surfaceTint: Color(0xFF1E1128),    // Muted purple-rose surface
    streakBg: Color(0xFF1C0F1F),
    streakBorder: Color(0xFFD64F84),
    streakContentColor: Color(0xFFE8729A),
    verifiedBadgeBg: Color(0xFFD64F84),
    verifiedIconColor: Colors.white,
    verifiedIcon: Icons.check_rounded,
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD64F84), Color(0xFFB5476B)],
    ),
    navPillGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD64F84), Color(0xFFB5476B)],
    ),
    logoGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFD64F84), // Soft rose
        Color(0xFFE8729A), // Warm blush
        Color(0xFFFCE7F3), // Blush white highlight
        Color(0xFFE8729A), // Warm blush
        Color(0xFFD64F84), // Soft rose
      ],
      stops: [0.0, 0.28, 0.55, 0.82, 1.0],
    ),
  );

  // ─── ⚡ Boy Mode (Sapphire & Steel Blue) ────────────────────────────────────
  static const male = AppPalette(
    id: 'male',
    displayName: 'Boy Mode (Sapphire)',
    primary: Color(0xFF2D6FD4),        // Rich sapphire — deep and confident
    secondary: Color(0xFF48AADB),      // Soft steel blue
    accent: Color(0xFF6AC2E8),         // Light sky accent
    backgroundTint: Color(0xFF080F1F), // Deep navy-black
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
        Color(0xFF2D6FD4), // Sapphire
        Color(0xFF6AC2E8), // Sky blue
        Color(0xFFDCEEFA), // Pale ice highlight
        Color(0xFF48AADB), // Steel blue
        Color(0xFF1E5BB8), // Deep sapphire
      ],
      stops: [0.0, 0.28, 0.55, 0.82, 1.0],
    ),
  );

  // ─── 🌿 Cyber Sage / Default Signature ─────────────────────────────────────
  static const cyber = AppPalette(
    id: 'cyber',
    displayName: 'Cyber Sage',
    primary: Color(0xFF8EC93D),        // Muted chartreuse — calm, not glaring
    secondary: Color(0xFFB95DD4),      // Soft orchid
    accent: Color(0xFF9ED64E),         // Sage-lime accent
    backgroundTint: Color(0xFF0C0D15),
    surfaceTint: Color(0xFF141622),
    streakBg: Color(0xFF16201A),
    streakBorder: Color(0xFF8EC93D),
    streakContentColor: Color(0xFF9ED64E),
    verifiedBadgeBg: Color(0xFF8EC93D),
    verifiedIconColor: Color(0xFF0E1A10),
    verifiedIcon: Icons.verified_user_rounded,
    primaryGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8EC93D), Color(0xFF5DBD6A)],
    ),
    navPillGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8EC93D), Color(0xFF78B530)],
    ),
    logoGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF8EC93D), // Muted chartreuse
        Color(0xFFC5E882), // Light sage
        Color(0xFFEDE9FF), // Soft lavender highlight
        Color(0xFFCB8FE6), // Soft orchid
        Color(0xFFB95DD4), // Rich orchid
      ],
      stops: [0.0, 0.28, 0.55, 0.82, 1.0],
    ),
  );
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
  if (vibe == ThemeVibe.cyber) return AppPalette.cyber;

  // Otherwise, automatically derive from current user's registered gender:
  final user = ref.watch(currentUserProvider);
  if (user.isFemale) return AppPalette.female;
  if (user.isMale) return AppPalette.male;

  // Default fallback for guest or other
  return AppPalette.cyber;
});
