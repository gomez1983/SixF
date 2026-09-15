import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/ssdp_discovery_service.dart';

void main() {
  test('DiscoveredTv supports all TvBrands', () {
    const lg = DiscoveredTv(ip: '192.168.1.10', name: 'LG OLED', brand: TvBrand.lgWebOs);
    expect(lg.brand, TvBrand.lgWebOs);
    expect(lg.toString(), contains('LG'));

    const cast = DiscoveredTv(ip: '192.168.1.20', name: 'Quarto André', brand: TvBrand.androidTv);
    expect(cast.brand, TvBrand.androidTv);
    expect(cast.toString(), contains('Google TV'));

    const samsung = DiscoveredTv(ip: '192.168.1.30', name: 'Samsung QLED', brand: TvBrand.samsungTizen);
    expect(samsung.brand, TvBrand.samsungTizen);
    expect(samsung.toString(), contains('Samsung'));
  });

  test('extractXmlTag extracts tags correctly', () {
    const xml = '<root><friendlyName>Sala de Estar</friendlyName><modelName>OLED55C1</modelName></root>';
    expect(SsdpDiscoveryService.extractXmlTag(xml, 'friendlyName'), 'Sala de Estar');
    expect(SsdpDiscoveryService.extractXmlTag(xml, 'modelName'), 'OLED55C1');
  });
}
