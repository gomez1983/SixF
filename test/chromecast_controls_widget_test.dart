import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/google_tv_driver.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/ui/widgets/dpad_widget.dart';
import 'package:sixf_remote/ui/widgets/system_navigation_controls.dart';
import 'package:sixf_remote/ui/widgets/remote_button.dart';
import 'package:sixf_remote/ui/widgets/volume_channel_controls.dart';
import 'package:sixf_remote/ui/widgets/voice_listening_dialog.dart';

import 'session_regression_test.dart' show RecordingDriver;

class VoiceDriver extends GoogleTvDriver {
  int starts = 0, stops = 0;
  @override
  Future<void> startVoice() async {
    starts++;
  }

  @override
  Future<void> stopVoice() async {
    stops++;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [320.0, 393.0, 1280.0]) {
    testWidgets(
      'D-pad e botão Voltar mantêm posição padronizada na largura $width entre TV e Chromecast',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = RemoteController(
          initialDriver: RecordingDriver(TvBrand.googleTv),
        );
        await controller.ready;
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: controller,
            child: const MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [SystemNavigationControls(), DPadWidget()],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final wheel = find.byKey(const Key('chromecast-dpad'));
        final back = find.byKey(const Key('chromecast-back'));
        final home = find.byWidgetPredicate(
          (w) => w is RemoteButton && w.label == 'HOME',
        );

        final googleWheelCenter = tester.getCenter(wheel);
        final googleWheelSize = tester.getSize(wheel);
        final googleBackCenter = tester.getCenter(back);
        final googleBackSize = tester.getSize(back);
        final googleHomeCenter = tester.getCenter(home);

        // Roda sempre centralizada e Voltar alinhado na lateral esquerda da roda
        expect(googleWheelCenter.dx, closeTo(width / 2, 0.1));
        expect(googleBackCenter.dx, lessThan(tester.getTopLeft(wheel).dx));
        expect(googleBackCenter.dy, closeTo(googleWheelCenter.dy, 0.1));

        // Alternar para LG webOS e Samsung Tizen deve manter a exata mesma posição e tamanho
        for (final brand in [TvBrand.lgWebOs, TvBrand.samsungTizen]) {
          controller.selectBrand(brand);
          await tester.pump();
          expect(tester.getCenter(wheel).dx, closeTo(googleWheelCenter.dx, 0.1));
          expect(tester.getCenter(wheel).dy, closeTo(googleWheelCenter.dy, 0.1));
          expect(tester.getSize(wheel), googleWheelSize);
          expect(tester.getCenter(back).dx, closeTo(googleBackCenter.dx, 0.1));
          expect(tester.getCenter(back).dy, closeTo(googleBackCenter.dy, 0.1));
          expect(tester.getSize(back), googleBackSize);
          expect(tester.getCenter(home), googleHomeCenter);
        }

        controller.selectBrand(TvBrand.googleTv);
        await controller.setBackButtonOnRight(true);
        await tester.pump();
        expect(tester.getCenter(wheel).dx, closeTo(width / 2, 0.1));
        expect(tester.getCenter(back).dx, greaterThan(tester.getTopRight(wheel).dx));
        expect(tester.getCenter(back).dy, closeTo(googleWheelCenter.dy, 0.1));
        final restored = RemoteController(
          initialDriver: RecordingDriver(TvBrand.googleTv),
        );
        await restored.ready;
        expect(restored.backButtonOnRight, isTrue);
        restored.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Google TV microphone uses press/hold/release rather than a toggle',
    (tester) async {
      final driver = VoiceDriver();
      final controller = RemoteController(initialDriver: driver);
      await controller.ready;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            home: Scaffold(
              body: Center(child: VoicePttButton(controller: controller)),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(VoicePttButton)),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(driver.starts, 1);
      expect(VoiceListeningOverlay.isVisible, isTrue);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(driver.stops, greaterThanOrEqualTo(1));
      expect(VoiceListeningOverlay.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
