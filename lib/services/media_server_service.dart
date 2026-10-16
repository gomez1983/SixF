import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'network_operation.dart';
import 'package:flutter/foundation.dart';

/// Servidor HTTP leve embutido para streaming local de fotos, vídeos e músicas para Smart TVs (DLNA / UPnP).
///
/// Suporta requisições HTTP Range (206 Partial Content) para permitir buffering e seek de vídeos
/// em Smart TVs LG webOS e Samsung Tizen sem travar a memória do aparelho transmissor.
class MediaServerService {
  HttpServer? _server;
  File? _currentFile;
  String? _mimeType;
  String? _fileName;
  String? _mediaPath;
  NetworkOperation? _starting;
  Future<int>? _startFuture;

  String? get mediaPath => _mediaPath;

  int? get port => _server?.port;
  bool get isRunning => _server != null;
  String? get currentFileName => _fileName;
  String? get currentMimeType => _mimeType;

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
        onDiscard: (server) { server.close(force: true); },
      );
      operation.onCancel(() { server.close(force: true); });
      operation.check();
      _server = server;
      server.listen((request) async {
        try {
          await _handleRequest(request);
        } catch (_) {
          try { await request.response.close(); } catch (_) {}
        }
      }, onError: (Object error) {
        debugPrint('[MediaServer] Erro no servidor: ${error.runtimeType}');
      });
      return server.port;
    } finally {
      if (identical(_starting, operation)) {
        _starting = null;
        _startFuture = null;
      }
    }
  }

  /// Define o arquivo local a ser disponibilizado para a Smart TV.
  void serveFile(File file, {String? mimeType, String? customName}) {
    final random = Random.secure();
    final token = List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _currentFile = file;
    _fileName = customName ?? file.uri.pathSegments.last;
    _mimeType = mimeType ?? _guessMimeType(_fileName!);
    _mediaPath = '/media/$token/${Uri.encodeComponent(_fileName!)}';
    debugPrint('[MediaServer] Arquivo carregado para streaming: $_fileName ($_mimeType)');
  }

  /// Resolve o endereço IP local da máquina/celular que está na mesma sub-rede da TV.
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

      // 2. Fallback: primeira interface IPv4 privada válida
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

  /// Gera a URL HTTP completa do arquivo para envio à TV.
  Future<String?> getMediaUrlForTv(String targetTvIp) async {
    if (_server == null || _currentFile == null) return null;
    final server = _server;
    final path = _mediaPath;
    final localIp = await getLocalIpForTarget(targetTvIp);
    if (!identical(server, _server) || path != _mediaPath) return null;
    if (localIp == null) return null;

    return 'http://$localIp:${server!.port}$path';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final res = request.response;

    // Cabeçalhos universais de compatibilidade
    res.headers.set('Access-Control-Allow-Origin', '*');
    res.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    res.headers.set('Access-Control-Allow-Headers', 'Range, Content-Type, Accept');
    res.headers.set('Server', 'SixF-DLNA-MediaServer/1.0');

    final file = _currentFile;
    final path = _mediaPath;
    final mime = _mimeType ?? 'application/octet-stream';
    if (file == null || path == null || request.uri.path != Uri.parse(path).path || request.uri.hasQuery) {
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

    if (!await file.exists() || path != _mediaPath) {
      res.statusCode = HttpStatus.notFound;
      res.write('Arquivo não encontrado no servidor SixF.');
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

    res.headers.set(HttpHeaders.contentTypeHeader, mime);
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

    // Cabeçalhos essenciais para players de Smart TVs (LG webOS SmartShare e Samsung Tizen)
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

    // Se a TV enviar apenas uma requisição HEAD para verificar o arquivo
    if (request.method == 'HEAD') {
      res.statusCode = HttpStatus.ok;
      res.headers.set(HttpHeaders.contentLengthHeader, fileLength);
      await res.close().catchError((_) {});
      return;
    }

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    // Suporte a HTTP Range (206 Partial Content) para Seek e Streaming de Vídeo
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      try {
        final rangeSpec = rangeHeader.substring(6).trim();
        int start = 0;
        int end = fileLength - 1;

        if (rangeSpec.startsWith('-')) {
          // Suffix byte range: ex: bytes=-500 (solicita os últimos 500 bytes)
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

        final contentLength = end - start + 1;
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileLength');
        res.headers.set(HttpHeaders.contentLengthHeader, contentLength);

        // Transmissão protegida contra cancelamento prematuro da conexão pela TV
        await res.addStream(file.openRead(start, end + 1)).catchError((e) {
          debugPrint('[MediaServer] Stream de range interrompido pelo cliente: $e');
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

    // Streaming padrão 200 OK (fotos ou downloads completos)
    try {
      res.statusCode = HttpStatus.ok;
      res.headers.set(HttpHeaders.contentLengthHeader, fileLength);
      await res.addStream(file.openRead()).catchError((e) {
        debugPrint('[MediaServer] Stream completo interrompido pelo cliente: $e');
      });
    } catch (e) {
      debugPrint('[MediaServer] Erro ao transmitir arquivo: $e');
    } finally {
      await res.close().catchError((_) {});
    }
  }

  /// Identifica o MIME type com base na extensão do arquivo.
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

      // Vídeos
      case 'mp4':
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

      // Áudios
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
        return 'audio/aac';
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

  /// Encerra o servidor e libera portas locais.
  Future<void> stop() async {
    _starting?.cancel();
    _starting = null;
    _startFuture = null;
    final server = _server;
    _server = null;
    _currentFile = null;
    _fileName = null;
    _mimeType = null;
    _mediaPath = null;
    await server?.close(force: true);
  }
}
