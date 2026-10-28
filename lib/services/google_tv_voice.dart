import 'dart:async';

import 'package:record/record.dart';

import 'drivers/google_tv/wire.dart';

abstract class VoiceAudioSource {
  Future<Stream<List<int>>> start(void Function(int rate, int channels) format);
  Future<void> stop();
  Future<void> dispose();
}

class MicrophoneAudioSource implements VoiceAudioSource {
  final AudioRecorder _recorder = AudioRecorder();
  @override
  Future<Stream<List<int>>> start(void Function(int, int) format) async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Permita o acesso ao microfone do SixF.');
    }
    format(48000, 1);
    await _recorder.setOnConfigChanged(
      (config) => format(config.sampleRate, config.numChannels),
    );
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 48000,
        numChannels: 1,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// PCM signed 16-bit LE, hardware format -> 8kHz mono, preserving split frames.
class VoicePcmConverter {
  int rate = 48000, channels = 1;
  final _pending = <int>[];
  double _weight = 0, _sum = 0;
  void configure(int rate, int channels) {
    if (rate <= 0 || channels <= 0) {
      throw const FormatException('Formato de áudio inválido.');
    }
    this.rate = rate;
    this.channels = channels;
    _pending.clear();
    _weight = 0;
    _sum = 0;
  }

  List<int> add(List<int> bytes) {
    _pending.addAll(bytes);
    final result = <int>[];
    final frameSize = channels * 2;
    var offset = 0;
    while (offset + frameSize <= _pending.length) {
      var sample = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        final i = offset + channel * 2;
        var value = _pending[i] | (_pending[i + 1] << 8);
        if (value >= 32768) value -= 65536;
        sample += value / channels;
      }
      var left = 8000.0;
      while (left > 0) {
        final take = left < rate - _weight ? left : rate - _weight;
        _sum += sample * take;
        _weight += take;
        left -= take;
        if (_weight >= rate) {
          final value = (_sum / rate).round().clamp(-32768, 32767);
          result.add(value & 255);
          result.add((value >> 8) & 255);
          _sum = 0;
          _weight = 0;
        }
      }
      offset += frameSize;
    }
    _pending.removeRange(0, offset);
    return result;
  }
}

/// One press owns capture, server handshake, final audio drain and VOICE_END.
class GoogleTvVoiceSession {
  GoogleTvVoiceSession({
    required this.source,
    required this.send,
    required this.search,
    this.handshakeTimeout = const Duration(seconds: 4),
  });
  final VoiceAudioSource source;
  final void Function(List<int>) send;
  final void Function() search;
  final Duration handshakeTimeout;
  final converter = VoicePcmConverter();
  final _buffer = <int>[];
  final _ready = Completer<int?>();
  final _captureStarted = Completer<void>();
  final _captureDone = Completer<void>();
  StreamSubscription<List<int>>? _subscription;
  Future<void>? _starting, _finishing;
  bool _released = false;
  int? _id;
  int bytesCaptured = 0;
  int bytesSent = 0;
  double level = 0;
  Object? _failure;
  void _captureFailed(Object error) {
    _failure = error;
    if (!_ready.isCompleted) _ready.complete(null);
  }

  void acceptSession(int id) {
    if (!_ready.isCompleted) _ready.complete(id);
  }

  Future<void> start() {
    if (_released) return Future.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      final stream = await source.start(converter.configure);
      _subscription = stream.listen(
        (data) {
          if (_failure != null) return;
          final converted = converter.add(data);
          bytesCaptured += converted.length;
          var peak = 0;
          for (var i = 0; i + 1 < converted.length; i += 2) {
            final sample = (converted[i] | (converted[i + 1] << 8))
                .toSigned(16)
                .abs();
            if (sample > peak) peak = sample;
          }
          level = peak / 32768;

          // Bound buffering while waiting for TV handshake.
          if (_buffer.length + converted.length > 16000 * 8) {
            _captureFailed(StateError('O Chromecast não iniciou a escuta.'));
            return;
          }
          _buffer.addAll(converted);
          try {
            _drain();
          } catch (error) {
            _captureFailed(error);
          }
        },
        onDone: () {
          if (!_captureDone.isCompleted) _captureDone.complete();
        },
        onError: (Object error) {
          _captureFailed(error);
          if (!_captureDone.isCompleted) _captureDone.complete();
        },
      );
      _captureStarted.complete();
      search();
      final id = await _ready.future.timeout(
        handshakeTimeout,
        onTimeout: () => null,
      );
      if (id == null) {
        throw StateError('O Google TV não iniciou a escuta. Tente novamente.');
      }
      _id = id;
      send(TvWire.bytes(30, TvWire.number(1, id)));
      _drain();
    } finally {
      if (!_captureStarted.isCompleted) _captureStarted.complete();
    }
  }

  void _chunk(List<int> bytes) {
    // Client -> TV field 31 is raw PCM, not a nested session/sample message.
    // The active session is established by VOICE_BEGIN and closed by VOICE_END.
    send(TvWire.bytes(31, bytes));
    bytesSent += bytes.length;
  }

  void _drain() {
    if (_id == null) return;
    while (_buffer.length >= 8192) {
      _chunk(_buffer.sublist(0, 8192));
      _buffer.removeRange(0, 8192);
    }
  }

  Future<void> finish() {
    _released = true;
    return _finishing ??= _finish();
  }

  Future<void> _finish() async {
    try {
      if (_starting == null) return;
      await _captureStarted.future;
      try {
        await source.stop();
      } catch (e) {
        _failure = e;
      }
      if (_subscription != null) {
        await _captureDone.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
      try {
        await _starting;
      } catch (error) {
        _failure ??= error;
      }
      if (_id != null) {
        _drain();
        if (_buffer.isNotEmpty) {
          _chunk([..._buffer, ...List.filled(8192 - _buffer.length, 0)]);
        }
        send(TvWire.bytes(32, TvWire.number(1, _id!)));
        _id = null;
      }
      if (bytesCaptured == 0 && _failure == null) {
        throw StateError(
          'Nenhum áudio foi captado. Confira o microfone e sua permissão.',
        );
      }
      if (_failure != null) {
        throw StateError(
          'Falha ao captar o microfone. Confira a permissão e o dispositivo de entrada.',
        );
      }
    } finally {
      _buffer.clear();
      await _subscription?.cancel();
      await source.dispose();
    }
  }
}
