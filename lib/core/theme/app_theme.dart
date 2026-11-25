import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_palette.dart';
import 'design_tokens.dart';

class AppTheme {
  static AppPalette _activePalette = AppPalette.male;

  static void setPalette(AppPalette palette) {
    _activePalette = palette;
  }
  static AppPalette get activePalette => _activePalette;

  // ─── Brand Color Palette (Obsidian & Luminescence) ─────────────────────────
  static Color get primaryPink   => _activePalette.primary;
  static Color get hotPink       => _activePalette.primary;
  static Color get blushPink     => _activePalette.backgroundTint;
  static const Color deepPlum    = Color(0xFF160A22);

  // Dynamic aliases mapping to active palette
  static Color get primaryBlue  => _activePalette.primary;
  static Color get primaryGreen => _activePalette.secondary;
  static Color get accentPurple => _activePalette.secondary;
  static Color get accentPink   => _activePalette.accent;

  // ─── Dark Mode Surfaces (Midnight Obsidian) ─────────────────────────────────
  static Color get darkBg      => _activePalette.backgroundTint;
  static Color get darkSurface => _activePalette.surfaceTint;
  static const Color darkCard    = Color(0xFF15141E);
  static const Color darkBorder  = Color(0x1FFFFFFF);
  static const Color darkGlass   = Color(0x0FFFFFFF);

  // ─── Light Mode Surfaces (Mapped to dark obsidian for uniform elegance) ─────
  static const Color lightBg      = Color(0xFF09090D);
  static const Color lightSurface = Color(0xFF13131A);
  static const Color lightCard    = Color(0xFF161620);
  static const Color lightGlass   = Color(0x1AFFFFFF);

  // ─── Text Tokens ───────────────────────────────────────────────────────────
  static const Color textPrimary   = DesignTokens.textPrimary;
  static const Color textSecondary = DesignTokens.textSecondary;
  static const Color textTertiary  = DesignTokens.textMuted;

  // ─── Semantic Tokens ───────────────────────────────────────────────────────
  static Color get success => DesignTokens.success;
  static const Color error   = DesignTokens.error;
  static const Color warning = DesignTokens.warning;
  static const Color gold    = DesignTokens.gold;

  // ─── Gradients ─────────────────────────────────────────────────────────────
  static LinearGradient get primaryGradient => _activePalette.primaryGradient;
  static LinearGradient get vibeGradient => _activePalette.primaryGradient;

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF14121E), Color(0xFF09090D)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xEE09090D)],
  );

  static LinearGradient get matchGradient => _activePalette.primaryGradient;
  static LinearGradient get limeGradient => _activePalette.primaryGradient;

  // ─── Glassmorphism & Card Decorators ───────────────────────────────────────

  /// Core micro-glass card
  static BoxDecoration glassDecoration({required bool isDark, double radius = 20}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.10),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  /// Premium elevated card with crisp hairline border and soft glow
  static BoxDecoration premiumCard({required bool isDark, double radius = 22}) {
    return BoxDecoration(
      color: darkCard,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.08),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.40),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: primaryBlue.withValues(alpha: 0.06),
          blurRadius: 36,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  /// Frosted pill badge
  static BoxDecoration frostPill({required bool isDark}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.12),
        width: 0.8,
      ),
    );
  }

  // ─── Theme Handlers (Strictly Dark Theme Only) ──────────────────────────────
  static ThemeData get lightTheme => darkThemeWith(_activePalette);

  static ThemeData lightThemeWith([AppPalette? palette]) =>
      darkThemeWith(palette ?? _activePalette);

  // ─── Dark Theme ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => darkThemeWith(_activePalette);

  static ThemeData darkThemeWith([AppPalette? palette]) {
    final p = palette ?? _activePalette;
    final primary = p.primary;
    final secondary = p.secondary;
    final accent = p.accent;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        tertiary: accent,
        surface: p.surfaceTint,
        surfaceContainerHighest: darkCard,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        error: error,
      ),
      scaffoldBackgroundColor: p.backgroundTint,
      textTheme: _buildTextTheme(isDark: true),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.4,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.07), width: 1.0),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        selectedColor: primary.withValues(alpha: 0.22),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        shape: const StadiumBorder(),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      inputDecorationTheme: _buildInputTheme(isDark: true, primaryColor: primary),
      elevatedButtonTheme: _buildElevatedButtonTheme(primary),
      outlinedButtonTheme: _buildOutlinedButtonTheme(primary),
      navigationBarTheme: _buildNavBarTheme(isDark: true, primaryColor: primary),
      dialogTheme: DialogThemeData(
        backgroundColor: DesignTokens.obsidianModal,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 1.0),
        ),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
        backgroundColor: DesignTokens.obsidianElevated,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.07),
        thickness: 0.8,
      ),
    );
  }

  // ─── Text Theme ────────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme({required bool isDark}) {
    const color = textPrimary;
    const sub   = textSecondary;
    return TextTheme(
      displayLarge:  GoogleFonts.plusJakartaSans(fontSize: 44, fontWeight: FontWeight.w800, color: color, letterSpacing: -1.2),
      displayMedium: GoogleFonts.plusJakartaSans(fontSize: 34, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.8),
      displaySmall:  GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.5),
      headlineLarge: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.3),
      headlineMedium:GoogleFonts.plusJakartaSans(fontSize: 19, fontWeight: FontWeight.w600, color: color),
      headlineSmall: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w600, color: color),
      titleLarge:    GoogleFonts.plusJakartaSans(fontSize: 15.5, fontWeight: FontWeight.w600, color: color),
      titleMedium:   GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: color),
      bodyLarge:     GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w400, color: sub, height: 1.5),
      bodyMedium:    GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w400, color: sub, height: 1.45),
      bodySmall:     GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w400, color: textTertiary),
      labelLarge:    GoogleFonts.plusJakartaSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.3),
    );
  }

  // ─── Input Theme ───────────────────────────────────────────────────────────
  static InputDecorationTheme _buildInputTheme({required bool isDark, required Color primaryColor}) {
    return InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: BorderSide(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: BorderSide(color: primaryColor, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        borderSide: const BorderSide(color: error, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      ),
      floatingLabelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: primaryColor,
      ),
      hintStyle: GoogleFonts.plusJakartaSans(
        fontSize: 13.5,
        color: textTertiary,
      ),
    );
  }

  // ─── Button Themes ─────────────────────────────────────────────────────────
  static ElevatedButtonThemeData _buildElevatedButtonTheme([Color? primary]) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary ?? primaryPink,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusFull)),
        elevation: 0,
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonTheme([Color? primary]) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusFull)),
        side: BorderSide(color: primary ?? primaryBlue, width: 1.2),
        textStyle: GoogleFonts.plusJakartaSans(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ─── Navigation Bar Theme ──────────────────────────────────────────────────
  static NavigationBarThemeData _buildNavBarTheme({required bool isDark, required Color primaryColor}) {
    return NavigationBarThemeData(
      backgroundColor: darkSurface,
      indicatorColor: primaryColor.withValues(alpha: 0.15),
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: primaryColor);
        }
        return GoogleFonts.plusJakartaSans(fontSize: 11, color: textTertiary);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: primaryColor, size: 22);
        }
        return const IconThemeData(color: textTertiary, size: 22);
      }),
    );
  }
}
