import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'network_operation.dart';

class MediaTrack {
  const MediaTrack({
    required this.id,
    required this.type,
    required this.title,
    this.language,
    this.codec,
    this.channels,
    this.profile,
    this.isDefault = false,
  });

  final int id;
  final String type; // 'audio' or 'subtitle'
  final String title;
  final String? language;
  final String? codec;
  final int? channels;
  final String? profile;
  final bool isDefault;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'language': language,
    'codec': codec,
    'channels': channels,
    'profile': profile,
    'isDefault': isDefault,
  };

  factory MediaTrack.fromJson(Map<String, dynamic> json) => MediaTrack(
    id: json['id'] as int,
    type: json['type'] as String,
    title: json['title'] as String,
    language: json['language'] as String?,
    codec: json['codec'] as String?,
    channels: json['channels'] as int?,
    profile: json['profile'] as String?,
    isDefault: json['isDefault'] == true,
  );
}

class MediaDetails {
  const MediaDetails({
    required this.tracks,
    this.videoCodec,
    this.videoPixFmt,
    this.videoBitRate,
    this.width,
    this.height,
    this.duration = Duration.zero,
  });

  final List<MediaTrack> tracks;
  final String? videoCodec;
  final String? videoPixFmt;
  final int? videoBitRate;
  final int? width;
  final int? height;
  final Duration duration;

  /// Indica se o codec de vídeo é nativamente suportado pelo decodificador de hardware do Chromecast.
  /// Formatos como MPEG-4 ASP (XviD/DivX), MPEG-2, 10-bit H.264 ou remuxes Blu-ray de altíssimo bitrate exigem transcodificação.
  bool get isChromecastVideoCompatible {
    if (videoCodec == null) return true;
    final codec = videoCodec!.toLowerCase();
    if (codec == 'mjpeg' ||
        codec == 'png' ||
        codec == 'bmp' ||
        codec == 'webp' ||
        codec == 'gif') {
      return true;
    }
    if (codec != 'h264' && codec != 'vp8') {
      return false;
    }
    if (videoPixFmt != null &&
        videoPixFmt != 'yuv420p' &&
        videoPixFmt != 'yuvj420p') {
      return false;
    }
    if (videoBitRate != null && videoBitRate! > 12000000) {
      return false;
    }
    return true;
  }

  /// Indica se a faixa de Ã¡udio padrÃ£o Ã© nativamente decodificada pelo Chromecast.
  /// Trilhas em DTS, DTS-HD, TrueHD ou multicanal sem AAC resultam em filme mudo.
  bool get isChromecastAudioCompatible {
    final audios = tracks.where((t) => t.type == 'audio').toList();
    if (audios.isEmpty) return true;
    final defaultAudio =
        audios.where((t) => t.isDefault).firstOrNull ?? audios.first;
    final codec = defaultAudio.codec?.toLowerCase();
    // Conservative MP4 baseline, independent of receiver/surround passthrough.
    // Unknown channel counts/profiles also require normalization.
    return codec == 'aac' &&
        defaultAudio.channels == 2 &&
        defaultAudio.profile?.toLowerCase() == 'lc';
  }
}

class MediaRemuxService {
  static final Map<String, String> _thumbnailCache = {};
  static final Map<String, Future<String?>> _inFlightThumbnails = {};
  static final Map<String, String> _convertedMediaCache = {};
  static bool? _hasFfmpeg;
  static bool? _hasFfprobe;

  static Future<({int exitCode, String stdout})?> _runProcess(
    String executable,
    List<String> args, {
    required Duration timeout,
    bool captureStdout = false,
  }) async {
    Process? process;
    try {
      final operation = NetworkOperation.current;
      operation?.check();
      process = await Process.start(executable, args);
      operation?.onCancel(() {
        process?.kill();
      });
      unawaited(process.stderr.drain<void>().catchError((_) {}));
      final Future<String> stdoutFuture = captureStdout
          ? process.stdout.transform(utf8.decoder).join().catchError((_) => '')
          : process.stdout.drain<void>().then((_) => '').catchError((_) => '');
      final exitCode = await process.exitCode.timeout(timeout);
      final stdoutText = await stdoutFuture.timeout(
        const Duration(seconds: 1),
        onTimeout: () => '',
      );
      operation?.check();
      return (exitCode: exitCode, stdout: stdoutText);
    } catch (_) {
      return null;
    } finally {
      if (process != null) {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(milliseconds: 250));
        } catch (_) {}
      }
    }
  }

  static Future<bool> isFfmpegAvailable() async {
    if (_hasFfmpeg != null) return _hasFfmpeg!;
    final res = await _runProcess(
      'ffmpeg',
      ['-version'],
      timeout: const Duration(seconds: 2),
    );
    return _hasFfmpeg = (res != null && res.exitCode == 0);
  }

  static Future<bool> isFfprobeAvailable() async {
    if (_hasFfprobe != null) return _hasFfprobe!;
    final res = await _runProcess(
      'ffprobe',
      ['-version'],
      timeout: const Duration(seconds: 2),
    );
    return _hasFfprobe = (res != null && res.exitCode == 0);
  }

  /// Extrai miniatura (thumbnail) de vÃ­deo local via FFmpeg de forma ultra-leve.
  static Future<String?> extractVideoThumbnail(String videoPath) {
    if (_thumbnailCache.containsKey(videoPath)) {
      return Future<String?>.value(_thumbnailCache[videoPath]);
    }
    final inFlight = _inFlightThumbnails[videoPath];
    if (inFlight != null) return inFlight;
    late final Future<String?> future;
    future = _extractVideoThumbnailImpl(videoPath).whenComplete(() {
      if (identical(_inFlightThumbnails[videoPath], future)) {
        _inFlightThumbnails.remove(videoPath);
      }
    });
    _inFlightThumbnails[videoPath] = future;
    return future;
  }

  static Future<String?> _extractVideoThumbnailImpl(String videoPath) async {
    if (_thumbnailCache.containsKey(videoPath)) {
      return _thumbnailCache[videoPath];
    }
    if (!await isFfmpegAvailable()) return null;

    File? target;
    try {
      final tempDir = Directory.systemTemp;
      final hash = videoPath.hashCode.abs().toString();
      target = File('${tempDir.path}\\sixf_thumb_$hash.jpg');

      if (await target.exists() && await target.length() > 0) {
        return _thumbnailCache[videoPath] = target.path;
      }

      final res = await _runProcess(
        'ffmpeg',
        [
          '-ss',
          '00:00:03',
          '-i',
          videoPath,
          '-vframes',
          '1',
          '-vf',
          'scale=160:-1',
          '-q:v',
          '5',
          '-y',
          target.path,
        ],
        timeout: const Duration(seconds: 4),
      );

      if (res != null &&
          res.exitCode == 0 &&
          await target.exists() &&
          await target.length() > 0) {
        return _thumbnailCache[videoPath] = target.path;
      }
      if (await target.exists()) {
        try {
          await target.delete();
        } catch (_) {}
      }
    } catch (_) {
      if (target != null) {
        try {
          if (await target.exists()) await target.delete();
        } catch (_) {}
      }
    }
    return null;
  }

  /// Converte imagens ou animaÃ§Ãµes (como WEBP e GIF) para formatos universais para Chromecast.
  /// Se for vÃ­deo/animaÃ§Ã£o com mÃºltiplos quadros, converte para MP4 universal.
  /// Se for foto estÃ¡tica, converte para PNG.
  static Future<File> convertImageOrAnimationForCast(File sourceFile) async {
    final path = sourceFile.path.toLowerCase();
    if (!path.endsWith('.webp') && !path.endsWith('.gif')) {
      return sourceFile;
    }
    if (path.endsWith('.webp')) {
      final codec = await ui.instantiateImageCodec(
        await sourceFile.readAsBytes(),
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final bytes = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (bytes == null) {
            throw StateError('NÃ£o foi possÃ­vel converter a foto WEBP.');
          }
          final stat = await sourceFile.stat();
          final target = File(
            '${Directory.systemTemp.path}/sixf_webp_${sourceFile.path.hashCode}_${stat.modified.millisecondsSinceEpoch}.png',
          );
          await target.writeAsBytes(bytes.buffer.asUint8List());
          return target;
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    }
    if (!await isFfmpegAvailable()) return sourceFile;

    if (_convertedMediaCache.containsKey(sourceFile.path)) {
      final cached = File(_convertedMediaCache[sourceFile.path]!);
      if (await cached.exists()) return cached;
    }

    try {
      final tempDir = Directory.systemTemp;
      final hash = sourceFile.path.hashCode.abs().toString();

      // Inspeciona se possui mÃºltiplos quadros ou stream de vÃ­deo ativo
      final details = await probeMediaDetails(sourceFile.path);
      final isAnimationOrVideo =
          path.endsWith('.gif') ||
          details.videoCodec == 'webp' ||
          details.videoCodec == 'gif';

      if (isAnimationOrVideo) {
        final targetMp4 = File('${tempDir.path}\\sixf_conv_$hash.mp4');
        if (await targetMp4.exists() && await targetMp4.length() > 0) {
          _convertedMediaCache[sourceFile.path] = targetMp4.path;
          return targetMp4;
        }

        final res = await _runProcess(
          'ffmpeg',
          [
            '-v',
            'error',
            '-stream_loop',
            '4',
            '-t',
            '12',
            '-i',
            sourceFile.path,
            '-vf',
            "scale='min(1280,trunc(iw/2)*2)':trunc(ow/a/2)*2",
            '-c:v',
            'libx264',
            '-preset',
            'ultrafast',
            '-pix_fmt',
            'yuv420p',
            '-movflags',
            'faststart',
            '-y',
            targetMp4.path,
          ],
          timeout: const Duration(seconds: 8),
        );

        if (res != null &&
            res.exitCode == 0 &&
            await targetMp4.exists() &&
            await targetMp4.length() > 0) {
          _convertedMediaCache[sourceFile.path] = targetMp4.path;
          return targetMp4;
        }
        if (await targetMp4.exists()) {
          try {
            await targetMp4.delete();
          } catch (_) {}
        }
      } else {
        final targetPng = File('${tempDir.path}\\sixf_conv_$hash.png');
        if (await targetPng.exists() && await targetPng.length() > 0) {
          _convertedMediaCache[sourceFile.path] = targetPng.path;
          return targetPng;
        }

        final res = await _runProcess(
          'ffmpeg',
          [
            '-v',
            'error',
            '-i',
            sourceFile.path,
            '-y',
            targetPng.path,
          ],
          timeout: const Duration(seconds: 4),
        );

        if (res != null &&
            res.exitCode == 0 &&
            await targetPng.exists() &&
            await targetPng.length() > 0) {
          _convertedMediaCache[sourceFile.path] = targetPng.path;
          return targetPng;
        }
        if (await targetPng.exists()) {
          try {
            await targetPng.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}

    return sourceFile;
  }

  /// Inspeciona detalhadamente codecs de vÃ­deo e todas as faixas de Ã¡udio e legendas de um arquivo ou stream.
  static Future<MediaDetails> probeMediaDetails(
    String inputPathOrUrl, {
    Map<String, String>? headers,
  }) async {
    if (!await isFfprobeAvailable()) {
      return const MediaDetails(tracks: []);
    }

    try {
      final args = <String>[
        '-v',
        'quiet',
        '-print_format',
        'json',
        '-show_streams',
        '-show_format',
      ];
      if (headers != null && headers.isNotEmpty) {
        final headerStr = headers.entries
            .map((e) => '${e.key}: ${e.value}\r\n')
            .join();
        args.addAll([
          '-probesize',
          '2000000',
          '-analyzeduration',
          '2000000',
          '-headers',
          headerStr,
        ]);
      }
      args.add(inputPathOrUrl);

      final res = await _runProcess(
        'ffprobe',
        args,
        timeout: const Duration(seconds: 6),
        captureStdout: true,
      );
      if (res == null || res.exitCode != 0 || res.stdout.isEmpty) {
        return const MediaDetails(tracks: []);
      }

      final data = jsonDecode(res.stdout) as Map<String, dynamic>;
      final streams = (data['streams'] as List?) ?? [];
      final format = data['format'] as Map?;
      final formatBitRate = int.tryParse('${format?['bit_rate']}');
      final tracks = <MediaTrack>[];
      String? videoCodec;
      String? videoPixFmt;
      int? videoBitRate;
      int? width;
      int? height;

      const bitmapSubtitleCodecs = {
        'hdmv_pgs_subtitle',
        'pgssub',
        'dvd_subtitle',
        'dvdsub',
        'dvb_subtitle',
        'dvbsub',
        'xsub',
        'hdmv_text_subtitle',
      };

      for (var i = 0; i < streams.length; i++) {
        final s = streams[i] as Map<String, dynamic>;
        final codecType = s['codec_type'] as String?;

        if (codecType == 'video' && videoCodec == null) {
          videoCodec = s['codec_name'] as String?;
          videoPixFmt = s['pix_fmt'] as String?;
          width = (s['width'] as num?)?.toInt();
          height = (s['height'] as num?)?.toInt();
          final vTags = (s['tags'] as Map<String, dynamic>?) ?? {};
          videoBitRate =
              int.tryParse('${s['bit_rate']}') ??
              int.tryParse('${vTags['BPS']}') ??
              int.tryParse('${vTags['BPS-eng']}') ??
              formatBitRate;
          continue;
        }

        if (codecType != 'audio' && codecType != 'subtitle') continue;

        final tags = (s['tags'] as Map<String, dynamic>?) ?? {};
        final rawTitle = tags['title'] as String?;
        final lang = tags['language'] as String? ?? tags['lang'] as String?;
        final disp = (s['disposition'] as Map<String, dynamic>?) ?? {};
        final isDef = disp['default'] == 1;
        final codecName = s['codec_name'] as String?;

        if (codecType == 'subtitle' &&
            codecName != null &&
            bitmapSubtitleCodecs.contains(codecName.toLowerCase())) {
          continue;
        }

        String displayTitle;
        if (rawTitle != null && rawTitle.trim().isNotEmpty) {
          displayTitle = rawTitle.trim();
          if (lang != null &&
              !displayTitle.toLowerCase().contains(lang.toLowerCase())) {
            displayTitle = '$displayTitle [${lang.toUpperCase()}]';
          }
        } else if (lang != null && lang.isNotEmpty) {
          final langName = _mapLanguageName(lang);
          displayTitle = codecType == 'audio'
              ? 'Ãudio $langName'
              : 'Legenda $langName';
        } else {
          final count = tracks.where((t) => t.type == codecType).length + 1;
          displayTitle = codecType == 'audio'
              ? 'Ãudio $count'
              : 'Legenda $count';
        }

        tracks.add(
          MediaTrack(
            id: s['index'] as int? ?? i,
            type: codecType!,
            title: displayTitle,
            language: lang,
            codec: codecName,
            channels: (s['channels'] as num?)?.toInt(),
            profile: s['profile'] as String?,
            isDefault: isDef,
          ),
        );
      }

      return MediaDetails(
        duration: parseDuration(data),
        tracks: tracks,
        videoCodec: videoCodec,
        videoPixFmt: videoPixFmt,
        videoBitRate: videoBitRate,
        width: width,
        height: height,
      );
    } catch (_) {
      return const MediaDetails(tracks: []);
    }
  }

  static Duration parseDuration(Map<String, dynamic> data) {
    final format = data['format'] as Map?;
    final seconds = double.tryParse('${format?['duration']}');
    if (seconds != null && seconds.isFinite && seconds > 0) {
      return Duration(milliseconds: (seconds * 1000).round());
    }
    var longest = 0.0;
    for (final stream in (data['streams'] as List? ?? [])) {
      final value = double.tryParse('${stream['duration']}');
      if (value != null && value.isFinite && value > longest) longest = value;
    }
    return Duration(milliseconds: (longest * 1000).round());
  }

  /// Mapeia siglas ISO de idiomas para nomes legÃ­veis em portuguÃªs.
  static String _mapLanguageName(String code) {
    final lower = code.toLowerCase();
    switch (lower) {
      case 'por':
      case 'pt':
      case 'pt-br':
        return 'PortuguÃªs';
      case 'eng':
      case 'en':
        return 'InglÃªs';
      case 'spa':
      case 'es':
        return 'Espanhol';
      case 'fre':
      case 'fra':
      case 'fr':
        return 'FrancÃªs';
      case 'ger':
      case 'deu':
      case 'de':
        return 'AlemÃ£o';
      case 'ita':
      case 'it':
        return 'Italiano';
      case 'jpn':
      case 'ja':
        return 'JaponÃªs';
      case 'chi':
      case 'zho':
      case 'zh':
        return 'ChinÃªs';
      case 'kor':
      case 'ko':
        return 'Coreano';
      case 'rus':
      case 'ru':
        return 'Russo';
      case 'dan':
      case 'da':
        return 'DinamarquÃªs';
      case 'dut':
      case 'nl':
        return 'HolandÃªs';
      case 'fin':
      case 'fi':
        return 'FinlandÃªs';
      case 'gre':
      case 'el':
        return 'Grego';
      case 'nor':
      case 'no':
        return 'NorueguÃªs';
      case 'pol':
      case 'pl':
        return 'PolonÃªs';
      case 'swe':
      case 'sv':
        return 'Sueco';
      case 'tur':
      case 'tr':
        return 'Turco';
      default:
        return code.toUpperCase();
    }
  }

  /// Converte códigos ISO-639-1 / ISO-639-2 em tags BCP 47 / RFC 5646 válidas para Chromecast.
  static String toBcp47(String? code) {
    if (code == null || code.trim().isEmpty) return 'und';
    final lower = code.toLowerCase().trim();
    switch (lower) {
      case 'por':
      case 'pt':
      case 'pt-br':
      case 'pob':
        return 'pt-BR';
      case 'eng':
      case 'en':
        return 'en';
      case 'spa':
      case 'es':
        return 'es';
      case 'fre':
      case 'fra':
      case 'fr':
        return 'fr';
      case 'ger':
      case 'deu':
      case 'de':
        return 'de';
      case 'ita':
      case 'it':
        return 'it';
      case 'jpn':
      case 'ja':
        return 'ja';
      case 'chi':
      case 'zho':
      case 'zh':
        return 'zh';
      case 'kor':
      case 'ko':
        return 'ko';
      case 'rus':
      case 'ru':
        return 'ru';
      case 'dan':
      case 'da':
        return 'da';
      case 'dut':
      case 'nld':
      case 'nl':
        return 'nl';
      case 'fin':
      case 'fi':
        return 'fi';
      case 'gre':
      case 'ell':
      case 'el':
        return 'el';
      case 'nor':
      case 'nob':
      case 'no':
        return 'no';
      case 'pol':
      case 'pl':
        return 'pl';
      case 'swe':
      case 'sv':
        return 'sv';
      case 'cze':
      case 'ces':
      case 'cs':
        return 'cs';
      case 'hun':
      case 'hu':
        return 'hu';
      case 'tur':
      case 'tr':
        return 'tr';
      case 'bul':
      case 'bg':
        return 'bg';
      case 'rum':
      case 'ron':
      case 'ro':
        return 'ro';
      case 'slo':
      case 'slk':
      case 'sk':
        return 'sk';
      case 'slv':
      case 'sl':
        return 'sl';
      case 'hrv':
      case 'hr':
        return 'hr';
      case 'srp':
      case 'sr':
        return 'sr';
      case 'tha':
      case 'th':
        return 'th';
      case 'ind':
      case 'id':
        return 'id';
      case 'ice':
      case 'isl':
      case 'is':
        return 'is';
      case 'est':
      case 'et':
        return 'et';
      case 'lit':
      case 'lt':
        return 'lt';
      case 'lav':
      case 'lv':
        return 'lv';
      case 'heb':
      case 'he':
        return 'he';
      case 'ara':
      case 'ar':
        return 'ar';
      default:
        return lower.length == 2 ? lower : 'und';
    }
  }

  /// Inspeciona as faixas de Ã¡udio e legendas de um arquivo ou stream.
  static Future<List<MediaTrack>> probeTracks(
    String inputPathOrUrl, {
    Map<String, String>? headers,
  }) async {
    final details = await probeMediaDetails(inputPathOrUrl, headers: headers);
    return details.tracks;
  }

  /// Extrai uma faixa de legenda embutida diretamente como WebVTT para Chromecast e navegadores.
  static Future<String?> extractVttSubtitle(
    String filePath,
    int streamIndex, {
    Duration startPosition = Duration.zero,
    Duration subtitleOffset = Duration.zero,
    Map<String, String>? headers,
  }) async {
    if (!await isFfmpegAvailable()) return null;
    Process? process;
    try {
      final operation = NetworkOperation.current;
      operation?.check();
      process = await Process.start('ffmpeg', [
        '-v',
        'error',
        '-copyts',
        '-start_at_zero',
        if (headers != null && headers.isNotEmpty) ...[
          '-headers',
          headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join(),
        ],
        '-i',
        filePath,
        '-map',
        '0:$streamIndex',
        '-c:s',
        'webvtt',
        '-avoid_negative_ts',
        'disabled',
        '-f',
        'webvtt',
        'pipe:1',
      ]);
      operation?.onCancel(() {
        process?.kill();
      });
      unawaited(process.stderr.drain<void>().catchError((_) {}));
      final text = await process.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 60));
      final code = await process.exitCode.timeout(const Duration(seconds: 5));
      operation?.check();
      if (code == 0 && text.startsWith('WEBVTT')) {
        return retimeVtt(text, subtitleOffset - startPosition);
      }
    } catch (_) {
      return null;
    } finally {
      if (process != null) {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(milliseconds: 250));
        } catch (_) {}
      }
    }
    return null;
  }

  /// Positive offsets delay captions. Keep cues crossing the segment boundary,
  /// clipping at zero, and discard cues that have already ended.
  static String retimeVtt(String text, Duration offset) {
    final timing = RegExp(
      r'^(?:(\d+):)?(\d{2}):(\d{2})\.(\d{3}) --> (?:(\d+):)?(\d{2}):(\d{2})\.(\d{3})([^\n]*)$',
      multiLine: true,
    );
    int milliseconds(RegExpMatch match, int group) =>
        (int.parse(match[group] ?? '0') * 3600 +
                int.parse(match[group + 1]!) * 60 +
                int.parse(match[group + 2]!)) *
            1000 +
        int.parse(match[group + 3]!);
    String timestamp(int ms) {
      final d = Duration(milliseconds: ms);
      return '${d.inHours.toString().padLeft(2, '0')}:'
          '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
          '${(d.inSeconds % 60).toString().padLeft(2, '0')}.'
          '${(ms % 1000).toString().padLeft(3, '0')}';
    }

    final blocks = <String>[];
    for (final block in text.replaceAll('\r\n', '\n').split(RegExp(r'\n\n+'))) {
      if (block.trim().isEmpty) continue;
      final match = timing.firstMatch(block);
      if (match == null) {
        blocks.add(block);
        continue;
      }
      final start = milliseconds(match, 1) + offset.inMilliseconds;
      final end = milliseconds(match, 5) + offset.inMilliseconds;
      if (end <= 0) continue;
      blocks.add(
        block.replaceRange(
          match.start,
          match.end,
          '${timestamp(start < 0 ? 0 : start)} --> ${timestamp(end)}${match[9]}',
        ),
      );
    }
    return '${blocks.join('\n\n')}\n';
  }

  /// Inicia processo de remuxing/transcode leve para saÃ­da MP4 (fragmented mp4) compatÃ­vel com Chromecast e TVs.
  /// Copia vÃ­deo (-c:v copy) se compatÃ­vel, ou recodifica se incompatÃ­vel; converte Ã¡udio para AAC stereo.
  static Future<Process?> startRemuxProcess(
    String inputPathOrUrl, {
    int? selectedAudioIndex,
    int? selectedSubtitleIndex,
    bool transcodeVideo = false,
    Duration startPosition = Duration.zero,
    Map<String, String>? headers,
  }) async {
    if (!await isFfmpegAvailable()) return null;

    try {
      final args = <String>['-v', 'error'];
      if (headers != null && headers.isNotEmpty) {
        final headerStr = headers.entries
            .map((e) => '${e.key}: ${e.value}\r\n')
            .join();
        args.addAll([
          '-probesize',
          '2000000',
          '-analyzeduration',
          '2000000',
          '-headers',
          headerStr,
        ]);
      }
      if (startPosition > Duration.zero) {
        args.addAll(['-ss', (startPosition.inMilliseconds / 1000).toString()]);
      }
      args.addAll(['-i', inputPathOrUrl]);

      // Mapeamento de vÃ­deo: primeiro stream de vÃ­deo
      args.addAll(['-map', '0:v:0?']);

      args.addAll([
        '-vf',
        "scale='min(1920,trunc(iw/2)*2)':-2",
        '-c:v',
        'libx264',
        '-preset',
        'ultrafast',
        '-tune',
        'zerolatency',
        '-g',
        '24',
        '-sc_threshold',
        '0',
        '-crf',
        '23',
        '-maxrate',
        '8M',
        '-bufsize',
        '16M',
        '-pix_fmt',
        'yuv420p',
      ]);

      // Mapeamento de Ã¡udio: stream selecionado ou default
      if (selectedAudioIndex != null) {
        args.addAll(['-map', '0:$selectedAudioIndex']);
      } else {
        args.addAll(['-map', '0:a:0?']);
      }
      // Ãudio universal AAC estÃ©reo compatÃ­vel com 100% dos Chromecast e Smart TVs
      args.addAll(['-c:a', 'aac', '-b:a', '192k', '-ac', '2']);

      // Formato de saída: Fragmented MP4 direto para stdout (pipe:1)
      args.addAll([
        '-movflags',
        'frag_keyframe+empty_moov+default_base_moof',
        '-flush_packets',
        '1',
        '-f',
        'mp4',
        'pipe:1',
      ]);

      final process = await Process.start('ffmpeg', args);
      return process;
    } catch (_) {
      return null;
    }
  }
}
