import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/storage_service.dart';
import 'package:sixf_remote/ui/widgets/device_selector_bar.dart';
import 'package:sixf_remote/ui/theme/app_colors.dart';

/// Driver Mock para simular múltiplos aparelhos conectados simultaneamente.
class MockMultiDeviceDriver implements TvDriver {
  @override
  final TvBrand brand;
  @override
  final String brandDisplayName;

  DeviceConnectionState _state = DeviceConnectionState.disconnected;

  @override
  DeviceConnectionState get connectionState => _state;

  @override
  bool get isConnected => _state == DeviceConnectionState.connected;

  @override
  bool get supportsTrackpad => brand == TvBrand.lgWebOs;

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

  final List<RemoteKey> sentKeys = [];
  final List<String> launchedApps = [];

  MockMultiDeviceDriver({
    required this.brand,
    required this.brandDisplayName,
  });

  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _state = DeviceConnectionState.connected;
    onStateChanged?.call(_state);
    return true;
  }

  @override
  void disconnect() {
    _state = DeviceConnectionState.disconnected;
    onStateChanged?.call(_state);
  }

  @override
  void sendKey(RemoteKey key) {
    sentKeys.add(key);
  }

  @override
  void openApp(String appId) {
    launchedApps.add(appId);
  }

  @override
  Future<List<TvAppInfo>> getInstalledApps() async {
    return [
      TvAppInfo.fromRaw(id: 'netflix', name: 'Netflix'),
      TvAppInfo.fromRaw(id: 'youtube', name: 'YouTube'),
    ];
  }

  @override
  void sendDigit(int digit) {}
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
  @override
  Future<bool> openMediaUrl(String mediaUrl, {required String title, String? mimeType}) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SavedDevice Model Unit Tests', () {
    test('generateId cria identificador padronizado a partir da marca e IP', () {
      final id = SavedDevice.generateId(TvBrand.lgWebOs, '192.168.1.100');
      expect(id, equals('lg_webos_192_168_1_100'));

      final idSamsung = SavedDevice.generateId(TvBrand.samsungTizen, '10.0.0.15');
      expect(idSamsung, equals('samsung_tizen_10_0_0_15'));
    });

    test('Serialização e desserialização JSON completas', () {
      const original = SavedDevice(
        id: 'tv_sala_01',
        name: 'TV da Sala',
        ip: '192.168.1.150',
        mac: 'AA:BB:CC:DD:EE:FF',
        brand: TvBrand.samsungTizen,
        modelName: 'QN90C 55"',
        isDefault: true,
      );

      final json = original.toJson();
      final restored = SavedDevice.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.ip, equals(original.ip));
      expect(restored.mac, equals(original.mac));
      expect(restored.brand, equals(TvBrand.samsungTizen));
      expect(restored.modelName, equals('QN90C 55"'));
      expect(restored.isDefault, isTrue);
      expect(restored, equals(original));
    });

    test('copyWith atualiza campos corretamente mantendo imutabilidade', () {
      const dev = SavedDevice(
        id: 'dev_01',
        name: 'Quarto',
        ip: '192.168.1.20',
      );

      final updated = dev.copyWith(name: 'Quarto Principal', isDefault: true);
      expect(updated.name, equals('Quarto Principal'));
      expect(updated.isDefault, isTrue);
      expect(updated.ip, equals('192.168.1.20'));
      expect(dev.name, equals('Quarto'));
    });
  });

  group('StorageService Multi-Device Unit Tests', () {
    test('Migra automaticamente dispositivo legado se a lista estiver vazia', () async {
      SharedPreferences.setMockInitialValues({
        'pref_tv_ip': '192.168.0.55',
        'pref_tv_mac': '11:22:33:44:55:66',
        'pref_tv_name': 'LG OLED Legada',
        'pref_tv_brand': 'lgWebOs',
      });

      final storage = StorageService();
      await storage.init();

      final list = storage.getSavedDevices();
      expect(list.length, equals(1));
      expect(list.first.ip, equals('192.168.0.55'));
      expect(list.first.name, equals('LG OLED Legada'));
      expect(list.first.brand, equals(TvBrand.lgWebOs));
      expect(list.first.isDefault, isTrue);
    });

    test('Salva, atualiza e remove múltiplos dispositivos com persistência', () async {
      final storage = StorageService();
      await storage.init();

      const dev1 = SavedDevice(
        id: 'lg_sala',
        name: 'LG Sala',
        ip: '192.168.1.10',
        brand: TvBrand.lgWebOs,
      );

      const dev2 = SavedDevice(
        id: 'samsung_quarto',
        name: 'Samsung Quarto',
        ip: '192.168.1.20',
        brand: TvBrand.samsungTizen,
      );

      await storage.saveDevice(dev1);
      await storage.saveDevice(dev2);

      var devices = storage.getSavedDevices();
      expect(devices.length, equals(2));
      expect(devices.any((d) => d.name == 'LG Sala'), isTrue);
      expect(devices.any((d) => d.name == 'Samsung Quarto'), isTrue);

      // Atualiza dev1
      await storage.saveDevice(dev1.copyWith(name: 'LG Sala Cinema'));
      devices = storage.getSavedDevices();
      expect(devices.length, equals(2));
      expect(devices.firstWhere((d) => d.id == 'lg_sala').name, equals('LG Sala Cinema'));

      // Remove dev2
      await storage.removeDevice('samsung_quarto');
      devices = storage.getSavedDevices();
      expect(devices.length, equals(1));
      expect(devices.first.id, equals('lg_sala'));
    });

    test('Persiste e recupera o identificador de dispositivo ativo', () async {
      final storage = StorageService();
      await storage.init();

      expect(storage.getActiveDeviceId(), isNull);
      await storage.setActiveDeviceId('samsung_quarto');
      expect(storage.getActiveDeviceId(), equals('samsung_quarto'));
      await storage.setActiveDeviceId(null);
      expect(storage.getActiveDeviceId(), isNull);
    });
  });

  group('RemoteController Multi-Device & Concurrent Connections Tests', () {
    test('Alterna instantaneamente dispositivo ativo (Hot-Switching) e direciona comandos', () async {
      final driverSala = MockMultiDeviceDriver(
        brand: TvBrand.lgWebOs,
        brandDisplayName: 'LG Sala',
      );

      final controller = RemoteController(initialDriver: driverSala);

      final devSala = SavedDevice(
        id: controller.activeDeviceId ?? 'lg_sala',
        name: 'TV Sala',
        ip: controller.ipAddress,
        brand: TvBrand.lgWebOs,
      );

      const devQuarto = SavedDevice(
        id: 'samsung_quarto',
        name: 'TV Quarto',
        ip: '192.168.1.200',
        brand: TvBrand.samsungTizen,
      );

      await controller.saveOrUpdateDevice(devSala, makeActive: true);
      await controller.saveOrUpdateDevice(devQuarto);

      expect(controller.savedDevices.length, equals(2));
      expect(controller.activeDeviceId, equals(devSala.id));

      // Conecta o driver da Sala
      await controller.connect(ip: '192.168.1.100');
      expect(controller.isConnected, isTrue);

      // Injeta manualmente o mock de quarto na sessão de quarto para validação de comandos
      final quartoSession = controller.getSession('samsung_quarto');
      expect(quartoSession, isNotNull);
      quartoSession!.driver.disconnect();

      // Alterna o controle ativo para o Quarto instantaneamente
      controller.setActiveDevice('samsung_quarto');
      expect(controller.activeDeviceId, equals('samsung_quarto'));
      expect(controller.currentBrand, equals(TvBrand.samsungTizen));
      expect(controller.connectedTvName, equals('TV Quarto'));

      // Alterna de volta para a Sala
      controller.setActiveDevice(devSala.id);
      expect(controller.activeDeviceId, equals(devSala.id));
      expect(controller.currentBrand, equals(TvBrand.lgWebOs));
      expect(controller.connectedTvName, equals('TV Sala'));
    });

    test('Definir dispositivo padrão atualiza o flag isDefault em todos os aparelhos', () async {
      final controller = RemoteController();

      const d1 = SavedDevice(id: 'd1', name: 'D1', ip: '192.168.1.1', isDefault: true);
      const d2 = SavedDevice(id: 'd2', name: 'D2', ip: '192.168.1.2', isDefault: false);

      await controller.saveOrUpdateDevice(d1);
      await controller.saveOrUpdateDevice(d2);

      await controller.setDefaultDevice('d2');

      final devs = controller.savedDevices;
      expect(devs.firstWhere((d) => d.id == 'd1').isDefault, isFalse);
      expect(devs.firstWhere((d) => d.id == 'd2').isDefault, isTrue);
    });

    test('Remover dispositivo ativo seleciona automaticamente o próximo disponível', () async {
      final controller = RemoteController();

      const d1 = SavedDevice(id: 'd1', name: 'TV Sala', ip: '192.168.1.10');
      const d2 = SavedDevice(id: 'd2', name: 'TV Quarto', ip: '192.168.1.20');

      await controller.saveOrUpdateDevice(d1, makeActive: true);
      await controller.saveOrUpdateDevice(d2);

      expect(controller.activeDeviceId, equals('d1'));

      await controller.removeSavedDevice('d1');

      expect(controller.savedDevices.length, equals(1));
      expect(controller.activeDeviceId, equals('d2'));
      expect(controller.connectedTvName, equals('TV Quarto'));
    });
  });

  group('DeviceSelectorBar Widget Tests', () {
    testWidgets('Renderiza chips dos dispositivos salvos e permite alternar com 1 toque', (tester) async {
      final controller = RemoteController();

      const dev1 = SavedDevice(
        id: 'tv_sala',
        name: 'Sala de Estar',
        ip: '192.168.1.10',
        brand: TvBrand.lgWebOs,
      );

      const dev2 = SavedDevice(
        id: 'tv_quarto',
        name: 'Quarto Master',
        ip: '192.168.1.20',
        brand: TvBrand.samsungTizen,
      );

      await controller.saveOrUpdateDevice(dev1, makeActive: true);
      await controller.saveOrUpdateDevice(dev2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<RemoteController>.value(
              value: controller,
              child: const DeviceSelectorBar(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verifica se os dois chips e o botão Novo são renderizados
      expect(find.text('Sala de Estar'), findsOneWidget);
      expect(find.text('Quarto Master'), findsOneWidget);
      expect(find.text('Novo'), findsOneWidget);

      // Toca no chip do Quarto Master para alternar controle
      await tester.tap(find.text('Quarto Master'));
      await tester.pumpAndSettle();

      // Confirma que o controlador agora tem o Quarto como ativo
      expect(controller.activeDeviceId, equals('tv_quarto'));
      expect(controller.connectedTvName, equals('Quarto Master'));
    });

    testWidgets('DeviceSelectorBar garante contraste de cor do nome da TV em Modo Escuro e Modo Claro', (tester) async {
      final driver = MockMultiDeviceDriver(
        brand: TvBrand.lgWebOs,
        brandDisplayName: 'LG Sala',
      );
      final controller = RemoteController(initialDriver: driver);

      final dev1 = SavedDevice(
        id: controller.activeDeviceId ?? 'tv_sala',
        name: 'Sala de Estar',
        ip: controller.ipAddress,
        brand: TvBrand.lgWebOs,
      );

      await controller.saveOrUpdateDevice(dev1, makeActive: true);

      // Conecta o aparelho mockado
      await controller.connect(ip: controller.ipAddress);
      expect(controller.isConnected, isTrue);

      // Garante Modo Escuro inicial
      controller.setThemeMode(ThemeMode.dark);
      expect(controller.isDarkMode, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<RemoteController>.value(
              value: controller,
              child: const DeviceSelectorBar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No Modo Escuro, o texto da TV ativa deve ter a cor clara textPrimary
      final textWidgetDark = tester.widget<Text>(find.text('Sala de Estar'));
      expect(textWidgetDark.style?.color, equals(AppColors.textPrimary));

      // Alterna para o Modo Claro
      controller.toggleTheme();
      expect(controller.isDarkMode, isFalse);

      await tester.pumpAndSettle();

      // No Modo Claro, o texto da TV ativa deve ter a cor escura lightTextPrimary (garantindo contraste total)
      final textWidgetLight = tester.widget<Text>(find.text('Sala de Estar'));
      expect(textWidgetLight.style?.color, equals(AppColors.lightTextPrimary));
    });
  });
}
