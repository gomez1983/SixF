import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/ui/theme/app_theme.dart';
import 'package:sixf_remote/ui/views/remote_view.dart';

import 'multi_device_test.dart' show MockMultiDeviceDriver;

/// Widgets que estouraram (arquivo e linha), coletados do relatório de erro.
final _culprits = <String>[];

/// Falha mostrando qual widget estourou.
void _expectClean(WidgetTester tester, String where) {
  final error = tester.takeException();
  if (error == null) return;
  fail('$where: $error ${_culprits.toSet().join(' | ')}');
}

/// Pente-fino de limites de tela: percorre todas as abas em celulares,
/// paisagem, janelas do Windows e desktop, com fonte normal e ampliada, e
/// falha se qualquer card/linha estourar (faixa amarela e preta de overflow).
void main() {
  const sizes = <Size>[
    Size(320, 568), // celular bem pequeno
    Size(360, 640),
    Size(393, 852),
    Size(412, 915),
    Size(430, 932),
    Size(426, 858), // janela estreita do Windows
    Size(480, 700),
    Size(640, 300), // paisagem muito baixa
    Size(740, 360),
    Size(915, 412),
    Size(840, 640), // menor desktop
    Size(1024, 700),
    Size(1280, 720),
    Size(1920, 1080),
  ];

  // (nome, criador do driver, conectar?) — a LG real (desconectada) mostra
  // TV Digital/HDMI e trackpad; os mocks conectados mostram apps e nomes.
  final devices = <(String, TvDriver? Function(), bool)>[
    ('LG real', () => null, false),
    (
      'LG conectada',
      () => MockMultiDeviceDriver(
        brand: TvBrand.lgWebOs,
        brandDisplayName: 'LG webOS',
      ),
      true,
    ),
    (
      'Chromecast conectado',
      () => MockMultiDeviceDriver(
        brand: TvBrand.googleTv,
        brandDisplayName: 'Chromecast / Google TV',
      ),
      true,
    ),
  ];

  for (final device in devices) {
    for (final scale in const [1.0, 1.3]) {
      for (final size in sizes) {
        testWidgets('sem overflow: ${device.$1}, fonte x$scale, $size', (
          tester,
        ) async {
          SharedPreferences.setMockInitialValues({});
          _culprits.clear();
          final previous = FlutterError.onError;
          FlutterError.onError = (details) {
            final match = RegExp(
              r'file:///\S+?/lib/\S+?:\d+:\d+',
            ).firstMatch(details.toString());
            if (match != null) _culprits.add(match.group(0)!);
            previous?.call(details);
          };
          addTearDown(() => FlutterError.onError = previous);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          final driver = device.$2();
          final remote = driver == null
              ? RemoteController()
              : RemoteController(initialDriver: driver);
          await remote.ready;
          if (device.$3) {
            await remote.connect(ip: remote.ipAddress);
            await remote.fetchInstalledApps(forceRefresh: true);
          }
          final cast = MediaCastController();

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: remote),
                ChangeNotifierProvider.value(value: cast),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                home: const RemoteView(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          _expectClean(tester, 'aba 0 (inicial)');

          for (final tab in [1, 2, 3, 4, 0]) {
            final nav = find.byKey(ValueKey('nav-$tab'));
            if (nav.evaluate().isEmpty) continue; // aba ausente (trackpad)
            await tester.tap(nav.first);
            await tester.pumpAndSettle();
            _expectClean(tester, 'aba $tab');
          }

          await tester.pumpWidget(const SizedBox());
          remote.dispose();
          cast.dispose();
        });
      }
    }
  }
}
