import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'android_tv_cert_manager.dart';
import 'androidtv_proto/polo.pb.dart';
import 'androidtv_proto/remotemessage.pb.dart';
import 'tv_driver.dart';

/// Driver de comunicação para Chromecast com Google TV e Android TVs
/// (Sony, TCL, Philips, Xiaomi) via protocolo Android TV Remote Service v2 (TLS 6466/6467).
class AndroidTvDriver implements TvDriver {
  SecureSocket? _remoteSocket;
  SecureSocket? _pairingSocket;
  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  String? _currentIp;

  // Ports: 6467 for pairing handshake, 6466 for remote commands
  static const int pairingPort = 6467;
  static const int remotePort = 6466;

  // Buffer de mensagens recebidas
  final List<int> _pairingBuffer = <int>[];
  final List<int> _remoteBuffer = <int>[];

  // Certificados e chaves do servidor e cliente
  BigInt? _serverModulus;
  BigInt? _serverExponent;

  // Timer para Ping periódico na porta remota
  Timer? _pingTimer;

  @override
  final TvBrand brand = TvBrand.androidTv;

  @override
  String get brandDisplayName => brand.displayName;

  @override
  bool get supportsTrackpad => false;

  @override
  bool get supportsPairingPin => true;

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
    _setState(DeviceConnectionState.connecting);

    if (kIsWeb) {
      debugPrint('[AndroidTV] Sockets TLS nativos não são suportados no navegador Web.');
      _setState(DeviceConnectionState.disconnected);
      return false;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _setState(DeviceConnectionState.disconnected);
      return false;
    }

    try {
      // 1. Garante que os certificados mTLS existam
      final certs = await AndroidTvCertificateManager.getOrCreateCertificate(
        clientName: 'SixF Remote',
      );

      final securityContext = SecurityContext(withTrustedRoots: false);
      securityContext.useCertificateChainBytes(certs['cert']!.codeUnits);
      securityContext.usePrivateKeyBytes(certs['key']!.codeUnits);

      // 2. Verifica se o dispositivo já possui pareamento prévio com este IP
      final prefs = await SharedPreferences.getInstance();
      final pairedDeviceIp = prefs.getString('atv_paired_device');
      final isKnownPaired = (pairedDeviceIp == _currentIp);

      if (isKnownPaired) {
        debugPrint('[AndroidTV] Dispositivo já pareado anteriormente. Tentando canal remoto (6466)...');
        final connectedRemote = await _connectRemoteSocket(securityContext, timeout);
        if (connectedRemote) {
          return true;
        }
      }

      // 3. Se não estiver pareado ou a conexão remota falhar/exigir pareamento, inicia pareamento na porta 6467
      debugPrint('[AndroidTV] Iniciando Pareamento Polo na porta $pairingPort...');
      return await _startPairingFlow(securityContext, timeout);
    } catch (e) {
      debugPrint('[AndroidTV] Erro de inicialização da conexão: $e');
      _setState(DeviceConnectionState.disconnected);
      onError?.call('Erro ao conectar Google TV: $e');
      return false;
    }
  }

  Completer<bool>? _remoteConfigureCompleter;

  Future<bool> _connectRemoteSocket(SecurityContext context, Duration timeout) async {
    try {
      debugPrint('[AndroidTV] Tentando conectar na porta remota $remotePort em $_currentIp...');
      _remoteConfigureCompleter = Completer<bool>();

      _remoteSocket = await SecureSocket.connect(
        _currentIp!,
        remotePort,
        context: context,
        onBadCertificate: (cert) => true,
        timeout: timeout,
      );

      _remoteBuffer.clear();
      _remoteSocket!.listen(
        _handleRemoteStreamData,
        onDone: () {
          debugPrint('[AndroidTV] Canal remoto encerrado pelo dispositivo.');
          if (_remoteConfigureCompleter != null && !_remoteConfigureCompleter!.isCompleted) {
            _remoteConfigureCompleter!.complete(false);
          }
          disconnect();
        },
        onError: (err) {
          debugPrint('[AndroidTV] Erro no canal remoto: $err');
          if (_remoteConfigureCompleter != null && !_remoteConfigureCompleter!.isCompleted) {
            _remoteConfigureCompleter!.complete(false);
          }
          disconnect();
        },
      );

      // Aguarda confirmação do handshake de configuração da TV por até 2 segundos
      final configured = await _remoteConfigureCompleter!.future.timeout(
        const Duration(milliseconds: 2200),
        onTimeout: () {
          debugPrint('[AndroidTV] Timeout aguardando RemoteConfigure no canal 6466.');
          return false;
        },
      );

      if (configured) {
        _setState(DeviceConnectionState.connected);
        debugPrint('[AndroidTV] Conectado e autenticado com sucesso no canal de controle (porta $remotePort)!');
        _startPingTimer();
        return true;
      } else {
        debugPrint('[AndroidTV] Canal 6466 não autenticado pelo dispositivo.');
        disconnect();
        return false;
      }
    } catch (e) {
      debugPrint('[AndroidTV] Não foi possível conectar ao canal remoto (porta $remotePort): $e');
      return false;
    }
  }

  Completer<bool>? _pairingStartedCompleter;

  Future<bool> _startPairingFlow(SecurityContext context, Duration timeout) async {
    try {
      _setState(DeviceConnectionState.connecting);
      debugPrint('[AndroidTV] Conectando ao canal de pareamento (porta $pairingPort)...');

      _pairingStartedCompleter = Completer<bool>();

      _pairingSocket = await SecureSocket.connect(
        _currentIp!,
        pairingPort,
        context: context,
        onBadCertificate: (cert) {
          // Extrai a chave pública do certificado da TV para uso na geração do Hash do PIN
          try {
            final derBytes = Uint8List.fromList(cert.der);
            final (mod, exp) = AndroidTvCertificateManager.extractModulusExponentFromDer(derBytes);
            _serverModulus = mod;
            _serverExponent = exp;
            debugPrint('[AndroidTV Pairing] Certificado do servidor recebido com sucesso (Modulus len: ${mod.bitLength} bits)');
          } catch (e) {
            debugPrint('[AndroidTV Pairing] Falha ao extrair chave pública do servidor: $e');
          }
          return true;
        },
        timeout: timeout,
      );

      _pairingBuffer.clear();
      _pairingSocket!.listen(
        _handlePairingStreamData,
        onDone: () {
          debugPrint('[AndroidTV Pairing] Socket de pareamento encerrado.');
          if (_pairingStartedCompleter != null && !_pairingStartedCompleter!.isCompleted) {
            _pairingStartedCompleter!.complete(false);
          }
        },
        onError: (err) {
          debugPrint('[AndroidTV Pairing] Erro no socket de pareamento: $err');
          if (_pairingStartedCompleter != null && !_pairingStartedCompleter!.isCompleted) {
            _pairingStartedCompleter!.complete(false);
          }
          disconnect();
        },
      );

      // Envia OuterMessage com PairingRequest
      _sendPairingRequest();

      // Aguarda até o ConfigurationAck ser recebido (ou expirar o timeout)
      final started = await _pairingStartedCompleter!.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('[AndroidTV Pairing] Timeout aguardando ConfigurationAck');
          return false;
        },
      );

      return started;
    } catch (e) {
      debugPrint('[AndroidTV] Falha ao conectar na porta de pareamento $pairingPort: $e');
      if (_pairingStartedCompleter != null && !_pairingStartedCompleter!.isCompleted) {
        _pairingStartedCompleter!.complete(false);
      }
      _setState(DeviceConnectionState.disconnected);
      onError?.call('Não foi possível conectar ao Google TV em $_currentIp:$pairingPort.');
      return false;
    }
  }

  void _sendPairingRequest() {
    if (_pairingSocket == null) return;
    try {
      final msg = OuterMessage(
        protocolVersion: 2,
        status: OuterMessage_Status.STATUS_OK,
        pairingRequest: PairingRequest(
          serviceName: 'atvremote',
          clientName: 'SixF Remote',
        ),
      );
      _sendDelimitedMessage(_pairingSocket!, msg.writeToBuffer());
      debugPrint('[AndroidTV] PairingRequest enviado. Aguardando resposta da TV...');
    } catch (e) {
      debugPrint('[AndroidTV] Erro ao enviar PairingRequest: $e');
    }
  }

  void _handlePairingStreamData(List<int> chunk) {
    _pairingBuffer.addAll(chunk);

    while (_pairingBuffer.isNotEmpty) {
      final (msgLen, offset) = _decodeVarint(_pairingBuffer);
      if (offset == 0) return; // Varint incompleto

      final totalLen = offset + msgLen;
      if (_pairingBuffer.length < totalLen) return; // Mensagem incompleta

      final rawMsg = _pairingBuffer.sublist(offset, totalLen);
      _pairingBuffer.removeRange(0, totalLen);

      try {
        final outer = OuterMessage.fromBuffer(rawMsg);
        _handlePoloMessage(outer);
      } catch (e) {
        debugPrint('[AndroidTV Pairing] Erro ao decodificar OuterMessage: $e');
      }
    }
  }

  void _handlePoloMessage(OuterMessage msg) {
    debugPrint('[AndroidTV Pairing] OuterMessage recebida (status: ${msg.status})');

    if (msg.hasPairingRequestAck()) {
      debugPrint('[AndroidTV Pairing] PairingRequestAck recebido. Enviando Options...');
      final optMsg = OuterMessage(
        protocolVersion: 2,
        status: OuterMessage_Status.STATUS_OK,
        options: Options(
          preferredRole: Options_RoleType.ROLE_TYPE_INPUT,
          inputEncodings: [
            Options_Encoding(
              type: Options_Encoding_EncodingType.ENCODING_TYPE_HEXADECIMAL,
              symbolLength: 6,
            ),
          ],
        ),
      );
      _sendDelimitedMessage(_pairingSocket!, optMsg.writeToBuffer());
    } else if (msg.hasOptions()) {
      debugPrint('[AndroidTV Pairing] Options recebido da TV. Enviando Configuration...');
      final configMsg = OuterMessage(
        protocolVersion: 2,
        status: OuterMessage_Status.STATUS_OK,
        configuration: Configuration(
          clientRole: Options_RoleType.ROLE_TYPE_INPUT,
          encoding: Options_Encoding(
            type: Options_Encoding_EncodingType.ENCODING_TYPE_HEXADECIMAL,
            symbolLength: 6,
          ),
        ),
      );
      _sendDelimitedMessage(_pairingSocket!, configMsg.writeToBuffer());
    } else if (msg.hasConfigurationAck()) {
      debugPrint('[AndroidTV Pairing] ConfigurationAck recebido! O código de 6 dígitos deve estar na TV!');
      _setState(DeviceConnectionState.pairingPrompt);
      if (_pairingStartedCompleter != null && !_pairingStartedCompleter!.isCompleted) {
        _pairingStartedCompleter!.complete(true);
      }
      onPinPromptRequested?.call(true);
    } else if (msg.hasSecretAck()) {
      debugPrint('[AndroidTV Pairing] SecretAck recebido com SUCESSO! Dispositivo pareado!');
      _finalizePairingSuccess();
    } else if (msg.status != OuterMessage_Status.STATUS_OK) {
      debugPrint('[AndroidTV Pairing] Erro recebido da TV: status ${msg.status}');
      if (_pairingStartedCompleter != null && !_pairingStartedCompleter!.isCompleted) {
        _pairingStartedCompleter!.complete(false);
      }
      onError?.call('Erro de autenticação Google TV: status ${msg.status}');
      disconnect();
    }
  }

  @override
  Future<void> sendPairingPin(String pin) async {
    final cleanPin = pin.trim().toUpperCase();
    if (cleanPin.isEmpty || _pairingSocket == null) return;

    debugPrint('[AndroidTV] Calculando Secret Hash para o PIN: $cleanPin');
    try {
      final (clientMod, clientExp) = AndroidTvCertificateManager.getClientModulusAndExponent();
      final serverMod = _serverModulus ?? BigInt.zero;
      final serverExp = _serverExponent ?? BigInt.from(65537);

      final secretHash = AndroidTvCertificateManager.computeSecretHash(
        clientModulus: clientMod,
        clientExponent: clientExp,
        serverModulus: serverMod,
        serverExponent: serverExp,
        pinHex: cleanPin,
      );

      final secretMsg = OuterMessage(
        protocolVersion: 2,
        status: OuterMessage_Status.STATUS_OK,
        secret: Secret(secret: secretHash),
      );

      _sendDelimitedMessage(_pairingSocket!, secretMsg.writeToBuffer());
      debugPrint('[AndroidTV] Secret Hash enviado. Aguardando confirmação SecretAck...');
    } catch (e) {
      debugPrint('[AndroidTV] Erro ao calcular/enviar PIN: $e');
      onError?.call('Erro ao processar PIN: $e');
    }
  }

  Future<void> _finalizePairingSuccess() async {
    final token = 'atv_paired_${DateTime.now().millisecondsSinceEpoch}';
    onAuthTokenReceived?.call(token);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('atv_paired_device', _currentIp ?? '');
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 300));
    _pairingSocket?.destroy();
    _pairingSocket = null;

    // Agora que está pareado, conecta no canal de comandos 6466
    if (_currentIp != null) {
      final certs = await AndroidTvCertificateManager.getOrCreateCertificate();
      final secContext = SecurityContext(withTrustedRoots: false);
      secContext.useCertificateChainBytes(certs['cert']!.codeUnits);
      secContext.usePrivateKeyBytes(certs['key']!.codeUnits);

      await _connectRemoteSocket(secContext, const Duration(seconds: 4));
    }
  }

  void _handleRemoteStreamData(List<int> chunk) {
    _remoteBuffer.addAll(chunk);

    while (_remoteBuffer.isNotEmpty) {
      final (msgLen, offset) = _decodeVarint(_remoteBuffer);
      if (offset == 0) return;

      final totalLen = offset + msgLen;
      if (_remoteBuffer.length < totalLen) return;

      final rawMsg = _remoteBuffer.sublist(offset, totalLen);
      _remoteBuffer.removeRange(0, totalLen);

      try {
        final remoteMsg = RemoteMessage.fromBuffer(rawMsg);
        _handleRemoteMessage(remoteMsg);
      } catch (e) {
        debugPrint('[AndroidTV Remote] Erro ao decodificar RemoteMessage: $e');
      }
    }
  }

  void _handleRemoteMessage(RemoteMessage msg) {
    if (msg.hasRemoteConfigure()) {
      debugPrint('[AndroidTV Remote] Configuração remota recebida do dispositivo.');
      final reply = RemoteMessage(
        remoteConfigure: RemoteConfigure(
          code1: 622, // PING | KEY | POWER | VOLUME | APP_LINK
          deviceInfo: RemoteDeviceInfo(
            unknown1: 1,
            unknown2: '1',
            packageName: 'atvremote',
            appVersion: '1.0.0',
          ),
        ),
      );
      _sendDelimitedMessage(_remoteSocket!, reply.writeToBuffer());
    } else if (msg.hasRemoteSetActive()) {
      final reply = RemoteMessage(
        remoteSetActive: RemoteSetActive(active: 622),
      );
      _sendDelimitedMessage(_remoteSocket!, reply.writeToBuffer());
    } else if (msg.hasRemoteStart()) {
      debugPrint('[AndroidTV Remote] RemoteStart recebido! Canal de controle ativo e pronto para comandos.');
      if (_remoteConfigureCompleter != null && !_remoteConfigureCompleter!.isCompleted) {
        _remoteConfigureCompleter!.complete(true);
      }
    } else if (msg.hasRemotePingRequest()) {
      final reply = RemoteMessage(
        remotePingResponse: RemotePingResponse(val1: msg.remotePingRequest.val1),
      );
      _sendDelimitedMessage(_remoteSocket!, reply.writeToBuffer());
    } else if (msg.hasRemoteSetVolumeLevel()) {
      final vol = msg.remoteSetVolumeLevel;
      onVolumeStatusChanged?.call(vol.volumeLevel, vol.volumeMuted);
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!isConnected || _remoteSocket == null) return;
      try {
        final ping = RemoteMessage(
          remotePingRequest: RemotePingRequest(val1: 1, val2: 1),
        );
        _sendDelimitedMessage(_remoteSocket!, ping.writeToBuffer());
      } catch (_) {}
    });
  }

  /// Escreve mensagem delimitada por Varint no socket TLS
  void _sendDelimitedMessage(SecureSocket socket, List<int> payload) {
    final varintBytes = _encodeVarint(payload.length);
    socket.add([...varintBytes, ...payload]);
  }

  List<int> _encodeVarint(int value) {
    final bytes = <int>[];
    while (value >= 0x80) {
      bytes.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    bytes.add(value & 0x7F);
    return bytes;
  }

  (int, int) _decodeVarint(List<int> buffer) {
    int res = 0;
    int shift = 0;
    for (int i = 0; i < buffer.length; i++) {
      final b = buffer[i];
      res |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) {
        return (res, i + 1);
      }
      shift += 7;
      if (shift > 35) return (0, 0); // Erro de overflow
    }
    return (0, 0); // Varint incompleto
  }

  @override
  void disconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    try {
      _remoteSocket?.destroy();
      _pairingSocket?.destroy();
    } catch (_) {}
    _remoteSocket = null;
    _pairingSocket = null;
    _pairingBuffer.clear();
    _remoteBuffer.clear();
    _setState(DeviceConnectionState.disconnected);
  }

  @override
  void sendKey(RemoteKey key) {
    final keyCode = _mapKeyToAndroidKeyCode(key);
    if (keyCode != null) {
      _sendAndroidKey(keyCode);
    }
  }

  @override
  void sendDigit(int digit) {
    if (digit >= 0 && digit <= 9) {
      _sendAndroidKey(RemoteKeyCode.valueOf(RemoteKeyCode.KEYCODE_0.value + digit) ?? RemoteKeyCode.KEYCODE_0);
    }
  }

  @override
  void setMute(bool mute) {
    _sendAndroidKey(RemoteKeyCode.KEYCODE_VOLUME_MUTE);
  }

  @override
  void setVolume(int volume) {
    _sendAndroidKey(RemoteKeyCode.KEYCODE_VOLUME_UP);
  }

  @override
  void sendTrackpadDelta(double dx, double dy) {
    if (dx.abs() > dy.abs()) {
      if (dx > 20) sendKey(RemoteKey.dpadRight);
      if (dx < -20) sendKey(RemoteKey.dpadLeft);
    } else {
      if (dy > 20) sendKey(RemoteKey.dpadDown);
      if (dy < -20) sendKey(RemoteKey.dpadUp);
    }
  }

  @override
  void sendTrackpadClick() {
    sendKey(RemoteKey.dpadOk);
  }

  @override
  void sendText(String text) {
    if (!isConnected || _remoteSocket == null) return;
    try {
      final paramValue = text.length - 1;
      final edit = RemoteMessage(
        remoteImeBatchEdit: RemoteImeBatchEdit(
          imeCounter: 0,
          fieldCounter: 0,
          editInfo: [
            RemoteEditInfo(
              insert: 1,
              textFieldStatus: RemoteImeObject(
                start: paramValue,
                end: paramValue,
                value: text,
              ),
            ),
          ],
        ),
      );
      _sendDelimitedMessage(_remoteSocket!, edit.writeToBuffer());
      debugPrint('[AndroidTV] Texto enviado: $text');
    } catch (e) {
      debugPrint('[AndroidTV] Erro ao enviar texto: $e');
    }
  }

  @override
  void openApp(String appId) {
    if (!isConnected || _remoteSocket == null) return;
    try {
      final prefix = appId.contains('://') ? '' : 'market://launch?id=';
      final msg = RemoteMessage(
        remoteAppLinkLaunchRequest: RemoteAppLinkLaunchRequest(
          appLink: '$prefix$appId',
        ),
      );
      _sendDelimitedMessage(_remoteSocket!, msg.writeToBuffer());
      debugPrint('[AndroidTV] Solicitando abertura de app: $appId');
    } catch (e) {
      debugPrint('[AndroidTV] Erro ao abrir app: $e');
    }
  }

  void _sendAndroidKey(RemoteKeyCode keyCode) {
    if (!isConnected || _remoteSocket == null) {
      debugPrint('[AndroidTV] Tecla não enviada: dispositivo desconectado (KeyCode: $keyCode)');
      return;
    }

    try {
      final msg = RemoteMessage(
        remoteKeyInject: RemoteKeyInject(
          keyCode: keyCode,
          direction: RemoteDirection.SHORT,
        ),
      );
      _sendDelimitedMessage(_remoteSocket!, msg.writeToBuffer());
      debugPrint('[AndroidTV] KeyCode enviado: ${keyCode.name}');
    } catch (e) {
      debugPrint('[AndroidTV] Erro ao enviar KeyCode: $e');
    }
  }

  RemoteKeyCode? _mapKeyToAndroidKeyCode(RemoteKey key) {
    switch (key) {
      case RemoteKey.power:
        return RemoteKeyCode.KEYCODE_POWER;
      case RemoteKey.volumeUp:
        return RemoteKeyCode.KEYCODE_VOLUME_UP;
      case RemoteKey.volumeDown:
        return RemoteKeyCode.KEYCODE_VOLUME_DOWN;
      case RemoteKey.mute:
        return RemoteKeyCode.KEYCODE_VOLUME_MUTE;
      case RemoteKey.channelUp:
        return RemoteKeyCode.KEYCODE_CHANNEL_UP;
      case RemoteKey.channelDown:
        return RemoteKeyCode.KEYCODE_CHANNEL_DOWN;
      case RemoteKey.dpadUp:
        return RemoteKeyCode.KEYCODE_DPAD_UP;
      case RemoteKey.dpadDown:
        return RemoteKeyCode.KEYCODE_DPAD_DOWN;
      case RemoteKey.dpadLeft:
        return RemoteKeyCode.KEYCODE_DPAD_LEFT;
      case RemoteKey.dpadRight:
        return RemoteKeyCode.KEYCODE_DPAD_RIGHT;
      case RemoteKey.dpadOk:
        return RemoteKeyCode.KEYCODE_DPAD_CENTER;
      case RemoteKey.back:
        return RemoteKeyCode.KEYCODE_BACK;
      case RemoteKey.home:
        return RemoteKeyCode.KEYCODE_HOME;
      case RemoteKey.menu:
        return RemoteKeyCode.KEYCODE_MENU;
      case RemoteKey.exit:
        return RemoteKeyCode.KEYCODE_BACK;
      case RemoteKey.input:
        return RemoteKeyCode.KEYCODE_TV_INPUT;
      case RemoteKey.play:
        return RemoteKeyCode.KEYCODE_MEDIA_PLAY;
      case RemoteKey.pause:
        return RemoteKeyCode.KEYCODE_MEDIA_PAUSE;
      case RemoteKey.stop:
        return RemoteKeyCode.KEYCODE_MEDIA_STOP;
      case RemoteKey.rewind:
        return RemoteKeyCode.KEYCODE_MEDIA_REWIND;
      case RemoteKey.fastForward:
        return RemoteKeyCode.KEYCODE_MEDIA_FAST_FORWARD;
      case RemoteKey.colorRed:
        return RemoteKeyCode.KEYCODE_PROG_RED;
      case RemoteKey.colorGreen:
        return RemoteKeyCode.KEYCODE_PROG_GREEN;
      case RemoteKey.colorYellow:
        return RemoteKeyCode.KEYCODE_PROG_YELLOW;
      case RemoteKey.colorBlue:
        return RemoteKeyCode.KEYCODE_PROG_BLUE;
      case RemoteKey.dash:
        return RemoteKeyCode.KEYCODE_MINUS;
    }
  }
}
