import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/haptic_service.dart';
import 'package:sixf_remote/services/ssdp_discovery_service.dart';
import 'package:sixf_remote/ui/widgets/device_discovery_dialog.dart';
import 'package:sixf_remote/ui/widgets/remote_button.dart';

import 'session_regression_test.dart' show RecordingDriver;

class DiscoveryPreview extends RemoteController {
  DiscoveryPreview() : super(driverFactory: RecordingDriver.new);
  DeviceConnectionState state = DeviceConnectionState.disconnected;
  @override
  bool get isConnected => state == DeviceConnectionState.connected;
  @override
  bool get isConnecting => state == DeviceConnectionState.connecting;
  @override
  bool get isWaitingPairing => state == DeviceConnectionState.pairingPrompt;
  @override
  String get ipAddress => '192.168.1.10';
  @override
  List<DiscoveredTv> get discoveredTvs => const [
    DiscoveredTv(
      ip: '192.168.1.10',
      name: 'TV LG da sala com nome comprido',
      modelName: '49LF5900-SA',
    ),
    DiscoveredTv(
      ip: '192.168.1.11',
      name: 'Samsung do quarto',
      brand: TvBrand.samsungTizen,
    ),
  ];
  @override
  Future<List<DiscoveredTv>> scanForTvs() async => discoveredTvs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 360.0, 393.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('busca com TVs salvas e novas cabe em $width, fonte $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = DiscoveryPreview();
        await controller.ready;
        await controller.saveOrUpdateDevice(
          const SavedDevice(id: 'lg', name: 'Sala', ip: '192.168.1.10'),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<RemoteController>.value(
            value: controller,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const Scaffold(body: DeviceDiscoveryDialog()),
            ),
          ),
        );
        await tester.pump();
        expect(find.textContaining('49LF5900-SA'), findsOneWidget);
        expect(find.text('Salvo'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final state in [
          DeviceConnectionState.connecting,
          DeviceConnectionState.pairingPrompt,
        ]) {
          controller.state = state;
          controller.notifyListeners();
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('segurar volume vibra em cada comando e para ao soltar', (
    tester,
  ) async {
    final previousEnabled = HapticService.isEnabled;
    HapticService.isEnabled = true;
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      HapticService.isEnabled = previousEnabled;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteButton(
            width: 60,
            height: 60,
            icon: Icons.add,
            repeatOnHold: true,
            onPressed: () => presses++,
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RemoteButton)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 360));
    expect(presses, greaterThan(1));
    expect(calls, hasLength(presses));
    expect(
      calls.every((call) => call.arguments == 'HapticFeedbackType.lightImpact'),
      isTrue,
    );
    await gesture.up();
    final count = presses;
    await tester.pump(const Duration(milliseconds: 360));
    expect(presses, count);
    expect(calls, hasLength(count));
    HapticService.isEnabled = false;
    await tester.tap(find.byType(RemoteButton));
    await tester.pump();
    expect(presses, count + 1);
    expect(calls, hasLength(count));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
