import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/lg_webos_driver.dart';
import 'package:sixf_remote/services/drivers/samsung_tizen_driver.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/ui/views/remote_view.dart';
import 'package:sixf_remote/ui/widgets/app_drawer_widget.dart';

/// Driver Mock para simular aplicativos instalados em testes
class MockAppDriver implements TvDriver {
  @override
  TvBrand get brand => TvBrand.lgWebOs;

  @override
  String get brandDisplayName => 'Mock TV';

  @override
  DeviceConnectionState connectionState = DeviceConnectionState.disconnected;

  @override
  bool get isConnected => connectionState == DeviceConnectionState.connected;

  @override
  bool get supportsTrackpad => true;

  @override
  bool get supportsPairingPin => false;

  @override
  void Function(DeviceConnectionState state)? onStateChanged;
  @override
  void Function(String token)? onAuthTokenReceived;
  @override
  void Function(String error)? onError;
  @override
  void Function(String deviceName, String? modelName)? onDeviceNameResolved;
  @override
  void Function(int volume, bool isMuted)? onVolumeStatusChanged;
  @override
  void Function(bool promptPin)? onPinPromptRequested;

  final List<String> launchedApps = [];
  List<TvAppInfo> mockApps = [
    TvAppInfo.fromRaw(id: 'netflix', name: 'Netflix'),
    TvAppInfo.fromRaw(id: 'youtube.leanback.v4', name: 'YouTube'),
    TvAppInfo.fromRaw(id: 'amazon', name: 'Prime Video'),
  ];

  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    connectionState = DeviceConnectionState.connected;
    onStateChanged?.call(connectionState);
    return true;
  }

  @override
  void disconnect() {
    connectionState = DeviceConnectionState.disconnected;
    onStateChanged?.call(connectionState);
  }

  @override
  void openApp(String appId) {
    launchedApps.add(appId);
  }

  @override
  Future<List<TvAppInfo>> getInstalledApps() async {
    return mockApps;
  }

  @override
  void sendDigit(int digit) {}
  @override
  void sendKey(RemoteKey key) {}
  @override
  Future<void> sendPairingPin(String pin) async {}
  @override
  void sendText(String text) {}
  @override
  void sendTrackpadClick() {}
  @override
  void sendTrackpadDelta(double dx, double dy) {}
  @override
  void setMute(bool mute) {}
  @override
  void setVolume(int volume) {}
  @override
  void triggerVoice() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TvAppInfo Unit Tests', () {
    test('Identifica corretamente serviços populares a partir do id ou nome', () {
      final netflix = TvAppInfo.fromRaw(id: 'netflix', name: 'Netflix');
      expect(netflix.iconKey, equals('netflix'));
      expect(netflix.brandColor, isNotNull);

      final youtube = TvAppInfo.fromRaw(id: 'com.google.android.youtube.tv', name: 'YouTube');
      expect(youtube.iconKey, equals('youtube'));

      final prime = TvAppInfo.fromRaw(id: 'amazon', name: 'Prime Video');
      expect(prime.iconKey, equals('prime'));

      final disney = TvAppInfo.fromRaw(id: 'disney', name: 'Disney+');
      expect(disney.iconKey, equals('disney'));

      final spotify = TvAppInfo.fromRaw(id: 'spotify', name: 'Spotify');
      expect(spotify.iconKey, equals('spotify'));

      final browser = TvAppInfo.fromRaw(id: 'org.tizen.browser', name: 'Navegador');
      expect(browser.iconKey, equals('browser'));

      final generic = TvAppInfo.fromRaw(id: 'custom.app', name: 'Minha TV');
      expect(generic.iconKey, equals('generic'));
    });
  });

  group('Driver getInstalledApps Unit Tests', () {
    test('SamsungTizenDriver retorna catálogo curado de streaming', () async {
      final samsungDriver = SamsungTizenDriver();
      final apps = await samsungDriver.getInstalledApps();

      expect(apps, isNotEmpty);
      expect(apps.any((a) => a.name == 'YouTube'), isTrue);
      expect(apps.any((a) => a.name == 'Netflix'), isTrue);
      expect(apps.any((a) => a.name == 'Prime Video'), isTrue);
      expect(apps.any((a) => a.name == 'Disney+'), isTrue);
      expect(apps.any((a) => a.name == 'Spotify'), isTrue);
    });

    test('LgWebOsDriver retorna lista vazia quando desconectado', () async {
      final lgDriver = LgWebOsDriver();
      final apps = await lgDriver.getInstalledApps();
      expect(apps, isEmpty);
    });
  });

  group('RemoteController Apps State Tests', () {
    test('fetchInstalledApps atualiza lista e dispara notificação', () async {
      final mockDriver = MockAppDriver();
      final controller = RemoteController(initialDriver: mockDriver);

      expect(controller.installedApps, isEmpty);
      expect(controller.isLoadingApps, isFalse);

      await controller.fetchInstalledApps();

      expect(controller.installedApps.length, equals(3));
      expect(controller.installedApps[0].name, equals('Netflix'));
      expect(controller.installedApps[1].name, equals('YouTube'));
      expect(controller.installedApps[2].name, equals('Prime Video'));
    });

    test('openApp despacha para o driver e registra log', () {
      final mockDriver = MockAppDriver();
      final controller = RemoteController(initialDriver: mockDriver);

      controller.openApp('netflix', appName: 'Netflix');

      expect(mockDriver.launchedApps, contains('netflix'));
      expect(controller.lastActionMessage, contains('Netflix'));
    });

    test('Alternância de marca limpa os aplicativos carregados', () {
      final mockDriver = MockAppDriver();
      final controller = RemoteController(initialDriver: mockDriver);

      controller.selectBrand(TvBrand.samsungTizen);
      expect(controller.installedApps, isEmpty);
    });
  });

  group('AppDrawerWidget Widget Tests', () {
    testWidgets('Exibe estado desconectado quando a TV não está conectada', (tester) async {
      final mockDriver = MockAppDriver();
      final controller = RemoteController(initialDriver: mockDriver);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<RemoteController>.value(
              value: controller,
              child: const AppDrawerWidget(),
            ),
          ),
        ),
      );

      expect(find.text('Smart TV Desconectada'), findsOneWidget);
      expect(find.text('Conectar TV'), findsOneWidget);
    });

    testWidgets('Exibe lista de apps e permite busca por texto', (tester) async {
      final mockDriver = MockAppDriver();
      final controller = RemoteController(initialDriver: mockDriver);

      // Simula TV conectada com apps
      await controller.connect(ip: '192.168.1.50');
      await controller.fetchInstalledApps();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<RemoteController>.value(
              value: controller,
              child: const AppDrawerWidget(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verifica exibição dos apps
      expect(find.text('Netflix'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Prime Video'), findsOneWidget);

      // Digita no campo de busca
      await tester.enterText(find.byType(TextField), 'You');
      await tester.pumpAndSettle();

      // Agora só YouTube deve estar visível
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Netflix'), findsNothing);
      expect(find.text('Prime Video'), findsNothing);

      // Toca no YouTube para abrir
      await tester.tap(find.text('YouTube'));
      await tester.pumpAndSettle();

      expect(mockDriver.launchedApps, contains('youtube.leanback.v4'));
    });

    testWidgets('Navega para a 4ª aba (Apps) no RemoteView Mobile', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockDriver = MockAppDriver();
      final controller = RemoteController(initialDriver: mockDriver);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<RemoteController>.value(
            value: controller,
            child: const RemoteView(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verifica que a 4ª aba "Apps" existe na barra inferior
      final appsTabFinder = find.text('Apps');
      expect(appsTabFinder, findsOneWidget);

      // Toca na aba "Apps"
      await tester.tap(appsTabFinder);
      await tester.pumpAndSettle();

      // Verifica que a tela de aplicativos está ativa
      expect(find.text('Aplicativos & Atalhos'), findsOneWidget);
    });
  });
}
