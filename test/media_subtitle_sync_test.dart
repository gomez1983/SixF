import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/media_remux_service.dart';

import 'security_lifecycle_test.dart' show LocalMediaServer, RealHttp;

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'VTT shifts preserve cue IDs/settings, clip overlaps and drop past cues',
    () {
      const source =
          'WEBVTT\n\nold\n00:00.100 --> 00:01.000\nPast\n\n'
          'overlap\n00:02.000 --> 00:04.000 align:start\nTwo\nlines\n\n'
          '01:02:03.456 --> 01:02:05.789\nLater\n';
      final shifted = MediaRemuxService.retimeVtt(
        source,
        const Duration(seconds: -3),
      );
      expect(shifted, isNot(contains('Past')));
      expect(
        shifted,
        contains(
          'overlap\n00:00:00.000 --> 00:00:01.000 align:start\nTwo\nlines',
        ),
      );
      expect(shifted, contains('01:02:00.456 --> 01:02:02.789'));
      expect(
        MediaRemuxService.retimeVtt(source, const Duration(milliseconds: 500)),
        contains('00:00:02.500 --> 00:00:04.500'),
      );
    },
  );

  test('Cast baseline requires known AAC LC stereo; legacy, mono and surround normalize', () {
    for (final codec in [
      'mp2',
      'ac3',
      'eac3',
      'flac',
      'wmav2',
      'dts',
      'mp3',
      'opus',
      null,
    ]) {
      expect(
        MediaDetails(
          tracks: [
            MediaTrack(
              id: 0,
              type: 'audio',
              title: 'Audio',
              codec: codec,
              channels: 2,
              profile: 'LC',
            ),
          ],
        ).isChromecastAudioCompatible,
        isFalse,
        reason: '$codec',
      );
    }
    for (final channels in [null, 1, 6, 8]) {
      expect(
        MediaDetails(
          tracks: [
            MediaTrack(
              id: 0,
              type: 'audio',
              title: 'Audio',
              codec: 'aac',
              channels: channels,
              profile: 'LC',
            ),
          ],
        ).isChromecastAudioCompatible,
        isFalse,
      );
    }
    const good = MediaTrack(
      id: 1,
      type: 'audio',
      title: 'AAC',
      codec: 'aac',
      channels: 2,
      profile: 'LC',
      isDefault: true,
    );
    expect(
      const MediaDetails(tracks: [good]).isChromecastAudioCompatible,
      isTrue,
    );
    expect(MediaTrack.fromJson(good.toJson()).channels, 2);
    expect(MediaTrack.fromJson(good.toJson()).profile, 'LC');
    expect(const MediaDetails(tracks: []).isChromecastAudioCompatible, isTrue);
  });

  final available =
      await MediaRemuxService.isFfmpegAvailable() &&
      await MediaRemuxService.isFfprobeAvailable();
  test('real MKV PTS offset, B-frames, MP2 mono, segment and manual subtitle offsets', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final dir = await Directory.systemTemp.createTemp('sixf-sync-');
      final server = LocalMediaServer();
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.stop();
        await dir.delete(recursive: true);
      });
      final srt = File('${dir.path}/cues.srt');
      await srt.writeAsString(
        '1\n00:00:02,000 --> 00:00:04,000\nPrimeira\n\n'
        '2\n00:00:06,000 --> 00:00:08,000\nSegunda\n',
      );
      final source = File('${dir.path}/offset.mkv');
      final generated = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-f',
        'lavfi',
        '-i',
        'testsrc2=size=160x90:rate=25:duration=10',
        '-f',
        'lavfi',
        '-i',
        'sine=frequency=440:duration=10',
        '-i',
        srt.path,
        '-map',
        '0:v',
        '-map',
        '1:a',
        '-map',
        '2:s',
        '-c:v',
        'libx264',
        '-c:a',
        'mp2',
        '-c:s',
        'srt',
        '-output_ts_offset',
        '7',
        source.path,
      ]);
      expect(generated.exitCode, 0, reason: '${generated.stderr}');
      final details = await MediaRemuxService.probeMediaDetails(source.path);
      final audio = details.tracks.singleWhere((t) => t.type == 'audio');
      expect(audio.codec, 'mp2');
      expect(audio.channels, 1);
      expect(details.isChromecastAudioCompatible, isFalse);
      final sub = details.tracks.singleWhere((t) => t.type == 'subtitle');
      await server.start();
      server.serveFile(
        source,
        mimeType: 'video/mp4',
        remuxProcessFactory: () => MediaRemuxService.startRemuxProcess(
          source.path,
          startPosition: server.remuxStart,
        ),
      );
      Future<String> readVtt(String url) async {
        final res = await (await client.getUrl(Uri.parse(url))).close();
        expect(res.statusCode, 200);
        return res.transform(utf8.decoder).join();
      }

      final firstSubUrl = (await server.getSubtitleUrlForTv(
        '127.0.0.1',
        sub.id,
      ))!;
      expect(
        await readVtt(firstSubUrl),
        contains('00:00:02.000 --> 00:00:04.000'),
      );
      Future<void> checkRemux(String name, {String mime = 'video/mp4'}) async {
        final url = (await server.getMediaUrlForTv('127.0.0.1'))!;
        final response = await (await client.getUrl(Uri.parse(url))).close();
        expect(response.statusCode, 200);
        expect(response.headers.contentType?.mimeType, mime);
        final output = File('${dir.path}/$name.mp4');
        await response.pipe(output.openWrite());
        final result = await MediaRemuxService.probeMediaDetails(output.path);
        expect(result.isChromecastAudioCompatible, isTrue);
        final probe = await Process.run('ffprobe', [
          '-v',
          'error',
          '-show_entries',
          'stream=index,start_time',
          '-of',
          'json',
          output.path,
        ]);
        final streams =
            (jsonDecode(probe.stdout as String) as Map)['streams'] as List;
        for (final stream in streams) {
          expect(
            double.parse(stream['start_time'] as String),
            closeTo(0, 0.025),
          );
        }
        final pcm = await Process.run('ffmpeg', [
          '-v',
          'error',
          '-i',
          output.path,
          '-map',
          '0:a:0',
          '-f',
          's16le',
          '-t',
          '1',
          'pipe:1',
        ], stdoutEncoding: null);
        expect(pcm.exitCode, 0);
        expect((pcm.stdout as List<int>).any((v) => v != 0), isTrue);
      }

      await checkRemux('first');
      server.restartRemuxAt(const Duration(seconds: 3));
      server.setSubtitleOffset(const Duration(milliseconds: 500));
      final nextSubUrl = (await server.getSubtitleUrlForTv(
        '127.0.0.1',
        sub.id,
      ))!;
      expect(nextSubUrl, isNot(firstSubUrl));
      final vtt = await readVtt(nextSubUrl);
      expect(vtt, contains('00:00:00.000 --> 00:00:01.500'));
      expect(vtt, contains('00:00:03.500 --> 00:00:05.500'));
      // Each URL retains its own timeline if the receiver retries an old load
      // or a new LOAD is refused. Changing files still revokes every old URL.
      expect(
        await readVtt(firstSubUrl),
        contains('00:00:02.000 --> 00:00:04.000'),
      );
      await checkRemux('seek');
      // The conservative AAC policy also covers music. An absent video stream
      // must not turn a legacy audio-only file into an empty/failed MP4.
      final audioOnly = File('${dir.path}/legacy.mp2');
      final extractedAudio = await Process.run('ffmpeg', [
        '-v',
        'error',
        '-i',
        source.path,
        '-map',
        '0:a:0',
        '-c:a',
        'copy',
        audioOnly.path,
      ]);
      expect(extractedAudio.exitCode, 0);
      server.serveFile(
        audioOnly,
        mimeType: 'audio/mp4',
        remuxProcessFactory: () =>
            MediaRemuxService.startRemuxProcess(audioOnly.path),
      );
      await checkRemux('audio-only', mime: 'audio/mp4');
    }, RealHttp());
  }, skip: available ? false : 'FFmpeg/ffprobe não disponíveis');
}
