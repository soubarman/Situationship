import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized Design System Tokens for Situationship.
///
/// Designed with an Obsidian & Luminescence aesthetic:
/// Deep velvet-black obsidian bases paired with ultra-crisp hairline micro-borders,
/// refined typography, and purposeful luminescence.
abstract class DesignTokens {
  // ─── Neutral Surfaces (Deep Obsidian Palette) ──────────────────────────────
  static const Color obsidianBase     = Color(0xFF09090D); // App background
  static const Color obsidianElevated = Color(0xFF111117); // Nav bar / bottom sheets
  static const Color obsidianCard     = Color(0xFF161620); // Cards & tiles
  static const Color obsidianInput    = Color(0xFF1A1A26); // Input fields & active chips
  static const Color obsidianModal    = Color(0xFF14141E); // Dialogs & sheets

  // ─── Text Colors (High Legibility & Contrast) ──────────────────────────────
  static const Color textPrimary   = Color(0xFFF8FAFC); // 98% pure white
  static const Color textSecondary = Color(0xFF94A3B8); // Slate silver
  static const Color textMuted     = Color(0xFF64748B); // Slate mist
  static const Color textDisabled  = Color(0xFF475569); // Dark slate
  static const Color textTertiary  = Color(0xFF64748B); // Alias for textMuted

  // ─── Semantic & Feedback Colors ───────────────────────────────────────────
  static const Color success = Color(0xFF10B981); // Emerald glow
  static const Color warning = Color(0xFFF59E0B); // Warm amber
  static const Color error   = Color(0xFFEF4444); // Crimson red
  static const Color info    = Color(0xFF38BDF8); // Sky blue
  static const Color gold    = Color(0xFFFBBF24); // Coin & Spotlight gold
  static const Color purple  = Color(0xFFA855F7); // VIP & Superlike purple

  // ─── Spacing Scale (4pt Grid) ──────────────────────────────────────────────
  static const double space2xs = 4.0;
  static const double spaceXs  = 8.0;
  static const double spaceSm  = 12.0;
  static const double spaceMd  = 16.0;
  static const double spaceLg  = 20.0;
  static const double spaceXl  = 24.0;
  static const double space2xl = 32.0;
  static const double space3xl = 40.0;
  static const double space4xl = 48.0;

  // Numeric spacing aliases
  static const double spacing4  = 4.0;
  static const double spacing8  = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;

  // ─── Corner Radii System ───────────────────────────────────────────────────
  static const double radiusXs   = 6.0;
  static const double radiusSm   = 10.0;
  static const double radiusMd   = 14.0;
  static const double radiusLg   = 18.0;
  static const double radiusXl   = 24.0;
  static const double radius2xl  = 30.0;
  static const double radiusFull = 999.0; // Stadium / pill

  // Numeric radius aliases
  static const double radius12 = 12.0;
  static const double radius16 = 16.0;
  static const double radius20 = 20.0;
  static const double radius24 = 24.0;

  // ─── Micro-Borders (Hairline Precision) ────────────────────────────────────
  static Color get hairline => Colors.white.withValues(alpha: 0.08);
  static Border hairlineBorder([Color? color]) => Border.all(
    color: color ?? Colors.white.withValues(alpha: 0.08),
    width: 1.0,
  );

  static Border activeBorder(Color accentColor) => Border.all(
    color: accentColor.withValues(alpha: 0.45),
    width: 1.2,
  );

  // ─── Elevation & Shadow System ─────────────────────────────────────────────
  static List<BoxShadow> cardShadow({Color? glowColor}) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
    if (glowColor != null)
      BoxShadow(
        color: glowColor.withValues(alpha: 0.12),
        blurRadius: 28,
        offset: const Offset(0, 8),
      ),
  ];

  static List<BoxShadow> floatingShadow({Color? glowColor}) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.55),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
    if (glowColor != null)
      BoxShadow(
        color: glowColor.withValues(alpha: 0.22),
        blurRadius: 36,
        offset: const Offset(0, 6),
      ),
  ];

  static List<BoxShadow> buttonGlow(Color primaryColor) => [
    BoxShadow(
      color: primaryColor.withValues(alpha: 0.35),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];

  // ─── Surface BoxDecorations ────────────────────────────────────────────────
  /// Standard container / card decoration with hairline border
  static BoxDecoration cardDecoration({
    double radius = radiusLg,
    Color? backgroundColor,
    Color? borderColor,
    Color? glowColor,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? obsidianCard,
      borderRadius: BorderRadius.circular(radius),
      border: hairlineBorder(borderColor),
      boxShadow: cardShadow(glowColor: glowColor),
    );
  }

  /// Frosted glass surface with subtle translucency
  static BoxDecoration glassDecoration({
    double radius = radiusLg,
    Color? tintColor,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: (tintColor ?? Colors.white).withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: 0.10),
        width: 1.0,
      ),
    );
  }

  /// Elevated pill button/badge
  static BoxDecoration pillDecoration({
    Color? backgroundColor,
    Color? borderColor,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? obsidianInput,
      borderRadius: BorderRadius.circular(radiusFull),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: 0.10),
        width: 1.0,
      ),
    );
  }

  // ─── Animation Curves & Durations ──────────────────────────────────────────
  static const Duration durationFast   = Duration(milliseconds: 140);
  static const Duration durationNormal = Duration(milliseconds: 240);
  static const Duration durationSlow   = Duration(milliseconds: 360);

  static const Curve curveSpring = Curves.easeOutCubic;
  static const Curve curveEnter  = Curves.easeOutQuart;
  static const Curve curveExit   = Curves.easeInCubic;
  static const Curve curveDecelerate = Curves.easeOutCubic;

  // ─── Typography Scale ──────────────────────────────────────────────────────
  static TextStyle fontDisplay({
    double fontSize = 28,
    FontWeight fontWeight = FontWeight.w800,
    Color color = textPrimary,
    double? letterSpacing = -0.5,
    double? height,
  }) => GoogleFonts.plusJakartaSans(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color,
    height: height,
  );

  static TextStyle fontBody({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = textSecondary,
    double? letterSpacing,
    double? height = 1.4,
  }) => GoogleFonts.plusJakartaSans(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color,
    height: height,
  );
  static TextStyle displayHero({Color color = textPrimary}) => GoogleFonts.plusJakartaSans(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    color: color,
    height: 1.2,
  );

  static TextStyle headingLarge({Color color = textPrimary}) => GoogleFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: color,
    height: 1.25,
  );

  static TextStyle headingMedium({Color color = textPrimary}) => GoogleFonts.plusJakartaSans(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: color,
    height: 1.3,
  );

  static TextStyle titleMedium({Color color = textPrimary}) => GoogleFonts.plusJakartaSans(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: color,
  );

  static TextStyle bodyLarge({Color color = textSecondary}) => GoogleFonts.plusJakartaSans(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.5,
  );

  static TextStyle bodyMedium({Color color = textSecondary}) => GoogleFonts.plusJakartaSans(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    color: color,
    height: 1.45,
  );

  static TextStyle labelBold({Color color = textPrimary}) => GoogleFonts.plusJakartaSans(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: color,
  );

  static TextStyle microBadge({Color color = textMuted}) => GoogleFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: color,
  );
}
