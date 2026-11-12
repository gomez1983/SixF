import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/ui/views/media_library.dart';

import 'media_controls_gallery_widget_test.dart' show ScopedRemote;
import 'media_gallery_cast_test.dart' show SimulatedCast;
import 'security_lifecycle_test.dart' show LocalMediaServer;

const _folders = [
  'Arquivos computador',
  'Google AI Studio',
  'Google Earth',
  'Midia',
  'Pessoal',
  'Trabalho',
];

void main() {
  Future<void> pumpLibrary(
    WidgetTester tester,
    Directory dir, {
    List<List<Map<String, Object>>> recent = const [],
    bool openFolder = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
    final root = {
      'source': 'local',
      'id': dir.path,
      'name': 'Pasta',
      'folder': true,
    };
    SharedPreferences.setMockInitialValues({
      'mediaLibrary.v1': jsonEncode({
        if (openFolder) 'trail': [root],
        'recent': recent,
      }),
    });
    final remote = ScopedRemote();
    final media = MediaCastController(
      serverService: LocalMediaServer(),
      castFactory: SimulatedCast.new,
    );
    await remote.ready;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
      media.dispose();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await dir.delete(recursive: true);
      });
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RemoteController>.value(value: remote),
          ChangeNotifierProvider.value(value: media),
        ],
        child: const MaterialApp(
          home: Scaffold(body: MediaLibrary(embedded: true)),
        ),
      ),
    );
    Future<void> settleIO() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
    }

    await settleIO();
    await tester.tap(find.text('Arquivos'));
    await settleIO();
  }

  testWidgets(
    'celular deitado: todas as pastas ficam alcançáveis rolando a lista',
    (tester) async {
      // Área da aba Mídia num celular deitado, já sem o trilho lateral e o
      // cabeçalho do app.
      tester.view.physicalSize = const Size(700, 300);
      final dir = Directory.systemTemp.createTempSync('sixf-landscape-');
      for (final name in _folders) {
        Directory('${dir.path}/$name').createSync();
      }
      await pumpLibrary(tester, dir);
      expect(find.text(_folders.first), findsOneWidget);

      // Arrasta a própria lista, como o dedo do usuário faz.
      await tester.drag(find.text(_folders.first), const Offset(0, -400));
      await tester.pumpAndSettle();

      final last = find.text(_folders.last);
      expect(last, findsOneWidget);
      final rect = tester.getRect(last);
      expect(
        rect.bottom,
        lessThanOrEqualTo(300),
        reason: 'a última pasta ficou abaixo da área visível: $rect',
      );
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(last.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('botão Limpar apaga a lista de abertas recentemente', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    final dir = Directory.systemTemp.createTempSync('sixf-recent-');
    final root = <String, Object>{
      'source': 'local',
      'id': dir.path,
      'name': 'Pasta secreta',
      'folder': true,
    };
    await pumpLibrary(
      tester,
      dir,
      recent: [
        [root],
      ],
      openFolder: false,
    );
    expect(find.text('ABERTAS RECENTEMENTE'), findsOneWidget);
    expect(find.text('Pasta secreta'), findsWidgets);

    final clear = find.byKey(const ValueKey('library-clear-recent'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.text('ABERTAS RECENTEMENTE'), findsNothing);
    expect(find.text('Pasta secreta'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('mediaLibrary.v1')!);
    expect(saved['recent'], isEmpty);
    // Fecha o aviso (SnackBar) antes de desmontar.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
