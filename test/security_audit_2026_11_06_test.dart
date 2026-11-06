import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/services/library_sources.dart';

/// Regressões da auditoria de 06/11/2026 (SEC-09).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SEC-09: token da nuvem nunca vai para o disco', () {
    late Directory cache;

    setUp(() {
      cache = Directory.systemTemp.createTempSync('sixf-sec09-');
      SharedPreferences.setMockInitialValues({
        'sixf.oauth.access.drive': 'TOKEN-SECRETO-DO-TESTE',
        'sixf.oauth.expires.drive': DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      });
    });

    tearDown(() => cache.deleteSync(recursive: true));

    test('o descritor .cloud.json gravado por resolve() não contém o token', () async {
      const entry = LibraryEntry(
        LibrarySource.drive,
        'abc123',
        'filme.mkv',
        mimeType: 'video/x-matroska',
        size: 1024,
      );
      final file = await LibrarySources().resolve(entry, cache);
      final raw = File('${file.path}.cloud.json').readAsStringSync();
      expect(raw, isNot(contains('TOKEN-SECRETO-DO-TESTE')));
      expect(raw, isNot(contains('Bearer')));
      expect(raw.toLowerCase(), isNot(contains('authorization')));
      final data = jsonDecode(raw) as Map<String, dynamic>;
      expect(data['source'], 'drive');
      expect(data['id'], 'abc123');
      expect(data['size'], 1024);
      expect(data['url'], contains('drive/v3/files/abc123'));
    });

    test('o cabeçalho continua disponível, só em memória, para ffmpeg/legendas', () async {
      final headers = await LibrarySources.authHeadersForSourceName('drive');
      expect(headers, {'Authorization': 'Bearer TOKEN-SECRETO-DO-TESTE'});
      expect(await LibrarySources.authHeadersForSourceName(null), isNull);
    });
  });
}
