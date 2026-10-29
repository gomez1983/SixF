import '../google_tv_apps_adb.dart';
import '../google_tv_voice.dart';

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'google_tv/credentials.dart';
import 'google_tv/wire.dart';
import '../network_security_utils.dart';
import 'tv_driver.dart';

/// Android TV Remote Service v2 (6466 control / 6467 pairing), not Cast 8009.
/// Protocol reference: github.com/tronikos/androidtvremote2.
class GoogleTvDriver extends TvDriver {
  GoogleTvDriver({
    this.controlPort = 6466,
    this.pairingPort = 6467,
    this.idleTimeout = const Duration(seconds: 20),
    this.reconnectDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
    Future<GoogleTvCredentials> Function()? credentialsFactory,
    VoiceAudioSource Function()? audioSourceFactory,
  }) : _audioSourceFactory = audioSourceFactory ?? MicrophoneAudioSource.new,
       _credentialsFactory =
           credentialsFactory ??
           (() => Isolate.run(GoogleTvCredentials.generate));
  final int controlPort;
  final int pairingPort;
  final Duration idleTimeout;
  final List<Duration> reconnectDelays;
  final Future<GoogleTvCredentials> Function() _credentialsFactory;
  GoogleTvCredentials? _credentials;
  SecureSocket? _socket;
  StreamSubscription<List<int>>? _subscription;
  Timer? _deadline;
  Completer<bool>? _ready;
  Completer<bool>? _pinAck;
  DeviceConnectionState _state = DeviceConnectionState.disconnected;
  String _host = '';
  int _generation = 0;
  int _features = 0;
  final VoiceAudioSource Function() _audioSourceFactory;
  GoogleTvVoiceSession? _voice;
  double get voiceInputLevel => _voice?.level ?? 0;
  int get voiceCapturedBytes => _voice?.bytesCaptured ?? 0;
  int get voiceSentBytes => _voice?.bytesSent ?? 0;
  Future<void> startVoice() async {
    if (!isConnected || (_features & 8) == 0) {
      throw StateError('O Google TV não disponibilizou o microfone remoto.');
    }
    final previous = _voice;
    if (previous != null) {
      try {
        await stopVoice();
      } catch (_) {
        /* Previous capture is already disposed. */
      }
    }
    if (!isConnected) throw StateError('O Google TV desconectou.');
    final socket = _socket;
    final generation = _generation;
    final voice = GoogleTvVoiceSession(
      source: _audioSourceFactory(),
      send: (message) {
        if (generation != _generation || !identical(socket, _socket)) {
          throw StateError('A conexão mudou durante a fala.');
        }
        _send(message);
      },
      search: () => _key(84),
    );
    _voice = voice;
    try {
      await voice.start();
    } catch (_) {
      try {
        await voice.finish();
      } catch (_) {}
      if (identical(_voice, voice)) _voice = null;
      rethrow;
    }
  }

  Future<void> stopVoice() async {
    final voice = _voice;
    final socket = _socket;
    if (voice == null) return;
    // Keep routing the server acknowledgement until finish drains short speech.
    try {
      await voice.finish();
      if (identical(socket, _socket)) await socket?.flush();
    } finally {
      if (identical(_voice, voice)) _voice = null;
    }
  }

  Timer? _reconnectTimer;
  bool _keepConnected = false;
  bool _authenticationRejected = false;
  int _reconnectAttempts = 0;
  static bool _isCertificateRejection(Object error) {
    final text = error.toString().toUpperCase();
    return error is TlsException &&
        (text.contains('CERTIFICATE_UNKNOWN') ||
            text.contains('BAD_CERTIFICATE') ||
            text.contains('UNKNOWN_CA') ||
            text.contains('CERTIFICATE_REQUIRED') ||
            text.contains('ACCESS_DENIED'));
  }

  void _touchActivity() {
    if (isConnected) {
      _expire(idleTimeout, 'O Google TV parou de responder.');
    }
  }

  void _scheduleReconnect() {
    if (!_keepConnected ||
        _authenticationRejected ||
        _reconnectAttempts >= reconnectDelays.length) {
      return;
    }
    final delay = reconnectDelays[_reconnectAttempts++];
    final generation = _generation;
    _setState(DeviceConnectionState.connecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      if (generation != _generation || !_keepConnected) return;
      try {
        await _connectPaired(generation);
      } catch (_) {
        if (generation == _generation) {
          _fail(
            'Não foi possível reconectar ao Google TV. Toque em conectar para tentar novamente.',
          );
        }
      }
    });
  }

  Future<bool> _connectPaired(int generation) async {
    try {
      final connected = await _openControl(generation);
      if (connected || !_authenticationRejected || generation != _generation) {
        return connected;
      }
    } on TlsException catch (error) {
      if (!_isCertificateRejection(error)) rethrow;
      if (generation != _generation) return false;
    }
    // The TLS alert can arrive after SecureSocket.connect has already completed.
    // Only an explicit certificate rejection warrants another PIN. Preserve
    // the private key; upgrade a colliding legacy subject only for this pairing.
    _keepConnected = false;
    _closeChannel();
    _credentials = _credentials!.forPairing();
    await _openPairing(generation);
    return false;
  }

  int _imeCounter = 0;
  int _fieldCounter = 0;
  bool? _muted;
  bool _isOn = false;
  bool get isOn => _isOn;
  Duration _timeout = const Duration(seconds: 10);

  @override
  TvBrand get brand => TvBrand.googleTv;
  @override
  DeviceConnectionState get connectionState => _state;
  @override
  bool get supportsTrackpad => false;
  @override
  bool get supportsPairingPin => true;
  void _setState(DeviceConnectionState value) {
    _state = value;
    onStateChanged?.call(value);
  }

  void _complete(Completer<bool>? pending, bool value) {
    if (pending != null && !pending.isCompleted) pending.complete(value);
  }

  void _closeChannel() {
    _deadline?.cancel();
    _deadline = null;
    _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
  }

  void _fail(String message) {
    unawaited(stopVoice().catchError((Object _) {}));
    _closeChannel();
    _complete(_ready, false);
    _complete(_pinAck, false);
    onError?.call(message);
    _setState(DeviceConnectionState.disconnected);
    _scheduleReconnect();
  }

  @override
  void disconnect() {
    _keepConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    unawaited(stopVoice().catchError((Object _) {}));
    ++_generation;
    _closeChannel();
    _complete(_ready, false);
    _complete(_pinAck, false);
    _muted = null;
    _setState(DeviceConnectionState.disconnected);
  }

  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 10),
    bool pairAgain = false,
  }) async {
    disconnect();
    final generation = _generation;
    _host = ipAddress;
    _timeout = timeout;
    _imeCounter = 0;
    _fieldCounter = 0;
    if (!NetworkSecurityUtils.isLocalNetworkHost(ipAddress)) {
      _fail('Informe o IP local do Chromecast / Google TV.');
      return false;
    }
    _setState(DeviceConnectionState.connecting);
    try {
      final credentials = authToken != null && authToken.isNotEmpty
          ? GoogleTvCredentials.decode(authToken)
          : await _credentialsFactory();
      if (generation != _generation) return false;
      _credentials = pairAgain ? credentials.forPairing() : credentials;
      if (!pairAgain && authToken != null && authToken.isNotEmpty) {
        return await _connectPaired(generation);
      }
      await _openPairing(generation);
    } catch (_) {
      if (generation == _generation) {
        _fail(
          'Não foi possível conectar ao Google TV. Confira o IP, a rede e o Android TV Remote Service.',
        );
      }
    }
    return false;
  }

  Future<bool> _openSocket(
    int port,
    int generation,
    void Function(Map<int, Object>) handler,
  ) async {
    _authenticationRejected = false;
    final socket = await SecureSocket.connect(
      _host,
      port,
      context: _credentials!.context(),
      timeout: _timeout,
      onBadCertificate: (_) => NetworkSecurityUtils.isLocalNetworkHost(_host),
    );
    if (generation != _generation) {
      socket.destroy();
      return false;
    }
    _socket = socket;
    final decoder = TvFrameDecoder();
    _subscription = socket.listen(
      (data) {
        if (generation != _generation || !identical(_socket, socket)) return;
        try {
          for (final message in decoder.add(data)) {
            if (!identical(_socket, socket)) break;
            handler(TvWire.decode(message));
          }
        } catch (_) {
          _fail('Resposta inválida do Google TV. Tente reconectar.');
        }
      },
      onDone: () {
        if (generation == _generation && identical(_socket, socket)) {
          // EOF also happens while Remote Service starts or restarts. It is
          // not evidence that a saved certificate was rejected.
          _fail(
            'A conexão com o Google TV foi encerrada. Reconecte para continuar.',
          );
        }
      },
      onError: (Object error) {
        if (generation == _generation && identical(_socket, socket)) {
          _authenticationRejected = _isCertificateRejection(error);
          _fail(
            _authenticationRejected
                ? 'O Chromecast recusou o pareamento salvo. Confirme o novo código na TV.'
                : 'A conexão com o Google TV foi interrompida.',
          );
        }
      },
      cancelOnError: true,
    );
    return true;
  }

  void _send(List<int> message) {
    _socket?.add(TvWire.frame(message));
    _touchActivity();
  }

  List<int> _pairMessage(int field, List<int> data) => [
    ...TvWire.number(1, 2),
    ...TvWire.number(2, 200),
    ...TvWire.bytes(field, data),
  ];
  void _expire(Duration duration, String message) {
    _deadline?.cancel();
    _deadline = Timer(duration, () => _fail(message));
  }

  Future<void> _openPairing(int generation) async {
    final ready = _ready = Completer<bool>();
    if (!await _openSocket(pairingPort, generation, _handlePairing)) return;
    _expire(
      const Duration(seconds: 10),
      'O Google TV não iniciou o pareamento.',
    );
    _send(
      _pairMessage(10, [
        ...TvWire.text(1, 'atvremote'),
        ...TvWire.text(2, 'SixF Remote'),
      ]),
    );
    await ready.future;
  }

  void _handlePairing(Map<int, Object> fields) {
    if (TvWire.integer(fields, 2) != 200) {
      _fail('O Google TV recusou o pareamento. Conecte novamente.');
      return;
    }
    final encoding = [...TvWire.number(1, 3), ...TvWire.number(2, 6)];
    if (fields.containsKey(11)) {
      _send(
        _pairMessage(20, [
          ...TvWire.bytes(1, encoding),
          ...TvWire.number(3, 1),
        ]),
      );
    } else if (fields.containsKey(20)) {
      _send(
        _pairMessage(30, [
          ...TvWire.bytes(1, encoding),
          ...TvWire.number(2, 1),
        ]),
      );
    } else if (fields.containsKey(31)) {
      _expire(
        const Duration(minutes: 2),
        'O código de pareamento expirou. Conecte novamente.',
      );
      _setState(DeviceConnectionState.pairingPrompt);
      _complete(_ready, true);
      onPinPromptRequested?.call(true);
    } else if (fields.containsKey(41)) {
      _complete(_pinAck, true);
    }
  }

  @override
  Future<void> sendPairingPin(String pin) async {
    if (_state != DeviceConnectionState.pairingPrompt || _socket == null) {
      throw StateError('O pareamento expirou. Conecte novamente.');
    }
    if (_pinAck != null && !_pinAck!.isCompleted) return;
    final generation = _generation;
    final secret = _credentials!.secret(
      pin.trim(),
      _socket!.peerCertificate!.der,
    );
    final ack = _pinAck = Completer<bool>();
    _send(_pairMessage(40, TvWire.bytes(1, secret)));
    final success = await ack.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => false,
    );
    if (generation != _generation) return;
    if (!success) {
      _fail('O Google TV não confirmou o código. Conecte novamente.');
      throw StateError('Pareamento não confirmado.');
    }
    // Only persist an identity after the TV acknowledges its pairing secret.
    onAuthTokenReceived?.call(_credentials!.encode());
    _closeChannel();
    _setState(DeviceConnectionState.connecting);
    try {
      if (!await _openControl(generation) && generation == _generation) {
        throw StateError('Pareado. Toque em conectar para tentar novamente.');
      }
    } catch (_) {
      if (generation == _generation) {
        _fail(
          'Pareamento salvo, mas a conexão falhou. Toque em conectar novamente.',
        );
      }
      rethrow;
    }
  }

  Future<bool> _openControl(int generation) async {
    final ready = _ready = Completer<bool>();
    if (!await _openSocket(controlPort, generation, _handleControl)) {
      return false;
    }
    _expire(_timeout, 'O Google TV não concluiu a conexão.');
    return ready.future;
  }

  void _handleControl(Map<int, Object> fields) {
    _touchActivity();
    if (fields.containsKey(1)) {
      final cfg = TvWire.message(fields, 1);
      // PING, KEY, IME, VOICE, POWER, VOLUME and APP_LINK.
      _features = TvWire.integer(cfg, 1) & 623;
      if ((_features & 2) == 0) {
        _fail('O aparelho não oferece controle remoto por teclas.');
        return;
      }
      final info = TvWire.message(cfg, 2);
      final model = TvWire.string(info, 1);
      if (model.isNotEmpty) onDeviceNameResolved?.call(model, model);
      _send(
        TvWire.bytes(1, [
          ...TvWire.number(1, _features),
          ...TvWire.bytes(2, [
            ...TvWire.number(3, 1),
            ...TvWire.text(4, '1'),
            ...TvWire.text(5, 'sixf.remote'),
            ...TvWire.text(6, '1.0.6'),
          ]),
        ]),
      );
    }
    if (fields.containsKey(2)) {
      _send(TvWire.bytes(2, TvWire.number(1, _features)));
    }
    if (fields.containsKey(8)) {
      _send(
        TvWire.bytes(
          9,
          TvWire.number(1, TvWire.integer(TvWire.message(fields, 8), 1)),
        ),
      );
    }
    if (fields.containsKey(21)) {
      final edit = TvWire.message(fields, 21);
      _imeCounter = TvWire.integer(edit, 1);
      _fieldCounter = TvWire.integer(edit, 2);
    }
    if (fields.containsKey(30)) {
      _voice?.acceptSession(TvWire.integer(TvWire.message(fields, 30), 1));
    }
    if (fields.containsKey(40)) {
      _isOn = TvWire.integer(TvWire.message(fields, 40), 1) != 0;
      _keepConnected = true;
      _setState(DeviceConnectionState.connected);
      _expire(
        idleTimeout,
        'O Google TV parou de responder. Reconecte para continuar.',
      );
      _complete(_ready, true);
    }
    if (fields.containsKey(50)) {
      final volume = TvWire.message(fields, 50);
      final max = TvWire.integer(volume, 6);
      _muted = TvWire.integer(volume, 8) != 0;
      if (max > 0) {
        onVolumeStatusChanged?.call(
          (TvWire.integer(volume, 7) * 100 / max).round().clamp(0, 100),
          _muted!,
        );
      }
    }
    if (fields.containsKey(3)) {
      onError?.call('O Google TV não aceitou esse comando.');
    }
  }

  static const keyCodes = <RemoteKey, int>{
    RemoteKey.power: 26,
    RemoteKey.volumeUp: 24,
    RemoteKey.volumeDown: 25,
    RemoteKey.mute: 164,
    RemoteKey.channelUp: 166,
    RemoteKey.channelDown: 167,
    RemoteKey.dpadUp: 19,
    RemoteKey.dpadDown: 20,
    RemoteKey.dpadLeft: 21,
    RemoteKey.dpadRight: 22,
    RemoteKey.dpadOk: 23,
    RemoteKey.back: 4,
    RemoteKey.home: 3,
    RemoteKey.menu: 176,
    RemoteKey.exit: 3,
    RemoteKey.input: 178,
    RemoteKey.play: 126,
    RemoteKey.pause: 127,
    RemoteKey.stop: 86,
    RemoteKey.rewind: 89,
    RemoteKey.fastForward: 90,
    RemoteKey.colorRed: 183,
    RemoteKey.colorGreen: 184,
    RemoteKey.colorYellow: 185,
    RemoteKey.colorBlue: 186,
    RemoteKey.dash: 69,
    RemoteKey.voice: 84,
  };
  void _key(int code) {
    if (isConnected) {
      _send(
        TvWire.bytes(10, [...TvWire.number(1, code), ...TvWire.number(2, 3)]),
      );
    }
  }

  @override
  void sendKey(RemoteKey key) => _key(keyCodes[key]!);
  @override
  void sendDigit(int digit) {
    if (digit >= 0 && digit <= 9) _key(7 + digit);
  }

  @override
  void setMute(bool mute) {
    if (_muted != mute) {
      _key(164);
      _muted = mute;
    }
  }

  @override
  void setVolume(int volume) {
    onError?.call('No Google TV, ajuste o volume pelos botões + e −.');
  }

  @override
  void sendTrackpadDelta(double dx, double dy) {}
  @override
  void sendTrackpadClick() => _key(23);
  @override
  void sendText(String text) {
    if (!isConnected || text.isEmpty) return;
    if ((_features & 4) == 0) {
      onError?.call('Este Google TV não oferece digitação remota.');
      return;
    }
    if (text.length > 4000) {
      onError?.call('Envie até 4000 caracteres por vez.');
      return;
    }
    final end = text.length - 1;
    _send(
      TvWire.bytes(21, [
        ...TvWire.number(1, _imeCounter),
        ...TvWire.number(2, _fieldCounter),
        ...TvWire.bytes(3, [
          ...TvWire.number(1, 1),
          ...TvWire.bytes(2, [
            ...TvWire.number(1, end),
            ...TvWire.number(2, end),
            ...TvWire.text(3, text),
          ]),
        ]),
      ]),
    );
  }

  @override
  void openApp(String appId) {
    if (!isConnected) return;
    if (appId.startsWith('adb:')) {
      unawaited(
        GoogleTvAppsAdb.launch(_host, appId.substring(4)).catchError((
          Object e,
        ) {
          onError?.call(e.toString());
        }),
      );
      return;
    }
    if ((_features & 512) == 0) {
      onError?.call('Este Google TV não oferece abertura de aplicativos.');
      return;
    }
    const links = {
      'youtube': 'https://www.youtube.com',
      'netflix': 'netflix://',
      'prime': 'https://app.primevideo.com',
      'disney': 'https://www.disneyplus.com',
      'spotify': 'spotify:',
      'max': 'https://www.max.com',
      'globoplay': 'https://globoplay.globo.com',
    };
    final link = links[appId] ?? appId;
    if (!link.contains(':')) {
      onError?.call(
        'Atalho indisponível para Google TV. Abra o app pela tela inicial.',
      );
      return;
    }
    _send(TvWire.bytes(90, TvWire.text(1, link)));
  }

  @override
  Future<List<TvAppInfo>> getInstalledApps() async {
    if (await GoogleTvAppsAdb.configured(_host)) {
      return GoogleTvAppsAdb.apps(_host);
    }
    return [
      TvAppInfo.fromRaw(id: 'youtube', name: 'YouTube'),
      TvAppInfo.fromRaw(id: 'netflix', name: 'Netflix'),
    ];
  }
}
