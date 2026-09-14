import 'dart:async';
import 'package:flutter/foundation.dart';
import 'tv_driver.dart';

/// Driver de comunicação para Smart TVs Samsung rodando Tizen OS
/// via protocolo WebSocket (portas 8001/8002).
class SamsungTizenDriver implements TvDriver {
  DeviceConnectionState _state = DeviceConnectionState.disconnected;

  @override
  final TvBrand brand = TvBrand.samsungTizen;

  @override
  String get brandDisplayName => brand.displayName;

  @override
  bool get supportsTrackpad => false;

  @override
  bool get supportsPairingPin => false;

  @override
  DeviceConnectionState get connectionState => _state;

  @override
  bool get isConnected => _state == DeviceConnectionState.connected;

  @override
  void Function(DeviceConnectionState state)? onStateChanged;

  @override
  void Function(String token)? onAuthTokenReceived;

  @override
  void Function(String error)? onError;

  @override
  void Function(String deviceName, String? modelName)? onDeviceNameResolved;

  @override
  void Function(int volume, bool isMuted)? onVolumeStatusChanged;

  @override
  void Function(bool promptPin)? onPinPromptRequested;

  void _setState(DeviceConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(_state);
    }
  }

  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _setState(DeviceConnectionState.connecting);
    debugPrint('[Samsung] Conectando à TV Samsung Tizen em $ipAddress...');
    // A implementação completa de WebSocket porta 8001/8002 será adicionada na expansão de marcas.
    return false;
  }

  @override
  Future<void> sendPairingPin(String pin) async {}

  @override
  void disconnect() {
    _setState(DeviceConnectionState.disconnected);
    debugPrint('[Samsung] Desconectado da TV Samsung.');
  }

  @override
  void sendKey(RemoteKey key) {
    debugPrint('[Samsung] Comando enviado: $key');
  }

  @override
  void sendDigit(int digit) {
    debugPrint('[Samsung] Dígito enviado: $digit');
  }

  @override
  void setMute(bool mute) {
    debugPrint('[Samsung] Mudo: $mute');
  }

  @override
  void setVolume(int volume) {
    debugPrint('[Samsung] Volume: $volume');
  }

  @override
  void sendTrackpadDelta(double dx, double dy) {}

  @override
  void sendTrackpadClick() {
    sendKey(RemoteKey.dpadOk);
  }

  @override
  void sendText(String text) {
    debugPrint('[Samsung] Digitando texto: $text');
  }

  @override
  void openApp(String appId) {
    debugPrint('[Samsung] Abrindo app: $appId');
  }
}
