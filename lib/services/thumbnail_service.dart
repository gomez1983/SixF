import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library_sources.dart';
import 'media_remux_service.dart';

/// Miniaturas da Biblioteca de mídia para todas as fontes, com cache em disco.
///
/// - Imagem local (Windows): o próprio arquivo (o `Image` reduz na decodificação).
/// - Vídeo local (Windows): quadro extraído pelo FFmpeg.
/// - Pasta do aparelho no Android (SAF `content://`, inclusive o Drive pelo
///   seletor nativo): miniatura do provedor, quadro do vídeo ou imagem reduzida.
/// - Google Drive / OneDrive: `thumbnailLink` / miniatura pré-assinada; fotos do
///   Drive sem miniatura caem no download direto (limitado a 15 MB).
///
/// Resultados (inclusive falhas) ficam memorizados por item, então reconstruir
/// a interface nunca dispara uma nova extração.
class ThumbnailService {
  ThumbnailService._();

  static final Map<String, Future<File?>> _memo = {};
  static Directory? _dir;
  static int _running = 0;
  static final List<Completer<void>> _waiting = [];
  static const _maxParallel = 3;
  static const _maxDirectImageBytes = 15 * 1024 * 1024;

  static String _key(LibraryEntry e) => '${e.source.name}:${e.id}';

  static bool supports(LibraryEntry e) => !e.folder && (e.isImage || e.isVideo);

  /// Esquece a miniatura de um item (ex.: após trocar de conta na nuvem).
  static void forget(LibraryEntry e) {
    _memo.remove(_key(e));
    _done.remove(_key(e));
  }

  static final Map<String, File?> _done = {};

  /// Resultado já pronto (sem esperar), para a miniatura não piscar ao rolar.
  static File? peek(LibraryEntry e) => _done[_key(e)];

  static Future<File?> thumbnailFor(LibraryEntry e) {
    if (!supports(e)) return Future.value(null);
    final key = _key(e);
    return _memo.putIfAbsent(key, () async {
      final file = await _guarded(() => _resolve(e));
      _done[key] = file;
      return file;
    });
  }

  static Future<File?> _guarded(Future<File?> Function() task) async {
    while (_running >= _maxParallel) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    }
    _running++;
    try {
      return await task();
    } catch (_) {
      return null;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  static Future<Directory> _cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final dir = Directory(
      p.join((await getTemporaryDirectory()).path, 'sixf-thumbs'),
    );
    await dir.create(recursive: true);
    return _dir = dir;
  }

  static Future<File> _target(LibraryEntry e) async => File(
    p.join(
      (await _cacheDir()).path,
      '${sha256.convert(utf8.encode(_key(e)))}.jpg',
    ),
  );

  static Future<File?> _resolve(LibraryEntry e) async {
    switch (e.source) {
      case LibrarySource.local:
        if (e.isImage) {
          final f = File(e.id);
          return await f.exists() ? f : null;
        }
        final path = await MediaRemuxService.extractVideoThumbnail(e.id);
        return path == null ? null : File(path);
      case LibrarySource.androidTree:
        final target = await _target(e);
        if (await target.exists() && await target.length() > 0) return target;
        final path = await LibrarySources.tree
            .invokeMethod<String>('thumbnail', {
              'uri': e.id,
              'path': target.path,
              'size': 320,
              'video': e.isVideo,
            })
            .timeout(const Duration(seconds: 20));
        return path == null ? null : File(path);
      case LibrarySource.drive:
      case LibrarySource.oneDrive:
        final target = await _target(e);
        if (await target.exists() && await target.length() > 0) return target;
        final thumb = e.thumbnailUrl;
        if (thumb != null && await _download(Uri.parse(thumb), target, e)) {
          return target;
        }
        if (e.source == LibrarySource.drive &&
            e.isImage &&
            (e.size == null || e.size! <= _maxDirectImageBytes)) {
          final direct = Uri.https(
            'www.googleapis.com',
            '/drive/v3/files/${e.id}',
            {'alt': 'media'},
          );
          if (await _download(direct, target, e, authOnly: true)) {
            return target;
          }
        }
        return null;
    }
  }

  /// Baixa a miniatura. Links pré-assinados funcionam sem cabeçalho; alguns
  /// `thumbnailLink` privados do Drive exigem o token, então tenta os dois.
  static Future<bool> _download(
    Uri uri,
    File target,
    LibraryEntry e, {
    bool authOnly = false,
  }) async {
    if (uri.scheme != 'https') return false;
    final token = await LibrarySources.freshTokenForSourceName(e.source.name);
    final attempts = <Map<String, String>>[
      if (token != null) {'Authorization': 'Bearer $token'},
      if (!authOnly) const {},
    ];
    for (final headers in attempts) {
      try {
        final res = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          await target.writeAsBytes(res.bodyBytes, flush: true);
          return true;
        }
      } catch (_) {}
    }
    return false;
  }
}
