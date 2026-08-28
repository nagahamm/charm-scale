import "package:flutter/material.dart";

/// 色・サイズはここに一元管理する。画面・ウィジェット側でリテラル値を直書きしない。
class AppColors {
  AppColors._();

  static const primary = Color(0xFFE8547A);
  static const primaryDark = Color(0xFFB8375A);
  static const background = Color(0xFFFAF7F8);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF222222);
  static const textSecondary = Color(0xFF6B6B6B);
  static const border = Color(0xFFE3DEE0);

  static const scoreLow = Color(0xFF9B9B9B);
  static const scoreMid = Color(0xFFE8A93F);
  static const scoreHigh = Color(0xFFE8547A);

  static Color forScore(int score) {
    if (score >= 70) return scoreHigh;
    if (score >= 40) return scoreMid;
    return scoreLow;
  }
}

class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const radius = 12.0;
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    surface: AppColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
      bodyMedium: TextStyle(color: AppColors.textPrimary),
      bodySmall: TextStyle(color: AppColors.textSecondary),
    ),
  );
}
