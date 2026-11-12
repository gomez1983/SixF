import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/media_remux_service.dart';
import 'package:sixf_remote/ui/views/media_library.dart';
import 'package:sixf_remote/ui/widgets/media_progress_slider.dart';

import 'media_controls_gallery_widget_test.dart' show ScopedRemote;
import 'media_gallery_cast_test.dart' show SimulatedCast;
import 'security_lifecycle_test.dart' show LocalMediaServer, RealHttp;

String? _lastOverflow;

void main() {
  testWidgets(
    'file click offers playlist or immediate TV playback for video, audio and photo',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final m = RegExp(r'lib/[a-z_/]+\.dart:\d+')
            .firstMatch(details.toString());
        if (m != null) _lastOverflow = m.group(0);
        previousOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousOnError);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory.systemTemp.createTempSync('sixf-actions-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final pngBytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.blue, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(2, 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return bytes!.buffer.asUint8List();
      });
      for (final name in ['clip.mp4', 'song.mp3', 'photo.png', 'second.png']) {
        File('${dir.path}/$name')
            .writeAsBytesSync(name.endsWith('.png') ? pngBytes! : [1, 2, 3]);
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
          'lists': [
            {'name': 'Favoritos', 'items': []},
          ],
          'queue': [
            {
              'source': 'local',
              'id': '${dir.path}/missing.mp4',
              'name': 'missing.mp4',
            },
          ],
        }),
      });
      final remote = ScopedRemote();
      final receiver = SimulatedCast();
      final media = MediaCastController(
        serverService: LocalMediaServer(),
        castFactory: () => receiver,
      );
      await remote.ready;
      MediaRemuxService.setFfmpegAvailableForTesting(false);
      addTearDown(() => MediaRemuxService.setFfmpegAvailableForTesting(null));
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
          child: const MaterialApp(home: MediaLibrary()),
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
      // Regra: ao abrir uma pasta, ela aparece na grade e nada é enviado à
      // TV (nem aberto no visualizador) até o usuário pedir.
      expect(remote.isConnected, isTrue);
      expect(find.text('Na TV'), findsNothing);
      expect(receiver.loadedUrl, isNull);
      // Segurar o arquivo abre as opções (fila, playlist, enviar à TV).
      await tester.longPress(find.text('clip.mp4').first);
      await tester.pumpAndSettle();
      expect(find.text('Reproduzir agora na televisão'), findsOneWidget);
      await tester.tap(find.text('Adicionar à playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favoritos').last);
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString('mediaLibrary.v1')!,
        )['lists'][0]['items'][0]['name'],
        'clip.mp4',
      );
      await tester.tap(find.text('Arquivos'));
      await settleIO();
      for (final name in ['song.mp3', 'clip.mp4', 'photo.png']) {
        await tester.ensureVisible(find.text(name).first);
        await tester.longPress(find.text(name).first);
        await tester.pumpAndSettle();
        expect(find.text('Adicionar à playlist'), findsOneWidget);
        await tester.runAsync(
          () => HttpOverrides.runWithHttpOverrides(() async {
            await tester.tap(find.text('Reproduzir agora na televisão'));
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }, RealHttp()),
        );
        for (var n = 0; n < 40; n++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          if (media.currentFileName == name &&
              (receiver.loadedUrl?.endsWith(name) ?? false)) {
            break;
          }
        }
        await tester.pump();
        expect(
          media.currentFileName,
          name,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .join(' | '),
        );
        expect(media.errorMessage, isNull);
        expect(receiver.loadedUrl, isNotNull);
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const ValueKey('photo-thumbnail-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-thumbnail-1')), findsOneWidget);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final size in [
        const Size(393, 600),
        const Size(320, 480),
        const Size(740, 360),
      ]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          tester.view.physicalSize = size;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pump();
          final error = tester.takeException();
          expect(
            error,
            isNull,
            reason: '$size, text scale $scale ${_lastOverflow ?? ''}',
          );
        }
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(600, 1400);
      await tester.pump();
      Future<void> waitPhoto(String name) async {
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)),
          );
          if (receiver.loadedUrl?.endsWith(name) ?? false) break;
        }
        expect(media.currentFileName, name);
      }

      await tester.tap(find.byTooltip('Próxima imagem'));
      await waitPhoto('second.png');
      await tester.tap(find.byKey(const ValueKey('photo-thumbnail-0')));
      await waitPhoto('photo.png');
      await tester.tap(find.byTooltip('Próxima imagem'));
      await waitPhoto('second.png');
      await tester.tap(find.byTooltip('Imagem anterior'));
      await waitPhoto('photo.png');
      await tester.tap(find.byKey(const ValueKey('media-thumbnail-0')));
      await waitPhoto('clip.mp4');
      await tester.pump();
      // A linha do tempo precisa estar visível (é o caso do aparelho real).
      expect(
        find.byType(MediaProgressSlider),
        findsOneWidget,
        reason: 'linha do tempo do vídeo na TV',
      );
      // Vídeo tocando na TV: o card do player não pode estourar em nenhuma
      // medida (celular deitado como o S23 Ultra, janelas baixas, fonte grande).
      for (final size in [
        const Size(915, 412), // Galaxy S23 Ultra deitado
        const Size(
          915,
          390,
        ), // S23 Ultra deitado, descontando a barra de status
        const Size(915, 365), // idem, com barra de navegação por botões
        const Size(780, 412),
        const Size(700, 320),
        const Size(740, 360),
        const Size(640, 300),
        const Size(844, 390),
        const Size(1024, 600),
        const Size(393, 852),
      ]) {
        for (final scale in [1.0, 1.15, 1.3]) {
          tester.view.physicalSize = size;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(
            tester.takeException(),
            isNull,
            reason:
                'vídeo tocando: $size, fonte x$scale ${_lastOverflow ?? ''}',
          );
          // Tela deitada: o visualizador é um card próprio que ocupa a
          // altura inteira, e o carrossel fica na coluna da direita.
          if (size.width > size.height) {
            final viewer = find.byKey(const ValueKey('wide-viewer-card'));
            final side = find.byKey(const ValueKey('wide-side-card'));
            expect(viewer, findsOneWidget, reason: '$size');
            expect(
              tester.getSize(viewer).height,
              // O teste monta a biblioteca com AppBar própria (não embutida).
              greaterThan(size.height - kToolbarHeight - 24),
              reason: 'visualizador sem a altura inteira em $size',
            );
            expect(
              find.descendant(
                of: side,
                matching: find.byKey(const ValueKey('photo-thumbnail-0')),
              ),
              findsOneWidget,
              reason: 'carrossel fora da coluna direita em $size',
            );
            expect(
              find.descendant(
                of: viewer,
                matching: find.byKey(const ValueKey('photo-thumbnail-0')),
              ),
              findsNothing,
            );
          }
        }
      }
      // Coluna direita baixa (celular deitado): arrastar a lista recolhe o
      // topo (dados da mídia, carrossel, abas) e a lista ganha a altura toda.
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(915, 412);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final sideCard = find.byKey(const ValueKey('wide-side-card'));
      final closeButton = find.byTooltip('Fechar visualizador de fotos');
      final before = tester.getTopLeft(closeButton).dy;
      final sideRect = tester.getRect(sideCard);
      final nested = tester.state<NestedScrollViewState>(
        find.byType(NestedScrollView),
      );
      // A lista da aba usa o controle interno do NestedScrollView: é isso
      // que faz o arrasto da lista recolher o topo antes de rolar a lista.
      expect(nested.innerController.positions, isNotEmpty);
      await tester.dragFrom(
        Offset(sideRect.center.dx, sideRect.top + 30),
        const Offset(0, -150),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getTopLeft(closeButton).dy,
        lessThan(before - 40),
        reason: 'o topo da coluna direita não recolheu ao rolar',
      );
      await tester.dragFrom(
        Offset(sideRect.center.dx, sideRect.top + 60),
        const Offset(0, 300),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getTopLeft(closeButton).dy, closeTo(before, 1));
      expect(tester.takeException(), isNull);
      // No Windows a lista também precisa herdar o controle interno.
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      tester.view.physicalSize = const Size(916, 412);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final inheritedOnWindows = tester
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .innerController
          .positions
          .isNotEmpty;
      debugDefaultTargetPlatformOverride = null;
      expect(inheritedOnWindows, isTrue);
      await tester.pump();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(600, 1400);
      await tester.pump();
      expect(find.byTooltip('Reproduzir vídeo'), findsOneWidget);
      expect(find.byTooltip('Pausar vídeo'), findsOneWidget);
      expect(find.byTooltip('Repetir vídeo'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-thumbnail-0')), findsOneWidget);
      await tester.runAsync(() async {
        await media.stop();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
    },
  );
}
