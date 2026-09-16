import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'tv_driver.dart';

/// Driver de comunicação para Smart TVs Samsung rodando Tizen OS
/// via protocolo WebSocket (portas 8001/8002) e consulta REST.
class SamsungTizenDriver implements TvDriver {
  WebSocket? _socket;
  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  String? _currentIp;
  String? _token;

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
    disconnect();
    _currentIp = ipAddress.trim();
    _token = authToken;
    _setState(DeviceConnectionState.connecting);

    if (kIsWeb) {
      debugPrint('[Samsung] WebSocket nativo não é suportado no navegador Web.');
      _setState(DeviceConnectionState.disconnected);
      return false;
    }

    // 1. Tenta obter metadados do aparelho via REST em background
    _fetchDeviceInfo(_currentIp!);

    final appNameBase64 = base64Encode(utf8.encode('SixF'));

    try {
      // 2. Tenta porta segura 8002 (Tizen moderno 2016+)
      String secureUrl = 'wss://$_currentIp:8002/api/v2/channels/samsung.remote.control?name=$appNameBase64';
      if (_token != null && _token!.isNotEmpty) {
        secureUrl += '&token=$_token';
      }

      bool connected = await _tryConnect(secureUrl, isSecure: true, timeout: timeout);

      // 3. Fallback para porta 8001 (Tizen legado/HTTP)
      if (!connected) {
        debugPrint('[Samsung] Tentando fallback para porta 8001 (ws://)...');
        final legacyUrl = 'ws://$_currentIp:8001/api/v2/channels/samsung.remote.control?name=$appNameBase64';
        connected = await _tryConnect(legacyUrl, isSecure: false, timeout: timeout);
      }

      if (!connected) {
        debugPrint('[Samsung] Não foi possível conectar à TV Samsung em $_currentIp.');
        _setState(DeviceConnectionState.disconnected);
        onError?.call('Não foi possível conectar à TV Samsung em $_currentIp.');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[Samsung] Erro ao conectar: $e');
      _setState(DeviceConnectionState.disconnected);
      onError?.call('Erro de conexão Samsung: $e');
      return false;
    }
  }

  Future<bool> _tryConnect(String url, {required bool isSecure, required Duration timeout}) async {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return false;
      }

      final client = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

      _socket = await WebSocket.connect(
        url,
        customClient: isSecure ? client : null,
      ).timeout(timeout);

      _socket!.listen(
        _onMessageReceived,
        onDone: _onSocketClosed,
        onError: (err) {
          debugPrint('[Samsung] Erro no socket: $err');
          disconnect();
        },
      );

      _setState(DeviceConnectionState.connected);
      debugPrint('[Samsung] Conectado com sucesso em $url');
      return true;
    } catch (e) {
      debugPrint('[Samsung] Falha ao tentar $url: $e');
      return false;
    }
  }

  void _onMessageReceived(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final event = msg['event'];

      if (event == 'ms.channel.connect') {
        _setState(DeviceConnectionState.connected);
        final payload = msg['data'] as Map<String, dynamic>?;
        if (payload != null && payload.containsKey('token')) {
          final token = payload['token'] as String;
          _token = token;
          onAuthTokenReceived?.call(token);
          debugPrint('[Samsung] Token de autorização recebido: $token');
        }
      } else if (event == 'ms.channel.clientConnect') {
        _setState(DeviceConnectionState.connected);
      } else if (event == 'ms.channel.unauthorized') {
        _setState(DeviceConnectionState.pairingPrompt);
        debugPrint('[Samsung] Confirmação pendente na tela da TV Samsung...');
      }
    } catch (e) {
      debugPrint('[Samsung] Erro ao decodificar mensagem: $e');
    }
  }

  void _onSocketClosed() {
    debugPrint('[Samsung] Conexão com TV Samsung encerrada.');
    _socket = null;
    _setState(DeviceConnectionState.disconnected);
  }

  /// Consulta os metadados da TV Samsung via REST na porta 8001
  Future<void> _fetchDeviceInfo(String ip) async {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return;

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse('http://$ip:8001/api/v2/'));
      final response = await request.close().timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final device = json['device'] as Map<String, dynamic>?;
        if (device != null) {
          final name = device['name'] as String? ?? 'Samsung Smart TV';
          final model = device['modelName'] as String?;
          onDeviceNameResolved?.call(name, model);
          debugPrint('[Samsung] Informações resolvidas: $name ($model)');
        }
      }
    } catch (_) {
      // Falha silenciosa de probe REST
    }
  }

  @override
  Future<void> sendPairingPin(String pin) async {
    // Samsung Tizen exibe prompt "Permitir" na tela, sem PIN.
  }

  @override
  void disconnect() {
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    _setState(DeviceConnectionState.disconnected);
  }

  @override
  void sendKey(RemoteKey key) {
    final tizenKey = _mapKeyToTizen(key);
    if (tizenKey != null) {
      _sendTizenKey(tizenKey);
    }
  }

  @override
  void sendDigit(int digit) {
    if (digit >= 0 && digit <= 9) {
      _sendTizenKey('KEY_$digit');
    }
  }

  @override
  void setMute(bool mute) {
    _sendTizenKey('KEY_MUTE');
  }

  @override
  void setVolume(int volume) {
    // Samsung Tizen não possui comando REST/WS direto de volume absoluto sem SmartThings; usa VOLUP/VOLDOWN
    _sendTizenKey('KEY_VOLUP');
  }

  @override
  void sendTrackpadDelta(double dx, double dy) {}

  @override
  void sendTrackpadClick() {
    sendKey(RemoteKey.dpadOk);
  }

  @override
  void sendText(String text) {
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      _sendTizenKey('KEY_${char.toUpperCase()}');
    }
  }

  @override
  void openApp(String appId) {
    // Abre aplicativo via REST API
    if (_currentIp != null && _currentIp!.isNotEmpty) {
      _launchAppRest(_currentIp!, appId);
    }
  }

  @override
  Future<List<TvAppInfo>> getInstalledApps() async {
    // Tizen moderno bloqueia a listagem genérica de apps instalados via porta local
    // sem autenticação OAuth SmartThings. Entregamos a lista curada dos principais
    // serviços e apps suportados pelo Tizen OS.
    return [
      TvAppInfo.fromRaw(id: '111299001912', name: 'YouTube'),
      TvAppInfo.fromRaw(id: '11101200001', name: 'Netflix'),
      TvAppInfo.fromRaw(id: '3201512006785', name: 'Prime Video'),
      TvAppInfo.fromRaw(id: '3201901017640', name: 'Disney+'),
      TvAppInfo.fromRaw(id: '3201807016597', name: 'Apple TV'),
      TvAppInfo.fromRaw(id: '3201606009684', name: 'Spotify'),
      TvAppInfo.fromRaw(id: '3201601007250', name: 'Max'),
      TvAppInfo.fromRaw(id: '3201608010191', name: 'Globoplay'),
      TvAppInfo.fromRaw(id: '3201710015037', name: 'Twitch'),
      TvAppInfo.fromRaw(id: 'org.tizen.browser', name: 'Navegador Web'),
    ];
  }

  Future<void> _launchAppRest(String ip, String appId) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://$ip:8001/api/v2/applications/$appId'));
      await request.close();
      debugPrint('[Samsung] Requisição de abertura enviada para app $appId');
    } catch (e) {
      debugPrint('[Samsung] Erro ao abrir app $appId: $e');
    }
  }

  void _sendTizenKey(String keyName) {
    if (!isConnected || _socket == null) {
      debugPrint('[Samsung] Tecla não enviada: TV desconectada ($keyName)');
      return;
    }

    final payload = {
      'method': 'ms.remote.control',
      'params': {
        'Cmd': 'Click',
        'DataOfCmd': keyName,
        'Option': 'false',
        'TypeOfRemote': 'SendRemoteKey',
      }
    };

    try {
      _socket!.add(jsonEncode(payload));
      debugPrint('[Samsung] Tecla enviada: $keyName');
    } catch (e) {
      debugPrint('[Samsung] Erro ao enviar comando: $e');
    }
  }

  String? _mapKeyToTizen(RemoteKey key) {
    switch (key) {
      case RemoteKey.power:
        return 'KEY_POWER';
      case RemoteKey.volumeUp:
        return 'KEY_VOLUP';
      case RemoteKey.volumeDown:
        return 'KEY_VOLDOWN';
      case RemoteKey.mute:
        return 'KEY_MUTE';
      case RemoteKey.channelUp:
        return 'KEY_CHUP';
      case RemoteKey.channelDown:
        return 'KEY_CHDOWN';
      case RemoteKey.dpadUp:
        return 'KEY_UP';
      case RemoteKey.dpadDown:
        return 'KEY_DOWN';
      case RemoteKey.dpadLeft:
        return 'KEY_LEFT';
      case RemoteKey.dpadRight:
        return 'KEY_RIGHT';
      case RemoteKey.dpadOk:
        return 'KEY_ENTER';
      case RemoteKey.back:
        return 'KEY_RETURN';
      case RemoteKey.home:
        return 'KEY_HOME';
      case RemoteKey.menu:
        return 'KEY_MENU';
      case RemoteKey.exit:
        return 'KEY_EXIT';
      case RemoteKey.input:
        return 'KEY_SOURCE';
      case RemoteKey.play:
        return 'KEY_PLAY';
      case RemoteKey.pause:
        return 'KEY_PAUSE';
      case RemoteKey.stop:
        return 'KEY_STOP';
      case RemoteKey.rewind:
        return 'KEY_REWIND';
      case RemoteKey.fastForward:
        return 'KEY_FF';
      case RemoteKey.colorRed:
        return 'KEY_RED';
      case RemoteKey.colorGreen:
        return 'KEY_GREEN';
      case RemoteKey.colorYellow:
        return 'KEY_YELLOW';
      case RemoteKey.colorBlue:
        return 'KEY_CYAN';
      case RemoteKey.dash:
        return 'KEY_DASH';
    }
  }
}
