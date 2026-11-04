import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum LibrarySource { local, androidTree, drive, oneDrive }

class LibraryEntry {
  const LibraryEntry(
    this.source,
    this.id,
    this.name, {
    this.folder = false,
    this.mimeType,
    this.size,
    this.thumbnailUrl,
  });

  final LibrarySource source;
  final String id, name;
  final bool folder;
  final String? mimeType;
  final int? size;
  final String? thumbnailUrl;

  static final _imageExtRegex = RegExp(
    r'\.(jpg|jpeg|png|webp|gif|bmp|heic|tiff|ico|svg|avif)$',
    caseSensitive: false,
  );
  static final _videoExtRegex = RegExp(
    r'\.(mp4|mkv|mov|avi|webm|m4v|ts|flv|wmv|mpg|mpeg|vob|ogv|3gp)$',
    caseSensitive: false,
  );
  static final _audioExtRegex = RegExp(
    r'\.(mp3|m4a|flac|wav|ogg|aac|oga|wma|opus|alac|aiff)$',
    caseSensitive: false,
  );

  static bool isSupportedFileName(String name) =>
      _imageExtRegex.hasMatch(name) ||
      _videoExtRegex.hasMatch(name) ||
      _audioExtRegex.hasMatch(name);

  bool get isImage =>
      (mimeType?.toLowerCase().startsWith('image/') ?? false) ||
      _imageExtRegex.hasMatch(name);

  bool get isVideo =>
      (mimeType?.toLowerCase().startsWith('video/') ?? false) ||
      _videoExtRegex.hasMatch(name);

  bool get isAudio =>
      (mimeType?.toLowerCase().startsWith('audio/') ?? false) ||
      _audioExtRegex.hasMatch(name);

  bool get isSupportedMedia => isImage || isVideo || isAudio;

  Map<String, dynamic> toJson() => {
    'source': source.name,
    'id': id,
    'name': name,
    'folder': folder,
    if (mimeType != null) 'mimeType': mimeType,
    if (size != null) 'size': size,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
  };

  factory LibraryEntry.fromJson(Map<String, dynamic> v) => LibraryEntry(
    LibrarySource.values.byName(v['source']),
    v['id'],
    v['name'],
    folder: v['folder'] == true,
    mimeType: v['mimeType'] as String?,
    size: (v['size'] as num?)?.toInt(),
    thumbnailUrl: v['thumbnailUrl'] as String?,
  );
}

class LibrarySources {
  static const tree = MethodChannel('sixf/library');
  static const driveScope = 'https://www.googleapis.com/auth/drive.readonly';

  static final Map<LibrarySource, ({String token, DateTime expires})> _tokens =
      {};
  static final Map<LibrarySource, String> _refreshTokens = {};
  static GoogleSignInAccount? _account;
  static Future<void>? _googleInit;
  static bool _prefsLoaded = false;

  final Set<HttpClient> _activeClients = {};

  static final Map<String, ({List<LibraryEntry> items, DateTime expires})> _folderCache = {};

  static void invalidateFolderCache([String? folderId]) {
    if (folderId != null) {
      _folderCache.remove(folderId);
    } else {
      _folderCache.clear();
    }
  }

  static String _refreshPrefKey(LibrarySource s) =>
      'sixf.oauth.refresh.${s.name}';
  static String _accessPrefKey(LibrarySource s) =>
      'sixf.oauth.access.${s.name}';
  static String _expiresPrefKey(LibrarySource s) =>
      'sixf.oauth.expires.${s.name}';

  static String? currentTokenForSource(LibrarySource source) {
    final cached = _tokens[source];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.token;
    }
    return null;
  }

  static String? currentTokenForSourceName(String? sourceName) {
    if (sourceName == null) return null;
    for (final s in LibrarySource.values) {
      if (s.name == sourceName) return currentTokenForSource(s);
    }
    return null;
  }

  /// Descarta o access token em memória (ex.: após HTTP 401 do provedor).
  static void invalidateTokenForSourceName(String? sourceName) {
    for (final s in LibrarySource.values) {
      if (s.name == sourceName) _tokens.remove(s);
    }
  }

  /// Token válido para o proxy de streaming, renovando silenciosamente via refresh token.
  /// Nunca abre o navegador: retorna `null` se não houver sessão renovável.
  static Future<String?> freshTokenForSourceName(String? sourceName) async {
    if (sourceName == null) return null;
    LibrarySource? source;
    for (final s in LibrarySource.values) {
      if (s.name == sourceName) source = s;
    }
    if (source == null) return null;
    final cached = currentTokenForSource(source);
    if (cached != null) return cached;
    try {
      return await LibrarySources().token(source);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _ensureStoredTokensLoaded() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final s in const [LibrarySource.drive, LibrarySource.oneDrive]) {
        final refresh = prefs.getString(_refreshPrefKey(s));
        if (refresh != null && refresh.isNotEmpty) {
          _refreshTokens[s] ??= refresh;
        }
        final access = prefs.getString(_accessPrefKey(s));
        final expiresMs = prefs.getInt(_expiresPrefKey(s));
        if (access != null && access.isNotEmpty && expiresMs != null) {
          final expires = DateTime.fromMillisecondsSinceEpoch(expiresMs);
          if (expires.isAfter(DateTime.now())) {
            _tokens[s] ??= (token: access, expires: expires);
          }
        }
      }
    } catch (_) {}
  }

  static Future<void> _persistTokens(
    LibrarySource source, {
    required String accessToken,
    required DateTime expires,
    String? refreshToken,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessPrefKey(source), accessToken);
      await prefs.setInt(
        _expiresPrefKey(source),
        expires.millisecondsSinceEpoch,
      );
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString(_refreshPrefKey(source), refreshToken);
      }
    } catch (_) {}
  }

  Future<bool> hasSavedSession(LibrarySource source) async {
    await _ensureStoredTokensLoaded();
    if (_refreshTokens.containsKey(source)) return true;
    final cached = _tokens[source];
    return cached != null && cached.expires.isAfter(DateTime.now());
  }

  Future<void> signOut(LibrarySource source) async {
    _tokens.remove(source);
    _refreshTokens.remove(source);
    if (source == LibrarySource.drive) {
      _account = null;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_refreshPrefKey(source));
      await prefs.remove(_accessPrefKey(source));
      await prefs.remove(_expiresPrefKey(source));
    } catch (_) {}
  }

  /// Cancela imediatamente todos os downloads/requisições em andamento.
  void abortActiveOperations() {
    for (final client in _activeClients.toList()) {
      try {
        client.close(force: true);
      } catch (_) {}
    }
    _activeClients.clear();
  }

  Future<String> token(LibrarySource source) async {
    await _ensureStoredTokensLoaded();
    final cached = _tokens[source];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.token;
    }
    if (source == LibrarySource.drive && Platform.isAndroid) {
      const server = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
      if (server.isEmpty) {
        throw const FormatException(
          'Configure o cliente Google desta instalação.',
        );
      }
      await (_googleInit ??= GoogleSignIn.instance.initialize(
        serverClientId: server,
      ));
      _account ??= await GoogleSignIn.instance.authenticate(
        scopeHint: [driveScope],
      );
      final auth =
          await _account!.authorizationClient.authorizationForScopes([
            driveScope,
          ]) ??
          await _account!.authorizationClient.authorizeScopes([driveScope]);
      final expires = DateTime.now().add(const Duration(minutes: 50));
      _tokens[source] = (token: auth.accessToken, expires: expires);
      await _persistTokens(
        source,
        accessToken: auth.accessToken,
        expires: expires,
      );
      return auth.accessToken;
    }
    final google = source == LibrarySource.drive;
    const googleId = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
    const microsoftId = String.fromEnvironment('ONEDRIVE_CLIENT_ID');
    final client = google ? googleId : microsoftId;
    if (client.isEmpty) {
      throw FormatException(
        'Configure o cliente ${google ? "Google Drive" : "OneDrive"} desta instalação.',
      );
    }
    const secret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');
    final endpoint = Uri.parse(
      google
          ? 'https://oauth2.googleapis.com/token'
          : 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    );
    Future<String?> exchange(Map<String, String> grant) async {
      final response = await http
          .post(
            endpoint,
            body: {
              'client_id': client,
              if (google && secret.isNotEmpty) 'client_secret': secret,
              ...grant,
            },
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final value = data['access_token'] as String;
      String? newRefresh;
      if (data['refresh_token'] case final String refresh
          when refresh.isNotEmpty) {
        _refreshTokens[source] = refresh;
        newRefresh = refresh;
      }
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      final expires = DateTime.now().add(
        Duration(seconds: max(60, expiresIn - 60)),
      );
      _tokens[source] = (token: value, expires: expires);
      await _persistTokens(
        source,
        accessToken: value,
        expires: expires,
        refreshToken: newRefresh ?? _refreshTokens[source],
      );
      return value;
    }

    if (_refreshTokens[source] case final String refresh
        when refresh.isNotEmpty) {
      final renewed = await exchange({
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
      });
      if (renewed != null) return renewed;
      _refreshTokens.remove(source);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_refreshPrefKey(source));
      } catch (_) {}
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect =
        'http://${google ? "127.0.0.1" : "localhost"}:${server.port}';
    String random() =>
        base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
            .replaceAll('=', '');
    final state = random(), verifier = random();
    final authority = google
        ? 'https://accounts.google.com/o/oauth2/v2/auth'
        : 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize';
    try {
      final uri = Uri.parse(authority).replace(
        queryParameters: {
          'client_id': client,
          'redirect_uri': redirect,
          'response_type': 'code',
          'scope': google ? driveScope : 'Files.Read offline_access',
          if (google) 'access_type': 'offline',
          if (google) 'prompt': 'consent',
          'state': state,
          'code_challenge_method': 'S256',
          'code_challenge': base64UrlEncode(
            sha256.convert(ascii.encode(verifier)).bytes,
          ).replaceAll('=', ''),
        },
      );
      final result = Completer<String>();
      server.listen((req) async {
        final params = req.uri.queryParameters;
        if (req.uri.path != '/' || params['state'] != state) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType.html;
        req.response.write(
          '<!DOCTYPE html><html><body style="font-family:sans-serif;text-align:center;padding:40px;background:#121318;color:#fff;">'
          '<h2>Autorização concluída com sucesso!</h2>'
          '<p>Seu login ficará salvo no SixF. Você já pode fechar esta aba e voltar ao aplicativo.</p>'
          '</body></html>',
        );
        await req.response.close();
        if (result.isCompleted) return;
        if (params['code'] case final String code) {
          result.complete(code);
        } else {
          result.completeError(const FormatException('Acesso cancelado.'));
        }
      });
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException('Não foi possível abrir o navegador.');
      }
      final code = await result.future.timeout(const Duration(minutes: 3));
      return await exchange({
            'grant_type': 'authorization_code',
            'code': code,
            'code_verifier': verifier,
            'redirect_uri': redirect,
          }) ??
          (throw const FormatException('A conta não autorizou o acesso.'));
    } finally {
      await server.close(force: true);
    }
  }

  static String _ensureExtension(
    String rawName,
    String? mimeType,
    String? fileExtension,
  ) {
    if (p.extension(rawName).isNotEmpty) return rawName;
    if (fileExtension != null && fileExtension.trim().isNotEmpty) {
      final cleanExt = fileExtension.trim().replaceAll('.', '');
      return '$rawName.$cleanExt';
    }
    if (mimeType == null) return rawName;
    final lower = mimeType.toLowerCase();
    return switch (lower) {
      'image/jpeg' || 'image/jpg' => '$rawName.jpg',
      'image/png' => '$rawName.png',
      'image/webp' => '$rawName.webp',
      'image/gif' => '$rawName.gif',
      'image/bmp' => '$rawName.bmp',
      'video/mp4' => '$rawName.mp4',
      'video/x-matroska' || 'video/mkv' => '$rawName.mkv',
      'video/quicktime' => '$rawName.mov',
      'video/x-msvideo' => '$rawName.avi',
      'video/webm' => '$rawName.webm',
      'audio/mpeg' || 'audio/mp3' => '$rawName.mp3',
      'audio/flac' => '$rawName.flac',
      'audio/wav' => '$rawName.wav',
      'audio/ogg' => '$rawName.ogg',
      'audio/aac' || 'audio/mp4' => '$rawName.m4a',
      _ => rawName,
    };
  }

  Future<List<LibraryEntry>> list(
    LibraryEntry dir, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = "${dir.source.name}:${dir.id}";
    if (!forceRefresh) {
      final cached = _folderCache[cacheKey];
      if (cached != null && cached.expires.isAfter(DateTime.now())) {
        return cached.items;
      }
    }
    final src = dir.source;
    final items = <LibraryEntry>[];
    if (src == LibrarySource.local) {
      final targetDir = Directory(dir.id);
      try {
        final dirEntries = targetDir.listSync(followLinks: false);
        for (final item in dirEntries) {
          final isDir = item is Directory;
          if (!isDir && item is! File) continue;
          final name = p.basename(item.path);
          if (!isDir && !LibraryEntry.isSupportedFileName(name)) continue;

          int? fileSize;
          if (!isDir) {
            try {
              fileSize = (item as File).lengthSync();
            } catch (_) {}
          }
          items.add(
            LibraryEntry(
              src,
              item.path,
              name,
              folder: isDir,
              size: fileSize,
            ),
          );
        }
      } catch (_) {
        await for (final item in targetDir.list(followLinks: false)) {
          final isDir = item is Directory;
          if (!isDir && item is! File) continue;
          final name = p.basename(item.path);
          if (!isDir && !LibraryEntry.isSupportedFileName(name)) continue;

          int? fileSize;
          if (!isDir) {
            try {
              fileSize = await (item as File).length();
            } catch (_) {}
          }
          items.add(
            LibraryEntry(
              src,
              item.path,
              name,
              folder: isDir,
              size: fileSize,
            ),
          );
        }
      }
    } else if (src == LibrarySource.androidTree) {
      final rows = await tree.invokeListMethod<dynamic>('list', dir.id);
      for (final row in rows!) {
        items.add(
          LibraryEntry(src, row['id'], row['name'], folder: row['folder']),
        );
      }
    } else {
      final google = src == LibrarySource.drive;
      Future<http.Response> fetchPage(Uri uri) async {
        var authToken = await token(src);
        var res = await http
            .get(uri, headers: {'Authorization': 'Bearer $authToken'})
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 401 && _refreshTokens.containsKey(src)) {
          _tokens.remove(src);
          authToken = await token(src);
          res = await http
              .get(uri, headers: {'Authorization': 'Bearer $authToken'})
              .timeout(const Duration(seconds: 10));
        }
        return res;
      }

      final sanitizedParent = dir.id.replaceAll("'", "\\'");
      final params = {
        'q':
            "'$sanitizedParent' in parents and trashed = false and (mimeType = 'application/vnd.google-apps.folder' or mimeType contains 'video/' or mimeType contains 'image/' or mimeType contains 'audio/' or fileExtension = 'mkv' or fileExtension = 'mp4' or fileExtension = 'webm' or fileExtension = 'webp' or fileExtension = 'avi' or fileExtension = 'ts')",
        'fields':
            'nextPageToken,files(id,name,mimeType,size,thumbnailLink,fileExtension)',
        'pageSize': '100',
      };
      Uri? next = google
          ? Uri.https('www.googleapis.com', '/drive/v3/files', params)
          : Uri.https(
              'graph.microsoft.com',
              '/v1.0/me/drive/${dir.id == "root" ? "root" : "items/${dir.id}"}/children',
            );
      var pageCount = 0;
      while (next != null && pageCount < 3) {
        pageCount++;
        final response = await fetchPage(next);
        if (response.statusCode != 200) {
          _tokens.remove(src);
          throw const FormatException(
            'Não foi possível abrir a pasta. Verifique a conta e tente novamente.',
          );
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        for (final row in data[google ? 'files' : 'value']) {
          final isFolder = google
              ? row['mimeType'] == 'application/vnd.google-apps.folder'
              : row['folder'] != null;
          final rawMime = google
              ? row['mimeType'] as String?
              : (row['file'] is Map
                    ? (row['file']['mimeType'] as String?)
                    : null);
          final rawName = (row['name'] as String?) ?? 'Arquivo';
          final normalizedName = isFolder
              ? rawName
              : _ensureExtension(
                  rawName,
                  rawMime,
                  google ? row['fileExtension'] as String? : null,
                );
          final parsedSize = google
              ? int.tryParse(row['size']?.toString() ?? '')
              : (row['size'] as num?)?.toInt();
          final thumb = google ? row['thumbnailLink'] as String? : null;

          items.add(
            LibraryEntry(
              src,
              row['id'] as String,
              normalizedName,
              folder: isFolder,
              mimeType: rawMime,
              size: parsedSize,
              thumbnailUrl: thumb,
            ),
          );
        }
        next = null;
        if (google && data['nextPageToken'] != null) {
          next = Uri.https('www.googleapis.com', '/drive/v3/files', {
            ...params,
            'pageToken': data['nextPageToken'],
          });
        }
        if (!google && data['@odata.nextLink'] != null) {
          final link = Uri.parse(data['@odata.nextLink']);
          if (link.scheme == 'https' && link.host == 'graph.microsoft.com') {
            next = link;
          }
        }
      }
    }
    items.removeWhere((e) => !e.folder && !e.isSupportedMedia);
    items.sort(
      (a, b) => a.folder != b.folder
          ? (a.folder ? -1 : 1)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _folderCache[cacheKey] = (
      items: List.unmodifiable(items),
      expires: DateTime.now().add(const Duration(minutes: 15)),
    );
    return items;
  }

  /// Resolve um item da biblioteca para transmissão.
  ///
  /// - Arquivos locais: retornados diretamente.
  /// - Vídeos e áudios na nuvem (Google Drive / OneDrive): **não baixam o arquivo inteiro**;
  ///   criam um descritor `.cloud.json` instantâneo para que o `MediaServerService` faça
  ///   streaming por pedaços sob demanda (HTTP Range Proxy 206 Partial Content).
  /// - Fotos na nuvem: baixadas em cache de sessão para visualização simultânea no app e na TV.
  Future<File> resolve(LibraryEntry entry, Directory cache) async {
    if (entry.source == LibrarySource.local) {
      final file = File(entry.id);
      if (!await file.exists()) {
        throw const FormatException('Arquivo local indisponível.');
      }
      return file;
    }
    var ext = p.extension(entry.name).toLowerCase();
    if (ext.isEmpty) {
      final withExt = _ensureExtension(entry.name, entry.mimeType, null);
      ext = p.extension(withExt).toLowerCase();
    }
    if (!RegExp(r'^\.[a-z0-9]{1,6}$').hasMatch(ext)) {
      ext = entry.isImage ? '.jpg' : '.mp4';
    }
    final file = File(
      p.join(
        cache.path,
        '${sha256.convert(utf8.encode(entry.source.name + entry.id))}$ext',
      ),
    );

    // Streaming sob demanda (HTTP Range Proxy) para vídeos e áudios em nuvem
    if ((entry.source == LibrarySource.drive ||
            entry.source == LibrarySource.oneDrive) &&
        !entry.isImage) {
      final google = entry.source == LibrarySource.drive;
      var authToken = await token(entry.source);
      var resolvedSize = entry.size;
      if (resolvedSize == null || resolvedSize <= 0) {
        final metaUri = google
            ? Uri.https('www.googleapis.com', '/drive/v3/files/${entry.id}', {
                'fields': 'size,name,mimeType',
              })
            : Uri.https(
                'graph.microsoft.com',
                '/v1.0/me/drive/items/${entry.id}',
                {r'$select': 'id,name,size'},
              );
        var metaRes = await http
            .get(metaUri, headers: {'Authorization': 'Bearer $authToken'})
            .timeout(const Duration(seconds: 15));
        if (metaRes.statusCode == 401 &&
            _refreshTokens.containsKey(entry.source)) {
          _tokens.remove(entry.source);
          authToken = await token(entry.source);
          metaRes = await http
              .get(metaUri, headers: {'Authorization': 'Bearer $authToken'})
              .timeout(const Duration(seconds: 15));
        }
        if (metaRes.statusCode != 200) {
          throw const FormatException('O provedor não liberou este arquivo.');
        }
        final metaData = jsonDecode(utf8.decode(metaRes.bodyBytes));
        resolvedSize = google
            ? int.tryParse(metaData['size']?.toString() ?? '')
            : (metaData['size'] as num?)?.toInt();
      }

      final remoteUrl = google
          ? Uri.https('www.googleapis.com', '/drive/v3/files/${entry.id}', {
              'alt': 'media',
            }).toString()
          : Uri.https(
              'graph.microsoft.com',
              '/v1.0/me/drive/items/${entry.id}/content',
            ).toString();

      final cloudMeta = File('${file.path}.cloud.json');
      await cloudMeta.writeAsString(
        jsonEncode({
          'url': remoteUrl,
          'source': entry.source.name,
          'id': entry.id,
          'name': entry.name,
          'size': resolvedSize ?? 0,
          'headers': {'Authorization': 'Bearer $authToken'},
        }),
      );
      if (!await file.exists()) {
        await file.writeAsBytes(const [0]);
      }
      return file;
    }

    if (await file.exists() && await file.length() > 1) return file;
    final partial = File('${file.path}.part');
    try {
      if (entry.source == LibrarySource.androidTree) {
        await tree.invokeMethod<void>('copy', {
          'uri': entry.id,
          'path': partial.path,
        });
      } else {
        final google = entry.source == LibrarySource.drive;
        final url = google
            ? Uri.https('www.googleapis.com', '/drive/v3/files/${entry.id}', {
                'alt': 'media',
              })
            : Uri.https(
                'graph.microsoft.com',
                '/v1.0/me/drive/items/${entry.id}/content',
              );
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 25);
        _activeClients.add(client);
        try {
          final req = await client.getUrl(url);
          req.headers.set(
            'Authorization',
            'Bearer ${await token(entry.source)}',
          );
          final res = await req.close().timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) {
            _tokens.remove(entry.source);
            throw const FormatException('O provedor não liberou este arquivo.');
          }
          await res
              .timeout(const Duration(minutes: 1))
              .pipe(partial.openWrite());
        } finally {
          _activeClients.remove(client);
          client.close(force: true);
        }
      }
      return await partial.rename(file.path);
    } finally {
      if (await partial.exists()) await partial.delete();
    }
  }

  static Future<Directory> sessionCache() async =>
      (await getTemporaryDirectory()).createTemp('sixf-play-');
}
