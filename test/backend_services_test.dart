import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/services/ssdp_discovery_service.dart';
import 'package:sixf_remote/services/storage_service.dart';
import 'package:sixf_remote/services/wake_on_lan_service.dart';
import 'package:sixf_remote/services/webos_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WakeOnLanService Tests', () {
    test('Valida e faz parse correto de endereços MAC em diferentes formatos', () {
      const macColons = 'A4:77:33:B2:9C:10';
      const macDashes = 'A4-77-33-B2-9C-10';
      const macRaw = 'A47733B29C10';

      final bytesColons = WakeOnLanService.parseMacAddress(macColons);
      final bytesDashes = WakeOnLanService.parseMacAddress(macDashes);
      final bytesRaw = WakeOnLanService.parseMacAddress(macRaw);

      expect(bytesColons, isNotNull);
      expect(bytesColons!.length, 6);
      expect(bytesColons, equals([0xA4, 0x77, 0x33, 0xB2, 0x9C, 0x10]));
      expect(bytesDashes, equals(bytesColons));
      expect(bytesRaw, equals(bytesColons));
    });

    test('Rejeita endereços MAC inválidos', () {
      expect(WakeOnLanService.parseMacAddress(''), isNull);
      expect(WakeOnLanService.parseMacAddress('12:34'), isNull);
      expect(WakeOnLanService.parseMacAddress('ZZ:ZZ:ZZ:ZZ:ZZ:ZZ'), isNull);
      expect(WakeOnLanService.buildMagicPacket('invalido'), isNull);
    });

    test('Constrói Magic Packet padrão de 102 bytes com 6x 0xFF e 16 repetições do MAC', () {
      const mac = 'AA:BB:CC:DD:EE:FF';
      final packet = WakeOnLanService.buildMagicPacket(mac);

      expect(packet, isNotNull);
      expect(packet!.length, 102);

      // Primeiros 6 bytes devem ser 0xFF
      for (var i = 0; i < 6; i++) {
        expect(packet[i], 0xFF);
      }

      // Próximos 96 bytes são 16 repetições de [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
      final expectedMac = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF];
      for (var rep = 0; rep < 16; rep++) {
        final offset = 6 + (rep * 6);
        for (var b = 0; b < 6; b++) {
          expect(packet[offset + b], expectedMac[b]);
        }
      }
    });
  });

  group('SSDP Discovery & XML Parsing Tests', () {
    test('Extrai friendlyName e modelName do XML UPnP da TV LG corretamente', () {
      const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <friendlyName>André TV</friendlyName>
    <modelName>OLED55C2PSA</modelName>
    <manufacturer>LG Electronics</manufacturer>
  </device>
</root>
''';

      expect(SsdpDiscoveryService.extractXmlTag(xml, 'friendlyName'), 'André TV');
      expect(SsdpDiscoveryService.extractXmlTag(xml, 'modelName'), 'OLED55C2PSA');
      expect(SsdpDiscoveryService.extractXmlTag(xml, 'manufacturer'), 'LG Electronics');
      expect(SsdpDiscoveryService.extractXmlTag(xml, 'inexistente'), '');
    });

    test('Extrai friendlyName mesmo se contiver bloco CDATA', () {
      const xml = '<device><friendlyName><![CDATA[André TV da Sala]]></friendlyName></device>';
      expect(SsdpDiscoveryService.extractXmlTag(xml, 'friendlyName'), 'André TV da Sala');
    });
  });

  group('StorageService Tests', () {
    late StorageService storage;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'pref_tv_ip': '192.168.1.50',
        'pref_tv_mac': '11:22:33:44:55:66',
        'pref_tv_client_key': 'test_token_123',
        'pref_app_theme_mode': 'light',
        'pref_tv_name': 'André TV',
      });
      storage = StorageService();
    });

    test('Lê valores persistidos e suporta valores padrão', () async {
      await storage.init();

      expect(storage.getIpAddress(), '192.168.1.50');
      expect(storage.getMacAddress(), '11:22:33:44:55:66');
      expect(storage.getClientKey(), 'test_token_123');
      expect(storage.getThemeMode(), 'light');
      expect(storage.getTvName(), 'André TV');
    });

    test('Salva novos valores e limpa clientKey quando nula', () async {
      await storage.init();

      await storage.setIpAddress('192.168.1.99');
      expect(storage.getIpAddress(), '192.168.1.99');

      await storage.setTvName('LG OLED André');
      expect(storage.getTvName(), 'LG OLED André');

      await storage.setMacAddress('AA:BB:CC:DD:EE:00');
      expect(storage.getMacAddress(), 'AA:BB:CC:DD:EE:00');

      await storage.setClientKey(null);
      expect(storage.getClientKey(), isNull);
    });
  });

  group('WebOsService Unit Tests', () {
    late WebOsService webOs;

    setUp(() {
      webOs = WebOsService();
    });

    tearDown(() {
      webOs.disconnect();
    });

    test('Estado inicial é desconectado', () {
      expect(webOs.state, WebOsConnectionState.disconnected);
      expect(webOs.isConnected, isFalse);
      expect(webOs.clientKey, isNull);
    });
  });
}
