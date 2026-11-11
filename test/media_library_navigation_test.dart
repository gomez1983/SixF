import 'glass_test_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/ui/views/remote_view.dart';
import 'package:sixf_remote/ui/views/media_library.dart';

import 'dlna_media_cast_test.dart' show FakeTvDriver;

void main() {
  for (final width in [393.0, 1000.0]) {
    testWidgets('biblioteca abre como aba inferior em largura $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = RemoteController(initialDriver: FakeTvDriver());
      final cast = MediaCastController();
      await remote.ready;
      addTearDown(remote.dispose);
      addTearDown(cast.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RemoteController>.value(value: remote),
            ChangeNotifierProvider<MediaCastController>.value(value: cast),
          ],
          child: const MaterialApp(home: RemoteView()),
        ),
      );
      await tester.pumpAndSettle();
      final libraryTabLeft = tester
          .getTopLeft(find.text(tabLibraryLabel).last)
          .dx;
      final appsTabLeft = tester.getTopLeft(find.text('Apps').last).dx;
      expect(libraryTabLeft, lessThan(appsTabLeft));
      await tester.tap(find.text(tabLibraryLabel).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Biblioteca de mídia ·'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);
      final libraryState = tester.state(find.byType(MediaLibrary));
      await tester.tap(find.text('Arquivos'));
      await tester.pumpAndSettle();
      for (final size in [
        const Size(960, 540),
        const Size(839, 640),
        const Size(840, 640),
        const Size(440, 860),
        const Size(1280, 720),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
        expect(tester.state(find.byType(MediaLibrary)), same(libraryState));
      }

      await tester.tap(find.text(tabKeysLabel).last);
      await tester.pumpAndSettle();
      expect(find.text('Atalhos de Teclado Físico (Desktop)'), findsNothing);
      await tester.tap(find.text(tabLibraryLabel).last);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(MediaLibrary)), same(libraryState));
      expect(tester.takeException(), isNull);
    });
  }
}
