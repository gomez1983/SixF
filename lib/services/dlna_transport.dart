import '../models/dlna_renderer.dart';
import 'dlna_service.dart';
import 'drivers/tv_driver.dart';

/// Fronteira de transporte usada pelo controlador e pelos testes de sessão.
class DlnaTransport {
  Future<DlnaRenderer?> resolveRenderer(
    String ip, {
    String? locationUrl,
    required TvBrand brand,
    String? tvName,
  }) => DlnaService.resolveRenderer(
    ip,
    locationUrl: locationUrl,
    brand: brand,
    tvName: tvName,
  );

  Future<DlnaResult> setUri(
    String url,
    String mediaUrl, {
    required String title,
    required String mimeType,
    int? fileSize,
  }) => DlnaService.setAVTransportURI(
    url,
    mediaUrl,
    title: title,
    mimeType: mimeType,
    fileSize: fileSize,
  );

  Future<DlnaResult> play(String url) => DlnaService.play(url);
  Future<DlnaResult> pause(String url) => DlnaService.pause(url);
  Future<DlnaResult> stop(String url) => DlnaService.stop(url);
  Future<DlnaResult> seek(String url, String target) =>
      DlnaService.seek(url, target);
  Future<String?> state(String url) => DlnaService.getTransportInfo(url);
  Future<DlnaPositionInfo?> position(String url) =>
      DlnaService.getPositionInfo(url);
  Future<Set<String>?> actions(String url) =>
      DlnaService.getCurrentTransportActions(url);
}
