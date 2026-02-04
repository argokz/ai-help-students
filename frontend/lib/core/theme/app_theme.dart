import 'package:flutter/material.dart';

/// Тема в стиле Material 3 + Apple/Google: читабельная типографика,
/// мягкие тени, достаточные отступы.
class AppTheme {
  static const Color _primaryLight = Color(0xFF1A73E8);
  static const Color _primaryDark = Color(0xFF8AB4F8);
  static const Color _surfaceContainerHighestLight = Color(0xFFE8EAED);
  static const Color _surfaceContainerHighestDark = Color(0xFF2D3038);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryLight,
        brightness: Brightness.light,
        primary: _primaryLight,
      ),
      fontFamily: 'Roboto',
      textTheme: _buildTextTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: _surfaceContainerHighestLight.withOpacity(0.8),
        thickness: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryDark,
        brightness: Brightness.dark,
        primary: _primaryDark,
      ),
      fontFamily: 'Roboto',
      textTheme: _buildTextTheme(Brightness.dark),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: ColorScheme.fromSeed(seedColor: _primaryDark, brightness: Brightness.dark).onSurface,
        ),
        iconTheme: const IconThemeData(size: 24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: _surfaceContainerHighestDark.withOpacity(0.8),
        thickness: 1,
      ),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final base = brightness == Brightness.light
        ? Typography.material2021(platform: TargetPlatform.android).black
        : Typography.material2021(platform: TargetPlatform.android).white;
    return TextTheme(
      displayLarge: base.displayLarge?.copyWith(letterSpacing: -0.5, height: 1.2),
      displayMedium: base.displayMedium?.copyWith(letterSpacing: -0.5, height: 1.2),
      displaySmall: base.displaySmall?.copyWith(letterSpacing: -0.3, height: 1.25),
      headlineLarge: base.headlineLarge?.copyWith(letterSpacing: -0.3, height: 1.25),
      headlineMedium: base.headlineMedium?.copyWith(letterSpacing: -0.3, height: 1.3),
      headlineSmall: base.headlineSmall?.copyWith(letterSpacing: -0.2, height: 1.3),
      titleLarge: base.titleLarge?.copyWith(letterSpacing: -0.2, height: 1.35),
      titleMedium: base.titleMedium?.copyWith(letterSpacing: -0.1, height: 1.4),
      titleSmall: base.titleSmall?.copyWith(height: 1.4),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
      bodySmall: base.bodySmall?.copyWith(height: 1.4),
      labelLarge: base.labelLarge?.copyWith(letterSpacing: 0.1, height: 1.35),
      labelMedium: base.labelMedium?.copyWith(height: 1.35),
      labelSmall: base.labelSmall?.copyWith(letterSpacing: 0.5, height: 1.3),
    );
  }
}
