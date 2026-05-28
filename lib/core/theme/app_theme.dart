import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Brand Color Palette ───────────────────────────────────────────────────
  static const Color primaryBlue  = Color(0xFF6ECBF5);
  static const Color primaryGreen = Color(0xFF7EEECB);
  static const Color accentPurple = Color(0xFFB8A9FF);
  static const Color accentPink   = Color(0xFFFF8EC8);

  // ─── Dark Mode Surfaces ────────────────────────────────────────────────────
  static const Color darkBg      = Color(0xFF0A0D14);
  static const Color darkSurface = Color(0xFF141924);
  static const Color darkCard    = Color(0xFF1C2232);
  static const Color darkBorder  = Color(0xFF252E42);
  static const Color darkGlass   = Color(0x1AFFFFFF); // 10% white

  // ─── Light Mode Surfaces ───────────────────────────────────────────────────
  static const Color lightBg      = Color(0xFFF4F7FF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard    = Color(0xFFFBFCFF);
  static const Color lightGlass   = Color(0xBFFFFFFF); // 75% white

  // ─── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary  = Color(0xFF9CA3AF);

  // ─── Semantic ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF34D399);
  static const Color error   = Color(0xFFF87171);
  static const Color warning = Color(0xFFFBBF24);

  // ─── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, accentPurple],
  );

  static const LinearGradient vibeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, primaryGreen],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A1F2E), Color(0xFF0A0D14)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC000000)],
  );

  static const LinearGradient matchGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBlue, primaryGreen],
  );

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
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primaryBlue,
        secondary: primaryGreen,
        tertiary: accentPurple,
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
      cardTheme: CardTheme(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withOpacity(0.7),
        selectedColor: primaryBlue.withOpacity(0.15),
        labelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
        side: BorderSide(color: Colors.black.withOpacity(0.07)),
      ),
      inputDecorationTheme: _buildInputTheme(isDark: false),
      elevatedButtonTheme: _buildElevatedButtonTheme(),
      outlinedButtonTheme: _buildOutlinedButtonTheme(),
      navigationBarTheme: _buildNavBarTheme(isDark: false),
      dialogTheme: DialogTheme(
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
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primaryBlue,
        secondary: primaryGreen,
        tertiary: accentPurple,
        surface: darkSurface,
        surfaceContainerHighest: darkCard,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        error: error,
      ),
      scaffoldBackgroundColor: darkBg,
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
      cardTheme: CardTheme(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withOpacity(0.06),
        selectedColor: primaryBlue.withOpacity(0.2),
        labelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
        shape: const StadiumBorder(),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      inputDecorationTheme: _buildInputTheme(isDark: true),
      elevatedButtonTheme: _buildElevatedButtonTheme(),
      outlinedButtonTheme: _buildOutlinedButtonTheme(),
      navigationBarTheme: _buildNavBarTheme(isDark: true),
      dialogTheme: DialogTheme(
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
        borderSide: const BorderSide(color: primaryBlue, width: 1.8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      hintStyle: GoogleFonts.outfit(
        fontSize: 14,
        color: isDark ? Colors.white38 : textTertiary,
      ),
    );
  }

  // ─── Button Themes ─────────────────────────────────────────────────────────
  static ElevatedButtonThemeData _buildElevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
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
        side: const BorderSide(color: primaryBlue, width: 1.5),
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
          return const IconThemeData(color: primaryBlue, size: 24);
        }
        return IconThemeData(color: isDark ? Colors.white38 : textTertiary, size: 24);
      }),
    );
  }
}
