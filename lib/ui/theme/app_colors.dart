import 'package:flutter/material.dart';

import '../glass/glass_flags.dart';
import '../glass/liquid_glass.dart' show GlassTokens, glassFlatDecoration;

/// Paleta do padrão visual ZIXO (referência em `Referências/ZIXO*.jpg` e
/// mockup em `docs/design/mockups/sixf-zixo-mockup.html`): fundo cinza-claro
/// neutro com halos difusos, cards de vidro fosco e uma paleta fechada de
/// quatro cores — grafite #414140, branco #FFFFFF, verde #38BC37 e vermelho
/// #F44336. O Modo Escuro é a extrapolação da mesma paleta: fundo quase
/// preto, vidro escuro e o destaque invertido (claro com conteúdo escuro).
///
/// Os nomes dos campos vêm do padrão anterior (Payno); só os valores mudaram,
/// para nenhuma tela precisar trocar de chamada.
class AppColors {
  AppColors._();

  // --- Paleta ZIXO (base) ---
  static const Color zixoGraphite = Color(0xFF414140);
  static const Color zixoWhite = Color(0xFFFFFFFF);
  static const Color zixoGreen = Color(0xFF38BC37);
  static const Color zixoRed = Color(0xFFF44336);

  // --- Paleta Dark Mode (ZIXO escuro — #0F0F0F, vidro escuro) ---
  static const Color background = Color(0xFF0F0F0F);
  static const Color ambientGlowPrimary = Color(0x14FFFFFF);
  static const Color ambientGlowSecondary = Color(0x0AFFFFFF);
  static const Color remoteChassis = Color(0xF71A1A19);
  static const Color surfaceCard = Color(0xFA1E1E1D);
  static const Color surfaceElevated = Color(0xFF262625);
  static const Color surfaceInteractive = Color(0xFF222221);
  static const Color surfaceInteractiveHover = Color(0xFF2C2C2B);
  static const Color borderSubtle = Color(0x17FFFFFF);
  static const Color borderActive = Color(0xFFD6D6D2);
  static const Color textPrimary = Color(0xFFF2F2EF);
  static const Color textSecondary = Color(0xFFB4B4AF);
  static const Color textMuted = Color(0xFF8E8E89);
  static const Color iconDefault = Color(0xFFF2F2EF);
  static const Color iconHighlight = Color(0xFFEFEFEC);
  static const Color trackpadSurface = Color(0xFF1A1A19);
  static const Color trackpadBorder = Color(0x1FFFFFFF);
  static const Color trackpadCrosshair = Color(0x38EFEFEC);
  static const Color trackpadIndicator = Color(0xFFEFEFEC);

  // --- Paleta Light Mode (ZIXO claro — #EDEDEB, vidro claro) ---
  static const Color lightBackground = Color(0xFFEDEDEB);
  static const Color lightAmbientGlowPrimary = Color(0xCCFFFFFF);
  static const Color lightAmbientGlowSecondary = Color(0x80FFFFFF);
  static const Color lightRemoteChassis = Color(0xFAF7F7F6);
  static const Color lightSurfaceCard = Color(0xFAFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF5F5F4);
  static const Color lightSurfaceInteractive = Color(0xFFF3F3F2);
  static const Color lightSurfaceInteractiveHover = Color(0xFFE9E9E7);
  static const Color lightBorderSubtle = Color(0x14141414);
  static const Color lightBorderActive = zixoGraphite;
  static const Color lightTextPrimary = Color(0xFF141414);
  static const Color lightTextSecondary = Color(0xFF5C5C58);
  static const Color lightTextMuted = Color(0xFF8B8B87);
  static const Color lightIconDefault = Color(0xFF141414);
  static const Color lightIconHighlight = zixoGraphite;
  static const Color lightTrackpadSurface = Color(0xD9F5F5F4);
  static const Color lightTrackpadBorder = Color(0x1F141414);

  // --- Destaque (botão OK, aba ativa, botões primários) ---
  // Claro: grafite com conteúdo branco. Escuro: invertido, quase branco com
  // conteúdo grafite-escuro. Use sempre [onAccentOf] para o conteúdo.
  static const Color accentFill = Color(0xFFEFEFEC);
  static const Color lightAccentFill = zixoGraphite;
  static const Color onAccentFill = Color(0xFF141414);
  static const Color lightOnAccentFill = zixoWhite;

  // --- Cores Globais Compartilhadas ---
  static const Color lgRed = zixoGraphite;
  static const Color powerRed = zixoRed;
  static const Color powerGlow = Color(0x33F44336);

  // Status de conexão (verde ZIXO; "conectando" fica em cinza médio, porque
  // a paleta não tem âmbar)
  static const Color statusConnected = zixoGreen;
  static const Color statusConnectedDark = zixoGreen;
  static const Color statusDisconnected = Color(0xFF8B8B87);
  static const Color statusConnecting = Color(0xFFA8A8A3);

  // Cores tradicionais dos 4 botões de controle Smart TV (funções da TV:
  // ficam fora da paleta de propósito, só como pontos pequenos)
  static const Color buttonRed = zixoRed;
  static const Color buttonGreen = zixoGreen;
  static const Color buttonYellow = Color(0xFFE8B931);
  static const Color buttonBlue = Color(0xFF3D7FE0);

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

  /// Destaque sólido (botão OK, aba ativa, botões primários).
  static Color accentFillOf(BuildContext context) =>
      isDark(context) ? accentFill : lightAccentFill;

  /// Conteúdo (texto e ícone) sobre o destaque sólido.
  static Color onAccentOf(BuildContext context) =>
      isDark(context) ? onAccentFill : lightOnAccentFill;

  /// Fundo suave do destaque (linha selecionada, chips ativos discretos).
  static Color accentSoftOf(BuildContext context) => isDark(context)
      ? const Color(0x14FFFFFF)
      : const Color(0x14414140);

  /// Fundo de card de vidro fosco sobre o fundo ambiente.
  static Color cardOf(BuildContext context) =>
      isDark(context) ? const Color(0x17FFFFFF) : const Color(0xBFFFFFFF);

  /// Fundo de botões circulares (padrão "Quick Actions").
  static Color circleOf(BuildContext context) =>
      isDark(context) ? const Color(0xFF1F1F1E) : const Color(0xF2FFFFFF);

  /// Verde de status legível em cada tema.
  static Color okOf(BuildContext context) =>
      isDark(context) ? statusConnectedDark : statusConnected;

  /// Sombra suave usada nos cards e botões circulares.
  static List<BoxShadow> softShadowOf(BuildContext context) => isDark(context)
      ? const [
          BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 14)),
        ]
      : const [
          BoxShadow(color: Color(0x1A282826), blurRadius: 30, offset: Offset(0, 14)),
          BoxShadow(color: Color(0x0A282826), blurRadius: 2, offset: Offset(0, 1)),
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

  /// Card de vidro fosco ZIXO: preenchimento em degradê vertical (mais claro
  /// em cima), borda clara de reflexo e sombra difusa.
  static BoxDecoration paynoCardDecoration(
    BuildContext context, {
    double radius = 20,
    Color? color,
  }) {
    final dark = isDark(context);
    return BoxDecoration(
      color: color,
      gradient: color != null
          ? null
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? const [Color(0x16FFFFFF), Color(0x09FFFFFF)]
                  : const [Color(0xD1FFFFFF), Color(0x8CFFFFFF)],
            ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark ? const Color(0x17FFFFFF) : const Color(0xF2FFFFFF),
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
