import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_palette.dart';

class AppTheme {
  static AppPalette _activePalette = AppPalette.male;

  static void setPalette(AppPalette palette) {
    _activePalette = palette;
  }
  static AppPalette get activePalette => _activePalette;

  // ─── Brand Color Palette (Gen-Z Neon & Obsidian) ───────────────────────────
  static Color get primaryPink   => _activePalette.primary;
  static Color get hotPink       => _activePalette.primary;
  static Color get blushPink     => _activePalette.backgroundTint;
  static const Color deepPlum    = Color(0xFF1E0A30);

  // Backward compat aliases — all map dynamically to active palette
  static Color get primaryBlue  => _activePalette.primary;
  static Color get primaryGreen => _activePalette.secondary;
  static Color get accentPurple => _activePalette.secondary;
  static Color get accentPink   => _activePalette.accent;

  // ─── Dark Mode Surfaces (Midnight Obsidian) ─────────────────────────────────
  static Color get darkBg      => _activePalette.backgroundTint;
  static Color get darkSurface => _activePalette.surfaceTint;
  static const Color darkCard    = Color(0xFF19112E);
  static const Color darkBorder  = Color(0x24FFFFFF);
  static const Color darkGlass   = Color(0x1AFFFFFF); // 10% white

  // ─── Light Mode Surfaces ───────────────────────────────────────────────────
  static const Color lightBg      = Color(0xFFF7F5FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard    = Color(0xFFFAF8FF);
  static const Color lightGlass   = Color(0xBFFFFFFF); // 75% white

  // ─── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary  = Color(0xFF9CA3AF);

  // ─── Semantic ──────────────────────────────────────────────────────────────
  static Color get success => _activePalette.primary;
  static const Color error   = Color(0xFFF87171);
  static const Color warning = Color(0xFFFBBF24);

  // ─── Gradients ─────────────────────────────────────────────────────────────
  static LinearGradient get primaryGradient => _activePalette.primaryGradient;
  static LinearGradient get vibeGradient => _activePalette.primaryGradient;

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF17102C), Color(0xFF0B0715)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xDD000000)],
  );

  static LinearGradient get matchGradient => _activePalette.primaryGradient;
  static LinearGradient get limeGradient => _activePalette.primaryGradient;

  // ─── Glassmorphism ─────────────────────────────────────────────────────────

  /// Core glass card (dark or light)
  static BoxDecoration glassDecoration({required bool isDark, double radius = 24}) {
    return BoxDecoration(
      color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.72),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.9),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.07),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Premium elevated card used for post cards
  static BoxDecoration premiumCard({required bool isDark, double radius = 28}) {
    return BoxDecoration(
      color: isDark ? darkCard.withOpacity(0.82) : Colors.white.withOpacity(0.88),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.045),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: isDark ? Colors.black.withOpacity(0.28) : Colors.black.withOpacity(0.06),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: primaryBlue.withOpacity(isDark ? 0.06 : 0.04),
          blurRadius: 48,
          offset: const Offset(0, 24),
        ),
      ],
    );
  }

  /// Frosted pill badge
  static BoxDecoration frostPill({required bool isDark}) {
    return BoxDecoration(
      color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.7),
      borderRadius: BorderRadius.circular(50),
      border: Border.all(
        color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.06),
        width: 0.8,
      ),
    );
  }

  // ─── Light Theme ───────────────────────────────────────────────────────────
  // ─── Light Theme ───────────────────────────────────────────────────────────
  static ThemeData get lightTheme => lightThemeWith(AppPalette.female);

  static ThemeData lightThemeWith([AppPalette palette = AppPalette.female]) {
    final primary = palette.primary;
    final secondary = palette.secondary;
    final accent = palette.accent;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        tertiary: accent,
        surface: lightSurface,
        surfaceContainerHighest: const Color(0xFFEDF0FF),
        onPrimary: Colors.white,
        onSecondary: textPrimary,
        error: error,
      ),
      scaffoldBackgroundColor: lightBg,
      textTheme: _buildTextTheme(isDark: false),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withOpacity(0.7),
        selectedColor: primary.withOpacity(0.15),
        labelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
        side: BorderSide(color: Colors.black.withOpacity(0.07)),
      ),
      inputDecorationTheme: _buildInputTheme(isDark: false),
      elevatedButtonTheme: _buildElevatedButtonTheme(primary),
      outlinedButtonTheme: _buildOutlinedButtonTheme(),
      navigationBarTheme: _buildNavBarTheme(isDark: false),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: const Color(0xFF1C2232),
        contentTextStyle: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withOpacity(0.06),
        thickness: 0.8,
      ),
    );
  }

  // ─── Dark Theme ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => darkThemeWith(AppPalette.female);

  static ThemeData darkThemeWith([AppPalette palette = AppPalette.female]) {
    final primary = palette.primary;
    final secondary = palette.secondary;
    final accent = palette.accent;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        tertiary: accent,
        surface: darkSurface,
        surfaceContainerHighest: darkCard,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        error: error,
      ),
      scaffoldBackgroundColor: palette.backgroundTint,
      textTheme: _buildTextTheme(isDark: true),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withOpacity(0.06),
        selectedColor: primary.withOpacity(0.2),
        labelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
        shape: const StadiumBorder(),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      inputDecorationTheme: _buildInputTheme(isDark: true),
      elevatedButtonTheme: _buildElevatedButtonTheme(primary),
      outlinedButtonTheme: _buildOutlinedButtonTheme(),
      navigationBarTheme: _buildNavBarTheme(isDark: true),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: darkCard,
        contentTextStyle: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.08),
        thickness: 0.8,
      ),
    );
  }

  // ─── Text Theme ────────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme({required bool isDark}) {
    final color = isDark ? Colors.white : textPrimary;
    final sub   = isDark ? Colors.white70 : textSecondary;
    return TextTheme(
      displayLarge:  GoogleFonts.outfit(fontSize: 48, fontWeight: FontWeight.w800, color: color, letterSpacing: -1.5),
      displayMedium: GoogleFonts.outfit(fontSize: 36, fontWeight: FontWeight.w700, color: color, letterSpacing: -1.0),
      displaySmall:  GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.5),
      headlineLarge: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.3),
      headlineMedium:GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w600, color: color),
      headlineSmall: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w600, color: color),
      titleLarge:    GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600, color: color),
      titleMedium:   GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500, color: color),
      bodyLarge:     GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w400, color: sub, height: 1.6),
      bodyMedium:    GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w400, color: sub, height: 1.5),
      bodySmall:     GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w400, color: isDark ? Colors.white38 : textTertiary),
      labelLarge:    GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.5),
    );
  }

  // ─── Input Theme ───────────────────────────────────────────────────────────
  static InputDecorationTheme _buildInputTheme({required bool isDark}) {
    return InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? Colors.white.withOpacity(0.06)
          : Colors.white.withOpacity(0.82),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08),
          width: 1.0,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: primaryBlue, width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      hintStyle: GoogleFonts.outfit(
        fontSize: 14,
        color: isDark ? Colors.white38 : textTertiary,
      ),
    );
  }

  // ─── Button Themes ─────────────────────────────────────────────────────────
  static ElevatedButtonThemeData _buildElevatedButtonTheme([Color? primary]) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary ?? primaryPink,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        elevation: 0,
        textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonTheme() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        side: BorderSide(color: primaryBlue, width: 1.5),
        textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ─── Navigation Bar Theme ──────────────────────────────────────────────────
  static NavigationBarThemeData _buildNavBarTheme({required bool isDark}) {
    return NavigationBarThemeData(
      backgroundColor: isDark ? darkSurface : Colors.white,
      indicatorColor: primaryBlue.withOpacity(0.15),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w700, color: primaryBlue);
        }
        return GoogleFonts.outfit(fontSize: 11, color: isDark ? Colors.white38 : textTertiary);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: primaryBlue, size: 24);
        }
        return IconThemeData(color: isDark ? Colors.white38 : textTertiary, size: 24);
      }),
    );
  }
}
