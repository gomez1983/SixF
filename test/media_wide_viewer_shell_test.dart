import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/main.dart';
import 'package:sixf_remote/ui/widgets/device_selector_bar.dart';
import 'package:sixf_remote/ui/widgets/header_bar.dart';

void main() {
  for (final size in const [
    Size(915, 412), // celular deitado (layout de paisagem)
    Size(1280, 720), // janela do Windows (layout desktop)
  ]) {
    testWidgets(
      'mídia aberta em tela deitada: visualizador de altura inteira e '
      'cabeçalho do app na coluna direita ($size)',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dir = Directory.systemTemp.createTempSync('sixf-wide-shell-');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => dir.path,
            );
        final png = await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
          final picture = recorder.endRecording();
          final image = await picture.toImage(4, 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          return bytes!.buffer.asUint8List();
        });
        for (final name in ['photo.png', 'second.png', 'third.png']) {
          File('${dir.path}/$name').writeAsBytesSync(png!);
        }
        SharedPreferences.setMockInitialValues({
          'mediaLibrary.v1': jsonEncode({
            'trail': [
              {
                'source': 'local',
                'id': dir.path,
                'name': 'Pasta',
                'folder': true,
              },
            ],
          }),
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            try {
              await dir.delete(recursive: true);
            } on FileSystemException {
              // Arquivo temporário ainda em uso: o sistema limpa depois.
            }
          });
        });

        Future<void> settleIO() async {
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 120)),
            );
            await tester.pump(const Duration(milliseconds: 100));
          }
        }

        await tester.pumpWidget(const SixFRemoteApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-3')));
        await settleIO();
        await tester.tap(find.text('Arquivos').hitTestable().first);
        await settleIO();

        final viewer = find.byKey(const ValueKey('wide-viewer-card'));
        final side = find.byKey(const ValueKey('wide-side-card'));
        Finder inSide(Finder f) => find.descendant(of: side, matching: f);
        // Só as cópias em cena (abas escondidas do IndexedStack não contam).
        final header = find.byType(HeaderBar);

        // Sem mídia aberta: cabeçalho do app no topo, como sempre.
        expect(viewer, findsNothing);
        expect(header, findsOneWidget);
        final headerTopBefore = tester.getTopLeft(header).dy;

        await tester.ensureVisible(find.text('photo.png').first);
        await tester.pump();
        await tester.tap(find.text('photo.png').hitTestable().first);
        await settleIO();
        expect(tester.takeException(), isNull);

        expect(viewer.hitTestable(), findsOneWidget);
        final viewerRect = tester.getRect(viewer.hitTestable());
        final sideRect = tester.getRect(side.hitTestable());
        // O visualizador vai do topo à base da área útil; nada acima dele.
        expect(
          viewerRect.top,
          lessThanOrEqualTo(headerTopBefore + 24),
          reason: 'sobrou cabeçalho acima do visualizador: $viewerRect',
        );
        expect(viewerRect.bottom, greaterThan(size.height - 40));
        expect(viewerRect.right, lessThanOrEqualTo(sideRect.left + 1));

        // Cabeçalho do app e aparelhos: uma única cópia visível, dentro da
        // coluna direita, junto com o carrossel e as abas.
        expect(header, findsOneWidget);
        expect(inSide(find.byType(HeaderBar)), findsOneWidget);
        expect(inSide(find.byType(DeviceSelectorBar)), findsOneWidget);
        expect(find.byType(DeviceSelectorBar), findsOneWidget);
        expect(
          inSide(find.byKey(const ValueKey('photo-thumbnail-0'))),
          findsOneWidget,
        );
        expect(inSide(find.text('Playlists')), findsOneWidget);

        // Fechar a mídia devolve o cabeçalho ao topo.
        await tester.tap(
          find.byTooltip('Fechar visualizador de fotos').hitTestable(),
        );
        await settleIO();
        expect(viewer, findsNothing);
        expect(header, findsOneWidget);
        expect(tester.getTopLeft(header).dy, headerTopBefore);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
