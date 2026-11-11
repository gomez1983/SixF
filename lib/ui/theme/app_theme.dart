import 'package:flutter/material.dart';
import '../glass/glass_flags.dart';
import '../glass/liquid_glass.dart' show GlassTokens;
import 'app_colors.dart';

/// Configuração do ThemeData para o aplicativo Desktop com estética Fluent/Flat
/// suportando Modo Escuro (Dark Mode) e Modo Claro (Light Mode).
class AppTheme {
  AppTheme._();

  /// Tema Escuro (Dark Mode)
  static ThemeData get darkTheme => kGlassUi ? _glassify(_dark) : _payno(_dark);

  static ThemeData get lightTheme =>
      kGlassUi ? _glassify(_light) : _payno(_light);

  /// Padrão Payno: cantos bem arredondados, azul-marinho como cor primária e
  /// componentes do Material (diálogos, chips, menus, botões) sem sombras
  /// duras, para telas e diálogos comuns seguirem o mesmo visual.
  static ThemeData _payno(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final accent = dark ? AppColors.accentFill : AppColors.lightAccentFill;
    final surface = dark ? AppColors.remoteChassis : AppColors.lightRemoteChassis;
    final line = dark ? AppColors.borderSubtle : AppColors.lightBorderSubtle;
    final ink = dark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final muted = dark ? AppColors.textMuted : AppColors.lightTextMuted;
    final key = dark ? AppColors.surfaceInteractive : AppColors.lightSurfaceInteractive;
    RoundedRectangleBorder shape(double r, {bool border = true}) =>
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r),
          side: border ? BorderSide(color: line) : BorderSide.none,
        );
    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: c, width: w),
    );
    return base.copyWith(
      // Contêineres (botões "tonais", chips, etc.) em cinza-azulado claro com
      // conteúdo escuro; o azul-marinho sólido fica só para o que é primário
      // e sempre leva conteúdo branco.
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        onPrimary: Colors.white,
        secondary: dark ? AppColors.iconHighlight : AppColors.lightIconHighlight,
        onSecondary: dark ? AppColors.background : Colors.white,
        primaryContainer: dark ? AppColors.surfaceElevated : const Color(0xFFE3E9F3),
        onPrimaryContainer: ink,
        secondaryContainer: dark ? AppColors.surfaceElevated : const Color(0xFFE3E9F3),
        onSecondaryContainer: ink,
        tertiaryContainer: key,
        onTertiaryContainer: ink,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: shape(24),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: shape(16),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: key,
        hintStyle: TextStyle(color: muted, fontSize: 13),
        enabledBorder: field(line),
        focusedBorder: field(accent, 1.5),
        border: field(line),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: key,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
          shape: shape(999),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: shape(999, border: false),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: line),
          shape: shape(999, border: false),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: dark ? AppColors.iconHighlight : AppColors.lightIconHighlight,
          shape: shape(999, border: false),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: key,
        selectedColor: accent,
        checkmarkColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: line),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: ink, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : key,
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: WidgetStatePropertyAll(line),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: key,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    );
  }

  static ThemeData get _dark {
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
  static ThemeData get _light {
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
  /// Modo Liquid Glass: reveste os componentes padrão do Material (gaveta,
  /// diálogos, campos, botões, chips, menus) com vidro translúcido, para que
  /// telas e diálogos que usam widgets comuns sigam o mesmo visual.
  static ThemeData _glassify(ThemeData base) {
    final t = base.brightness == Brightness.dark
        ? GlassTokens.dark
        : GlassTokens.light;
    final dark = base.brightness == Brightness.dark;
    final surface = dark ? const Color(0xF21F2233) : const Color(0xF2F4F6FC);
    final rim = t.rimLight.withValues(alpha: dark ? 0.28 : 0.85);
    RoundedSuperellipseBorder shape(double r, {bool border = true}) => RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(r),
      side: border ? BorderSide(color: rim) : BorderSide.none,
    );
    OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(primary: t.accent),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: shape(28),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        shape: RoundedSuperellipseBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: rim),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: shape(18),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: t.fillStrong,
        enabledBorder: field(rim.withValues(alpha: dark ? 0.2 : 0.7)),
        focusedBorder: field(t.accent, 1.5),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: t.fillStrong,
          foregroundColor: t.label,
          surfaceTintColor: Colors.transparent,
          shape: shape(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: Colors.white,
          shape: shape(16, border: false),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.label,
          side: BorderSide(color: rim),
          shape: shape(16, border: false),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          shape: shape(14, border: false),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (dark ? const Color(0xFF7466B0) : t.success)
              : (dark ? const Color(0x47787880) : const Color(0x29787880)),
        ),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: t.fillStrong,
        selectedColor: t.tintBlue,
        surfaceTintColor: Colors.transparent,
        side: BorderSide(color: rim),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(color: t.label),
      ),
      dividerTheme: DividerThemeData(
        color: rim.withValues(alpha: dark ? 0.12 : 0.5),
        thickness: 1,
        space: 24,
      ),
      tooltipTheme: base.tooltipTheme.copyWith(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: rim),
        ),
      ),
    );
  }
}
