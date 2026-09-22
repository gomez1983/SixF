import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'drivers/tv_driver.dart';

/// Tipos de intenção reconhecidos pelo comando de voz do SixF.
enum VoiceIntentType {
  /// Aumentar o volume em 5 passos consecutivos.
  volumeUp,

  /// Diminuir o volume em 5 passos consecutivos.
  volumeDown,

  /// Alternar o modo mudo (mute / unmute).
  toggleMute,

  /// Desligar o dispositivo / TV.
  powerOff,

  /// Abrir um aplicativo instalado pelo nome ou id.
  openApp,

  /// Inserir o texto ditado diretamente no campo de pesquisa da TV.
  textSearch,
}

/// Representa a intenção classificada a partir do texto falado ou digitado.
class VoiceIntent {
  final VoiceIntentType type;
  final String rawText;
  final String? targetApp;
  final String? targetAppId;
  final String displayDescription;

  const VoiceIntent({
    required this.type,
    required this.rawText,
    this.targetApp,
    this.targetAppId,
    required this.displayDescription,
  });

  bool get isCommand => type != VoiceIntentType.textSearch;

  @override
  String toString() =>
      'VoiceIntent(type: $type, rawText: "$rawText", app: $targetApp, desc: "$displayDescription")';
}

/// Serviço de reconhecimento de voz e classificação de intenções do SixF.
///
/// Suporta:
/// - Reconhecimento de fala em tempo real via [stt.SpeechToText].
/// - Alternância de idioma entre Português (pt_BR) e Inglês (en_US).
/// - Classificação inteligente de comandos de ação vs. ditado para pesquisa.
class VoiceService {
  final stt.SpeechToText _speech;
  bool _isInitialized = false;
  bool _isListening = false;
  String currentLocaleId = 'pt_BR';

  VoiceService({stt.SpeechToText? speechInstance})
      : _speech = speechInstance ?? stt.SpeechToText();

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;

  /// Inicializa o mecanismo de reconhecimento de fala e verifica permissões.
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (err) {
          debugPrint('[VoiceService] Erro no SpeechToText: ${err.errorMsg}');
          _isListening = false;
        },
        onStatus: (status) {
          debugPrint('[VoiceService] Status do SpeechToText: $status');
          if (status == 'notListening' || status == 'done') {
            _isListening = false;
          }
        },
      );
      return _isInitialized;
    } catch (e) {
      debugPrint('[VoiceService] Falha ao inicializar microfone: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// Inicia a captura de fala com streaming do texto reconhecido.
  Future<bool> startListening({
    required ValueChanged<String> onResult,
    VoidCallback? onDone,
    String? localeId,
  }) async {
    final ready = await initialize();
    if (!ready) {
      debugPrint('[VoiceService] Microfone não inicializado ou sem permissão.');
      return false;
    }

    final targetLocale = localeId ?? currentLocaleId;
    _isListening = true;

    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords;
          onResult(words);
          if (result.finalResult) {
            _isListening = false;
            onDone?.call();
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          cancelOnError: true,
          partialResults: true,
          localeId: targetLocale,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[VoiceService] Erro ao iniciar escuta: $e');
      _isListening = false;
      return false;
    }
  }

  /// Para a escuta de áudio ativamente.
  Future<void> stopListening() async {
    if (_isListening) {
      _isListening = false;
      try {
        await _speech.stop();
      } catch (e) {
        debugPrint('[VoiceService] Erro ao parar escuta: $e');
      }
    }
  }

  /// Cancela o reconhecimento sem disparar callbacks finais.
  Future<void> cancelListening() async {
    _isListening = false;
    try {
      await _speech.cancel();
    } catch (e) {
      debugPrint('[VoiceService] Erro ao cancelar escuta: $e');
    }
  }

  /// Remove acentuação e pontuações para análise robusta.
  static String normalizeText(String input) {
    var s = input.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[.,!?;:]'), '');

    // Remoção simples de acentos comuns em PT
    s = s
        .replaceAll(RegExp(r'[áàãâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòõôö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c');

    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Classifica o texto transcrito em comando de ação da TV ou texto de busca livre.
  ///
  /// Regras solicitadas:
  /// 1. Comandos curtos (<= 4 palavras) para Volume (+/- 5 passos), Apps, Mudo e Desligar.
  /// 2. Frases mais longas ou não coincidentes com ações viram [VoiceIntentType.textSearch].
  static VoiceIntent classifyIntent(
    String spokenText, {
    List<TvAppInfo>? installedApps,
  }) {
    final raw = spokenText.trim();
    if (raw.isEmpty) {
      return const VoiceIntent(
        type: VoiceIntentType.textSearch,
        rawText: '',
        displayDescription: 'Nenhum texto informado',
      );
    }

    final normalized = normalizeText(raw);
    final words = normalized.split(' ');

    // 1. Comando de Volume +5
    const volumeUpPatterns = [
      'aumentar volume',
      'aumenta volume',
      'aumenta o volume',
      'aumentar o volume',
      'subir volume',
      'sobe volume',
      'sobe o volume',
      'subir o volume',
      'mais volume',
      'volume mais',
      'volume pra cima',
      'volume para cima',
      'aumentar som',
      'aumentar o som',
      'aumenta som',
      'aumenta o som',
      'mais som',
      'sobe som',
      'sobe o som',
      'subir o som',
      'volume up',
    ];
    if (volumeUpPatterns.contains(normalized)) {
      return VoiceIntent(
        type: VoiceIntentType.volumeUp,
        rawText: raw,
        displayDescription: 'Aumentar volume (+5)',
      );
    }

    // 2. Comando de Volume -5
    const volumeDownPatterns = [
      'diminuir volume',
      'diminui volume',
      'diminui o volume',
      'diminuir o volume',
      'baixar volume',
      'baixa volume',
      'baixa o volume',
      'baixar o volume',
      'abaixar volume',
      'abaixa volume',
      'abaixa o volume',
      'abaixar o volume',
      'menos volume',
      'volume menos',
      'volume pra baixo',
      'volume para baixo',
      'diminuir som',
      'diminuir o som',
      'diminui som',
      'diminui o som',
      'baixar som',
      'baixar o som',
      'baixa o som',
      'abaixar o som',
      'menos som',
      'volume down',
    ];
    if (volumeDownPatterns.contains(normalized)) {
      return VoiceIntent(
        type: VoiceIntentType.volumeDown,
        rawText: raw,
        displayDescription: 'Diminuir volume (-5)',
      );
    }

    // 3. Comando de Mudo / Tirar mudo
    const mutePatterns = [
      'mudo',
      'mutar',
      'muta',
      'mutar tv',
      'muta a tv',
      'tirar mudo',
      'tira o mudo',
      'desmutar',
      'desmuta',
      'sem som',
      'mute',
      'unmute',
    ];
    if (mutePatterns.contains(normalized)) {
      return VoiceIntent(
        type: VoiceIntentType.toggleMute,
        rawText: raw,
        displayDescription: 'Alternar Mudo',
      );
    }

    // 4. Comando de Desligar TV
    const powerPatterns = [
      'desligar tv',
      'desliga tv',
      'desligar a tv',
      'desliga a tv',
      'desligar televisao',
      'desliga televisao',
      'desligar',
      'desliga',
      'apagar tv',
      'power off',
      'turn off tv',
    ];
    if (powerPatterns.contains(normalized)) {
      return VoiceIntent(
        type: VoiceIntentType.powerOff,
        rawText: raw,
        displayDescription: 'Desligar TV',
      );
    }

    // 5. Comando de Abrir Aplicativos
    const openPrefixes = [
      'abrir o aplicativo ',
      'abrir a aplicacao ',
      'abrir o app ',
      'abrir a app ',
      'abrir app ',
      'abrir o ',
      'abrir a ',
      'abrir ',
      'abre o app ',
      'abre o ',
      'abre a ',
      'abre ',
      'iniciar o ',
      'iniciar a ',
      'iniciar ',
      'inicia o ',
      'inicia a ',
      'inicia ',
      'lancar ',
      'open ',
      'launch ',
    ];

    for (final prefix in openPrefixes) {
      if (normalized.startsWith(prefix)) {
        final appQuery = normalized.substring(prefix.length).trim();
        if (appQuery.isNotEmpty && words.length <= 5) {
          // Busca correspondência nos apps instalados
          if (installedApps != null && installedApps.isNotEmpty) {
            for (final app in installedApps) {
              final appTitleNorm = normalizeText(app.name);
              if (appTitleNorm == appQuery ||
                  appTitleNorm.contains(appQuery) ||
                  appQuery.contains(appTitleNorm)) {
                return VoiceIntent(
                  type: VoiceIntentType.openApp,
                  rawText: raw,
                  targetApp: app.name,
                  targetAppId: app.id,
                  displayDescription: 'Abrir ${app.name}',
                );
              }
            }
          }

          // Catálogo de apps populares padrão
          final resolvedApp = _matchPopularApp(appQuery);
          return VoiceIntent(
            type: VoiceIntentType.openApp,
            rawText: raw,
            targetApp: resolvedApp.name,
            targetAppId: resolvedApp.id,
            displayDescription: 'Abrir ${resolvedApp.name}',
          );
        }
      }
    }

    // 6. Caso geral: Inserção de texto para pesquisa na TV
    return VoiceIntent(
      type: VoiceIntentType.textSearch,
      rawText: raw,
      displayDescription: 'Pesquisar: "$raw"',
    );
  }

  /// Auxiliar para mapear nomes falados aos IDs de aplicativos padrão da LG e Samsung.
  static ({String name, String id}) _matchPopularApp(String query) {
    final q = query.toLowerCase();
    if (q.contains('youtube') || q.contains('you tube')) {
      return (name: 'YouTube', id: 'youtube.leanback.v4');
    }
    if (q.contains('netflix')) {
      return (name: 'Netflix', id: 'netflix');
    }
    if (q.contains('prime') || q.contains('amazon')) {
      return (name: 'Prime Video', id: 'amazon');
    }
    if (q.contains('spotify')) {
      return (name: 'Spotify', id: 'spotify-beehive');
    }
    if (q.contains('disney')) {
      return (name: 'Disney+', id: 'com.disney.disneyplus-prod');
    }
    if (q.contains('max') || q.contains('hbo')) {
      return (name: 'Max', id: 'com.wbd.stream');
    }
    if (q.contains('globo') || q.contains('globoplay')) {
      return (name: 'Globoplay', id: 'com.globo.globotv');
    }
    if (q.contains('apple')) {
      return (name: 'Apple TV', id: 'com.apple.appletv');
    }
    if (q.contains('twitch')) {
      return (name: 'Twitch', id: 'tv.twitch.android.app');
    }
    // Fallback com o nome capitalizado
    final capName = query.length > 1
        ? '${query[0].toUpperCase()}${query.substring(1)}'
        : query.toUpperCase();
    return (name: capName, id: query);
  }
}
