import 'package:flutter/material.dart';

import '../domain/local_app_preferences.dart';

abstract final class WampAppTheme {
  static const ink = Color(0xFF16201D);
  static const mint = Color(0xFFD8F3EA);
  static const sand = Color(0xFFF8FAF8);

  static Color accentColor(WampAppAccentPreference preference) =>
      switch (preference) {
        WampAppAccentPreference.teal => const Color(0xFF006B5E),
        WampAppAccentPreference.blue => const Color(0xFF165FA7),
        WampAppAccentPreference.coral => const Color(0xFFA54040),
        WampAppAccentPreference.amber => const Color(0xFF8A5600),
        WampAppAccentPreference.indigo => const Color(0xFF4E5D95),
      };

  static ThemeData light([
    WampAppAccentPreference accent = WampAppAccentPreference.teal,
  ]) => _build(
    ColorScheme.fromSeed(
      seedColor: accentColor(accent),
      brightness: Brightness.light,
      contrastLevel: 0.5,
    ),
  );

  static ThemeData dark([
    WampAppAccentPreference accent = WampAppAccentPreference.teal,
  ]) => _build(
    ColorScheme.fromSeed(
      seedColor: accentColor(accent),
      brightness: Brightness.dark,
      contrastLevel: 0.5,
    ),
  );

  static ThemeData _build(ColorScheme colors) {
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    return base.copyWith(
      scaffoldBackgroundColor: colors.surface,
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          height: 1.08,
          letterSpacing: -0.8,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -0.4,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.45,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.4,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: colors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: colors.outlineVariant),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainer,
        indicatorColor: colors.secondaryContainer,
      ),
    );
  }
}
