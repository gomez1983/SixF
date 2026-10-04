import '../services/drivers/tv_driver.dart';

/// Informações de um renderizador de mídia UPnP / DLNA AVTransport (Smart TV ou Receiver).
class DlnaRenderer {
  final String ip;
  final String name;
  final String controlUrl;
  final String? locationUrl;
  final TvBrand brand;

  const DlnaRenderer({
    required this.ip,
    required this.name,
    required this.controlUrl,
    this.locationUrl,
    this.brand = TvBrand.lgWebOs,
  });

  @override
  String toString() => 'DlnaRenderer($name @ $ip -> $controlUrl)';
}
