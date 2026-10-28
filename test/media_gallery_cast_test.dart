import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/services/google_cast_media.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';

import 'security_lifecycle_test.dart' show LocalMediaServer, RealHttp;

class SimulatedCast extends GoogleCastMedia {
  int reloads = 0;
  int id = 1;
  bool closed = false;
  bool rejectSeek = false;
  Completer<void>? pendingSeek;
  final commands = <String>[];
  Map<String, dynamic> current = {};
  @override
  Map<String, dynamic> get status => current;
  void emit(String state, {String? reason, int mask = 3, int position = 12}) {
    current = {
      'mediaSessionId': id,
      'playerState': state,
      'currentTime': position,
      'supportedMediaCommands': mask,
      'media': {'duration': 100},
      'idleReason': ?reason,
    };
    onStatus?.call(current);
  }

  @override
  Future<void> load(String host, String url, String title, String mime) async {
    emit('PLAYING');
  }

  @override
  Future<void> refresh() async {}
  @override
  Future<void> reload() async {
    reloads++;
    id++;
    emit('PLAYING', position: 0);
  }

  @override
  Future<void> command(String type, {double? currentTime}) async {
    commands.add('$type:$currentTime');
    if (type == 'SEEK' && pendingSeek != null) await pendingSeek!.future;
    if (type == 'SEEK' && rejectSeek) throw StateError('Recusado');
    emit(
      type == 'PAUSE' ? 'PAUSED' : 'PLAYING',
      position: currentTime?.round() ?? 12,
    );
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late MediaCastController controller;
  late List<SimulatedCast> casts;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sixf-gallery-');
    casts = [];
    controller = MediaCastController(
      serverService: LocalMediaServer(),
      castFactory: () {
        final c = SimulatedCast();
        casts.add(c);
        return c;
      },
    );
  });
  tearDown(() async {
    controller.dispose();
    await dir.delete(recursive: true);
  });
  Future<File> file(String name) async =>
      File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);
  Future<bool> load(List<File> files) => HttpOverrides.runWithHttpOverrides(
    () => controller.castPlaylist(
      files,
      targetTvIp: '127.0.0.1',
      brand: TvBrand.googleTv,
      tvName: 'Chromecast',
    ),
    RealHttp(),
  );
  test(
    'Cast telemetry enables timeline, seek, pause and replay only with support',
    () async {
      await load([await file('video.mp4')]);
      expect(controller.hasProgress, isTrue);
      expect(controller.canSeek, isTrue);
      expect(await controller.seekTo(const Duration(seconds: 30)), isTrue);
      expect(controller.currentPosition, const Duration(seconds: 30));
      casts.single.rejectSeek = true;
      expect(await controller.seekTo(const Duration(seconds: 50)), isFalse);
      expect(controller.currentPosition, const Duration(seconds: 30));
      await controller.pause();
      expect(controller.isPaused, isTrue);
      casts.single.emit('PLAYING', mask: 0);
      expect(controller.canSeek, isFalse);
      expect(controller.canLoop, isFalse);
      expect(controller.canPause, isFalse);
    },
  );
  test('natural FINISHED repeats once, other idle reasons and duplicate events do not', () async {
    await load([await file('video.mp4')]);
    controller.toggleLoop();
    final c = casts.single;
    c.emit('IDLE', reason: 'CANCELLED');
    await Future<void>.delayed(Duration.zero);
    expect(c.reloads, 0);
    c.emit('IDLE', reason: 'FINISHED');
    c.emit('IDLE', reason: 'FINISHED');
    await Future<void>.delayed(Duration.zero);
    expect(c.reloads, 1);
    expect(controller.isPlaying, isTrue);
    await controller.stop();
    c.emit('IDLE', reason: 'FINISHED');
    await Future<void>.delayed(Duration.zero);
    expect(c.reloads, 1);
  });
  test('gallery next and previous preserve list and destination and stop clears it', () async {
    final a = await file('a.jpg'),
        b = await file('b.jpg'),
        c = await file('c.jpg');
    await load([a, b, c]);
    expect(controller.playlistCount, 3);
    expect(controller.canPrevious, isFalse);
    expect(controller.canNext, isTrue);
    await HttpOverrides.runWithHttpOverrides(controller.next, RealHttp());
    expect(controller.currentFilePath, b.path);
    expect(controller.playlistPosition, 2);
    expect(controller.isTarget('127.0.0.1', TvBrand.googleTv), isTrue);
    await HttpOverrides.runWithHttpOverrides(controller.previous, RealHttp());
    expect(controller.currentFilePath, a.path);
    controller.toggleShuffle();
    expect(controller.isShuffling, isTrue);
    casts.last.emit('IDLE',reason:'FINISHED');
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentFilePath,a.path);
    expect(casts.length,3);
    await HttpOverrides.runWithHttpOverrides(controller.next, RealHttp());
    expect(controller.currentFilePath, isNot(a.path));
    await controller.stop();
    expect(controller.playlistCount, 0);
    expect(controller.canNext, isFalse);
  });
  test(
    'stop during seek ignores stale telemetry and cannot revive playback',
    () async {
      await load([await file('video.mp4')]);
      final c = casts.single;
      final pending = c.pendingSeek = Completer<void>();
      final seeking = controller.seekTo(const Duration(seconds: 55));
      await controller.stop();
      pending.complete();
      expect(await seeking, isFalse);
      expect(controller.status, MediaCastStatus.idle);
      expect(controller.hasProgress, isFalse);
    },
  );
  test(
    'missing next image does not replace the currently displayed file',
    () async {
      final a = await file('a.jpg'), b = await file('b.jpg');
      await load([a, b]);
      await b.delete();
      expect(await controller.next(), isFalse);
      expect(controller.currentFilePath, a.path);
    },
  );
}
