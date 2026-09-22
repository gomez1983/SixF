import 'dart:async';
import '../webos_service.dart';
import 'tv_driver.dart';

/// Driver de comunicação para Smart TVs LG rodando webOS via protocolo SSAP.
class LgWebOsDriver implements TvDriver {
  final WebOsService _webOsService;

  @override
  final TvBrand brand = TvBrand.lgWebOs;

  @override
  String get brandDisplayName => brand.displayName;

  @override
  bool get supportsTrackpad => true;

  @override
  bool get supportsPairingPin => false;

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

  /// Retorna a instância interna de [WebOsService] para interoperabilidade e testes.
  WebOsService get webOsService => _webOsService;

  LgWebOsDriver({WebOsService? webOsService})
      : _webOsService = webOsService ?? WebOsService() {
    _bindCallbacks();
  }

  void _bindCallbacks() {
    _webOsService.onStateChanged = (state) {
      final mappedState = _mapWebOsState(state);
      onStateChanged?.call(mappedState);
    };

    _webOsService.onClientKeyReceived = (key) {
      onAuthTokenReceived?.call(key);
    };

    _webOsService.onError = (err) {
      onError?.call(err);
    };

    _webOsService.onDeviceNameResolved = (name, model) {
      onDeviceNameResolved?.call(name, model);
    };

    _webOsService.onVolumeStatusChanged = (volume, isMuted) {
      onVolumeStatusChanged?.call(volume, isMuted);
    };
  }

  DeviceConnectionState _mapWebOsState(WebOsConnectionState state) {
    switch (state) {
      case WebOsConnectionState.disconnected:
        return DeviceConnectionState.disconnected;
      case WebOsConnectionState.connecting:
        return DeviceConnectionState.connecting;
      case WebOsConnectionState.pairingPrompt:
        return DeviceConnectionState.pairingPrompt;
      case WebOsConnectionState.connected:
        return DeviceConnectionState.connected;
    }
  }

  @override
  DeviceConnectionState get connectionState =>
      _mapWebOsState(_webOsService.state);

  @override
  bool get isConnected => _webOsService.isConnected;

  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 4),
  }) {
    return _webOsService.connect(
      ipAddress: ipAddress,
      savedClientKey: authToken,
      timeout: timeout,
    );
  }

  @override
  Future<void> sendPairingPin(String pin) async {
    // LG webOS utiliza confirmação na tela da TV, não código PIN.
  }

  @override
  void disconnect() {
    _webOsService.disconnect();
  }

  @override
  void sendKey(RemoteKey key) {
    switch (key) {
      case RemoteKey.power:
        _webOsService.turnOff();
        break;
      case RemoteKey.volumeUp:
        _webOsService.volumeUp();
        break;
      case RemoteKey.volumeDown:
        _webOsService.volumeDown();
        break;
      case RemoteKey.mute:
        // RemoteController gerencia toggle ou setMute
        _webOsService.setMute(true);
        break;
      case RemoteKey.channelUp:
        _webOsService.channelUp();
        break;
      case RemoteKey.channelDown:
        _webOsService.channelDown();
        break;
      case RemoteKey.dpadUp:
        _webOsService.dpadUp();
        break;
      case RemoteKey.dpadDown:
        _webOsService.dpadDown();
        break;
      case RemoteKey.dpadLeft:
        _webOsService.dpadLeft();
        break;
      case RemoteKey.dpadRight:
        _webOsService.dpadRight();
        break;
      case RemoteKey.dpadOk:
        _webOsService.pressOk();
        break;
      case RemoteKey.back:
        _webOsService.pressBack();
        break;
      case RemoteKey.home:
        _webOsService.pressHome();
        break;
      case RemoteKey.menu:
        _webOsService.pressMenu();
        break;
      case RemoteKey.exit:
        _webOsService.pressExit();
        break;
      case RemoteKey.input:
        _webOsService.sendButton('INPUT');
        break;
      case RemoteKey.play:
        _webOsService.mediaPlay();
        break;
      case RemoteKey.pause:
        _webOsService.mediaPause();
        break;
      case RemoteKey.stop:
        _webOsService.mediaStop();
        break;
      case RemoteKey.rewind:
        _webOsService.mediaRewind();
        break;
      case RemoteKey.fastForward:
        _webOsService.mediaFastForward();
        break;
      case RemoteKey.colorRed:
        _webOsService.pressColorRed();
        break;
      case RemoteKey.colorGreen:
        _webOsService.pressColorGreen();
        break;
      case RemoteKey.colorYellow:
        _webOsService.pressColorYellow();
        break;
      case RemoteKey.colorBlue:
        _webOsService.pressColorBlue();
        break;
      case RemoteKey.dash:
        _webOsService.pressDash();
        break;
      case RemoteKey.voice:
        _webOsService.triggerVoiceSearch();
        break;
    }
  }

  @override
  void triggerVoice() {
    _webOsService.triggerVoiceSearch();
  }

  @override
  void sendDigit(int digit) {
    _webOsService.pressDigit(digit);
  }

  @override
  void setMute(bool mute) {
    _webOsService.setMute(mute);
  }

  @override
  void setVolume(int volume) {
    _webOsService.sendCommand('ssap://audio/setVolume', {'volume': volume});
  }

  @override
  void sendTrackpadDelta(double dx, double dy) {
    _webOsService.sendTrackpadDelta(dx, dy);
  }

  @override
  void sendTrackpadClick() {
    _webOsService.sendTrackpadClick();
  }

  @override
  void sendText(String text) {
    _webOsService.sendCommand('ssap://com.webos.service.ime/insertText', {
      'text': text,
      'replace': 0,
    });
  }

  @override
  void openApp(String appId) {
    _webOsService.launchApp(appId);
  }

  @override
  Future<List<TvAppInfo>> getInstalledApps() {
    return _webOsService.getInstalledApps();
  }
}
