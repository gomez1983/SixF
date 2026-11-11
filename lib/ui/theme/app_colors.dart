import 'package:flutter/material.dart';

import '../glass/glass_flags.dart';
import '../glass/liquid_glass.dart' show GlassTokens, glassFlatDecoration;

/// Paleta do padrão visual Payno (referência em `Referências/` e mockup em
/// `docs/design/mockups/sixf-payno-mockup.html`): fundo cinza-azulado com uma
/// mancha azul-aço difusa no topo, cards translúcidos claros e um único azul-
/// marinho como destaque. Modo Escuro e Modo Claro.
class AppColors {
  AppColors._();

  // --- Paleta Dark Mode (Payno escuro — #0D121B com destaque azul-marinho) ---
  static const Color background = Color(0xFF0D121B);
  static const Color ambientGlowPrimary = Color(0x8C4669AA);
  static const Color ambientGlowSecondary = Color(0x80324B7D);
  static const Color remoteChassis = Color(0xF7161D2A);
  static const Color surfaceCard = Color(0xFA1A2232);
  static const Color surfaceElevated = Color(0xFF222B3D);
  static const Color surfaceInteractive = Color(0xFF1F2838);
  static const Color surfaceInteractiveHover = Color(0xFF2A3448);
  static const Color borderSubtle = Color(0x17FFFFFF);
  static const Color borderActive = Color(0xFF86A5DC);
  static const Color textPrimary = Color(0xFFE7ECF4);
  static const Color textSecondary = Color(0xFFA9B3C6);
  static const Color textMuted = Color(0xFF8792A7);
  static const Color iconDefault = Color(0xFFE7ECF4);
  static const Color iconHighlight = Color(0xFF9DB7E6);
  static const Color trackpadSurface = Color(0xFF172030);
  static const Color trackpadBorder = Color(0x1FFFFFFF);
  static const Color trackpadCrosshair = Color(0x389DB7E6);
  static const Color trackpadIndicator = Color(0xFF9DB7E6);

  // --- Paleta Light Mode (Payno claro — #EEF1F5 com destaque azul-marinho) ---
  static const Color lightBackground = Color(0xFFEEF1F5);
  static const Color lightAmbientGlowPrimary = Color(0x8C3D5A8C);
  static const Color lightAmbientGlowSecondary = Color(0x737891BE);
  static const Color lightRemoteChassis = Color(0xFAF7F9FC);
  static const Color lightSurfaceCard = Color(0xFAFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF4F6FA);
  static const Color lightSurfaceInteractive = Color(0xFFF2F4F8);
  static const Color lightSurfaceInteractiveHover = Color(0xFFE6EBF3);
  static const Color lightBorderSubtle = Color(0x161B2232);
  static const Color lightBorderActive = Color(0xFF3B5788);
  static const Color lightTextPrimary = Color(0xFF1B2232);
  static const Color lightTextSecondary = Color(0xFF5E6779);
  static const Color lightTextMuted = Color(0xFF8A93A3);
  static const Color lightIconDefault = Color(0xFF1B2232);
  static const Color lightIconHighlight = Color(0xFF3B5788);
  static const Color lightTrackpadSurface = Color(0xD9F4F6FA);
  static const Color lightTrackpadBorder = Color(0x1F1B2232);

  // --- Destaque azul-marinho (preenchimento de botões ativos, OK, abas) ---
  static const Color accentFill = Color(0xFF4A6AA3);
  static const Color lightAccentFill = Color(0xFF3B5788);

  // --- Cores Globais Compartilhadas ---
  static const Color lgRed = Color(0xFF3B5788);
  static const Color powerRed = Color(0xFFD94A4A);
  static const Color powerGlow = Color(0x33D94A4A);

  // Status de conexão
  static const Color statusConnected = Color(0xFF2FA36B);
  static const Color statusConnectedDark = Color(0xFF4CC38A);
  static const Color statusDisconnected = Color(0xFF8A93A3);
  static const Color statusConnecting = Color(0xFFD9932B);

  // Cores tradicionais dos 4 botões de controle Smart TV
  static const Color buttonRed = Color(0xFFE5484D);
  static const Color buttonGreen = Color(0xFF30A46C);
  static const Color buttonYellow = Color(0xFFF5B82E);
  static const Color buttonBlue = Color(0xFF3E63DD);

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

  static Color remoteChassisOf(BuildContext context) => kGlassUi
      ? (isDark(context) ? const Color(0xF21F2233) : const Color(0xF2F4F6FC))
      : (isDark(context) ? remoteChassis : lightRemoteChassis);

  static Color surfaceCardOf(BuildContext context) =>
      isDark(context) ? surfaceCard : lightSurfaceCard;

  static Color surfaceElevatedOf(BuildContext context) =>
      isDark(context) ? surfaceElevated : lightSurfaceElevated;

  // No modo Liquid Glass (experimental) as superfícies de conteúdo viram vidro
  // translúcido sobre o fundo ambiente; dialogs e menus (surfaceCardOf,
  // remoteChassisOf) continuam opacos para ficarem legíveis.
  static Color surfaceInteractiveOf(BuildContext context) => kGlassUi
      ? GlassTokens.of(context).fillStrong
      : (isDark(context) ? surfaceInteractive : lightSurfaceInteractive);

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

  /// Azul-marinho sólido (botão OK, aba ativa, botões primários).
  static Color accentFillOf(BuildContext context) =>
      isDark(context) ? accentFill : lightAccentFill;

  /// Fundo suave do destaque (linha selecionada, chips ativos discretos).
  static Color accentSoftOf(BuildContext context) => isDark(context)
      ? const Color(0x1F7DA0DC)
      : const Color(0x173B5788);

  /// Fundo de card translúcido sobre o fundo ambiente.
  static Color cardOf(BuildContext context) =>
      isDark(context) ? const Color(0xB31C2433) : const Color(0xB8FFFFFF);

  /// Fundo sólido de botões circulares (padrão "Quick Actions").
  static Color circleOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF1F2839) : Colors.white;

  /// Verde de status legível em cada tema.
  static Color okOf(BuildContext context) =>
      isDark(context) ? statusConnectedDark : statusConnected;

  /// Sombra suave usada nos cards e botões circulares.
  static List<BoxShadow> softShadowOf(BuildContext context) => isDark(context)
      ? const [
          BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, 12)),
        ]
      : const [
          BoxShadow(color: Color(0x0F1E2D50), blurRadius: 30, offset: Offset(0, 10)),
          BoxShadow(color: Color(0x0A1E2D50), blurRadius: 2, offset: Offset(0, 1)),
        ];

  static Color trackpadSurfaceOf(BuildContext context) => kGlassUi
      ? GlassTokens.of(context).fill
      : (isDark(context) ? trackpadSurface : lightTrackpadSurface);

  static Color trackpadBorderOf(BuildContext context) => kGlassUi
      ? GlassTokens.of(context).rimLight.withValues(alpha: 0.5)
      : (isDark(context) ? trackpadBorder : lightTrackpadBorder);

  /// Decoração Liquid Glass para o chassi principal e grandes painéis.
  static BoxDecoration glassPanelDecoration(
    BuildContext context, {
    double borderRadius = 28,
  }) {
    if (kGlassUi) {
      return glassFlatDecoration(context, radius: borderRadius, strong: true);
    }
    return paynoCardDecoration(context, radius: borderRadius);
  }

  /// Card Payno: translúcido, borda clara quase invisível, sombra difusa.
  static BoxDecoration paynoCardDecoration(
    BuildContext context, {
    double radius = 20,
    Color? color,
  }) {
    final dark = isDark(context);
    return BoxDecoration(
      color: color ?? cardOf(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark ? const Color(0x10FFFFFF) : const Color(0xE6FFFFFF),
      ),
      boxShadow: softShadowOf(context),
    );
  }

  /// Decoração Liquid Glass para cards internos (Header, Teclado, Multimídia, Console).
  static BoxDecoration glassCardDecoration(
    BuildContext context, {
    double borderRadius = 18,
  }) {
    if (kGlassUi) return glassFlatDecoration(context, radius: borderRadius);
    return paynoCardDecoration(context, radius: borderRadius);
  }
}
