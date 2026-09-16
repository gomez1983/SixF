import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serviço utilitário centralizado para gerenciamento de feedback háptico (vibração tátil).
///
/// Fornece padrões distintos para cliques mecânicos de botões, ações críticas (como Power)
/// e seleções sutis de abas ou navegação, respeitando a preferência do usuário.
class HapticService {
  HapticService._();

  /// Define ou obtém se o feedback háptico está atualmente ativado.
  static bool isEnabled = true;

  /// Verifica se a plataforma atual suporta nativamente feedback tátil por vibração.
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Acionamento padrão para clique de botões do controle remoto (sensação de tecla mecânica).
  static Future<void> buttonPress() async {
    if (!isEnabled || !isSupportedPlatform) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      // Ignora falhas em plataformas sem motor de vibração disponível
    }
  }

  /// Acionamento de impacto médio para ações de destaque (ex: Ligar/Desligar Power).
  static Future<void> heavyPress() async {
    if (!isEnabled || !isSupportedPlatform) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      // Ignora falhas
    }
  }

  /// Acionamento sutil para navegação por abas ou cliques discretos no trackpad.
  static Future<void> selectionClick() async {
    if (!isEnabled || !isSupportedPlatform) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {
      // Ignora falhas
    }
  }
}
