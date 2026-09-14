import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/driver_factory.dart';
import 'package:sixf_remote/services/drivers/lg_webos_driver.dart';
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

      expect(TvBrand.androidTv.displayName, 'Google TV / Android TV');
      expect(TvBrand.androidTv.id, 'android_tv');

      expect(TvBrand.samsungTizen.displayName, 'Samsung Tizen');
      expect(TvBrand.samsungTizen.id, 'samsung_tizen');
    });

    test('DriverFactory instancia LgWebOsDriver corretamente', () {
      final driver = DriverFactory.create(TvBrand.lgWebOs);
      expect(driver, isA<LgWebOsDriver>());
      expect(driver.brand, TvBrand.lgWebOs);
      expect(driver.supportsTrackpad, isTrue);
      expect(driver.supportsPairingPin, isFalse);
      expect(driver.connectionState, DeviceConnectionState.disconnected);
      expect(driver.isConnected, isFalse);
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
      // Dispara todas as teclas em estado desconectado de forma segura
      for (final key in RemoteKey.values) {
        expect(() => driver.sendKey(key), returnsNormally);
      }

      expect(() => driver.sendDigit(5), returnsNormally);
      expect(() => driver.setMute(true), returnsNormally);
      expect(() => driver.setVolume(25), returnsNormally);
      expect(() => driver.sendTrackpadDelta(10, -5), returnsNormally);
      expect(() => driver.sendTrackpadClick(), returnsNormally);
      expect(() => driver.sendText('teste'), returnsNormally);
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

      controller.selectBrand(TvBrand.androidTv);
      expect(controller.currentBrand, TvBrand.androidTv);
      expect(controller.storageService.getBrand(), TvBrand.androidTv);

      controller.selectBrand(TvBrand.samsungTizen);
      expect(controller.currentBrand, TvBrand.samsungTizen);
      expect(controller.storageService.getBrand(), TvBrand.samsungTizen);

      controller.selectBrand(TvBrand.lgWebOs);
      expect(controller.currentBrand, TvBrand.lgWebOs);
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
    });
  });
}
