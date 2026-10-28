import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/google_tv_voice.dart';
import 'package:sixf_remote/services/drivers/google_tv/wire.dart';

class FakeAudioSource implements VoiceAudioSource {
  final stream = StreamController<List<int>>();
  final tail = <int>[0x34, 0x12];
  int disposals = 0;
  @override
  Future<Stream<List<int>>> start(void Function(int, int) format) async {
    format(8000, 1);
    return stream.stream;
  }

  @override
  Future<void> stop() async {
    stream.add(tail);
    await stream.close();
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  test('hardware PCM 48k stereo becomes signed 8k mono even when input frames split', () {
    final converter = VoicePcmConverter()..configure(48000, 2);
    // Left +2000, right -1000 => mono +500. Six input frames per output.
    final input = List.generate(
      12,
      (_) => [0xd0, 0x07, 0x18, 0xfc],
    ).expand((v) => v).toList();
    final output = <int>[];
    for (final byte in input) {
      output.addAll(converter.add([byte]));
    }
    expect(output, [0xf4, 0x01, 0xf4, 0x01]);
  });
  test('Android mono 16k preserves tail and sample sign across buffers', () {
    final converter = VoicePcmConverter()..configure(16000, 1);
    expect(converter.add([0x18]), isEmpty);
    expect(converter.add([0xfc, 0x18, 0xfc]), [0x18, 0xfc]);
  });
  test('release drains capture before final payload and VOICE_END; finish is idempotent', () async {
    final source = FakeAudioSource();
    final messages = <Map<int, Object>>[];
    final searched = Completer<void>();
    final voice = GoogleTvVoiceSession(
      source: source,
      send: (v) => messages.add(TvWire.decode(v)),
      search: searched.complete,
    );
    final starting = voice.start();
    await searched.future;
    source.stream.add([1, 0, 2, 0]);
    voice.acceptSession(7);
    await starting;
    await Future.wait([voice.finish(), voice.finish()]);
    expect(messages.map((m) => m.keys.single), [30, 31, 32]);
    // Receiver field 31 is bytes, not a nested protobuf. Extra headers shift
    // PCM sample alignment and were confirmed to produce unrecognizable speech.
    final payload = messages[1][31] as List<int>;
    expect(payload.take(6), [1, 0, 2, 0, 0x34, 0x12]);
    expect(payload.skip(6), everyElement(0));
    expect(payload, hasLength(8192));
    expect(source.disposals, 1);
  });
  test('quick release waits for server acknowledgement and still submits captured speech', () async {
    final source = FakeAudioSource();
    final packets = <Map<int, Object>>[];
    final searched = Completer<void>();
    final voice = GoogleTvVoiceSession(
      source: source,
      send: (v) => packets.add(TvWire.decode(v)),
      search: searched.complete,
    );
    final starting = voice.start();
    await searched.future;
    source.stream.add([100, 0]);
    final ending = voice.finish();
    voice.acceptSession(8);
    await starting;
    await ending;
    expect(packets.map((m) => m.keys.single), [30, 31, 32]);
    expect(TvWire.message(packets.last, 32)[1], 8);
  });
  test('handshake timeout releases microphone and never sends a fabricated session', () async {
    final source = FakeAudioSource();
    final packets = <List<int>>[];
    final voice = GoogleTvVoiceSession(
      source: source,
      send: packets.add,
      search: () {},
      handshakeTimeout: const Duration(milliseconds: 10),
    );
    await expectLater(voice.start(), throwsStateError);
    await expectLater(voice.finish(), throwsStateError);
    expect(packets, isEmpty);
    expect(source.disposals, 1);
  });
}
