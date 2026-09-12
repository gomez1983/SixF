import 'package:flutter/material.dart';

/// Paleta de cores completa com suporte a Dark Mode e Light Mode (Fluent/Flat Design).
class AppColors {
  AppColors._();

  // --- Paleta Dark Mode ---
  static const Color background = Color(0xFF0F1216);
  static const Color remoteChassis = Color(0xFF161A20);
  static const Color surfaceCard = Color(0xFF1E232B);
  static const Color surfaceElevated = Color(0xFF262C36);
  static const Color surfaceInteractive = Color(0xFF2D3541);
  static const Color surfaceInteractiveHover = Color(0xFF384252);
  static const Color borderSubtle = Color(0xFF2E3643);
  static const Color borderActive = Color(0xFF475569);
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color iconDefault = Color(0xFFE2E8F0);
  static const Color iconHighlight = Color(0xFF38BDF8);
  static const Color trackpadSurface = Color(0xFF12151B);
  static const Color trackpadBorder = Color(0xFF252C37);
  static const Color trackpadCrosshair = Color(0x3338BDF8);
  static const Color trackpadIndicator = Color(0xFF38BDF8);

  // --- Paleta Light Mode ---
  static const Color lightBackground = Color(0xFFF1F5F9);
  static const Color lightRemoteChassis = Color(0xFFFFFFFF);
  static const Color lightSurfaceCard = Color(0xFFF8FAFC);
  static const Color lightSurfaceElevated = Color(0xFFE2E8F0);
  static const Color lightSurfaceInteractive = Color(0xFFECEFF3);
  static const Color lightSurfaceInteractiveHover = Color(0xFFDFE4EA);
  static const Color lightBorderSubtle = Color(0xFFE2E8F0);
  static const Color lightBorderActive = Color(0xFF94A3B8);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);
  static const Color lightIconDefault = Color(0xFF1E293B);
  static const Color lightIconHighlight = Color(0xFF0284C7);
  static const Color lightTrackpadSurface = Color(0xFFE8EDF2);
  static const Color lightTrackpadBorder = Color(0xFFCBD5E1);

  // --- Cores Globais Compartilhadas ---
  static const Color lgRed = Color(0xFFE52345);
  static const Color powerRed = Color(0xFFFF3B30);
  static const Color powerGlow = Color(0x33FF3B30);

  // Status de conexão
  static const Color statusConnected = Color(0xFF30D158);
  static const Color statusDisconnected = Color(0xFF64748B);
  static const Color statusConnecting = Color(0xFFFF9F0A);

  // Cores tradicionais dos 4 botões de controle LG (Teletexto / Funções Smart)
  static const Color buttonRed = Color(0xFFE53935);
  static const Color buttonGreen = Color(0xFF43A047);
  static const Color buttonYellow = Color(0xFFFDD835);
  static const Color buttonBlue = Color(0xFF1E88E5);

  // --- Métodos Utilitários Reativos para Resolução de Tema ---

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color backgroundOf(BuildContext context) =>
      isDark(context) ? background : lightBackground;

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
}
