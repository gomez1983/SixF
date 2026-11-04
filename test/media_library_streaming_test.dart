import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/services/library_sources.dart';
import 'package:sixf_remote/services/media_server_service.dart';
import 'package:sixf_remote/ui/widgets/media_session_controls.dart';

class RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryEntry', () {
    test('reconhece fotos, vídeos MKV e áudios por extensão ou MIME', () {
      const jpg = LibraryEntry(LibrarySource.drive, '1', 'Totoro.JPEG');
      const mime = LibraryEntry(
        LibrarySource.drive,
        '2',
        'sem extensão',
        mimeType: 'image/png',
      );
      const mkv = LibraryEntry(
        LibrarySource.drive,
        '3',
        'De Volta para o Futuro.mkv',
      );
      const doc = LibraryEntry(LibrarySource.drive, '4', 'roteiro.pdf');
      expect(jpg.isImage, isTrue);
      expect(mime.isImage, isTrue);
      expect(mkv.isVideo, isTrue);
      expect(mkv.isImage, isFalse);
      expect(doc.isSupportedMedia, isFalse);
    });

    test('preserva miniatura, MIME e tamanho ao salvar e reabrir', () {
      const entry = LibraryEntry(
        LibrarySource.drive,
        'abc',
        'Chihiro.jpg',
        mimeType: 'image/jpeg',
        size: 1234,
        thumbnailUrl: 'https://example.com/t.jpg',
      );
      final restored = LibraryEntry.fromJson(
        jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>,
      );
      expect(restored.mimeType, 'image/jpeg');
      expect(restored.size, 1234);
      expect(restored.thumbnailUrl, 'https://example.com/t.jpg');
    });

    test('pastas locais listam imagens junto com vídeos', () async {
      final dir = await Directory.systemTemp.createTemp('sixf_lib_');
      addTearDown(() => dir.delete(recursive: true));
      for (final name in ['a.jpg', 'b.png', 'c.mkv', 'd.txt']) {
        await File('${dir.path}/$name').writeAsString('x');
      }
      final items = await LibrarySources().list(
        LibraryEntry(LibrarySource.local, dir.path, 'Ghibli', folder: true),
      );
      expect(items.map((e) => e.name), ['a.jpg', 'b.png', 'c.mkv']);
    });
  });

  group('Sessão de nuvem persistente', () {
    test('refresh token salvo é reconhecido e Sair da conta remove', () async {
      SharedPreferences.setMockInitialValues({
        'sixf.oauth.refresh.oneDrive': 'refresh-salvo',
      });
      final sources = LibrarySources();
      expect(await sources.hasSavedSession(LibrarySource.oneDrive), isTrue);
      await sources.signOut(LibrarySource.oneDrive);
      expect(await sources.hasSavedSession(LibrarySource.oneDrive), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sixf.oauth.refresh.oneDrive'), isNull);
    });
  });

  group('Proxy de streaming sob demanda', () {
    late HttpServer upstream;
    late Directory dir;
    late MediaServerService server;
    final requestedRanges = <String?>[];
    final payload = List<int>.generate(1000, (i) => i % 256);

    setUp(() async {
      requestedRanges.clear();
      dir = await Directory.systemTemp.createTemp('sixf_proxy_');
      server = MediaServerService();
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        requestedRanges.add(range);
        final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range ?? '');
        if (match == null) {
          req.response.statusCode = 200;
          req.response.add(payload);
        } else {
          final s = int.parse(match.group(1)!), e = int.parse(match.group(2)!);
          req.response.statusCode = 206;
          req.response.add(payload.sublist(s, e + 1));
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.stop();
      await upstream.close(force: true);
      await dir.delete(recursive: true);
    });

    test('repassa somente o trecho pedido pela TV, sem baixar o arquivo', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final placeholder = File('${dir.path}/filme.mkv')
          ..writeAsBytesSync([0]);
        File('${placeholder.path}.cloud.json').writeAsStringSync(
          jsonEncode({
            'url': 'http://127.0.0.1:${upstream.port}/filme',
            'source': 'drive',
            'id': 'filme',
            'name': 'De Volta para o Futuro.mkv',
            'size': payload.length,
          }),
        );
        final port = await server.start();
        server.serveFile(placeholder);
        expect(server.currentMimeType, 'video/x-matroska');
        expect(server.currentContentLength, payload.length);

        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        final uri = Uri.parse('http://127.0.0.1:$port${server.mediaPath}');

        final head = await (await client.headUrl(uri)).close();
        expect(head.statusCode, HttpStatus.ok);
        expect(head.headers.contentLength, payload.length);
        await head.drain<void>();

        final req = await client.getUrl(uri);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=100-199');
        final res = await req.close();
        final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
        expect(res.statusCode, HttpStatus.partialContent);
        expect(
          res.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 100-199/${payload.length}',
        );
        expect(body, payload.sublist(100, 200));
        expect(requestedRanges.last, 'bytes=100-199');
        // Nenhum dado do filme é gravado no disco local.
        expect(placeholder.lengthSync(), 1);
        expect(
          File('${placeholder.path}.cloud.json').readAsStringSync(),
          isNot(contains('Bearer')),
        );
      }, RealHttp());
    });
  });

  testWidgets(
    'linha do tempo contém apenas −10 s e +10 s, sem Play/Pausar redundantes',
    (tester) async {
      final cast = MediaCastController();
      addTearDown(cast.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MediaSessionControls(controller: cast)),
        ),
      );
      expect(find.text('Play'), findsNothing);
      expect(find.text('Pausar'), findsNothing);
      expect(find.byTooltip('Retomar reprodução'), findsOneWidget);
      expect(find.byTooltip('Pausar reprodução'), findsNothing);
    },
  );
}
