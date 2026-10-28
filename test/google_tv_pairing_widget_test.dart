import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/ui/widgets/google_tv_pairing_dialog.dart';

import 'session_regression_test.dart' show RecordingDriver;

class PairingDriver extends RecordingDriver {
  PairingDriver() : super(TvBrand.googleTv) {
    connectionState = DeviceConnectionState.pairingPrompt;
  }
  String? code;
  @override
  Future<void> sendPairingPin(String pin) async {
    code = pin;
    if (pin != 'AF1234') {
      throw const FormatException('Código incorreto. Confira a TV.');
    }
    connectionState = DeviceConnectionState.connected;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'PIN accepts hexadecimal, retries errors and closes on success at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = PairingDriver();
      final controller = RemoteController(initialDriver: driver);
      await controller.ready;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => GoogleTvPairingDialog(
                    controller: controller,
                    deviceId: controller.activeDeviceId!,
                    driver: driver,
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('Parear'));
      await tester.pumpAndSettle();
      expect(find.text('Código incorreto. Confira a TV.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'af1234');
      await tester.tap(find.text('Parear'));
      await tester.pumpAndSettle();
      expect(driver.code, 'AF1234');
      expect(find.byType(GoogleTvPairingDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cancel disconnects the paired target', (tester) async {
    final driver = PairingDriver();
    final controller = RemoteController(initialDriver: driver);
    await controller.ready;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => GoogleTvPairingDialog(
                  controller: controller,
                  deviceId: controller.activeDeviceId!,
                  driver: driver,
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(driver.connectionState, DeviceConnectionState.disconnected);
    expect(find.byType(GoogleTvPairingDialog), findsNothing);
  });
}
