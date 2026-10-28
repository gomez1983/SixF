import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'drivers/google_tv/wire.dart';
import 'network_security_utils.dart';

/// Google Cast V2 Default Media Receiver. Independent from Remote Service v2.
class GoogleCastMedia {
  GoogleCastMedia({this.port = 8009});
  final int port;
  static const receiver = 'urn:x-cast:com.google.cast.receiver';
  static const media = 'urn:x-cast:com.google.cast.media';
  static const connection = 'urn:x-cast:com.google.cast.tp.connection';
  static const heartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  SecureSocket? _socket;
  StreamSubscription<List<int>>? _subscription;
  Timer? _ping;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  final _buffer = <int>[];
  int _request = 0;
  int _generation = 0;
  String _destination = 'receiver-0';
  int? _mediaSession;
  Map<String, dynamic>? _lastLoad;
  bool _loading = false;
  Map<String, dynamic> _status = {};
  void Function(Map<String, dynamic> status)? onStatus;
  Map<String, dynamic> get status => Map.unmodifiable(_status);
  bool get isConnected => _socket != null && _mediaSession != null;
  void _acceptStatus(Map<String, dynamic> message) {
    final states = message['status'] as List? ?? [];
    if (states.isEmpty) return;
    final next = Map<String, dynamic>.from(states.first as Map);
    final id = next['mediaSessionId'] as int?;
    if (id == null || (_mediaSession != null && id != _mediaSession)) return;
    if (_mediaSession != id) _status = {};
    _mediaSession = id;
    _status = {..._status, ...next};
    if (_status['playerState'] != 'IDLE') _status.remove('idleReason');
    onStatus?.call(status);
  }

  void _send(
    String namespace,
    Map<String, dynamic> payload, {
    String? destination,
  }) {
    final packet = [
      ...TvWire.number(1, 0),
      ...TvWire.text(2, 'sender-sixf'),
      ...TvWire.text(3, destination ?? _destination),
      ...TvWire.text(4, namespace),
      ...TvWire.number(5, 0),
      ...TvWire.text(6, jsonEncode(payload)),
    ];
    final prefix = ByteData(4)..setUint32(0, packet.length);
    _socket?.add([...prefix.buffer.asUint8List(), ...packet]);
  }

  Future<Map<String, dynamic>> _ask(
    String ns,
    Map<String, dynamic> data, {
    String? destination,
  }) async {
    if (_socket == null) throw StateError('A sessão de mídia foi encerrada.');
    final id = ++_request;
    final reply = Completer<Map<String, dynamic>>();
    _pending[id] = reply;
    _send(ns, {...data, 'requestId': id}, destination: destination);
    try {
      return await reply.future.timeout(const Duration(seconds: 15));
    } finally {
      _pending.remove(id);
    }
  }

  void _read(List<int> bytes) {
    _buffer.addAll(bytes);
    try {
      while (_buffer.length >= 4) {
        final length = ByteData.sublistView(
          Uint8List.fromList(_buffer.sublist(0, 4)),
        ).getUint32(0);
        if (length > 1024 * 1024) {
          throw const FormatException('Cast frame too large');
        }
        if (_buffer.length < 4 + length) return;
        final fields = TvWire.decode(_buffer.sublist(4, 4 + length));
        _buffer.removeRange(0, 4 + length);
        final text = TvWire.string(fields, 6);
        if (text.isEmpty) continue;
        final message = jsonDecode(text) as Map<String, dynamic>;
        if (message['type'] == 'PING') {
          _send(heartbeat, {
            'type': 'PONG',
          }, destination: TvWire.string(fields, 2));
        }
        if (message['type'] == 'CLOSE') {
          close();
          return;
        }
        if (!_loading &&
            message['type'] == 'MEDIA_STATUS' &&
            TvWire.string(fields, 4) == media) {
          _acceptStatus(message);
        }
        final pending = _pending[message['requestId']];
        if (pending != null && !pending.isCompleted) pending.complete(message);
      }
    } catch (_) {
      close();
    }
  }

  Future<void> load(String host, String url, String title, String mime) async {
    close();
    final generation = _generation;
    if (!NetworkSecurityUtils.isLocalNetworkHost(host)) {
      throw StateError('IP local inválido.');
    }
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 8),
      onBadCertificate: (_) => true,
    );
    if (generation != _generation) {
      socket.destroy();
      throw StateError('Transmissão cancelada.');
    }
    _socket = socket;
    _destination = 'receiver-0';
    _subscription = socket.listen(
      (data) {
        if (generation == _generation && identical(socket, _socket)) {
          _read(data);
        }
      },
      onError: (Object _) {
        if (generation == _generation && identical(socket, _socket)) close();
      },
      onDone: () {
        if (generation == _generation && identical(socket, _socket)) close();
      },
    );
    _send(connection, {'type': 'CONNECT'}, destination: 'receiver-0');
    _ping = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _send(heartbeat, {'type': 'PING'}, destination: 'receiver-0'),
    );
    final launched = await _ask(receiver, {
      'type': 'LAUNCH',
      'appId': 'CC1AD845',
    }, destination: 'receiver-0');
    if (generation != _generation) throw StateError('Transmissão cancelada.');
    final status = launched['status'] as Map<String, dynamic>?;
    final apps = status?['applications'] as List? ?? [];
    final matches = apps.where((a) => a['appId'] == 'CC1AD845').toList();
    if (matches.isEmpty) {
      throw StateError('O Chromecast não abriu o receptor de mídia.');
    }
    _destination = matches.first['transportId'] as String;
    _send(connection, {'type': 'CONNECT'});
    _lastLoad = {
      'type': 'LOAD',
      'autoplay': true,
      'currentTime': 0,
      'media': {
        'contentId': url,
        'contentType': mime,
        'streamType': 'BUFFERED',
        'metadata': {
          'metadataType': mime.startsWith('image/') ? 4 : 0,
          'title': title,
        },
      },
    };
    await reload();
  }

  Future<void> reload() async {
    if (_lastLoad == null || _socket == null) {
      throw StateError('Não há mídia para repetir.');
    }
    final generation = _generation;
    _status = {};
    _mediaSession = null;
    _loading = true;
    late Map<String, dynamic> result;
    try {
      result = await _ask(media, _lastLoad!);
    } finally {
      if (generation == _generation) _loading = false;
    }
    if (generation != _generation) throw StateError('Transmissão cancelada.');
    final states = result['status'] as List? ?? [];
    if (result['type'] != 'MEDIA_STATUS' ||
        states.isEmpty ||
        states.first['idleReason'] == 'ERROR') {
      throw StateError(
        'O Chromecast recusou a mídia. Confira o formato e o acesso ao arquivo.',
      );
    }
    _acceptStatus(result);
  }

  Future<void> refresh() async {
    final result = await _ask(media, {'type': 'GET_STATUS'});
    if (result['type'] != 'MEDIA_STATUS') {
      throw StateError('O Chromecast não informou o estado da reprodução.');
    }
    _acceptStatus(result);
  }

  Future<void> command(String type, {double? currentTime}) async {
    if (type == 'PLAY' && _status['idleReason'] == 'FINISHED') {
      await reload();
      return;
    }
    if (_mediaSession == null || _socket == null) {
      throw StateError('A sessão de mídia foi encerrada.');
    }
    final result = await _ask(media, {
      'type': type,
      'mediaSessionId': _mediaSession,
      'currentTime': ?currentTime,
    });
    if (result['type'] != 'MEDIA_STATUS') {
      throw StateError('Comando de mídia recusado pelo Chromecast.');
    }
    _acceptStatus(result);
  }

  void close() {
    _generation++;
    _ping?.cancel();
    _ping = null;
    _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _buffer.clear();
    _mediaSession = null;
    _status = {};
    _lastLoad = null;
    _loading = false;
    for (final value in _pending.values) {
      if (!value.isCompleted) value.complete({'type': 'CLOSED'});
    }
    _pending.clear();
  }
}
