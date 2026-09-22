import 'dart:async';
import 'tv_app_info.dart';
export 'tv_app_info.dart';

/// Marcas e plataformas de Smart TVs e dispositivos suportados pelo SixF.
enum TvBrand {
  lgWebOs,
  samsungTizen,
}

extension TvBrandExtension on TvBrand {
  String get displayName {
    switch (this) {
      case TvBrand.lgWebOs:
        return 'LG webOS';
      case TvBrand.samsungTizen:
        return 'Samsung Tizen';
    }
  }

  String get id {
    switch (this) {
      case TvBrand.lgWebOs:
        return 'lg_webos';
      case TvBrand.samsungTizen:
        return 'samsung_tizen';
    }
  }
}

/// Estados de conexão padronizados para qualquer driver de dispositivo.
enum DeviceConnectionState {
  disconnected,
  connecting,
  pairingPrompt, // Prompt na tela (LG/Samsung) ou solicitação de PIN (Android TV)
  connected,
}

/// Teclas e comandos padronizados aceitos pelos drivers de controle remoto.
enum RemoteKey {
  power,
  volumeUp,
  volumeDown,
  mute,
  channelUp,
  channelDown,
  dpadUp,
  dpadDown,
  dpadLeft,
  dpadRight,
  dpadOk,
  back,
  home,
  menu,
  exit,
  input,
  play,
  pause,
  stop,
  rewind,
  fastForward,
  colorRed,
  colorGreen,
  colorYellow,
  colorBlue,
  dash,
  voice,
}

/// Interface base agnóstica para drivers de comunicação com Smart TVs e Dongles.
abstract class TvDriver {
  /// Marca ou ecossistema deste driver.
  TvBrand get brand;

  /// Nome de exibição amigável da marca.
  String get brandDisplayName => brand.displayName;

  /// Estado atual de conexão do dispositivo.
  DeviceConnectionState get connectionState;

  /// Indica se o dispositivo está atualmente conectado e autenticado.
  bool get isConnected => connectionState == DeviceConnectionState.connected;

  /// Indica se o driver suporta ponteiro livre / Magic Trackpad (ex: LG Magic Remote).
  bool get supportsTrackpad;

  /// Indica se o dispositivo exige inserção de código PIN durante o pareamento.
  bool get supportsPairingPin;

  // --- Callbacks de Ciclo de Vida e Eventos ---
  void Function(DeviceConnectionState state)? onStateChanged;
  void Function(String token)? onAuthTokenReceived;
  void Function(String error)? onError;
  void Function(String deviceName, String? modelName)? onDeviceNameResolved;
  void Function(int volume, bool isMuted)? onVolumeStatusChanged;
  void Function(bool promptPin)? onPinPromptRequested;

  // --- Ciclo de Vida e Conexão ---

  /// Inicia o processo de conexão com o dispositivo no [ipAddress].
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 4),
  });

  /// Envia o código PIN de pareamento (utilizado no Android TV / Google TV).
  Future<void> sendPairingPin(String pin);

  /// Encerra a conexão com o dispositivo.
  void disconnect();

  // --- Comandos de Controle ---

  /// Envia uma tecla padronizada para o dispositivo.
  void sendKey(RemoteKey key);

  /// Envia um dígito numérico (0 a 9) para seleção de canal ou PIN.
  void sendDigit(int digit);

  /// Define o estado de mudo do áudio.
  void setMute(bool mute);

  /// Ajusta o volume para um nível específico (se suportado pelo protocolo).
  void setVolume(int volume);

  /// Envia deslocamento de trackpad (para dispositivos com suporte a mouse/ponteiro).
  void sendTrackpadDelta(double dx, double dy);

  /// Envia clique do ponteiro ou confirmação de trackpad.
  void sendTrackpadClick();

  /// Envia uma cadeia de texto para campos de digitação abertos no dispositivo.
  void sendText(String text);

  /// Abre um aplicativo pelo identificador de pacote ou URI.
  void openApp(String appId);

  /// Retorna a lista de aplicativos instalados ou atalhos disponíveis no dispositivo.
  Future<List<TvAppInfo>> getInstalledApps();

  /// Aciona a busca ou assistente de voz nativo da TV.
  void triggerVoice() {
    sendKey(RemoteKey.voice);
  }
}
