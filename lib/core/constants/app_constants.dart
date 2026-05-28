import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppColors {
  static const Color primaryBlue = AppTheme.primaryBlue;
  static const Color primaryGreen = AppTheme.primaryGreen;
  static const Color accentPurple = AppTheme.accentPurple;
  static const Color accentPink = AppTheme.accentPink;
  static const Color success = AppTheme.success;
  static const Color error = AppTheme.error;
  static const Color warning = AppTheme.warning;
}

class AppSizes {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const double radiusSm = 8;
  static const double radiusMd = 16;
  static const double radiusLg = 24;
  static const double radiusXl = 32;
  static const double radiusFull = 100;

  static const double iconSm = 18;
  static const double iconMd = 24;
  static const double iconLg = 32;

  static const EdgeInsets paddingScreen = EdgeInsets.symmetric(horizontal: 20);
  static const EdgeInsets paddingCard = EdgeInsets.all(16);
}

class AppStrings {
  static const String appName = 'Situationship';
  static const String tagline = 'Vibe. Match. Connect. 🔥';
}

class AppDurations {
  // Daily bonus cooldown in milliseconds (24 hours)
  static const int dailyBonusCooldownMs = 24 * 60 * 60 * 1000; // 86400000 ms

  // Animation durations
  static const Duration heartAnimation = Duration(milliseconds: 600);
  static const Duration scaleAnimation = Duration(milliseconds: 120);
  static const Duration fadeAnimation = Duration(milliseconds: 200);

  // API timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
}
