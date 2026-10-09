import 'package:flutter/material.dart';

// Approved RingMaster Breeder brand palette, shared across all screens.
class BreederColors {
  static const background = Color(0xFFC7CBCC);
  static const header = Color(0xFF42101A);
  static const primary = Color(0xFF42101A);
  static const accent = Color(0xFFC7CBCC);
  static const text = Color(0xFF1E2849);
  static const surface = Colors.white;
}

class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: BreederColors.primary,
          surface: BreederColors.surface,
        ).copyWith(
          primary: BreederColors.primary,
          onPrimary: Colors.white,
          secondary: BreederColors.text,
          onSecondary: Colors.white,
          tertiary: BreederColors.accent,
          onTertiary: BreederColors.text,
          onSurface: BreederColors.text,
        ),
    scaffoldBackgroundColor: BreederColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: BreederColors.header,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: BreederColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BreederColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: BreederColors.accent,
      foregroundColor: BreederColors.text,
    ),
  );
}
