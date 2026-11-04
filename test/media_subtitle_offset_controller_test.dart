import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/media_remux_service.dart';

import 'media_gallery_cast_test.dart' show SimulatedCast;
import 'security_lifecycle_test.dart' show LocalMediaServer, RealHttp;

class _SubtitleServer extends LocalMediaServer {
  Completer<String>? pendingSubtitle;
  @override
  Future<String> prepareSubtitle(int trackId) async => pendingSubtitle != null
      ? await pendingSubtitle!.future
      : 'WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nHello\n';
}

class _SubtitleCast extends SimulatedCast {
  List<Map<String, dynamic>>? reloadedTracks;
  Duration? resumePosition;
  bool? autoplay;
  bool failReload = false;
  @override
  Future<void> reloadWithActiveTracks({
    required List<int> activeTrackIds,
    List<Map<String, dynamic>>? tracks,
    Duration? currentTime,
    bool autoplay = true,
  }) async {
    if (failReload) throw StateError('Reload refused');
    reloadedTracks = tracks;
    resumePosition = currentTime;
    this.autoplay = autoplay;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _SubtitleServer server;
  late _SubtitleCast receiver;
  late MediaCastController controller;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sixf-offset-controller-');
    server = _SubtitleServer();
    receiver = _SubtitleCast();
    controller = MediaCastController(
      serverService: server,
      castFactory: () => receiver,
      probeMedia: (_) async => const MediaDetails(
        tracks: [
          MediaTrack(
            id: 2,
            type: 'subtitle',
            title: 'English',
            language: 'eng',
            isDefault: true,
          ),
        ],
        duration: Duration(seconds: 100),
      ),
    );
  });
  tearDown(() async {
    controller.dispose();
    await server.stop();
    await dir.delete(recursive: true);
  });
  Future<void> load(String extension) async {
    final file = File('${dir.path}/movie.$extension')..writeAsBytesSync([1]);
    expect(
      await HttpOverrides.runWithHttpOverrides(
        () => controller.castFile(
          file,
          targetTvIp: '127.0.0.1',
          brand: TvBrand.googleTv,
        ),
        RealHttp(),
      ),
      isTrue,
    );
  }

  test('direct caption adjustment preserves pause/position, rolls back failure and resets on new file', () async {
    await load('mp4');
    await controller.pause();
    final position = controller.currentPosition;
    await controller.adjustSubtitleOffset(const Duration(milliseconds: 500));
    expect(controller.subtitleOffset, const Duration(milliseconds: 500));
    expect(receiver.resumePosition, position);
    expect(receiver.autoplay, isFalse);
    expect(
      receiver.reloadedTracks!.single['trackContentId'],
      contains('offsetUs=500000'),
    );
    receiver.failReload = true;
    await expectLater(
      controller.adjustSubtitleOffset(const Duration(seconds: -1)),
      throwsStateError,
    );
    expect(controller.subtitleOffset, const Duration(milliseconds: 500));
    expect(server.subtitleOffset, const Duration(milliseconds: 500));
    expect(controller.canAdjustSubtitleOffset, isTrue);
    expect(controller.errorMessage, contains('Reload refused'));
    receiver.failReload = false;
    await load('mp4');
    expect(controller.subtitleOffset, Duration.zero);
  });

  test('remux caption adjustment and subsequent seeks send the segment start and offset', () async {
    await load('mkv');
    await controller.pause();
    final position = controller.currentPosition;
    await controller.adjustSubtitleOffset(const Duration(seconds: -1));
    expect(server.remuxStart, position);
    expect(controller.isPaused, isTrue);
    expect(controller.currentPosition, position);
    expect(
      receiver.remuxTracks!.single['trackContentId'],
      contains('offsetUs=-1000000'),
    );
    await controller.seekTo(const Duration(seconds: 50));
    final url = Uri.parse(
      receiver.remuxTracks!.single['trackContentId'] as String,
    );
    expect(url.queryParameters['startUs'], '50000000');
    expect(url.queryParameters['offsetUs'], '-1000000');
    expect(controller.isPaused, isTrue);
  });

  test('Stop during pending caption extraction prevents late reload and offset changes', () async {
    await load('mp4');
    server.pendingSubtitle = Completer<String>();
    final adjustment = controller.adjustSubtitleOffset(
      const Duration(seconds: 1),
    );
    final failure = expectLater(adjustment, throwsA(anything));
    await controller.stop();
    server.pendingSubtitle!.complete('WEBVTT\n');
    await failure;
    expect(receiver.reloadedTracks, isNull);
    expect(controller.subtitleOffset, Duration.zero);
    expect(controller.isStreaming, isFalse);
  });
}
