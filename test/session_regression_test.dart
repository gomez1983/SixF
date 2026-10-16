import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/lg_webos_driver.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/ssdp_discovery_service.dart';

class RecordingDriver extends Fake implements TvDriver {
  RecordingDriver(this.brand);

  @override
  final TvBrand brand;
  @override
  String get brandDisplayName => brand.displayName;
  @override
  DeviceConnectionState connectionState = DeviceConnectionState.disconnected;
  @override
  bool get isConnected => connectionState == DeviceConnectionState.connected;

  @override
  void Function(DeviceConnectionState)? onStateChanged;
  @override
  void Function(String)? onAuthTokenReceived;
  @override
  void Function(String)? onError;
  @override
  void Function(String, String?)? onDeviceNameResolved;
  @override
  void Function(int, bool)? onVolumeStatusChanged;
  @override
  void Function(bool)? onPinPromptRequested;

  final connectedIps = <String>[];
  final receivedTokens = <String?>[];
  final failIps = <String>{};
  final sentKeys = <RemoteKey>[];
  void Function()? beforeConnect;

  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    beforeConnect?.call();
    connectedIps.add(ipAddress);
    receivedTokens.add(authToken);
    if (failIps.contains(ipAddress)) {
      connectionState = DeviceConnectionState.disconnected;
      onStateChanged?.call(connectionState);
      return false;
    }
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
  void sendKey(RemoteKey key) => sentKeys.add(key);

  @override
  Future<List<TvAppInfo>> getInstalledApps() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final controllers = <RemoteController>[];

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<RemoteController> createController({
    TvDriver Function(TvBrand)? factory,
    Future<List<DiscoveredTv>> Function({Duration timeout, String? knownIp})? discoveryRunner,
  }) async {
    final controller = RemoteController(
      driverFactory: factory,
      discoveryRunner: discoveryRunner,
    );
    controllers.add(controller);
    await pumpEventQueue();
    return controller;
  }

  tearDown(() async {
    for (final controller in controllers) {
      controller.disconnectAllDevices();
    }
    await pumpEventQueue();
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });

  test('Cada LG recebe transporte e callbacks independentes', () async {
    final controller = await createController();
    final firstId = controller.activeDeviceId!;
    final first = controller.driver as LgWebOsDriver;
    const other = SavedDevice(
      id: 'lg_other',
      name: 'Outra LG',
      ip: '192.168.1.201',
    );
    await controller.saveOrUpdateDevice(other);
    final second = controller.getSession(other.id)!.driver as LgWebOsDriver;

    expect(identical(first.webOsService, second.webOsService), isFalse);
    first.webOsService.onVolumeStatusChanged!(47, true);
    expect(controller.volumeLevel, 47);
    expect(controller.isMuted, isTrue);
    expect(controller.getSession(other.id)!.volumeLevel, 18);

    second.webOsService.onVolumeStatusChanged!(62, false);
    expect(controller.volumeLevel, 47);
    controller.setActiveDevice(other.id);
    expect(controller.volumeLevel, 62);
    expect(controller.isMuted, isFalse);
    expect(controller.getSession(firstId)!.volumeLevel, 47);
  });

  test(
    'Sessão inicial recebe estado, energia, nome e volume do driver',
    () async {
      final controller = await createController(factory: RecordingDriver.new);
      final driver = controller.driver as RecordingDriver;
      await controller.connectDevice(controller.activeDeviceId!);
      driver.onVolumeStatusChanged!(47, true);
      driver.onDeviceNameResolved!('TV identificada', 'Modelo teste');
      await pumpEventQueue();

      expect(controller.isConnected, isTrue);
      expect(controller.isPoweredOn, isTrue);
      expect(controller.shouldMaintainConnection, isTrue);
      expect(controller.volumeLevel, 47);
      expect(controller.isMuted, isTrue);
      expect(controller.activeDevice!.name, 'TV identificada');
      expect(controller.activeDevice!.modelName, 'Modelo teste');
      expect(controller.savedDevices.single.name, 'TV identificada');
    },
  );

  for (final secondBrand in TvBrand.values) {
    test('LG + ${secondBrand.name}: comandos e desconexão isolados', () async {
      final controller = await createController(factory: RecordingDriver.new);
      final firstId = controller.activeDeviceId!;
      final first = controller.driver as RecordingDriver;
      final other = SavedDevice(
        id: 'other',
        name: 'Outra TV',
        ip: '192.168.1.201',
        brand: secondBrand,
      );
      await controller.saveOrUpdateDevice(other);
      final second = controller.getSession(other.id)!.driver as RecordingDriver;

      await controller.connectAllDevices();
      expect(controller.isDeviceConnected(firstId), isTrue);
      expect(controller.isDeviceConnected(other.id), isTrue);
      controller.dpadUp();
      controller.setActiveDevice(other.id);
      controller.dpadDown();
      expect(first.sentKeys, [RemoteKey.dpadUp]);
      expect(second.sentKeys, [RemoteKey.dpadDown]);

      await controller.removeSavedDevice(firstId);
      expect(first.isConnected, isFalse);
      expect(second.isConnected, isTrue);
      expect(controller.activeDeviceId, other.id);
    });
  }

  test('Trocar marca para LG mantém transporte de outra LG isolado', () async {
    final controller = await createController();
    final first = controller.driver as LgWebOsDriver;
    const other = SavedDevice(
      id: 'other',
      name: 'Outra TV',
      ip: '192.168.1.202',
      brand: TvBrand.samsungTizen,
    );
    await controller.saveOrUpdateDevice(other, makeActive: true);
    controller.selectBrand(TvBrand.lgWebOs);
    final second = controller.driver as LgWebOsDriver;
    expect(identical(first.webOsService, second.webOsService), isFalse);
    first.webOsService.onVolumeStatusChanged!(32, false);
    expect(controller.volumeLevel, 18);
    second.webOsService.onVolumeStatusChanged!(61, true);
    expect(controller.volumeLevel, 61);
    expect(controller.isMuted, isTrue);
  });

  test('Primeiro clique cadastra e ativa antes de iniciar conexão', () async {
    late RemoteController controller;
    controller = await createController(
      factory: (brand) {
        final driver = RecordingDriver(brand);
        if (brand == TvBrand.samsungTizen) {
          driver.beforeConnect = () {
            expect(controller.activeDevice!.ip, '192.168.1.203');
            expect(
              controller.storageService.getSavedDevices().any(
                (device) => device.ip == '192.168.1.203',
              ),
              isTrue,
            );
          };
        }
        return driver;
      },
    );
    const tv = DiscoveredTv(
      ip: '192.168.1.203',
      name: 'TV descoberta',
      brand: TvBrand.samsungTizen,
    );

    await controller.connectToTv(tv);
    final driver = controller.driver as RecordingDriver;
    expect(driver.connectedIps, [tv.ip]);
    expect(controller.isConnected, isTrue);
    expect(controller.activeDeviceId, SavedDevice.generateId(tv.brand, tv.ip));
  });

  test('Descoberta reconecta usando ID existente e preserva apelido', () async {
    final controller = await createController(factory: RecordingDriver.new);
    const saved = SavedDevice(
      id: 'custom_saved_id',
      name: 'Sala',
      ip: '192.168.1.204',
      brand: TvBrand.samsungTizen,
    );
    await controller.saveOrUpdateDevice(saved);
    const tv = DiscoveredTv(
      ip: '192.168.1.204',
      name: 'Nome anunciado',
      brand: TvBrand.samsungTizen,
    );
    await controller.connectToTv(tv);

    expect(controller.activeDeviceId, saved.id);
    expect(controller.connectedTvName, 'Sala');
    expect((controller.driver as RecordingDriver).connectedIps, [tv.ip]);
    expect(controller.isConnected, isTrue);
    expect(controller.savedDevices.where((d) => d.ip == tv.ip).length, 1);
  });

  test(
    'Redescoberta após mudança de IP via DHCP preserva client-key pareada mesmo com dispositivo padrão presente',
    () async {
      final controller = await createController(factory: RecordingDriver.new);
      const initialTv = DiscoveredTv(
        ip: '192.168.15.10',
        name: 'LG Smart TV (192.168.15.10)',
        brand: TvBrand.lgWebOs,
      );

      await controller.connectToTv(initialTv);
      final pairedId = controller.activeDeviceId!;
      final driver = controller.driver as RecordingDriver;

      // Simula entrega do client-key após confirmação na TV e resolução apenas do modelName (webOS 2.0)
      driver.onAuthTokenReceived!('lg-secret-key-49lf5900');
      driver.onDeviceNameResolved!('', '49LF5900-SA');
      await pumpEventQueue();

      expect(controller.activeDevice!.modelName, '49LF5900-SA');

      // Roteador muda o IP via DHCP para 192.168.15.22 e probe HTTP anuncia sem modelName
      const dhcpRotatedTv = DiscoveredTv(
        ip: '192.168.15.22',
        name: 'LG Smart TV (192.168.15.22)',
        brand: TvBrand.lgWebOs,
      );

      expect(controller.isTvSaved(dhcpRotatedTv), isTrue);

      await controller.connectToTv(dhcpRotatedTv);
      expect(controller.activeDeviceId, pairedId);
      expect(controller.activeDevice!.ip, '192.168.15.22');
      expect(driver.receivedTokens.last, 'lg-secret-key-49lf5900');
    },
  );

  test(
    'connectDevice em aparelho salvo reconcilia novo IP via descoberta quando IP antigo falha (DHCP)',
    () async {
      const rotatedTv = DiscoveredTv(
        ip: '192.168.15.35',
        name: 'LG Smart TV (192.168.15.35)',
        brand: TvBrand.lgWebOs,
        modelName: '49LF5900-SA',
      );

      final controller = await createController(
        factory: RecordingDriver.new,
        discoveryRunner: ({timeout = const Duration(seconds: 4), knownIp}) async => [rotatedTv],
      );

      const saved = SavedDevice(
        id: 'lg_webos_192_168_15_10',
        name: 'TV da Sala',
        ip: '192.168.15.10',
        brand: TvBrand.lgWebOs,
        modelName: '49LF5900-SA',
      );
      await controller.saveOrUpdateDevice(saved, makeActive: true);
      await controller.storageService.setClientKey(
        'persisted-lg-token',
        brand: saved.brand,
        ip: saved.ip,
        deviceId: saved.id,
      );

      final driver = controller.driver as RecordingDriver;
      driver.failIps.add('192.168.15.10');

      await controller.connectDevice(saved.id);

      expect(driver.connectedIps, ['192.168.15.10', '192.168.15.35']);
      expect(driver.receivedTokens, ['persisted-lg-token', 'persisted-lg-token']);
      expect(controller.isConnected, isTrue);
      expect(controller.activeDevice!.ip, '192.168.15.35');
      expect(controller.activeDevice!.name, 'TV da Sala');
    },
  );
}
