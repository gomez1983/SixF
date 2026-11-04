// ignore_for_file: file_names

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/media_remux_service.dart';
import 'package:sixf_remote/services/media_server_service.dart';
import 'package:sixf_remote/services/network_operation.dart';

import '../../../../test/media_gallery_cast_test.dart' show SimulatedCast;
import '../../../../test/security_lifecycle_test.dart'
    show LocalMediaServer, RealHttp;

Future<List<int>> _findFfmpegPidsWithMarker(String marker) async {
  final lookup = await Process.run('python', [
    '-c',
    "import psutil,json,sys; sys.stdout.write(json.dumps([p.pid for p in psutil.process_iter(['name','cmdline']) if (p.info['name'] or '').lower()=='ffmpeg.exe' and any('$marker' in a for a in (p.info['cmdline'] or []))]))",
  ]);
  return (jsonDecode(lookup.stdout as String) as List).cast<int>();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'RES-03: session cache is removed on Stop, file switch, late resolution and dispose without deleting separate viewer photo',
    () async {
      final dir = await Directory.systemTemp.createTemp('sixf-audit-cache-');
      final viewerCache = await Directory('${dir.path}/viewer_cache').create();
      final viewerPhoto = File('${viewerCache.path}/open_photo.jpg')
        ..writeAsBytesSync([7, 8, 9]);
      final cacheStop = await Directory('${dir.path}/session_stop').create();
      final fileStop = File('${cacheStop.path}/photo.jpg')
        ..writeAsBytesSync([1]);
      final cacheSwitch = await Directory(
        '${dir.path}/session_switch',
      ).create();
      final fileSwitch = File('${cacheSwitch.path}/photo_switch.jpg')
        ..writeAsBytesSync([2]);
      final standaloneFile = File('${dir.path}/standalone.mp4')
        ..writeAsBytesSync([3]);
      final cacheDispose = await Directory(
        '${dir.path}/session_dispose',
      ).create();
      final fileDispose = File('${cacheDispose.path}/photo2.jpg')
        ..writeAsBytesSync([4]);

      final server = LocalMediaServer();
      final c = MediaCastController(
        serverService: server,
        castFactory: SimulatedCast.new,
        probeMedia: (_) async => const MediaDetails(tracks: []),
      );
      addTearDown(() async {
        c.dispose();
        await server.stop();
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final lateGate = Completer<File>();
      await HttpOverrides.runWithHttpOverrides(
        () => c.castResolvedPlaylist(
          fileStop,
          [
            () async => fileStop,
            () async {
              final f = await lateGate.future;
              await cacheStop.create(recursive: true);
              return File('${cacheStop.path}/late.jpg')
                ..writeAsBytesSync(await f.readAsBytes());
            },
          ],
          targetTvIp: '127.0.0.1',
          brand: TvBrand.googleTv,
          cacheDirectory: cacheStop,
        ),
        RealHttp(),
      );
      expect(c.activeCacheDirectory?.path, cacheStop.path);
      final navigating = c.next();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await c.stop();
      expect(await cacheStop.exists(), isFalse);
      expect(c.activeCacheDirectory, isNull);
      expect(await viewerPhoto.exists(), isTrue);

      lateGate.complete(viewerPhoto);
      expect(await navigating, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await cacheStop.exists(), isFalse);
      expect(await viewerPhoto.exists(), isTrue);

      await HttpOverrides.runWithHttpOverrides(
        () => c.castResolvedPlaylist(
          fileSwitch,
          [() async => fileSwitch],
          targetTvIp: '127.0.0.1',
          brand: TvBrand.googleTv,
          cacheDirectory: cacheSwitch,
        ),
        RealHttp(),
      );
      expect(c.activeCacheDirectory?.path, cacheSwitch.path);
      await HttpOverrides.runWithHttpOverrides(
        () => c.castFile(
          standaloneFile,
          targetTvIp: '127.0.0.1',
          brand: TvBrand.googleTv,
        ),
        RealHttp(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await cacheSwitch.exists(), isFalse);
      expect(c.activeCacheDirectory, isNull);
      expect(await viewerPhoto.exists(), isTrue);

      await HttpOverrides.runWithHttpOverrides(
        () => c.castResolvedPlaylist(
          fileDispose,
          [() async => fileDispose],
          targetTvIp: '127.0.0.1',
          brand: TvBrand.googleTv,
          cacheDirectory: cacheDispose,
        ),
        RealHttp(),
      );
      expect(c.activeCacheDirectory?.path, cacheDispose.path);
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await cacheDispose.exists(), isFalse);
      expect(c.activeCacheDirectory, isNull);
      expect(await viewerPhoto.exists(), isTrue);
    },
  );

  test(
    'RES-01: thumbnail timeout and operation cancellation terminate FFmpeg subprocesses and deduplicate in-flight calls',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final accepted = Completer<void>();
        final hanging = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        hanging.listen((request) {
          if (!accepted.isCompleted) accepted.complete();
        });
        final markerTimeout = 'sixf-audit-stall-${hanging.port}';
        final markerCancel = 'sixf-audit-cancel-${hanging.port}';
        final pids = <int>[];
        addTearDown(() async {
          for (final pid in pids) {
            Process.killPid(pid);
          }
          await hanging.close(force: true);
        });
        final urlTimeout = 'http://127.0.0.1:${hanging.port}/$markerTimeout';
        final firstCall = MediaRemuxService.extractVideoThumbnail(urlTimeout);
        final duplicateCall = MediaRemuxService.extractVideoThumbnail(
          urlTimeout,
        );
        expect(identical(firstCall, duplicateCall), isTrue);
        final result = await firstCall;
        expect(result, isNull);
        expect(await duplicateCall, isNull);

        pids.addAll(await _findFfmpegPidsWithMarker(markerTimeout));
        expect(pids, isEmpty);

        // Now verify cancellation kills the process immediately before the 60s subtitle timeout
        final op = NetworkOperation();
        final urlCancel = 'http://127.0.0.1:${hanging.port}/$markerCancel';
        final subtitleFuture = op.run(
          () => MediaRemuxService.extractVttSubtitle(urlCancel, 0),
        );
        final cancelled = expectLater(
          subtitleFuture,
          throwsA(isA<OperationCancelled>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        op.cancel();
        await cancelled;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        final cancelPids = await _findFfmpegPidsWithMarker(markerCancel);
        pids.addAll(cancelPids);
        expect(cancelPids, isEmpty);
      }, RealHttp());
    },
  );

  test(
    'MID-04: alternate audio choice is preserved across reload, keeps position/pause/subtitle offset, rolls back on invalid track, and resets on new file',
    () async {
      final dir = await Directory.systemTemp.createTemp('sixf-audit-audio-');
      final server = LocalMediaServer();
      final casts = <SimulatedCast>[];
      final c = MediaCastController(
        serverService: server,
        castFactory: () {
          final cast = SimulatedCast();
          casts.add(cast);
          return cast;
        },
        probeMedia: (_) async => const MediaDetails(
          duration: Duration(seconds: 600),
          tracks: [
            MediaTrack(id: 1, type: 'audio', title: 'Default', isDefault: true),
            MediaTrack(id: 2, type: 'audio', title: 'Alternate'),
            MediaTrack(
              id: 3,
              type: 'subtitle',
              title: 'Português',
              language: 'por',
              isDefault: true,
            ),
          ],
        ),
      );
      addTearDown(() async {
        c.dispose();
        await server.stop();
        await dir.delete(recursive: true);
      });
      final f1 = File('${dir.path}/movie.mkv')..writeAsBytesSync([1]);
      final f2 = File('${dir.path}/other.mkv')..writeAsBytesSync([2]);
      await HttpOverrides.runWithHttpOverrides(() async {
        expect(
          await c.castFile(
            f1,
            targetTvIp: '127.0.0.1',
            brand: TvBrand.googleTv,
          ),
          isTrue,
        );
        expect(c.selectedAudioTrack?.id, 1);
        await c.pause();
        expect(await c.seekTo(const Duration(seconds: 75)), isTrue);
        expect(c.isPaused, isTrue);
        expect(c.currentPosition, const Duration(seconds: 75));

        await c.selectAudioTrack(c.audioTracks.last);
        expect(c.selectedAudioTrack?.id, 2);
        expect(c.currentPosition, const Duration(seconds: 75));
        expect(c.isPaused, isTrue);
        expect(server.remuxStart, const Duration(seconds: 75));

        // Requesting a non-existent audio track rolls back to track 2 and keeps state
        await c.selectAudioTrack(
          const MediaTrack(id: 99, type: 'audio', title: 'Missing'),
        );
        expect(c.selectedAudioTrack?.id, 2);
        expect(c.currentPosition, const Duration(seconds: 75));
        expect(c.isPaused, isTrue);

        // Loading a different file resets to the default audio track (id: 1)
        expect(
          await c.castFile(
            f2,
            targetTvIp: '127.0.0.1',
            brand: TvBrand.googleTv,
          ),
          isTrue,
        );
        expect(c.selectedAudioTrack?.id, 1);
      }, RealHttp());
    },
  );

  test(
    'MID-02: concurrent GETs on the same active URL do not kill each other and respect concurrency limit',
    () async {
      if (!await MediaRemuxService.isFfmpegAvailable()) return;
      await HttpOverrides.runWithHttpOverrides(() async {
        final dir = await Directory.systemTemp.createTemp('sixf-audit-http-');
        final server = LocalMediaServer();
        final client = HttpClient();
        final processes = <Process>[];
        addTearDown(() async {
          client.close(force: true);
          await server.stop();
          for (final p in processes) {
            p.kill();
          }
          await dir.delete(recursive: true);
        });
        await server.start();
        server.serveFile(
          File('${dir.path}/dummy.mkv')..writeAsBytesSync([1]),
          mimeType: 'video/mp4',
          remuxProcessFactory: () async {
            final p = await Process.start('ffmpeg', [
              '-v',
              'error',
              '-re',
              '-f',
              'lavfi',
              '-i',
              'color=black:size=160x90:rate=10',
              '-t',
              '30',
              '-c:v',
              'libx264',
              '-tune',
              'zerolatency',
              '-g',
              '10',
              '-movflags',
              'frag_keyframe+empty_moov',
              '-f',
              'mp4',
              'pipe:1',
            ]);
            processes.add(p);
            return p;
          },
        );
        final url = Uri.parse((await server.getMediaUrlForTv('127.0.0.1'))!);
        final subs = <StreamSubscription<List<int>>>[];
        final chunkCompleters = <Completer<void>>[];
        var firstExited = false;

        for (var i = 0; i < MediaServerService.maxConcurrentRemuxStreams; i++) {
          final res = await (await client.getUrl(url)).close();
          expect(res.statusCode, HttpStatus.ok);
          if (i == 0) {
            unawaited(
              processes.first.exitCode.then((_) {
                firstExited = true;
              }),
            );
          }
          final c = Completer<void>();
          chunkCompleters.add(c);
          subs.add(
            res.listen((chunk) {
              if (chunk.isNotEmpty && !c.isCompleted) c.complete();
            }),
          );
        }

        await Future.wait(
          chunkCompleters.map(
            (c) => c.future.timeout(const Duration(seconds: 6)),
          ),
        );
        expect(
          processes.length,
          MediaServerService.maxConcurrentRemuxStreams,
        );
        expect(firstExited, isFalse);

        // Exceeding maxConcurrentRemuxStreams returns 503 without spawning an extra process
        final overflowRes = await (await client.getUrl(url)).close();
        await overflowRes.drain<void>();
        expect(overflowRes.statusCode, HttpStatus.serviceUnavailable);
        expect(
          processes.length,
          MediaServerService.maxConcurrentRemuxStreams,
        );

        await server.stop();
        await Future.wait(
          processes.map(
            (p) => p.exitCode.timeout(const Duration(seconds: 4)),
          ),
        );
        expect(firstExited, isTrue);
        for (final sub in subs) {
          await sub.cancel();
        }
      }, RealHttp());
    },
  );

  test(
    'MID-02b: Stop or media switch while remux factory is pending kills the late process without serving the cancelled session',
    () async {
      if (!await MediaRemuxService.isFfmpegAvailable()) return;
      await HttpOverrides.runWithHttpOverrides(() async {
        final dir = await Directory.systemTemp.createTemp('sixf-audit-late-');
        final server = LocalMediaServer();
        final client = HttpClient();
        final spawned = <Process>[];
        addTearDown(() async {
          client.close(force: true);
          await server.stop();
          for (final p in spawned) {
            p.kill();
          }
          await dir.delete(recursive: true);
        });
        await server.start();
        final dummyA = File('${dir.path}/a.mkv')..writeAsBytesSync([1]);
        final dummyB = File('${dir.path}/b.mkv')..writeAsBytesSync([2]);

        Future<Process> spawnLiveProcess() async {
          final p = await Process.start('ffmpeg', [
            '-v',
            'error',
            '-re',
            '-f',
            'lavfi',
            '-i',
            'color=black:size=160x90:rate=10',
            '-t',
            '30',
            '-c:v',
            'libx264',
            '-tune',
            'zerolatency',
            '-g',
            '10',
            '-movflags',
            'frag_keyframe+empty_moov',
            '-f',
            'mp4',
            'pipe:1',
          ]);
          spawned.add(p);
          return p;
        }

        // Case 1: Media switch (serveFile) while remuxProcessFactory is awaiting creation
        final factoryEnteredSwitch = Completer<void>();
        final factoryGateSwitch = Completer<Process?>();
        server.serveFile(
          dummyA,
          mimeType: 'video/mp4',
          remuxProcessFactory: () {
            if (!factoryEnteredSwitch.isCompleted) {
              factoryEnteredSwitch.complete();
            }
            return factoryGateSwitch.future;
          },
        );
        final urlA = Uri.parse((await server.getMediaUrlForTv('127.0.0.1'))!);
        final pendingResponseA = (await client.getUrl(urlA)).close();
        await factoryEnteredSwitch.future.timeout(const Duration(seconds: 2));

        // Switch media before the first factory finishes creating its process
        server.serveFile(
          dummyB,
          mimeType: 'video/mp4',
          remuxProcessFactory: spawnLiveProcess,
        );
        final lateProcessSwitch = await spawnLiveProcess();
        factoryGateSwitch.complete(lateProcessSwitch);

        final resA = await pendingResponseA;
        final bodyA = await resA.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        expect(resA.statusCode, HttpStatus.gone);
        expect(bodyA, isEmpty);
        await lateProcessSwitch.exitCode.timeout(const Duration(seconds: 4));

        // Case 2: Stop while remuxProcessFactory is awaiting creation
        final factoryEnteredStop = Completer<void>();
        final factoryGateStop = Completer<Process?>();
        server.serveFile(
          dummyB,
          mimeType: 'video/mp4',
          remuxProcessFactory: () {
            if (!factoryEnteredStop.isCompleted) {
              factoryEnteredStop.complete();
            }
            return factoryGateStop.future;
          },
        );
        final urlB = Uri.parse((await server.getMediaUrlForTv('127.0.0.1'))!);
        final pendingResponseB = (await client.getUrl(urlB))
            .close()
            .then<int?>((res) async {
              final bytes = await res.fold<List<int>>(
                <int>[],
                (a, b) => a..addAll(b),
              );
              expect(bytes, isEmpty);
              return res.statusCode;
            })
            .catchError((_) => null);
        await factoryEnteredStop.future.timeout(const Duration(seconds: 2));

        await server.stop();
        final lateProcessStop = await spawnLiveProcess();
        factoryGateStop.complete(lateProcessStop);

        final statusOrClosed = await pendingResponseB;
        expect(statusOrClosed, anyOf(isNull, equals(HttpStatus.gone)));
        await lateProcessStop.exitCode.timeout(const Duration(seconds: 4));
      }, RealHttp());
    },
  );
}
