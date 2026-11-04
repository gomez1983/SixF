import 'dart:convert';
import 'dart:io';

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
}
