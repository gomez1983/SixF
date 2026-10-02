import 'dart:io';

/// Utilitários de segurança de rede para validação de conexões com dispositivos locais (Smart TVs / IoT).
class NetworkSecurityUtils {
  NetworkSecurityUtils._();

  /// Verifica se um host pertence estritamente a um intervalo de rede local privada:
  /// - Loopback (127.0.0.0/8, ::1)
  /// - Link-Local (169.254.0.0/16)
  /// - RFC 1918:
  ///   - 10.0.0.0/8
  ///   - 172.16.0.0/12 (172.16.0.0 até 172.31.255.255)
  ///   - 192.168.0.0/16
  static bool isLocalNetworkHost(String host) {
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return false;

    if (ip.isLoopback || ip.isLinkLocal) return true;

    if (ip.type == InternetAddressType.IPv4) {
      final raw = ip.rawAddress;
      if (raw[0] == 10) return true;
      if (raw[0] == 172 && (raw[1] >= 16 && raw[1] <= 31)) return true;
      if (raw[0] == 192 && raw[1] == 168) return true;
    }

    return false;
  }
}
