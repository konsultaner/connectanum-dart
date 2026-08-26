import 'package:flutter/material.dart';

abstract final class WampAppTheme {
  static const ink = Color(0xFF17342D);
  static const pine = Color(0xFF1F6757);
  static const mint = Color(0xFFCFEBDD);
  static const sand = Color(0xFFF7F0E4);
  static const coral = Color(0xFFEE785F);

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: pine,
      primary: pine,
      secondary: coral,
      surface: sand,
    ),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: pine,
      brightness: Brightness.dark,
      primary: const Color(0xFF83D6BE),
      secondary: const Color(0xFFFFA08A),
      surface: const Color(0xFF10231E),
    ),
  );

  static ThemeData _build(ColorScheme colors) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      fontFamily: 'Georgia',
      textTheme: TextTheme(
        displaySmall: TextStyle(
          color: colors.onSurface,
          fontSize: 42,
          fontWeight: FontWeight.w700,
          height: 1.05,
        ),
        headlineSmall: TextStyle(
          color: colors.onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: colors.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          color: colors.onSurface,
          fontSize: 16,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          color: colors.onSurface,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.72),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLow.withValues(alpha: 0.92),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
    );
  }
}
