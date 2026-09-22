import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/driver_factory.dart';
import 'package:sixf_remote/services/drivers/lg_webos_driver.dart';
import 'package:sixf_remote/services/drivers/samsung_tizen_driver.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TvBrand & DriverFactory Unit Tests', () {
    test('Valida nomes de exibição e IDs de TvBrand', () {
      expect(TvBrand.lgWebOs.displayName, 'LG webOS');
      expect(TvBrand.lgWebOs.id, 'lg_webos');

      expect(TvBrand.samsungTizen.displayName, 'Samsung Tizen');
      expect(TvBrand.samsungTizen.id, 'samsung_tizen');
    });

    test('DriverFactory instancia cada driver correspondente à marca', () {
      final lg = DriverFactory.create(TvBrand.lgWebOs);
      expect(lg, isA<LgWebOsDriver>());
      expect(lg.brand, TvBrand.lgWebOs);
      expect(lg.supportsTrackpad, isTrue);
      expect(lg.supportsPairingPin, isFalse);

      final samsung = DriverFactory.create(TvBrand.samsungTizen);
      expect(samsung, isA<SamsungTizenDriver>());
      expect(samsung.brand, TvBrand.samsungTizen);
      expect(samsung.supportsTrackpad, isFalse);
      expect(samsung.supportsPairingPin, isFalse);
    });
  });

  group('LgWebOsDriver Unit Tests', () {
    late LgWebOsDriver driver;

    setUp(() {
      driver = LgWebOsDriver();
    });

    tearDown(() {
      driver.disconnect();
    });

    test('Estado inicial é desconectado e callbacks funcionam', () {
      DeviceConnectionState? receivedState;
      driver.onStateChanged = (s) => receivedState = s;

      expect(driver.connectionState, DeviceConnectionState.disconnected);
      expect(driver.isConnected, isFalse);
      expect(receivedState, isNull);
    });

    test('Envio de comandos RemoteKey não dispara exceções', () {
      for (final key in RemoteKey.values) {
        expect(() => driver.sendKey(key), returnsNormally);
      }

      expect(() => driver.sendDigit(5), returnsNormally);
      expect(() => driver.setMute(true), returnsNormally);
      expect(() => driver.setVolume(25), returnsNormally);
      expect(() => driver.sendTrackpadDelta(10, -5), returnsNormally);
      expect(() => driver.sendTrackpadClick(), returnsNormally);
      expect(() => driver.sendText('teste'), returnsNormally);
      expect(() => driver.triggerVoice(), returnsNormally);
    });
  });

  group('SamsungTizenDriver Unit Tests', () {
    late SamsungTizenDriver driver;

    setUp(() {
      driver = SamsungTizenDriver();
    });

    tearDown(() {
      driver.disconnect();
    });

    test('Propriedades e estados iniciais Samsung', () {
      expect(driver.brand, TvBrand.samsungTizen);
      expect(driver.brandDisplayName, 'Samsung Tizen');
      expect(driver.supportsTrackpad, isFalse);
      expect(driver.supportsPairingPin, isFalse);
      expect(driver.connectionState, DeviceConnectionState.disconnected);
      expect(driver.isConnected, isFalse);
    });

    test('Comandos Samsung são despachados sem exceções', () async {
      for (final key in RemoteKey.values) {
        expect(() => driver.sendKey(key), returnsNormally);
      }
      expect(() => driver.sendDigit(3), returnsNormally);
      expect(() => driver.setMute(true), returnsNormally);
      expect(() => driver.setVolume(15), returnsNormally);
      expect(() => driver.sendText('Samsung TV'), returnsNormally);
      expect(() => driver.sendTrackpadDelta(2, -2), returnsNormally);
      expect(() => driver.sendTrackpadClick(), returnsNormally);
      expect(() => driver.sendPairingPin('0000'), returnsNormally);
      expect(() => driver.openApp('111299001912'), returnsNormally);
      expect(() => driver.triggerVoice(), returnsNormally);
      expect(() => driver.disconnect(), returnsNormally);

      final apps = await driver.getInstalledApps();
      expect(apps, isNotEmpty);
      expect(apps.any((a) => a.name == 'YouTube'), isTrue);
      expect(apps.any((a) => a.name == 'Netflix'), isTrue);
    });

    test('Callbacks do driver Samsung podem ser configurados', () {
      DeviceConnectionState? state;
      String? token;
      String? error;
      String? name;

      driver.onStateChanged = (s) => state = s;
      driver.onAuthTokenReceived = (t) => token = t;
      driver.onError = (e) => error = e;
      driver.onDeviceNameResolved = (n, m) => name = n;

      expect(state, isNull);
      expect(token, isNull);
      expect(error, isNull);
      expect(name, isNull);
    });
  });

  group('RemoteController com TvDriver Unit Tests', () {
    late RemoteController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      controller = RemoteController();
    });

    tearDown(() {
      controller.disconnect();
    });

    test('Inicia com driver da LG por padrão', () {
      expect(controller.currentBrand, TvBrand.lgWebOs);
      expect(controller.driver, isA<LgWebOsDriver>());
      expect(controller.supportsTrackpad, isTrue);
      expect(controller.supportsPairingPin, isFalse);
    });

    test('Alternância de marca atualiza o driver e persiste no storage', () {
      expect(controller.currentBrand, TvBrand.lgWebOs);

      controller.selectBrand(TvBrand.samsungTizen);
      expect(controller.currentBrand, TvBrand.samsungTizen);
      expect(controller.driver, isA<SamsungTizenDriver>());
      expect(controller.supportsPairingPin, isFalse);
      expect(controller.storageService.getBrand(), TvBrand.samsungTizen);

      controller.selectBrand(TvBrand.lgWebOs);
      expect(controller.currentBrand, TvBrand.lgWebOs);
      expect(controller.driver, isA<LgWebOsDriver>());
      expect(controller.storageService.getBrand(), TvBrand.lgWebOs);
    });

    test('Despacho de comandos via TvDriver', () {
      // Comandos de volume
      controller.volumeUp();
      expect(controller.lastActionMessage, contains('Volume Up'));

      controller.volumeDown();
      expect(controller.lastActionMessage, contains('Volume Down'));

      // Comandos D-Pad
      controller.dpadUp();
      expect(controller.lastActionMessage, contains('D-Pad UP'));

      controller.dpadDown();
      expect(controller.lastActionMessage, contains('D-Pad DOWN'));

      controller.dpadOk();
      expect(controller.lastActionMessage, contains('D-Pad OK / Enter'));

      // Digitação
      controller.sendDigit(7);
      expect(controller.lastActionMessage, contains('Keypad Digit'));

      // Trackpad
      controller.sendTrackpadDelta(5.0, 5.0);
      expect(controller.lastActionMessage, contains('Trackpad Move'));

      controller.sendTrackpadClick();
      expect(controller.lastActionMessage, contains('Trackpad Click'));

      // Comando de voz
      controller.triggerVoice();
      expect(controller.lastActionMessage, contains('Comando de Voz'));
    });
  });
}
