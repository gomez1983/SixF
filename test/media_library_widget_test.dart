import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/ui/views/media_library.dart';

import 'session_regression_test.dart' show RecordingDriver;

void main() {
  testWidgets(
    'playlist favorita abre sem TV e mantém a ordem após arrastar e reabrir',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'mediaLibrary.v1': jsonEncode({
          'lists': [
            {
              'name': 'Série',
              'favorite': true,
              'items': [
                for (final i in [1, 2, 3])
                  {
                    'source': 'drive',
                    'id': 'episode-$i',
                    'name': 'Capítulo $i.mp4',
                  },
              ],
            },
            {'name': 'Outra', 'items': []},
          ],
        }),
      });
      final tv = RemoteController(
        initialDriver: RecordingDriver(TvBrand.lgWebOs),
      );
      await tv.ready;
      addTearDown(tv.dispose);
      Widget library() => ChangeNotifierProvider.value(
        value: tv,
        child: const MaterialApp(home: MediaLibrary()),
      );
      await tester.pumpWidget(library());
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Série')).dy,
        lessThan(tester.getTopLeft(find.text('Outra')).dy),
      );
      await tester.tap(find.text('Série'));
      await tester.pumpAndSettle();
      final drag = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await tester.pump();
      await drag.moveBy(const Offset(0, 118));
      await tester.pumpAndSettle();
      await drag.up();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(library());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Série'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Capítulo 1.mp4')).dy,
        greaterThan(tester.getTopLeft(find.text('Capítulo 2.mp4')).dy),
      );
    },
  );
}
