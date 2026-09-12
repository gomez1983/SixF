import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Configuração do ThemeData para o aplicativo Desktop com estética Fluent/Flat
/// suportando Modo Escuro (Dark Mode) e Modo Claro (Light Mode).
class AppTheme {
  AppTheme._();

  /// Tema Escuro (Dark Mode)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Segoe UI',
      colorScheme: const ColorScheme.dark(
        primary: AppColors.lgRed,
        secondary: AppColors.iconHighlight,
        surface: AppColors.surfaceCard,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: AppColors.textPrimary,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.remoteChassis,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
          side: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceInteractive,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        prefixIconColor: AppColors.textSecondary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.iconHighlight, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.powerRed, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.powerRed, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.surfaceInteractive,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.borderSubtle, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 24,
      ),
    );
  }

  /// Tema Claro (Light Mode)
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      fontFamily: 'Segoe UI',
      colorScheme: const ColorScheme.light(
        primary: AppColors.lgRed,
        secondary: AppColors.lightIconHighlight,
        surface: AppColors.lightSurfaceCard,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.lightTextPrimary,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.lightRemoteChassis,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
          side: BorderSide(color: AppColors.lightBorderSubtle, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceInteractive,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.lightTextMuted, fontSize: 13),
        labelStyle: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13),
        prefixIconColor: AppColors.lightTextSecondary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightBorderSubtle, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.lightIconHighlight, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.powerRed, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.powerRed, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.lightSurfaceInteractive,
          foregroundColor: AppColors.lightTextPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.lightBorderSubtle, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.lightTextSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.lightSurfaceCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.lightBorderSubtle),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        textStyle: const TextStyle(color: AppColors.lightTextPrimary, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorderSubtle,
        thickness: 1,
        space: 24,
      ),
    );
  }
}
