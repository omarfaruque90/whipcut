import 'package:flutter/material.dart';

/// Whipcut dark pro theme.
///
/// Brand: deep dark background (#101012) + amber accent (#f5a623).
/// All feature screens must use these tokens — no ad-hoc colors.
/// Access via `WhipcutTheme.darkTheme` (set on MaterialApp by main.dart).
/// Individual colors: `WhipcutTheme.background`, `.amber`, etc.
abstract final class WhipcutTheme {
  // Palette ---------------------------------------------------------------
  static const Color background = Color(0xFF101012);
  static const Color surface = Color(0xFF18181C);
  static const Color surfaceElevated = Color(0xFF232329);
  static const Color surfaceOutline = Color(0xFF2E2E35);
  static const Color amber = Color(0xFFF5A623);
  static const Color amberDark = Color(0xFFC77F0A);
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFFA8A8B0);
  static const Color danger = Color(0xFFE5484D);

  // ThemeData -------------------------------------------------------------
  static ThemeData get darkTheme {
    final scheme = ColorScheme.dark(
      primary: amber,
      onPrimary: Colors.black,
      secondary: amber,
      onSecondary: Colors.black,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceElevated,
      outline: surfaceOutline,
      error: danger,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: surfaceOutline, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: amber,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: amber),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: amber,
        foregroundColor: Colors.black,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: amber,
        unselectedItemColor: textSecondary,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: amber,
        inactiveTrackColor: surfaceElevated,
        thumbColor: amber,
        overlayColor: amber.withValues(alpha: 0.2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? amber : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? amber.withValues(alpha: 0.4)
              : surfaceElevated,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: TextStyle(color: textPrimary),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        displayMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        labelLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: textSecondary),
      ),
      iconTheme: const IconThemeData(color: textPrimary),
      dividerColor: surfaceOutline,
    );
  }
}
