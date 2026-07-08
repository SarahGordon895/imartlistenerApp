import 'package:flutter/material.dart';

class AppTheme {
  /// Brand red (iMart wordmark / globe quadrant).
  static const Color lushRed = Color(0xFFE31C23);
  /// Brand navy (globe + "Group ltd").
  static const Color lushNavy = Color(0xFF0B2C5F);
  /// Legacy accent (gold) — keep sparingly for highlights.
  static const Color lushGold = Color(0xFFD4AF37);
  /// Dark surface — navy-aligned.
  static const Color lushDark = Color(0xFF0B2C5F);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: lushRed,
      brightness: Brightness.light,
    );
    return base.copyWith(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: lushRed,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE6E8ED)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(88, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          backgroundColor: lushRed,
        ),
      ),
    );
  }
}
