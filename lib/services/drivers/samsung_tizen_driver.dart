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
  String? _detectedModel;

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

  Completer<bool>? _handshakeCompleter;
  Timer? _pairingTimeoutTimer;

  void _setState(DeviceConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(_state);
    }
  }

  String _buildWebSocketUrl({
    required String ip,
    required int port,
    required bool isSecure,
    String? token,
  }) {
    // Samsung Tizen espera "SamsungTvRemote" em Base64 (15 bytes -> exatamente 20 caracteres Base64 sem padding '=')
    // Qualquer caractere de padding '=' ou codificado como '%3D' é rejeitado pelo router WebSocket do Tizen OS.
    final nameBase64 = base64Encode(utf8.encode('SamsungTvRemote'));
    final scheme = isSecure ? 'wss' : 'ws';
    final tokenParam = (token != null && token.isNotEmpty) ? '&token=$token' : '';
    return '$scheme://$ip:$port/api/v2/channels/samsung.remote.control?name=$nameBase64$tokenParam';
  }

  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    disconnect();
    _currentIp = ipAddress.trim();
    _token = (authToken != null && authToken.trim().isNotEmpty) ? authToken.trim() : null;
    _setState(DeviceConnectionState.connecting);

    if (kIsWeb) {
      debugPrint('[Samsung] WebSocket nativo não é suportado no navegador Web.');
      _setState(DeviceConnectionState.disconnected);
      return false;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }

    // 1. Tenta obter metadados do aparelho via REST em background (portas 8001 e 8002)
    _fetchDeviceInfo(_currentIp!);

    try {
      // 2. Se houver token de autorização salvo, tenta porta segura 8002 (WSS) com o token
      if (_token != null && _token!.isNotEmpty) {
        debugPrint('[Samsung] Tentando reconectar na porta 8002 (WSS) com token salvo...');
        final secureUrlWithToken = _buildWebSocketUrl(
          ip: _currentIp!,
          port: 8002,
          isSecure: true,
          token: _token,
        );

        final connected = await _tryConnectWithToken(secureUrlWithToken, isSecure: true);
        if (connected && isConnected) {
          return true;
        }

        debugPrint('[Samsung] Token salvo rejeitado ou inválido. Limpando para novo pareamento...');
        _token = null;
        onAuthTokenReceived?.call('');
        disconnect();
      }

      // 3. Tenta porta segura 8002 (WSS) sem token para disparar o prompt "Permitir" na TV (Tizen 2016-2024)
      debugPrint('[Samsung] Conectando na porta segura 8002 (WSS) para novo pareamento...');
      _setState(DeviceConnectionState.connecting);
      final pairingUrl = _buildWebSocketUrl(
        ip: _currentIp!,
        port: 8002,
        isSecure: true,
        token: null,
      );

      final socketOpened = await _tryOpenPairingSocket(pairingUrl, isSecure: true);
      if (socketOpened) {
        return true;
      }

      // 4. Fallback para porta 8001 (ws:// legado)
      debugPrint('[Samsung] Tentando fallback para porta 8001 (ws://)...');
      disconnect();
      _setState(DeviceConnectionState.connecting);
      final legacyUrl = _buildWebSocketUrl(
        ip: _currentIp!,
        port: 8001,
        isSecure: false,
        token: null,
      );
      final legacySocketOpened = await _tryOpenPairingSocket(legacyUrl, isSecure: false);
      if (legacySocketOpened) {
        return true;
      }

      debugPrint('[Samsung] Não foi possível conectar à TV Samsung em $_currentIp.');
      _setState(DeviceConnectionState.disconnected);

      final modelUpper = _detectedModel?.toUpperCase() ?? '';
      if (modelUpper.contains('H4203') ||
          modelUpper.contains('H4000') ||
          modelUpper.contains('H6003') ||
          modelUpper.contains('H6103') ||
          modelUpper.contains('H6203')) {
        onError?.call('O modelo $modelUpper (2014) não possui suporte a controle via rede pelo fabricante, operando apenas por Infravermelho.');
      } else {
        onError?.call('Não foi possível conectar à TV em $_currentIp. O protocolo de rede é suportado em TVs Samsung Tizen (2016+). Modelos anteriores operam apenas via Infravermelho.');
      }
      return false;
    } catch (e) {
      debugPrint('[Samsung] Erro ao conectar: $e');
      _setState(DeviceConnectionState.disconnected);
      onError?.call('Erro de conexão Samsung: $e');
      return false;
    }
  }

  /// Conecta utilizando um token pré-existente e aguarda confirmação imediata
  Future<bool> _tryConnectWithToken(String url, {required bool isSecure}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;

      _socket = await WebSocket.connect(
        url,
        customClient: isSecure ? client : null,
      ).timeout(const Duration(seconds: 4));

      _socket!.pingInterval = const Duration(seconds: 5);

      final completer = Completer<bool>();
      _handshakeCompleter = completer;

      _socket!.listen(
        _onMessageReceived,
        onDone: _onSocketClosed,
        onError: (err) {
          debugPrint('[Samsung] Erro no socket com token: $err');
          if (!completer.isCompleted) completer.complete(false);
          disconnect();
        },
      );

      // Com token válido, a TV confirma ms.channel.connect em menos de 3 segundos
      final result = await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );
      return result;
    } catch (e) {
      debugPrint('[Samsung] Falha ao conectar com token em $url: $e');
      disconnect();
      return false;
    }
  }

  /// Estabelece o socket para pareamento inicial e aguarda confirmação "Permitir" na TV
  Future<bool> _tryOpenPairingSocket(String url, {required bool isSecure}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      client.badCertificateCallback = (X509Certificate cert, String host, int port) => true;

      _socket = await WebSocket.connect(
        url,
        customClient: isSecure ? client : null,
      ).timeout(const Duration(seconds: 4));

      _socket!.pingInterval = const Duration(seconds: 5);

      final completer = Completer<bool>();
      _handshakeCompleter = completer;

      _socket!.listen(
        _onMessageReceived,
        onDone: _onSocketClosed,
        onError: (err) {
          debugPrint('[Samsung] Erro no socket de pareamento: $err');
          if (!completer.isCompleted) completer.complete(false);
          disconnect();
        },
      );

      // Socket TCP/TLS estabelecido com sucesso!
      // A TV Samsung exibe neste momento o banner de permissão ("Permitir / Negar") na tela.
      _setState(DeviceConnectionState.pairingPrompt);

      // Timeout estendido de até 45 segundos para o usuário confirmar no controle físico da TV
      _pairingTimeoutTimer?.cancel();
      _pairingTimeoutTimer = Timer(const Duration(seconds: 45), () {
        if (_state == DeviceConnectionState.pairingPrompt) {
          debugPrint('[Samsung] Tempo limite de 45s para confirmação esgotado.');
          onError?.call('Tempo limite esgotado. A opção "Permitir" não foi acionada a tempo na TV.');
          disconnect();
        }
      });

      return true;
    } catch (e) {
      debugPrint('[Samsung] Falha ao abrir socket em $url: $e');
      disconnect();
      return false;
    }
  }

  void _onMessageReceived(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final event = msg['event'] as String?;
      debugPrint('[Samsung] Mensagem recebida da TV: $event');

      if (event == 'ms.channel.connect' || event == 'ms.channel.clientConnect') {
        _pairingTimeoutTimer?.cancel();
        _pairingTimeoutTimer = null;

        final payload = msg['data'] as Map<String, dynamic>?;
        final rawToken = payload?['token'];
        if (rawToken != null) {
          final token = rawToken.toString().trim();
          if (token.isNotEmpty) {
            _token = token;
            onAuthTokenReceived?.call(token);
            debugPrint('[Samsung] Token de autorização capturado com sucesso: $token');
          }
        }

        _setState(DeviceConnectionState.connected);

        if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
          _handshakeCompleter!.complete(true);
        }
      } else if (event == 'ms.channel.unauthorized') {
        // TV notificou que autorização é pendente
        debugPrint('[Samsung] Evento ms.channel.unauthorized recebido da TV.');
        if (_state == DeviceConnectionState.connecting) {
          _setState(DeviceConnectionState.pairingPrompt);
        }
        if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
          _handshakeCompleter!.complete(false);
        }
      }
    } catch (e) {
      debugPrint('[Samsung] Erro ao decodificar mensagem: $e');
    }
  }

  void _onSocketClosed() {
    debugPrint('[Samsung] Conexão com TV Samsung encerrada.');
    if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
      _handshakeCompleter!.complete(false);
    }
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
    _socket = null;
    _setState(DeviceConnectionState.disconnected);
  }

  /// Consulta os metadados da TV Samsung via REST nas portas 8001 e 8002
  Future<void> _fetchDeviceInfo(String ip) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    for (final port in [8001, 8002]) {
      try {
        final scheme = port == 8002 ? 'https' : 'http';
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2)
          ..badCertificateCallback = (cert, host, p) => true;
        final request = await client.getUrl(Uri.parse('$scheme://$ip:$port/api/v2/'));
        final response = await request.close().timeout(const Duration(seconds: 2));

        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          final device = json['device'] as Map<String, dynamic>?;
          if (device != null) {
            final name = device['name'] as String? ?? 'Samsung Smart TV';
            final model = device['modelName'] as String?;
            _detectedModel = model;
            onDeviceNameResolved?.call(name, model);
            debugPrint('[Samsung] Informações resolvidas ($port): $name ($model)');
            return;
          }
        }
      } catch (_) {
        // Tenta próxima porta
      }
    }
  }

  @override
  Future<void> sendPairingPin(String pin) async {
    // Samsung Tizen exibe prompt "Permitir" na tela, sem PIN.
  }

  @override
  void disconnect() {
    _handshakeCompleter = null;
    _pairingTimeoutTimer?.cancel();
    _pairingTimeoutTimer = null;
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
    // Abre aplicativo via REST API (compatível com Tizen legado e moderno)
    if (_currentIp != null && _currentIp!.isNotEmpty) {
      _launchAppRest(_currentIp!, appId);
    }
    // E também via WebSocket channel emit (Tizen moderno)
    _launchAppWs(appId);
  }

  void _launchAppWs(String appId) {
    if (!isConnected || _socket == null) return;
    try {
      final payload = {
        'method': 'ms.channel.emit',
        'params': {
          'event': 'ed.apps.launch',
          'to': 'host',
          'data': {
            'action_type': 'DEEP_LINK',
            'appId': appId,
            'metaTag': '',
          }
        }
      };
      _socket!.add(jsonEncode(payload));
      debugPrint('[Samsung] Requisição WebSocket de abertura enviada para app $appId');
    } catch (e) {
      debugPrint('[Samsung] Erro ao enviar comando WS para app $appId: $e');
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

  @override
  void triggerVoice() {
    sendKey(RemoteKey.voice);
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
      case RemoteKey.voice:
        return 'KEY_VOICE';
    }
  }
}
