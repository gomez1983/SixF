import 'dart:ui' as ui;
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
import 'security_lifecycle_test.dart' show LocalMediaServer, RealHttp;

void main() {
  testWidgets(
    'file click offers playlist or immediate TV playback for video, audio and photo',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
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
      await tester.tap(find.text('clip.mp4'));
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
        await tester.tap(find.text(name).first);
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
          expect(
            tester.takeException(),
            isNull,
            reason: '$size, text scale $scale',
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
      expect(find.byTooltip('Reproduzir vídeo'), findsOneWidget);
      expect(find.byTooltip('Pausar vídeo'), findsOneWidget);
      expect(find.byTooltip('Repetir vídeo'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-thumbnail-0')), findsOneWidget);
      await tester.runAsync(media.stop);
      await tester.pump();
    },
  );
}
