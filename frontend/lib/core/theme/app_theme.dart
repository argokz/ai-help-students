import 'package:flutter/material.dart';

/// Тема в стиле Material 3 + Apple/Google: читабельная типографика,
/// мягкие тени, достаточные отступы.
class AppTheme {
  // Premium Blue Palette
  static const Color _primaryLight = Color(0xFF0052CC); // Deep Blue
  static const Color _primaryDark = Color(0xFF4C9AFF); // Lighter Blue for Dark Mode
  static const Color _secondaryLight = Color(0xFF00B8D9); // Teal
  static const Color _secondaryDark = Color(0xFF00E0F0); // Bright Teal for Dark Mode
  
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _surfaceDark = Color(0xFF172B4D); // Dark Blue-Grey
  
  static const Color _backgroundLight = Color(0xFFF4F5F7); // Light Grey
  static const Color _backgroundDark = Color(0xFF091E42); // Very Dark Blue

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryLight,
        brightness: Brightness.light,
        primary: _primaryLight,
        secondary: _secondaryLight,
        surface: _surfaceLight,
        surfaceContainerHighest: Color(0xFFEBECF0),
      ),
      scaffoldBackgroundColor: _backgroundLight,
      fontFamily: 'Roboto', // Consider 'Inter' if available safely
      textTheme: _buildTextTheme(Brightness.light),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _backgroundLight,
        foregroundColor: Color(0xFF172B4D),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: Color(0xFF172B4D),
        ),
        iconTheme: IconThemeData(size: 24, color: Color(0xFF172B4D)),
      ),
      cardTheme: CardThemeData(
        elevation: 0, // Flat elegant look with border
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFEBECF0), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        color: _surfaceLight,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        tileColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: const Color(0xFFEBECF0),
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDFE1E6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryLight, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: _primaryLight,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: _primaryLight,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _surfaceLight,
        selectedItemColor: _primaryLight,
        unselectedItemColor: Color(0xFF6B778C),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFEBECF0),
        thickness: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryDark,
        brightness: Brightness.dark,
        primary: _primaryDark,
        secondary: _secondaryDark,
        surface: _surfaceDark,
        surfaceContainerHighest: Color(0xFF223655),
      ),
      scaffoldBackgroundColor: _backgroundDark,
      fontFamily: 'Roboto',
      textTheme: _buildTextTheme(Brightness.dark),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _backgroundDark,
        foregroundColor: Color(0xFFB3BAC5),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: Color(0xFFDEEBFF),
        ),
        iconTheme: IconThemeData(size: 24, color: Color(0xFFB3BAC5)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF223655), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        color: _surfaceDark,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        tileColor: Colors.transparent,
      ),
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: const Color(0xFF223655),
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E2F49),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2C3E5D)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2C3E5D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryDark, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: _primaryDark,
          foregroundColor: const Color(0xFF091E42),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: _primaryDark,
        foregroundColor: const Color(0xFF091E42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: _surfaceDark,
        selectedItemColor: _primaryDark,
        unselectedItemColor: Color(0xFF8993A4),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF223655),
        thickness: 1,
      ),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final base = brightness == Brightness.light
        ? Typography.material2021(platform: TargetPlatform.android).black
        : Typography.material2021(platform: TargetPlatform.android).white;
    return TextTheme(
      displayLarge: base.displayLarge?.copyWith(letterSpacing: -0.5, height: 1.2, fontWeight: FontWeight.w800),
      displayMedium: base.displayMedium?.copyWith(letterSpacing: -0.5, height: 1.2, fontWeight: FontWeight.w800),
      displaySmall: base.displaySmall?.copyWith(letterSpacing: -0.3, height: 1.25, fontWeight: FontWeight.w700),
      headlineLarge: base.headlineLarge?.copyWith(letterSpacing: -0.3, height: 1.25, fontWeight: FontWeight.w700),
      headlineMedium: base.headlineMedium?.copyWith(letterSpacing: -0.3, height: 1.3, fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(letterSpacing: -0.2, height: 1.3, fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(letterSpacing: -0.2, height: 1.35, fontWeight: FontWeight.w600),
      titleMedium: base.titleMedium?.copyWith(letterSpacing: -0.1, height: 1.4, fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(height: 1.4, fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
      bodySmall: base.bodySmall?.copyWith(height: 1.4, color: brightness == Brightness.light ? const Color(0xFF6B778C) : const Color(0xFF8993A4)),
      labelLarge: base.labelLarge?.copyWith(letterSpacing: 0.1, height: 1.35, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(height: 1.35, fontWeight: FontWeight.w500),
      labelSmall: base.labelSmall?.copyWith(letterSpacing: 0.5, height: 1.3, fontWeight: FontWeight.w500),
    );
  }
}
