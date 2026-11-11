import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/ui/glass/glass_flags.dart';
import 'package:sixf_remote/ui/views/remote_view.dart';

import 'dlna_media_cast_test.dart' show FakeTvDriver;

void main() {
  // Regressão: no Android o primeiro quadro chega com a tela 0x0; a roda do
  // D-pad em vidro calculava tamanho negativo e a árvore caía (tela vermelha
  // '_elements.contains(element)' no S23 Ultra).
  testWidgets('vidro sobrevive ao primeiro quadro 0x0 do Android', (tester) async {
    final previousGlass = kGlassUi;
    kGlassUi = true;
    addTearDown(() => kGlassUi = previousGlass);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(0, 0);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final remote = RemoteController(initialDriver: FakeTvDriver());
    final cast = MediaCastController();
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
    for (final s in const [
      Size(1080, 2340),
      Size(2340, 1080),
      Size(1080, 2340),
      Size(1440, 3088),
    ]) {
      tester.view.physicalSize = s;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: '$s');
    }
    await remote.ready;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
