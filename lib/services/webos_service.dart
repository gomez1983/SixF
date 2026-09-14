import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Estados possíveis da conexão WebOS com a TV LG.
enum WebOsConnectionState {
  disconnected,
  connecting,
  pairingPrompt,
  connected,
}

/// Serviço de Comunicação Direta com Smart TVs LG via protocolo WebSocket SSAP.
///
/// Suporta conexão com bypass de certificado SSL (porta 3001), fallback
/// para porta legado (3000), handshake de pareamento, persistência de client-key,
/// soquete secundário do Magic Remote (Pointer Socket) e comandos SSAP.
class WebOsService {
  WebSocket? _mainSocket;
  WebSocket? _pointerSocket;
  WebOsConnectionState _state = WebOsConnectionState.disconnected;

  int _requestId = 1;
  String? _clientKey;
  String? _currentIp;

  // Callbacks de eventos
  Function(WebOsConnectionState state)? onStateChanged;
  Function(String clientKey)? onClientKeyReceived;
  Function(String error)? onError;
  Function(String tvName, String? modelName)? onDeviceNameResolved;
  Function(int volume, bool isMuted)? onVolumeStatusChanged;

  WebOsConnectionState get state => _state;
  bool get isConnected => _state == WebOsConnectionState.connected;
  bool get isPointerSocketConnected => _pointerSocket != null;
  String? get clientKey => _clientKey;

  void _setState(WebOsConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(_state);
    }
  }

  /// Inicia a conexão com a Smart TV LG no [ipAddress].
  ///
  /// Tenta primeiro na porta segura 3001 (wss://) e, caso não responda,
  /// tenta fallback na porta 3000 (ws://).
  Future<bool> connect({
    required String ipAddress,
    String? savedClientKey,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    disconnect();

    _currentIp = ipAddress.trim();
    _clientKey = savedClientKey;
    _setState(WebOsConnectionState.connecting);

    if (kIsWeb) {
      debugPrint('[WebOS] WebSocket nativo seguro não é suportado no navegador Web.');
      _setState(WebOsConnectionState.disconnected);
      return false;
    }

    try {
      // 1. Tenta porta segura 3001 (WebOS 4.0+ moderno)
      bool connected = await _tryConnectWebSocket(
        'wss://$_currentIp:3001',
        isSecure: true,
        timeout: timeout,
      );

      // 2. Fallback para porta 3000 caso a 3001 falhe
      if (!connected) {
        debugPrint('[WebOS] Tentando fallback para porta 3000 (ws://)...');
        connected = await _tryConnectWebSocket(
          'ws://$_currentIp:3000',
          isSecure: false,
          timeout: timeout,
        );
      }

      if (!connected) {
        debugPrint('[WebOS] Não foi possível conectar à TV em $_currentIp.');
        _setState(WebOsConnectionState.disconnected);
        onError?.call('Não foi possível conectar à TV em $_currentIp. Verifique se ela está ligada na mesma rede.');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[WebOS] Exceção na conexão: $e');
      _setState(WebOsConnectionState.disconnected);
      onError?.call('Falha de conexão: $e');
      return false;
    }
  }

  /// Estabelece conexão com o endpoint WebSocket ignorando certificados autoassinados da LG.
  Future<bool> _tryConnectWebSocket(String url, {required bool isSecure, required Duration timeout}) async {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return false;
      }

      final uri = Uri.parse(url);
      final client = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

      _mainSocket = await WebSocket.connect(
        uri.toString(),
        customClient: isSecure ? client : null,
      ).timeout(timeout);

      // Keepalive automático (Heartbeat) para manter o socket ativo em segundo plano
      _mainSocket!.pingInterval = const Duration(seconds: 8);

      // Escuta mensagens da TV
      _mainSocket!.listen(
        _handleMainSocketMessage,
        onDone: () => _handleSocketClosed('Conexão principal encerrada'),
        onError: (err) => _handleSocketError('Erro no socket: $err'),
      );

      // Dispara o handshake de registro
      _sendRegisterHandshake();
      return true;
    } catch (e) {
      debugPrint('[WebOS] Falha ao conectar em $url: $e');
      return false;
    }
  }

  /// Envia o payload de handshake de registro na TV LG
  void _sendRegisterHandshake() {
    const allPermissions = [
      'LAUNCH',
      'LAUNCH_WEBAPP',
      'APP_TO_APP',
      'CLOSE',
      'TEST_OPEN',
      'TEST_PROTECTED',
      'CONTROL_AUDIO',
      'CONTROL_DISPLAY',
      'CONTROL_INPUT_JOYSTICK',
      'CONTROL_INPUT_MEDIA_RECORDING',
      'CONTROL_INPUT_MEDIA_PLAYBACK',
      'CONTROL_INPUT_TV',
      'CONTROL_POWER',
      'READ_APP_STATUS',
      'READ_CURRENT_CHANNEL',
      'READ_INPUT_DEVICE_LIST',
      'READ_NETWORK_STATUS',
      'READ_RUNNING_APPS',
      'READ_TV_CHANNEL_LIST',
      'WRITE_NOTIFICATION_TOAST',
      'READ_POWER_STATE',
      'READ_COUNTRY_INFO',
      'READ_SETTINGS',
      'CONTROL_TV_SCREEN',
      'CONTROL_TV_POWER',
      'READ_TV_CURRENT_TIME',
      'CONTROL_INPUT_TEXT',
      'CONTROL_MOUSE_AND_KEYBOARD',
      'READ_INSTALLED_APPS',
      'READ_LGE_SDX',
      'READ_NOTIFICATIONS',
      'SEARCH',
      'WRITE_SETTINGS',
      'WRITE_NOTIFICATION_ALERT',
      'CONTROL_USER_INPUT',
    ];

    final manifest = {
      'manifestVersion': 1,
      'appVersion': '1.0',
      'signed': {
        'created': '2024-01-01',
        'appId': 'com.antigravity.lgremote',
        'vendorId': 'antigravity',
        'localizedAppNames': {
          '': 'LG Remote Windows',
          'pt-BR': 'Controle LG Windows',
        },
        'permissions': allPermissions,
        'serial': 'antigravity_client_001',
      },
      'permissions': allPermissions,
    };

    final registerPayload = {
      'id': 'register_0',
      'type': 'register',
      'payload': {
        'forcePairing': false,
        'pairingType': 'PROMPT',
        'manifest': manifest,
        if (_clientKey != null && _clientKey!.isNotEmpty) 'client-key': _clientKey,
      },
    };

    _sendJson(_mainSocket, registerPayload);
    debugPrint('[WebOS] Handshake de registro enviado (client-key: ${_clientKey != null ? 'presente' : 'nova'})');
  }

  /// Processa respostas do WebSocket principal da TV
  void _handleMainSocketMessage(dynamic data) {
    try {
      final json = jsonDecode(data.toString()) as Map<String, dynamic>;
      final type = json['type'] as String?;
      final id = json['id'] as String?;
      final payload = json['payload'] as Map<String, dynamic>?;

      debugPrint('[WebOS] Resposta recebida ($type / $id): $payload');

      // 1. Mensagem de prompt para autorizar na tela da TV
      if (type == 'response' && payload?['pairingType'] == 'PROMPT') {
        _setState(WebOsConnectionState.pairingPrompt);
        debugPrint('[WebOS] Aguardando confirmação do usuário na tela da TV...');
      }

      // 2. Registro concluído com sucesso
      if (type == 'registered') {
        final newKey = payload?['client-key'] as String?;
        if (newKey != null && newKey.isNotEmpty) {
          _clientKey = newKey;
          onClientKeyReceived?.call(newKey);
          debugPrint('[WebOS] Chave client-key recebida e salva com sucesso!');
        }
        _setState(WebOsConnectionState.connected);
        debugPrint('[WebOS] TV Conectada e Autenticada!');

        // Solicita o socket do Magic Pointer (para que todos os botões de hardware funcionem)
        _initPointerSocket();

        // Solicita nome e dados da TV (ex: "André TV")
        _queryTvDeviceInfo();

        // Inscreve-se nas notificações de volume e mudo em tempo real
        _subscribeVolumeStatus();
      }

      // 3. Captura do socketPath do Pointer Socket (Magic Remote)
      final socketPath = (payload?['socketPath'] ?? json['socketPath']) as String?;
      if (socketPath != null && socketPath.isNotEmpty) {
        debugPrint('[WebOS] socketPath recebido da TV: $socketPath');
        connectPointerSocket(socketPath);
      }

      // 4. Captura do nome da TV / System Info
      final deviceName = (payload?['device_name'] ??
          payload?['tvName'] ??
          payload?['name'] ??
          payload?['deviceTitle']) as String?;
      final modelName = payload?['modelName'] as String?;
      if (deviceName != null && deviceName.isNotEmpty) {
        debugPrint('[WebOS] Nome da TV identificado: $deviceName ($modelName)');
        onDeviceNameResolved?.call(deviceName, modelName);
      }

      // 5. Captura do volume real e status de áudio emitido pela TV
      if (payload != null) {
        final rawVol = payload['volume'] ?? payload['volumeStatus']?['volume'];
        final int? volumeLevel = rawVol is int ? rawVol : int.tryParse(rawVol?.toString() ?? '');
        final bool? isMuted = (payload['muted'] ?? payload['mute'] ?? payload['volumeStatus']?['mute']) as bool?;
        if (volumeLevel != null) {
          debugPrint('[WebOS] Volume real recebido da TV: $volumeLevel (mudo: $isMuted)');
          onVolumeStatusChanged?.call(volumeLevel, isMuted ?? false);
        }
      }
    } catch (e) {
      debugPrint('[WebOS] Erro ao decodificar mensagem: $e');
    }
  }

  /// Assina e consulta o volume real e status de áudio da TV em tempo real
  void _subscribeVolumeStatus() {
    _sendJson(_mainSocket, {
      'id': 'sub_volume',
      'type': 'subscribe',
      'uri': 'ssap://audio/getVolume',
    });
    _sendJson(_mainSocket, {
      'id': 'sub_audio_status',
      'type': 'subscribe',
      'uri': 'ssap://audio/getStatus',
    });
    sendCommand('ssap://audio/getVolume');
  }

  /// Solicita informações de sistema e nome da TV (ex: "André TV")
  void _queryTvDeviceInfo() {
    sendCommand('ssap://system/getSystemInfo');
    sendCommand('ssap://com.webos.service.tv.display/getTVName');
  }

  /// Solicita e conecta o socket de entrada do ponteiro/trackpad
  Future<void> _initPointerSocket() async {
    try {
      final requestId = 'ptr_req_${_nextId()}';
      final request = {
        'id': requestId,
        'type': 'request',
        'uri': 'ssap://com.webos.service.networkinput/getPointerInputSocket',
      };

      _sendJson(_mainSocket, request);
    } catch (e) {
      debugPrint('[WebOS] Erro ao solicitar pointer input socket: $e');
    }
  }

  /// Conecta o socket de ponteiro quando o socketPath é retornado pela TV
  void connectPointerSocket(String socketPath) async {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return;
      }

      await _pointerSocket?.close();
      _pointerSocket = null;

      final client = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

      final isSecure = socketPath.startsWith('wss://');

      _pointerSocket = await WebSocket.connect(
        socketPath,
        customClient: isSecure ? client : null,
      ).timeout(const Duration(seconds: 4));

      _pointerSocket!.listen(
        (data) {
          debugPrint('[WebOS Pointer] Evento recebido: $data');
        },
        onDone: () {
          debugPrint('[WebOS Pointer] Socket de controle fechado.');
          _pointerSocket = null;
        },
        onError: (err) {
          debugPrint('[WebOS Pointer] Erro no socket de controle: $err');
          _pointerSocket = null;
        },
      );

      debugPrint('[WebOS] Magic Pointer Socket conectado com sucesso!');
    } catch (e) {
      debugPrint('[WebOS] Falha ao conectar Pointer Socket: $e');
    }
  }

  // --- Disparo de Comandos SSAP e Teclas ---

  void sendCommand(String uri, [Map<String, dynamic>? params]) {
    if (!isConnected || _mainSocket == null) {
      debugPrint('[WebOS] Comando não enviado: TV não conectada ($uri)');
      return;
    }

    final id = 'cmd_${_nextId()}';
    final request = {
      'id': id,
      'type': 'request',
      'uri': uri,
      if (params != null && params.isNotEmpty) 'payload': params,
    };

    _sendJson(_mainSocket, request);
  }

  // --- Métodos de Conveniência para Controles ---

  void volumeUp() {
    sendCommand('ssap://audio/volumeUp');
    Future.delayed(const Duration(milliseconds: 120), () {
      sendCommand('ssap://audio/getVolume');
    });
  }

  void volumeDown() {
    sendCommand('ssap://audio/volumeDown');
    Future.delayed(const Duration(milliseconds: 120), () {
      sendCommand('ssap://audio/getVolume');
    });
  }

  void setMute(bool mute) {
    sendCommand('ssap://audio/setMute', {'mute': mute});
    Future.delayed(const Duration(milliseconds: 120), () {
      sendCommand('ssap://audio/getStatus');
    });
  }

  void channelUp() {
    sendButton('CHANNELUP');
    sendCommand('ssap://tv/channelUp');
  }

  void channelDown() {
    sendButton('CHANNELDOWN');
    sendCommand('ssap://tv/channelDown');
  }

  void turnOff() => sendCommand('ssap://system/turnOff');

  void mediaPlay() {
    sendButton('PLAY');
    sendCommand('ssap://media.controls/play');
  }

  void mediaPause() {
    sendButton('PAUSE');
    sendCommand('ssap://media.controls/pause');
  }

  void mediaStop() {
    sendButton('STOP');
    sendCommand('ssap://media.controls/stop');
  }

  void mediaRewind() {
    sendButton('REWIND');
    sendCommand('ssap://media.controls/rewind');
  }

  void mediaFastForward() {
    sendButton('FASTFORWARD');
    sendCommand('ssap://media.controls/fastForward');
  }

  void pressHome() {
    sendButton('HOME');
    sendCommand('ssap://system.launcher/open');
  }

  void pressBack() {
    sendButton('BACK');
  }

  void pressMenu() {
    sendButton('MENU');
  }

  void pressExit() {
    sendButton('EXIT');
    sendCommand('ssap://system.launcher/close');
  }

  /// Alterna a entrada da TV para uma porta específica (ex: 'HDMI_1')
  void switchToInput(String inputId) {
    sendCommand('ssap://tv/switchInput', {'inputId': inputId});
    // Fallback via launcher caso a TV use o app de entrada
    sendCommand('ssap://system.launcher/launch', {'id': 'com.webos.app.hdmi1'});
  }

  /// Abre um aplicativo específico pelo seu ID (ex: 'netflix', 'youtube', etc.)
  void launchApp(String appId) {
    sendCommand('ssap://system.launcher/launch', {'id': appId});
  }

  /// Sintoniza/abre a TV Digital (Live TV aberta/antena)
  void launchLiveTv() {
    sendCommand('ssap://system.launcher/launch', {'id': 'com.webos.app.livetv'});
    sendButton('LIVE_TV');
  }

  void pressOk() => sendButton('ENTER');
  void dpadUp() => sendButton('UP');
  void dpadDown() => sendButton('DOWN');
  void dpadLeft() => sendButton('LEFT');
  void dpadRight() => sendButton('RIGHT');

  void pressDigit(int digit) => sendButton('$digit');
  void pressDash() => sendButton('DASH');

  void pressColorRed() => sendButton('RED');
  void pressColorGreen() => sendButton('GREEN');
  void pressColorYellow() => sendButton('YELLOW');
  void pressColorBlue() => sendButton('BLUE');

  /// Envia comando de botão de hardware via Pointer Socket ou SSAP
  void sendButton(String buttonName) {
    bool sentViaPointer = false;
    if (_pointerSocket != null) {
      try {
        _pointerSocket!.add('type:button\nname:$buttonName\n\n');
        sentViaPointer = true;
      } catch (e) {
        debugPrint('[WebOS] Erro ao enviar para pointer socket: $e');
        _pointerSocket = null;
      }
    }

    if (!sentViaPointer) {
      // Se o pointer socket não estiver pronto, solicita sua inicialização
      _initPointerSocket();

      // Fallback via SSAP tradicional para comandos com mapeamento conhecido
      switch (buttonName) {
        case 'HOME':
          sendCommand('ssap://system.launcher/open');
          break;
        case 'BACK':
          sendCommand('ssap://system.launcher/close');
          break;
        case 'MENU':
          sendCommand('ssap://system.launcher/open', {'id': 'com.palm.app.settings'});
          break;
        case 'EXIT':
          sendCommand('ssap://system.launcher/close');
          break;
        case 'CHANNELUP':
          sendCommand('ssap://tv/channelUp');
          break;
        case 'CHANNELDOWN':
          sendCommand('ssap://tv/channelDown');
          break;
        case 'VOLUMEUP':
          sendCommand('ssap://audio/volumeUp');
          break;
        case 'VOLUMEDOWN':
          sendCommand('ssap://audio/volumeDown');
          break;
        case 'MUTE':
          sendCommand('ssap://audio/setMute', {'mute': true});
          break;
        case 'PLAY':
          sendCommand('ssap://media.controls/play');
          break;
        case 'PAUSE':
          sendCommand('ssap://media.controls/pause');
          break;
        case 'STOP':
          sendCommand('ssap://media.controls/stop');
          break;
        case 'REWIND':
          sendCommand('ssap://media.controls/rewind');
          break;
        case 'FASTFORWARD':
          sendCommand('ssap://media.controls/fastForward');
          break;
        case 'ENTER':
          sendCommand('ssap://com.webos.service.ime/sendEnterKey');
          break;
      }
    }
    debugPrint('[WebOS] Botão enviado: $buttonName (viaPointer: $sentViaPointer)');
  }

  /// Envia deltas de deslocamento do Magic Remote trackpad
  void sendTrackpadDelta(double dx, double dy) {
    if (_pointerSocket != null) {
      _pointerSocket!.add('type:move\ndx:$dx\ndy:$dy\ndown:0\n\n');
    } else {
      _initPointerSocket();
    }
  }

  /// Envia clique de seleção do Magic Remote
  void sendTrackpadClick() {
    if (_pointerSocket != null) {
      _pointerSocket!.add('type:click\n\n');
    } else {
      pressOk();
    }
  }

  // --- Encerramento e Limpeza ---

  void disconnect() {
    _mainSocket?.close();
    _mainSocket = null;
    _pointerSocket?.close();
    _pointerSocket = null;
    _setState(WebOsConnectionState.disconnected);
    debugPrint('[WebOS] Desconectado da TV.');
  }

  void _handleSocketClosed(String reason) {
    debugPrint('[WebOS] Socket fechado: $reason');
    disconnect();
  }

  void _handleSocketError(String error) {
    debugPrint('[WebOS] Erro no WebSocket: $error');
    disconnect();
  }

  void _sendJson(WebSocket? ws, Map<String, dynamic> data) {
    if (ws != null) {
      ws.add(jsonEncode(data));
    }
  }

  int _nextId() => _requestId++;
}
