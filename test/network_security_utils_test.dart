import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/network_security_utils.dart';

void main() {
  group('NetworkSecurityUtils.isLocalNetworkHost', () {
    test('aceita endereços RFC 1918 classe C (192.168.x.x)', () {
      expect(NetworkSecurityUtils.isLocalNetworkHost('192.168.1.1'), isTrue);
      expect(NetworkSecurityUtils.isLocalNetworkHost('192.168.0.50'), isTrue);
      expect(NetworkSecurityUtils.isLocalNetworkHost('192.168.15.100'), isTrue);
    });

    test('aceita endereços RFC 1918 classe A (10.x.x.x)', () {
      expect(NetworkSecurityUtils.isLocalNetworkHost('10.0.0.1'), isTrue);
      expect(NetworkSecurityUtils.isLocalNetworkHost('10.200.5.25'), isTrue);
    });

    test('aceita endereços RFC 1918 classe B (172.16.x.x a 172.31.x.x)', () {
      expect(NetworkSecurityUtils.isLocalNetworkHost('172.16.0.1'), isTrue);
      expect(NetworkSecurityUtils.isLocalNetworkHost('172.25.10.5'), isTrue);
      expect(NetworkSecurityUtils.isLocalNetworkHost('172.31.255.254'), isTrue);
      // Fora do range 172.16-31
      expect(NetworkSecurityUtils.isLocalNetworkHost('172.15.0.1'), isFalse);
      expect(NetworkSecurityUtils.isLocalNetworkHost('172.32.0.1'), isFalse);
    });

    test('aceita loopback e link-local', () {
      expect(NetworkSecurityUtils.isLocalNetworkHost('127.0.0.1'), isTrue);
      expect(NetworkSecurityUtils.isLocalNetworkHost('169.254.10.20'), isTrue);
    });

    test('rejeita IPs públicos da internet', () {
      expect(NetworkSecurityUtils.isLocalNetworkHost('8.8.8.8'), isFalse);
      expect(NetworkSecurityUtils.isLocalNetworkHost('1.1.1.1'), isFalse);
      expect(NetworkSecurityUtils.isLocalNetworkHost('200.180.50.10'), isFalse);
    });

    test('rejeita domínios públicos ou strings inválidas', () {
      expect(NetworkSecurityUtils.isLocalNetworkHost('google.com'), isFalse);
      expect(NetworkSecurityUtils.isLocalNetworkHost('malicious-host.xyz'), isFalse);
      expect(NetworkSecurityUtils.isLocalNetworkHost(''), isFalse);
      expect(NetworkSecurityUtils.isLocalNetworkHost('not-an-ip'), isFalse);
    });
  });
}
