import 'package:flutter/material.dart';

/// Paleta de cores e tokens Liquid Glass inspirados no Dashboard do André,
/// com suporte completo a Modo Escuro (Dark Mode) e Modo Claro (Light Mode).
class AppColors {
  AppColors._();

  // --- Paleta Dark Mode (Liquid Glass Escuro — #17151F) ---
  static const Color background = Color(0xFF17151F);
  static const Color ambientGlowPrimary = Color(0x484B3564);
  static const Color ambientGlowSecondary = Color(0x30234C44);
  static const Color remoteChassis = Color(0xEB221E2E);
  static const Color surfaceCard = Color(0xF5272331);
  static const Color surfaceElevated = Color(0xFF332D41);
  static const Color surfaceInteractive = Color(0xFF2D273B);
  static const Color surfaceInteractiveHover = Color(0xFF3B334E);
  static const Color borderSubtle = Color(0x22FFFFFF);
  static const Color borderActive = Color(0xFFC29AEA);
  static const Color textPrimary = Color(0xFFEEEBF5);
  static const Color textSecondary = Color(0xFFBEB4CE);
  static const Color textMuted = Color(0xFFA8A1B8);
  static const Color iconDefault = Color(0xFFEEEBF5);
  static const Color iconHighlight = Color(0xFFC29AEA);
  static const Color trackpadSurface = Color(0xFF1D1A27);
  static const Color trackpadBorder = Color(0x26FFFFFF);
  static const Color trackpadCrosshair = Color(0x38C29AEA);
  static const Color trackpadIndicator = Color(0xFFC29AEA);

  // --- Paleta Light Mode (Liquid Glass Claro — #EEEDF5) ---
  static const Color lightBackground = Color(0xFFEEEDF5);
  static const Color lightAmbientGlowPrimary = Color(0x55DFD3F2);
  static const Color lightAmbientGlowSecondary = Color(0x55DBECE7);
  static const Color lightRemoteChassis = Color(0xD8FFFFFF);
  static const Color lightSurfaceCard = Color(0xF0FFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF3EFF9);
  static const Color lightSurfaceInteractive = Color(0xE6FFFFFF);
  static const Color lightSurfaceInteractiveHover = Color(0xFFEBE4F6);
  static const Color lightBorderSubtle = Color(0xFFDCD5EA);
  static const Color lightBorderActive = Color(0xFF9362D7);
  static const Color lightTextPrimary = Color(0xFF262637);
  static const Color lightTextSecondary = Color(0xFF626071);
  static const Color lightTextMuted = Color(0xFF747385);
  static const Color lightIconDefault = Color(0xFF262637);
  static const Color lightIconHighlight = Color(0xFF9362D7);
  static const Color lightTrackpadSurface = Color(0xCCF3EFF9);
  static const Color lightTrackpadBorder = Color(0xFFD8CFE8);

  // --- Cores Globais Compartilhadas ---
  static const Color lgRed = Color(0xFF9362D7);
  static const Color powerRed = Color(0xFFD16760);
  static const Color powerGlow = Color(0x33D16760);

  // Status de conexão (alinhados ao verde/coral do Dashboard)
  static const Color statusConnected = Color(0xFF088875);
  static const Color statusConnectedDark = Color(0xFF75D0B8);
  static const Color statusDisconnected = Color(0xFF747385);
  static const Color statusConnecting = Color(0xFFF59E0B);

  // Cores tradicionais dos 4 botões de controle Smart TV
  static const Color buttonRed = Color(0xFFD16760);
  static const Color buttonGreen = Color(0xFF088875);
  static const Color buttonYellow = Color(0xFFEAB308);
  static const Color buttonBlue = Color(0xFF3E82F7);

  // --- Métodos Utilitários Reativos para Resolução de Tema ---

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color backgroundOf(BuildContext context) =>
      isDark(context) ? background : lightBackground;

  static Color ambientPrimaryOf(BuildContext context) =>
      isDark(context) ? ambientGlowPrimary : lightAmbientGlowPrimary;

  static Color ambientSecondaryOf(BuildContext context) =>
      isDark(context) ? ambientGlowSecondary : lightAmbientGlowSecondary;

  static Color remoteChassisOf(BuildContext context) =>
      isDark(context) ? remoteChassis : lightRemoteChassis;

  static Color surfaceCardOf(BuildContext context) =>
      isDark(context) ? surfaceCard : lightSurfaceCard;

  static Color surfaceElevatedOf(BuildContext context) =>
      isDark(context) ? surfaceElevated : lightSurfaceElevated;

  static Color surfaceInteractiveOf(BuildContext context) =>
      isDark(context) ? surfaceInteractive : lightSurfaceInteractive;

  static Color surfaceInteractiveHoverOf(BuildContext context) =>
      isDark(context) ? surfaceInteractiveHover : lightSurfaceInteractiveHover;

  static Color borderSubtleOf(BuildContext context) =>
      isDark(context) ? borderSubtle : lightBorderSubtle;

  static Color borderActiveOf(BuildContext context) =>
      isDark(context) ? borderActive : lightBorderActive;

  static Color textPrimaryOf(BuildContext context) =>
      isDark(context) ? textPrimary : lightTextPrimary;

  static Color textSecondaryOf(BuildContext context) =>
      isDark(context) ? textSecondary : lightTextSecondary;

  static Color textMutedOf(BuildContext context) =>
      isDark(context) ? textMuted : lightTextMuted;

  static Color iconDefaultOf(BuildContext context) =>
      isDark(context) ? iconDefault : lightIconDefault;

  static Color iconHighlightOf(BuildContext context) =>
      isDark(context) ? iconHighlight : lightIconHighlight;

  static Color trackpadSurfaceOf(BuildContext context) =>
      isDark(context) ? trackpadSurface : lightTrackpadSurface;

  static Color trackpadBorderOf(BuildContext context) =>
      isDark(context) ? trackpadBorder : lightTrackpadBorder;

  /// Decoração Liquid Glass para o chassi principal e grandes painéis.
  static BoxDecoration glassPanelDecoration(
    BuildContext context, {
    double borderRadius = 28,
  }) {
    final dark = isDark(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xF0282434), Color(0xDF1B1824)]
            : const [Color(0xE8FFFFFF), Color(0xB8F4F0FA)],
      ),
      border: Border.all(
        color: dark ? const Color(0x26FFFFFF) : const Color(0xF2FFFFFF),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: dark ? const Color(0x50000000) : const Color(0x1448406C),
          blurRadius: 36,
          offset: const Offset(0, 14),
        ),
        BoxShadow(
          color: dark ? const Color(0x12FFFFFF) : const Color(0xCCFFFFFF),
          blurRadius: 1,
          offset: const Offset(0, 1),
        ),
      ],
    );
  }

  /// Decoração Liquid Glass para cards internos (Header, Teclado, Multimídia, Console).
  static BoxDecoration glassCardDecoration(
    BuildContext context, {
    double borderRadius = 18,
  }) {
    final dark = isDark(context);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: dark
            ? const [Color(0xF52A2536), Color(0xE6221E2C)]
            : const [Color(0xF5FFFFFF), Color(0xE0F7F4FC)],
      ),
      border: Border.all(
        color: dark ? const Color(0x1FFFFFFF) : const Color(0xFFE2DCF0),
        width: 1.0,
      ),
      boxShadow: [
        BoxShadow(
          color: dark ? const Color(0x38000000) : const Color(0x0D48406C),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
