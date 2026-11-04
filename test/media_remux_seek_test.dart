import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/media_remux_service.dart';

import 'security_lifecycle_test.dart' show LocalMediaServer, RealHttp;

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final available =
      await MediaRemuxService.isFfmpegAvailable() &&
      await MediaRemuxService.isFfprobeAvailable();

  test(
    'WEBP becomes PNG and embedded Portuguese subtitles are served as WebVTT',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final dir = await Directory.systemTemp.createTemp('sixf-formats-');
        final server = LocalMediaServer();
        final client = HttpClient();
        addTearDown(() async {
          client.close(force: true);
          await server.stop();
          await dir.delete(recursive: true);
        });
        final webp = File('${dir.path}/photo.webp');
        final generated = await Process.run('ffmpeg', [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=red:s=64x64',
          '-frames:v',
          '1',
          webp.path,
        ]);
        expect(generated.exitCode, 0);
        final png = await MediaRemuxService.convertImageOrAnimationForCast(
          webp,
        );
        expect(png.path.endsWith('.png'), isTrue);
        expect((await png.readAsBytes()).take(8), [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ]);
        await png.delete();
        final srt = File('${dir.path}/pt.srt');
        await srt.writeAsString(
          '1\n00:00:01,000 --> 00:00:03,000\nOlá, Homem-Aranha!\n',
        );
        final mkv = File('${dir.path}/movie.mkv');
        final mux = await Process.run('ffmpeg', [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=black:s=64x64:r=1',
          '-i',
          srt.path,
          '-t',
          '4',
          '-c:v',
          'libx264',
          '-c:s',
          'srt',
          '-metadata:s:s:0',
          'language=por',
          mkv.path,
        ]);
        expect(mux.exitCode, 0, reason: '${mux.stderr}');
        final details = await MediaRemuxService.probeMediaDetails(mkv.path);
        final track = details.tracks.singleWhere((t) => t.type == 'subtitle');
        expect(track.language, 'por');
        await server.start();
        server.serveFile(mkv);
        final text = await server.prepareSubtitle(track.id);
        expect(text, startsWith('WEBVTT'));
        expect(text, contains('Olá, Homem-Aranha!'));
        final uri = Uri.parse(
          (await server.getSubtitleUrlForTv('127.0.0.1', track.id))!,
        );
        final options = await (await client.openUrl('OPTIONS', uri)).close();
        expect(options.statusCode, 204);
        await options.drain<void>();
        final res = await (await client.getUrl(uri)).close();
        expect(res.headers.contentType?.mimeType, 'text/vtt');
        expect(res.headers.value('Access-Control-Allow-Origin'), '*');
        expect(
          await res.transform(utf8.decoder).join(),
          contains('Homem-Aranha'),
        );
      }, RealHttp());
    },
    skip: available ? false : 'FFmpeg/ffprobe não disponíveis',
  );

  test(
    'duration parsing handles format, stream fallback and invalid values',
    () {
      expect(
        MediaRemuxService.parseDuration({
          'format': {'duration': '7200.5'},
        }),
        const Duration(milliseconds: 7200500),
      );
      expect(
        MediaRemuxService.parseDuration({
          'streams': [
            {'duration': '3'},
            {'duration': '7.25'},
          ],
        }),
        const Duration(milliseconds: 7250),
      );
      expect(
        MediaRemuxService.parseDuration({
          'format': {'duration': 'NaN'},
        }),
        Duration.zero,
      );
    },
  );

  test('real FFmpeg HTTP remux restarts at requested input position', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final dir = await Directory.systemTemp.createTemp('sixf-remux-test-');
      final server = LocalMediaServer();
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
        await dir.delete(recursive: true);
      });
      final source = File('${dir.path}/source.mkv');
      final generated = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'testsrc=size=64x64:rate=24',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440',
        '-t',
        '4',
        '-c:v',
        'libx264',
        '-pix_fmt',
        'yuv420p',
        '-g',
        '24',
        '-c:a',
        'aac',
        source.path,
      ]).timeout(const Duration(seconds: 15));
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      final details = await MediaRemuxService.probeMediaDetails(source.path);
      expect(details.duration.inMilliseconds, greaterThanOrEqualTo(4000));
      await server.start();
      server.serveFile(
        source,
        mimeType: 'video/mp4',
        remuxProcessFactory: () => MediaRemuxService.startRemuxProcess(
          source.path,
          startPosition: server.remuxStart,
        ),
      );
      final firstUrl = await server.getMediaUrlForTv('127.0.0.1');
      final head = await (await client.headUrl(Uri.parse(firstUrl!))).close();
      expect(head.headers.value('accept-ranges'), 'none');
      await head.drain<void>();
      server.restartRemuxAt(const Duration(seconds: 2));
      final nextUrl = await server.getMediaUrlForTv('127.0.0.1');
      expect(nextUrl, isNot(firstUrl));
      final obsolete = await (await client.getUrl(Uri.parse(firstUrl))).close();
      expect(obsolete.statusCode, HttpStatus.notFound);
      await obsolete.drain<void>();
      final response = await (await client.getUrl(Uri.parse(nextUrl!))).close();
      expect(response.statusCode, HttpStatus.ok);
      final output = File('${dir.path}/result.mp4');
      await response.pipe(output.openWrite());
      final remuxed = await MediaRemuxService.probeMediaDetails(output.path);
      expect(remuxed.duration.inMilliseconds, inInclusiveRange(1700, 2400));
      expect(remuxed.videoCodec, 'h264');
    }, RealHttp());
  }, skip: available ? false : 'FFmpeg/ffprobe não disponíveis');

  test('long-GOP video emits short decodable fragments after forward and backward seeks', () async {
    final dir = await Directory.systemTemp.createTemp('sixf-long-gop-');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/long-gop.mkv');
    final generated = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=1920x1080:rate=30:duration=36',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:duration=36',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-g',
      '900',
      '-sc_threshold',
      '0',
      '-c:a',
      'aac',
      source.path,
    ]);
    expect(generated.exitCode, 0, reason: '${generated.stderr}');
    for (final seconds in [0.0, 25.5, 3.25]) {
      final process = await MediaRemuxService.startRemuxProcess(
        source.path,
        startPosition: Duration(milliseconds: (seconds * 1000).round()),
      );
      expect(process, isNotNull);
      final errors = process!.stderr.transform(utf8.decoder).join();
      final output = File('${dir.path}/segment-$seconds.mp4');
      await process.stdout.pipe(output.openWrite());
      expect(await process.exitCode, 0, reason: await errors);
      final bytes = await output.readAsBytes();
      final boxes = <({int start, int end})>[];
      for (var pos = 0; pos + 8 <= bytes.length;) {
        final size = ByteData.sublistView(bytes).getUint32(pos);
        expect(size, greaterThanOrEqualTo(8));
        final type = ascii.decode(bytes.sublist(pos + 4, pos + 8));
        if (type == 'mdat') boxes.add((start: pos, end: pos + size));
        pos += size;
      }
      expect(boxes.length, greaterThan(2));
      final probe = await Process.run('ffprobe', [
        '-v',
        'error',
        '-select_streams',
        'v:0',
        '-show_packets',
        '-show_entries',
        'packet=pts_time,pos,flags',
        '-of',
        'json',
        output.path,
      ]);
      final packets =
          (jsonDecode(probe.stdout as String) as Map)['packets'] as List;
      final firstFragment = packets
          .where((p) => int.parse(p['pos']) < boxes.first.end)
          .toList();
      // With the old default GOP, seek output buffered ~8.3 seconds before
      // the first fragment. Measure media duration rather than CPU wall time.
      final firstPts = double.parse(firstFragment.first['pts_time']);
      final lastPts = double.parse(firstFragment.last['pts_time']);
      expect(firstPts, inInclusiveRange(0, 0.05));
      expect(
        lastPts - firstPts,
        lessThanOrEqualTo(1.05),
        reason: 'seek $seconds',
      );
      expect(firstFragment.first['flags'], contains('K'));
      final decoded = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-i',
        output.path,
        '-t',
        '2',
        '-f',
        'null',
        '-',
      ]);
      expect(decoded.exitCode, 0, reason: '${decoded.stderr}');
      // Decode errors are often logged without a nonzero exit status.
      expect((decoded.stderr as String).trim(), isEmpty);
    }
  }, skip: available ? false : 'FFmpeg/ffprobe não disponíveis');

  test(
    'Stop or media switch while remux factory is pending terminates the late process without serving the cancelled session',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final dir = await Directory.systemTemp.createTemp('sixf-remux-late-');
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
    skip: available ? false : 'FFmpeg/ffprobe não disponíveis',
  );
}
