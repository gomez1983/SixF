import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'library_sources.dart';
import 'media_remux_service.dart';
import 'network_operation.dart';

import 'package:flutter/foundation.dart';

/// Servidor HTTP leve embutido para streaming local e proxy de nuvem (Google Drive / OneDrive)
/// de fotos, vÃ­deos e mÃºsicas para Smart TVs (DLNA / UPnP / Google Cast).
///
/// Suporta requisiÃ§Ãµes HTTP Range (206 Partial Content) tanto para arquivos locais quanto
/// para streaming sob demanda da nuvem (sem precisar baixar o arquivo inteiro no disco).
class MediaServerService {
  final Map<String, Future<String>> _subtitles = {};
  NetworkOperation _mediaOperation = NetworkOperation();
  Duration _subtitleOffset = Duration.zero;
  int _subtitleRevision = 0;
  final Map<int, ({Duration start, Duration offset})> _subtitleTimelines = {};
  Duration get subtitleOffset => _subtitleOffset;

  void setSubtitleOffset(Duration offset) {
    _subtitleOffset = offset;
    _subtitleRevision++;
  }

  Future<String> prepareSubtitle(int trackId) {
    final file = _currentFile;
    if (file == null) throw StateError('Nenhum vÃ­deo ativo.');
    final key = '$_currentToken:$trackId';
    final op = _mediaOperation;
    return _subtitles.putIfAbsent(key, () async {
      // Token só em memória (o descritor em disco não o guarda).
      final headers = await LibrarySources.authHeadersForSourceName(
        _cloudDescriptor?['source'] as String?,
      );
      final text = await op.run(
        () => MediaRemuxService.extractVttSubtitle(
          _cloudDescriptor?['url'] as String? ?? file.path,
          trackId,
          headers: headers,
        ),
      );
      if (text == null) {
        _subtitles.remove(key);
        throw StateError(
          'A faixa nÃ£o pÃ´de ser convertida para WebVTT. Legendas de imagem (PGS/VobSub) nÃ£o sÃ£o suportadas.',
        );
      }
      return text;
    });
  }

  HttpServer? _server;
  File? _currentFile;
  Map<String, dynamic>? _cloudDescriptor;
  final Set<HttpClient> _activeProxyClients = {};
  String? _mimeType;
  String? _fileName;
  String? _mediaPath;
  String? _currentToken;
  Future<Process?> Function()? _remuxProcessFactory;
  static const int maxConcurrentRemuxStreams = 4;
  final Set<Process> _activeRemuxProcesses = {};
  int _inFlightRemuxStarts = 0;
  Duration _remuxStart = Duration.zero;
  Duration get remuxStart => _remuxStart;
  bool get isRemuxing => _remuxProcessFactory != null;
  int _remuxRevision = 0;

  void _killActiveRemuxProcesses() {
    _inFlightRemuxStarts = 0;
    for (final p in _activeRemuxProcesses.toList()) {
      try {
        p.kill();
      } catch (_) {}
    }
    _activeRemuxProcesses.clear();
  }

  void restartRemuxAt(Duration position) {
    if (!isRemuxing || position < Duration.zero) {
      throw StateError('NÃ£o hÃ¡ remux ativo para reposicionar.');
    }
    _killActiveRemuxProcesses();
    _remuxStart = position;
    _subtitleRevision++;
    // A new URL prevents the receiver from reusing the old fragmented buffer.
    _mediaPath =
        '/media/$_currentToken/${++_remuxRevision}/${Uri.encodeComponent(_fileName!)}';
  }

  NetworkOperation? _starting;
  Future<int>? _startFuture;

  String? get mediaPath => _mediaPath;
  String? get currentToken => _currentToken;

  int? get port => _server?.port;
  bool get isRunning => _server != null;
  String? get currentFileName => _fileName;
  String? get currentMimeType => _mimeType;
  int? get currentContentLength => (_cloudDescriptor?['size'] as num?)?.toInt();

  /// Inicia o servidor HTTP em uma porta livre do sistema operacional.
  Future<int> start() {
    if (_server != null) return Future.value(_server!.port);
    if (_startFuture != null) return _startFuture!;
    final operation = NetworkOperation();
    _starting = operation;
    return _startFuture = _start(operation);
  }

  Future<int> _start(NetworkOperation operation) async {
    try {
      final server = await operation.wait(
        HttpServer.bind(InternetAddress.anyIPv4, 0),
        onDiscard: (server) {
          server.close(force: true);
        },
      );
      operation.onCancel(() {
        server.close(force: true);
      });
      operation.check();
      _server = server;
      server.listen(
        (request) async {
          try {
            await _handleRequest(request);
          } catch (_) {
            try {
              await request.response.close();
            } catch (_) {}
          }
        },
        onError: (Object error) {
          debugPrint('[MediaServer] Erro no servidor: ${error.runtimeType}');
        },
      );
      return server.port;
    } finally {
      if (identical(_starting, operation)) {
        _starting = null;
        _startFuture = null;
      }
    }
  }

  /// Define o arquivo local (ou descritor de streaming em nuvem) a ser disponibilizado para a Smart TV.
  void serveFile(
    File file, {
    String? mimeType,
    String? customName,
    Future<Process?> Function()? remuxProcessFactory,
  }) {
    _killActiveRemuxProcesses();
    _mediaOperation.cancel();
    _mediaOperation = NetworkOperation();
    _remuxProcessFactory = remuxProcessFactory;
    _subtitles.clear();
    _subtitleTimelines.clear();
    _subtitleOffset = Duration.zero;
    _subtitleRevision = 0;
    _remuxStart = Duration.zero;
    final random = Random.secure();
    final token = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _currentFile = file;
    _currentToken = token;
    _cloudDescriptor = null;
    try {
      final cloudMeta = File('${file.path}.cloud.json');
      if (cloudMeta.existsSync()) {
        final decoded = jsonDecode(cloudMeta.readAsStringSync());
        if (decoded is Map<String, dynamic>) {
          _cloudDescriptor = decoded;
        }
      }
    } catch (_) {}
    _fileName =
        customName ??
        (_cloudDescriptor?['name'] as String?) ??
        file.uri.pathSegments.last;
    _mimeType = mimeType ?? _guessMimeType(_fileName!);
    _mediaPath = '/media/$token/${Uri.encodeComponent(_fileName!)}';
    debugPrint(
      '[MediaServer] MÃ­dia carregada para streaming: $_fileName ($_mimeType)${_cloudDescriptor != null ? ' [Cloud Proxy]' : ''}',
    );
  }

  /// Resolve o endereÃ§o IP local da mÃ¡quina/celular que estÃ¡ na mesma sub-rede da TV.
  static Future<String?> getLocalIpForTarget(String targetTvIp) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final targetParts = targetTvIp.split('.');
      final targetSubnet = (targetParts.length == 4)
          ? '${targetParts[0]}.${targetParts[1]}.${targetParts[2]}'
          : null;

      // 1. Prioriza interface na mesma sub-rede exata da TV (ex: 192.168.1.x)
      if (targetSubnet != null) {
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (addr.address.startsWith(targetSubnet)) {
              return addr.address;
            }
          }
        }
      }

      // 2. Fallback: primeira interface IPv4 privada vÃ¡lida
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('[MediaServer] Erro ao identificar IP local: $e');
    }
    return null;
  }

  /// Gera a URL HTTP completa do arquivo para envio Ã  TV.
  Future<String?> getMediaUrlForTv(String targetTvIp) async {
    if (_server == null || _currentFile == null) return null;
    final server = _server;
    final path = _mediaPath;
    final localIp = await getLocalIpForTarget(targetTvIp);
    if (!identical(server, _server) || path != _mediaPath) return null;
    if (localIp == null) return null;

    return 'http://$localIp:${server!.port}$path';
  }

  /// Gera a URL HTTP para extraÃ§Ã£o de legenda WebVTT sob demanda para Smart TVs e Chromecast.
  Future<String?> getSubtitleUrlForTv(String targetTvIp, int trackId) async {
    if (_server == null || _currentFile == null || _currentToken == null) {
      return null;
    }
    final server = _server;
    final token = _currentToken;
    final revision = _subtitleRevision;
    final start = _remuxStart;
    final offset = _subtitleOffset;
    final localIp = await getLocalIpForTarget(targetTvIp);
    if (localIp == null ||
        server != _server ||
        token != _currentToken ||
        revision != _subtitleRevision) {
      return null;
    }

    _subtitleTimelines[revision] = (start: start, offset: offset);
    return 'http://$localIp:${server!.port}/media/$token/subtitle_$trackId.vtt'
        '?revision=$revision&startUs=${start.inMicroseconds}&offsetUs=${offset.inMicroseconds}';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final res = request.response;

    // CabeÃ§alhos universais de compatibilidade
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    res.headers.set(
      'Access-Control-Allow-Headers',
      'Range, Content-Type, Accept',
    );
    res.headers.set('Server', 'SixF-DLNA-MediaServer/1.0');

    final file = _currentFile;
    final token = _currentToken;

    // Rota de entrega de legendas WebVTT dinÃ¢micas (para Chromecast e Smart TVs)
    if (file != null &&
        token != null &&
        request.uri.path.startsWith('/media/$token/subtitle_') &&
        request.uri.path.endsWith('.vtt')) {
      if (request.method == 'OPTIONS') {
        res.statusCode = HttpStatus.noContent;
        await res.close();
        return;
      }
      final fileName = request.uri.pathSegments.last;
      final match = RegExp(r'subtitle_(\d+)\.vtt').firstMatch(fileName);
      if (match != null) {
        final trackId = int.tryParse(match.group(1)!);
        if (trackId != null) {
          final query = request.uri.queryParameters;
          final timeline =
              _subtitleTimelines[int.tryParse(query['revision'] ?? '')];
          if (timeline == null ||
              query['startUs'] != '${timeline.start.inMicroseconds}' ||
              query['offsetUs'] != '${timeline.offset.inMicroseconds}') {
            res.statusCode = HttpStatus.notFound;
            await res.close();
            return;
          }
          final original = await prepareSubtitle(trackId);
          if (token != _currentToken) {
            res.statusCode = HttpStatus.notFound;
            await res.close();
            return;
          }
          final vtt = MediaRemuxService.retimeVtt(
            original,
            timeline.offset - timeline.start,
          );
          final bytes = utf8.encode(vtt);
          res.statusCode = HttpStatus.ok;
          res.headers.set(
            HttpHeaders.contentTypeHeader,
            'text/vtt; charset=utf-8',
          );
          res.headers.set(
            HttpHeaders.contentLengthHeader,
            bytes.length.toString(),
          );
          res.headers.set('Access-Control-Allow-Origin', '*');
          res.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
          res.headers.set('Access-Control-Allow-Headers', '*');
          res.headers.set('Access-Control-Expose-Headers', '*');
          res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
          if (request.method != 'HEAD') res.add(bytes);
          await res.close().catchError((_) {});
          return;
        }
      }
    }

    final cloud = _cloudDescriptor;
    final path = _mediaPath;
    final mime = _mimeType ?? 'application/octet-stream';
    if (file == null ||
        path == null ||
        request.uri.path != Uri.parse(path).path ||
        request.uri.hasQuery) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    if (!const ['GET', 'HEAD', 'OPTIONS'].contains(request.method)) {
      res.statusCode = HttpStatus.methodNotAllowed;
      res.headers.set(HttpHeaders.allowHeader, 'GET, HEAD, OPTIONS');
      await res.close();
      return;
    }
    if (request.method == 'OPTIONS') {
      res.statusCode = HttpStatus.ok;
      await res.close();
      return;
    }

    if (_remuxProcessFactory != null && await file.exists()) {
      if (request.method == 'HEAD') {
        res.statusCode = HttpStatus.ok;
        res.headers.set(HttpHeaders.contentTypeHeader, mime);
        res.headers.set(HttpHeaders.acceptRangesHeader, 'none');
        res.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
        await res.close().catchError((_) {});
        return;
      }
      final factory = _remuxProcessFactory;
      if (factory == null ||
          _activeRemuxProcesses.length + _inFlightRemuxStarts >=
              maxConcurrentRemuxStreams) {
        res.statusCode = HttpStatus.serviceUnavailable;
        await res.close().catchError((_) {});
        return;
      }
      Process? process;
      _inFlightRemuxStarts++;
      var countedInFlight = true;
      try {
        process = await factory.call();
        if (identical(factory, _remuxProcessFactory)) {
          _inFlightRemuxStarts--;
        }
        countedInFlight = false;
        if (process != null) {
          // A previous HTTP handler must never replace or kill a newer stream,
          // and a second reader on the same active URL must not kill the first reader.
          unawaited(process.stderr.drain<void>().catchError((_) {}));
          if (path != _mediaPath || !identical(factory, _remuxProcessFactory)) {
            process.kill();
            try {
              res.statusCode = HttpStatus.gone;
              await res.close();
            } catch (_) {}
            return;
          }
          _activeRemuxProcesses.add(process);
          res.bufferOutput = false;
          res.statusCode = HttpStatus.ok;
          res.headers.set(HttpHeaders.contentTypeHeader, mime);
          res.headers.set(HttpHeaders.acceptRangesHeader, 'none');
          res.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
          res.headers.set('transferMode.dlna.org', 'Streaming');
          await res.addStream(process.stdout).catchError((_) {});
          await res.close().catchError((_) {});
          return;
        }
        res.statusCode = HttpStatus.serviceUnavailable;
        await res.close().catchError((_) {});
        return;
      } catch (e) {
        debugPrint('[MediaServer] Erro no streaming remux: $e');
      } finally {
        if (countedInFlight && identical(factory, _remuxProcessFactory)) {
          _inFlightRemuxStarts--;
        }
        if (process != null) {
          _activeRemuxProcesses.remove(process);
          process.kill();
        }
      }
      return;
    }

    if (cloud != null) {
      await _handleCloudProxyRequest(request, cloud, path, mime);
      return;
    }

    if (!await file.exists() || path != _mediaPath) {
      res.statusCode = HttpStatus.notFound;
      res.write('Arquivo nÃ£o encontrado no servidor SixF.');
      await res.close();
      return;
    }

    final fileLength = await file.length();
    if (path != _mediaPath) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final isVideo = mime.startsWith('video/') || mime.startsWith('audio/');

    final effectiveMime =
        (mime == 'video/x-matroska' ||
            mime == 'video/webm' ||
            mime == 'video/x-msvideo' ||
            mime == 'video/quicktime')
        ? 'video/mp4'
        : mime;
    res.headers.set(HttpHeaders.contentTypeHeader, effectiveMime);
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

    // CabeÃ§alhos essenciais para players de Smart TVs (LG webOS SmartShare e Samsung Tizen)
    res.headers.set('transferMode.dlna.org', 'Streaming');
    if (isVideo) {
      res.headers.set(
        'contentFeatures.dlna.org',
        'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000',
      );
    } else {
      res.headers.set(
        'contentFeatures.dlna.org',
        'DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=00D00000000000000000000000000000',
      );
    }

    // Se a TV enviar apenas uma requisiÃ§Ã£o HEAD para verificar o arquivo
    if (request.method == 'HEAD') {
      res.statusCode = HttpStatus.ok;
      res.headers.set(HttpHeaders.contentLengthHeader, fileLength);
      await res.close().catchError((_) {});
      return;
    }

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    // Suporte a HTTP Range (206 Partial Content) para Seek e Streaming de VÃ­deo
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      try {
        final rangeSpec = rangeHeader.substring(6).trim();
        int start = 0;
        int end = fileLength - 1;

        if (rangeSpec.startsWith('-')) {
          final suffixLength = int.tryParse(rangeSpec.substring(1)) ?? 0;
          if (suffixLength > 0) {
            start = (fileLength - suffixLength).clamp(0, fileLength - 1);
            end = fileLength - 1;
          }
        } else {
          final parts = rangeSpec.split('-');
          start = int.tryParse(parts[0]) ?? 0;
          if (parts.length > 1 && parts[1].isNotEmpty) {
            end = int.tryParse(parts[1]) ?? (fileLength - 1);
          }
        }

        if (start >= fileLength || start < 0) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */$fileLength',
          );
          await res.close().catchError((_) {});
          return;
        }

        if (end >= fileLength) {
          end = fileLength - 1;
        }

        final contentLength = end - start + 1;
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$fileLength',
        );
        res.headers.set(HttpHeaders.contentLengthHeader, contentLength);

        await res.addStream(file.openRead(start, end + 1)).catchError((e) {
          debugPrint(
            '[MediaServer] Stream de range interrompido pelo cliente: $e',
          );
        });
        await res.close().catchError((_) {});
        return;
      } catch (e) {
        debugPrint('[MediaServer] Erro ao servir range: $e');
        try {
          await res.close().catchError((_) {});
        } catch (_) {}
        return;
      }
    }

    // Streaming padrÃ£o 200 OK (fotos ou downloads completos)
    try {
      res.statusCode = HttpStatus.ok;
      res.headers.set(HttpHeaders.contentLengthHeader, fileLength);
      await res.addStream(file.openRead()).catchError((e) {
        debugPrint(
          '[MediaServer] Stream completo interrompido pelo cliente: $e',
        );
      });
    } catch (e) {
      debugPrint('[MediaServer] Erro ao transmitir arquivo: $e');
    } finally {
      await res.close().catchError((_) {});
    }
  }

  /// Proxy de streaming sob demanda para arquivos na nuvem (Google Drive / OneDrive).
  /// Repassa apenas os pedaÃ§os (Range bytes) solicitados pela TV em tempo real.
  Future<void> _handleCloudProxyRequest(
    HttpRequest request,
    Map<String, dynamic> cloud,
    String expectedPath,
    String mime,
  ) async {
    final res = request.response;
    final remoteUrl = cloud['url'] as String?;
    if (remoteUrl == null || expectedPath != _mediaPath) {
      res.statusCode = HttpStatus.notFound;
      await res.close().catchError((_) {});
      return;
    }

    final fileLength = (cloud['size'] as num?)?.toInt() ?? 0;
    final isVideo = mime.startsWith('video/') || mime.startsWith('audio/');

    final effectiveMime =
        (mime == 'video/x-matroska' ||
            mime == 'video/webm' ||
            mime == 'video/x-msvideo' ||
            mime == 'video/quicktime')
        ? 'video/mp4'
        : mime;
    res.headers.set(HttpHeaders.contentTypeHeader, effectiveMime);
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    res.headers.set('transferMode.dlna.org', 'Streaming');
    if (isVideo) {
      res.headers.set(
        'contentFeatures.dlna.org',
        'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000',
      );
    } else {
      res.headers.set(
        'contentFeatures.dlna.org',
        'DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=00D00000000000000000000000000000',
      );
    }

    if (request.method == 'HEAD') {
      res.statusCode = HttpStatus.ok;
      if (fileLength > 0) {
        res.headers.set(HttpHeaders.contentLengthHeader, fileLength);
      }
      await res.close().catchError((_) {});
      return;
    }

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    int start = 0;
    int end = fileLength > 0 ? fileLength - 1 : -1;
    bool isRange = false;

    if (rangeHeader != null &&
        rangeHeader.startsWith('bytes=') &&
        fileLength > 0) {
      isRange = true;
      final rangeSpec = rangeHeader.substring(6).trim();
      if (rangeSpec.startsWith('-')) {
        final suffixLength = int.tryParse(rangeSpec.substring(1)) ?? 0;
        if (suffixLength > 0) {
          start = (fileLength - suffixLength).clamp(0, fileLength - 1);
          end = fileLength - 1;
        }
      } else {
        final parts = rangeSpec.split('-');
        start = int.tryParse(parts[0]) ?? 0;
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? (fileLength - 1);
        }
      }

      if (start >= fileLength || start < 0) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$fileLength');
        await res.close().catchError((_) {});
        return;
      }
      if (end >= fileLength) {
        end = fileLength - 1;
      }
    }

    final proxyClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _activeProxyClients.add(proxyClient);

    try {
      final sourceName = cloud['source'] as String?;
      Future<HttpClientResponse> openUpstream() async {
        final upstreamReq = await proxyClient.getUrl(Uri.parse(remoteUrl));
        // O token Ã© obtido em memÃ³ria a cada requisiÃ§Ã£o (nunca gravado no descritor em disco)
        // e renovado silenciosamente durante filmes longos.
        final freshToken = await LibrarySources.freshTokenForSourceName(
          sourceName,
        );
        if (freshToken != null && freshToken.isNotEmpty) {
          upstreamReq.headers.set('Authorization', 'Bearer $freshToken');
        }
        if (isRange) {
          upstreamReq.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
        } else if (rangeHeader != null) {
          upstreamReq.headers.set(HttpHeaders.rangeHeader, rangeHeader);
        }
        return upstreamReq.close().timeout(const Duration(seconds: 25));
      }

      var upstreamRes = await openUpstream();
      if (upstreamRes.statusCode == HttpStatus.unauthorized) {
        await upstreamRes.drain<void>().catchError((_) {});
        LibrarySources.invalidateTokenForSourceName(sourceName);
        upstreamRes = await openUpstream();
      }

      if (upstreamRes.statusCode >= 400) {
        res.statusCode = upstreamRes.statusCode;
        await res.close().catchError((_) {});
        return;
      }

      if (isRange && fileLength > 0) {
        final contentLength = end - start + 1;
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$fileLength',
        );
        res.headers.set(HttpHeaders.contentLengthHeader, contentLength);
      } else {
        res.statusCode = upstreamRes.statusCode;
        final upRange = upstreamRes.headers.value(
          HttpHeaders.contentRangeHeader,
        );
        if (upRange != null) {
          res.headers.set(HttpHeaders.contentRangeHeader, upRange);
        }
        if (fileLength > 0) {
          res.headers.set(HttpHeaders.contentLengthHeader, fileLength);
        } else if (upstreamRes.contentLength > 0) {
          res.headers.set(
            HttpHeaders.contentLengthHeader,
            upstreamRes.contentLength,
          );
        }
      }

      await res.addStream(upstreamRes).catchError((e) {
        debugPrint(
          '[MediaServer] Proxy de nuvem interrompido pelo cliente: $e',
        );
      });
    } catch (e) {
      debugPrint('[MediaServer] Erro no proxy de nuvem: $e');
    } finally {
      _activeProxyClients.remove(proxyClient);
      try {
        proxyClient.close(force: true);
      } catch (_) {}
      try {
        await res.close().catchError((_) {});
      } catch (_) {}
    }
  }

  /// Identifica o MIME type com base na extensÃ£o do arquivo.
  static String _guessMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      // Imagens
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';

      // VÃ­deos
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'ts':
        return 'video/mp2t';

      // Ãudios
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';

      default:
        return 'application/octet-stream';
    }
  }

  /// Encerra o servidor, aborta streams de proxy ativos e libera portas locais.
  Future<void> stop() async {
    _killActiveRemuxProcesses();
    _mediaOperation.cancel();
    _mediaOperation = NetworkOperation();
    _remuxProcessFactory = null;
    _subtitles.clear();
    _subtitleTimelines.clear();
    _starting?.cancel();
    _starting = null;
    _startFuture = null;
    for (final client in _activeProxyClients.toList()) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
    _activeProxyClients.clear();
    final server = _server;
    _server = null;
    _currentFile = null;
    _cloudDescriptor = null;
    _fileName = null;
    _mimeType = null;
    _mediaPath = null;
    await server?.close(force: true);
  }
}
