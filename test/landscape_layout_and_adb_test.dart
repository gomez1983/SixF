import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/main.dart';
import 'package:sixf_remote/services/google_tv_apps_adb.dart';
import 'package:sixf_remote/ui/widgets/dpad_widget.dart';
import 'package:sixf_remote/ui/widgets/system_navigation_controls.dart';
import 'package:sixf_remote/ui/widgets/volume_channel_controls.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Paisagem no celular', () {
    for (final size in const [
      Size(915, 412), // Galaxy S23 Ultra deitado
      Size(740, 360), // celular compacto deitado
      Size(640, 300), // tela bem baixa
    ]) {
      testWidgets('divide o controle em duas metades sem transbordar: $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(const SixFRemoteApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final volume = tester.getCenter(find.byType(VolumeChannelControls));
        final nav = tester.getCenter(find.byType(SystemNavigationControls));
        final dpad = tester.getCenter(find.byType(DPadWidget));
        // Volume/mudo/canal e Home/Menu na metade esquerda; D-pad na direita.
        expect(volume.dx, lessThan(dpad.dx));
        expect(nav.dx, lessThan(dpad.dx));
        expect(find.text('VOLTAR'), findsOneWidget);
        expect(find.text('TV Digital'), findsOneWidget);
        expect(find.text('HDMI 1'), findsOneWidget);

        // Navegação vai para o trilho lateral: nenhuma barra inferior.
        expect(find.text('Teclas & Mídia'), findsNothing);
        await tester.tap(find.text('Mídia'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Apps'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('retrato continua com a barra inferior', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();
      expect(find.text('Teclas & Mídia'), findsOneWidget);
    });

    for (final size in const [Size(412, 915), Size(360, 640), Size(440, 860)]) {
      testWidgets('VOL/CH e D-pad crescem com a altura da tela: $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(const SixFRemoteApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final volume = tester.getSize(find.byType(VolumeChannelControls));
        final dpad = tester.getSize(find.byKey(const Key('chromecast-dpad')));
        // Nunca menores que o tamanho compacto antigo (130 px / roda 128 px).
        expect(volume.height, greaterThanOrEqualTo(130));
        expect(dpad.width, greaterThanOrEqualTo(128));
        if (size.height >= 860) {
          // Telas altas aproveitam o espaço: bloco e roda maiores.
          expect(volume.height, greaterThan(170));
          expect(dpad.width, greaterThan(210));
        }
      });
    }
  });

  group('ADB por Depuração por Wi-Fi', () {
    test('aceita a porta sozinha ou no formato "IP:porta" da TV', () {
      expect(GoogleTvAppsAdb.parsePort('37123'), 37123);
      expect(GoogleTvAppsAdb.parsePort(' 192.168.0.50:41005 '), 41005);
      expect(GoogleTvAppsAdb.parsePort(''), isNull);
      expect(GoogleTvAppsAdb.parsePort('abc'), isNull);
      expect(GoogleTvAppsAdb.parsePort('192.168.0.50:70000'), isNull);
    });

    test('sem porta salva pede configuração (não confunde com queda)', () async {
      await expectLater(
        GoogleTvAppsAdb.command('192.168.0.77', 'echo x'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
