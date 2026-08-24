import 'package:flutter/material.dart';

abstract final class WampAppTheme {
  static const ink = Color(0xFF17342D);
  static const pine = Color(0xFF1F6757);
  static const mint = Color(0xFFCFEBDD);
  static const sand = Color(0xFFF7F0E4);
  static const coral = Color(0xFFEE785F);

  static ThemeData light() {
    final colors = ColorScheme.fromSeed(
      seedColor: pine,
      primary: pine,
      secondary: coral,
      surface: sand,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: sand,
      fontFamily: 'Georgia',
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: ink,
          fontSize: 42,
          fontWeight: FontWeight.w700,
          height: 1.05,
        ),
        headlineSmall: TextStyle(
          color: ink,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: ink, fontSize: 16, height: 1.45),
        bodyMedium: TextStyle(color: ink, fontSize: 14, height: 1.4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.72),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x30204A40)),
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
        color: Colors.white.withValues(alpha: 0.75),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0x24204A40)),
        ),
      ),
    );
  }
}
