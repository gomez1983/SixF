import 'package:flutter/material.dart';

/// Representa um aplicativo ou atalho disponível na Smart TV.
class TvAppInfo {
  /// Identificador único ou pacote do aplicativo (ex: 'netflix', '111299001912').
  final String id;

  /// Nome de exibição amigável do aplicativo (ex: 'Netflix', 'YouTube').
  final String name;

  /// URL de ícone remoto fornecido pela TV (quando disponível, ex: LG webOS).
  final String? iconUrl;

  /// Chave identificadora para estilização e ícone padrão de marcas conhecidas.
  final String? iconKey;

  /// Cor de destaque temático para o card do app.
  final Color? brandColor;

  /// Ícone vetorial alternativo quando a imagem da rede não estiver disponível.
  final IconData fallbackIcon;

  const TvAppInfo({
    required this.id,
    required this.name,
    this.iconUrl,
    this.iconKey,
    this.brandColor,
    this.fallbackIcon = Icons.tv_rounded,
  });

  /// Determina uma chave de marca a partir do ID ou nome do aplicativo.
  static String resolveIconKey(String id, String name) {
    final lowerId = id.toLowerCase();
    final lowerName = name.toLowerCase();

    if (lowerId.contains('netflix') || lowerName.contains('netflix')) {
      return 'netflix';
    } else if (lowerId.contains('youtube') || lowerName.contains('youtube')) {
      return 'youtube';
    } else if (lowerId.contains('amazon') ||
        lowerId.contains('prime') ||
        lowerName.contains('prime video')) {
      return 'prime';
    } else if (lowerId.contains('disney') || lowerName.contains('disney')) {
      return 'disney';
    } else if (lowerId.contains('spotify') || lowerName.contains('spotify')) {
      return 'spotify';
    } else if (lowerId.contains('apple') || lowerName.contains('apple tv')) {
      return 'appletv';
    } else if (lowerId.contains('max') ||
        lowerId.contains('hbo') ||
        lowerName.contains('max') ||
        lowerName.contains('hbo')) {
      return 'max';
    } else if (lowerId.contains('globo') || lowerName.contains('globoplay')) {
      return 'globoplay';
    } else if (lowerId.contains('twitch') || lowerName.contains('twitch')) {
      return 'twitch';
    } else if (lowerId.contains('browser') ||
        lowerName.contains('navegador') ||
        lowerName.contains('internet')) {
      return 'browser';
    } else if (lowerId.contains('livetv') ||
        lowerId.contains('channel') ||
        lowerName.contains('tv aberta') ||
        lowerName.contains('canais')) {
      return 'livetv';
    }
    return 'generic';
  }

  /// Retorna cor de destaque e ícone para um aplicativo com base no seu nome/ID.
  factory TvAppInfo.fromRaw({
    required String id,
    required String name,
    String? iconUrl,
  }) {
    final key = resolveIconKey(id, name);
    Color? color;
    IconData icon = Icons.smart_display_rounded;

    switch (key) {
      case 'netflix':
        color = const Color(0xFFE50914);
        icon = Icons.movie_rounded;
        break;
      case 'youtube':
        color = const Color(0xFFFF0000);
        icon = Icons.play_circle_filled_rounded;
        break;
      case 'prime':
        color = const Color(0xFF00A8E1);
        icon = Icons.ondemand_video_rounded;
        break;
      case 'disney':
        color = const Color(0xFF113CCF);
        icon = Icons.auto_awesome_rounded;
        break;
      case 'spotify':
        color = const Color(0xFF1DB954);
        icon = Icons.music_note_rounded;
        break;
      case 'appletv':
        color = const Color(0xFF2C2C2E);
        icon = Icons.tv_rounded;
        break;
      case 'max':
        color = const Color(0xFF002BE7);
        icon = Icons.local_movies_rounded;
        break;
      case 'globoplay':
        color = const Color(0xFFFF2E00);
        icon = Icons.play_arrow_rounded;
        break;
      case 'twitch':
        color = const Color(0xFF9146FF);
        icon = Icons.videogame_asset_rounded;
        break;
      case 'browser':
        color = const Color(0xFF00BCD4);
        icon = Icons.language_rounded;
        break;
      case 'livetv':
        color = const Color(0xFF4CAF50);
        icon = Icons.live_tv_rounded;
        break;
      default:
        color = null;
        icon = Icons.tv_rounded;
    }

    return TvAppInfo(
      id: id,
      name: name,
      iconUrl: iconUrl,
      iconKey: key,
      brandColor: color,
      fallbackIcon: icon,
    );
  }

  @override
  String toString() => 'TvAppInfo(id: $id, name: $name, key: $iconKey)';
}
