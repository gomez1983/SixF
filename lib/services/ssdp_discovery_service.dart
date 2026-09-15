import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'drivers/tv_driver.dart';

/// Informações de uma TV ou aparelho descoberto na rede local.
class DiscoveredTv {
  final String ip;
  final String name;
  final String? modelName;
  final String? location;
  final TvBrand brand;

  const DiscoveredTv({
    required this.ip,
    required this.name,
    this.modelName,
    this.location,
    this.brand = TvBrand.lgWebOs,
  });

  @override
  String toString() => '$name ($ip - ${brand.displayName})';
}

/// Serviço Unificado de Descoberta Automática de Aparelhos na rede local:
/// - SSDP (UPnP UDP 1900): LG webOS e Samsung Tizen
/// - mDNS (Multicast DNS UDP 5353): Google Chromecast / Google TV
/// - Direct Probes (HTTP 8008 Eureka, 8001 Tizen, 19531 webOS)
class SsdpDiscoveryService {
  static const String _ssdpMulticastAddress = '239.255.255.250';
  static const int _ssdpPort = 1900;
  static const String _mdnsMulticastAddress = '224.0.0.251';
  static const int _mdnsPort = 5353;

  /// Realiza uma varredura unificada na rede local durante [timeout].
  static Future<List<DiscoveredTv>> discoverTvs({
    Duration timeout = const Duration(seconds: 4),
    String? knownIp,
  }) async {
    if (kIsWeb) {
      debugPrint('[Discovery] Descoberta UDP não é suportada no navegador Web.');
      return [];
    }

    final discoveredMap = <String, DiscoveredTv>{};
    final ssdpSockets = <RawDatagramSocket>[];
    final mdnsSockets = <RawDatagramSocket>[];
    final ssdpTarget = InternetAddress(_ssdpMulticastAddress);
    final mdnsTarget = InternetAddress(_mdnsMulticastAddress);
    final pendingLocations = <String, Map<String, dynamic>>{};

    try {
      // 1. Identifica as interfaces de rede IPv4 ativas
      List<NetworkInterface> interfaces = [];
      try {
        interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
      } catch (e) {
        debugPrint('[Discovery] Erro ao listar interfaces: $e');
      }

      // 2. Cria sockets vinculados às interfaces físicas
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          try {
            final sSsdp = await RawDatagramSocket.bind(addr, 0, reuseAddress: true);
            sSsdp.broadcastEnabled = true;
            sSsdp.multicastLoopback = false;
            ssdpSockets.add(sSsdp);
          } catch (_) {}

          try {
            final sMdns = await RawDatagramSocket.bind(addr, 0, reuseAddress: true);
            sMdns.broadcastEnabled = true;
            sMdns.multicastLoopback = false;
            try {
              sMdns.joinMulticast(mdnsTarget, iface);
            } catch (_) {}
            mdnsSockets.add(sMdns);
          } catch (_) {}
        }
      }

      // Fallback genérico para anyIPv4
      try {
        final sAnySsdp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: true);
        sAnySsdp.broadcastEnabled = true;
        ssdpSockets.add(sAnySsdp);
      } catch (_) {}

      try {
        final sAnyMdns = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: true);
        sAnyMdns.broadcastEnabled = true;
        try {
          sAnyMdns.joinMulticast(mdnsTarget);
        } catch (_) {}
        mdnsSockets.add(sAnyMdns);
      } catch (_) {}

      // 3. Configura ouvintes dos sockets SSDP ANTES de enviar pacotes
      for (final s in ssdpSockets) {
        s.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = s.receive();
            if (dg == null) return;
            final response = utf8.decode(dg.data, allowMalformed: true);
            final senderIp = dg.address.address;
            final respLower = response.toLowerCase();

            final isLg = respLower.contains('lg') ||
                respLower.contains('webos') ||
                respLower.contains('second-screen') ||
                respLower.contains('lge');

            final isSamsung = respLower.contains('samsung') ||
                respLower.contains('sec_hhp') ||
                respLower.contains('tizen');

            if (isLg || isSamsung) {
              String? locationUrl;
              for (final line in response.split('\r\n')) {
                if (line.toUpperCase().startsWith('LOCATION:')) {
                  locationUrl = line.substring(9).trim();
                  break;
                }
              }

              final brand = isSamsung ? TvBrand.samsungTizen : TvBrand.lgWebOs;

              if (locationUrl != null && locationUrl.isNotEmpty) {
                pendingLocations[senderIp] = {
                  'url': locationUrl,
                  'brand': brand,
                };
              } else if (!discoveredMap.containsKey(senderIp)) {
                discoveredMap[senderIp] = DiscoveredTv(
                  ip: senderIp,
                  name: isSamsung ? 'Samsung Smart TV ($senderIp)' : 'LG Smart TV ($senderIp)',
                  brand: brand,
                );
              }
            }
          }
        });
      }

      // 4. Configura ouvintes dos sockets mDNS ANTES de enviar pacotes
      for (final s in mdnsSockets) {
        s.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = s.receive();
            if (dg == null) return;
            final senderIp = dg.address.address;
            final str = utf8.decode(dg.data, allowMalformed: true);

            if (str.contains('googlecast') ||
                str.contains('androidtvremote') ||
                str.contains('Chromecast')) {
              String name = 'Google Chromecast ($senderIp)';
              final fnMatch = RegExp(r'fn=([^\x00\r\n]+)').firstMatch(str);
              if (fnMatch != null) {
                name = fnMatch.group(1)!.trim();
              }

              if (!discoveredMap.containsKey(senderIp) ||
                  discoveredMap[senderIp]?.brand != TvBrand.androidTv) {
                discoveredMap[senderIp] = DiscoveredTv(
                  ip: senderIp,
                  name: name,
                  brand: TvBrand.androidTv,
                  modelName: 'Chromecast / Google TV',
                );

                // Consulta eureka_info em background para refinar nome e modelo
                _probeGoogleCast(senderIp).then((castDev) {
                  if (castDev != null) {
                    discoveredMap[senderIp] = castDev;
                  }
                }).catchError((_) {});
              }
            }
          }
        });
      }

      // 5. Envia consultas SSDP
      final ssdpQueries = [
        'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_ssdpMulticastAddress:$_ssdpPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: urn:lge-com:service:webos-second-screen:1\r\n\r\n',
        'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_ssdpMulticastAddress:$_ssdpPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: urn:samsung.com:device:RemoteControlReceiver:1\r\n\r\n',
        'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_ssdpMulticastAddress:$_ssdpPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n',
        'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_ssdpMulticastAddress:$_ssdpPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n',
        'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_ssdpMulticastAddress:$_ssdpPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: ssdp:all\r\n\r\n',
      ];

      for (final s in ssdpSockets) {
        for (final q in ssdpQueries) {
          s.send(utf8.encode(q), ssdpTarget, _ssdpPort);
        }
      }

      // 6. Envia consultas mDNS (duplo disparo para resiliência de rede)
      final mdnsQueries = [
        _buildMdnsQuery('_googlecast._tcp.local'),
        _buildMdnsQuery('_androidtvremote2._tcp.local'),
      ];

      for (final s in mdnsSockets) {
        for (final q in mdnsQueries) {
          s.send(q, mdnsTarget, _mdnsPort);
        }
      }

      // 7. Varredura direta e probes paralelos (knownIp e varredura TCP na sub-rede física)
      final probeFutures = <Future<void>>[];

      if (knownIp != null && knownIp.trim().isNotEmpty && knownIp != '192.168.1.150') {
        probeFutures.add(probeTvAtIp(knownIp.trim()).then((dev) {
          if (dev != null) discoveredMap[dev.ip] = dev;
        }));
      }

      // Dispara varredura rápida de portas conhecidas (8008 Cast / 8001 Samsung) na sub-rede
      probeFutures.add(_sweepLocalSubnet(interfaces, discoveredMap));

      // Re-dispara mDNS após 500ms
      Future.delayed(const Duration(milliseconds: 500), () {
        for (final s in mdnsSockets) {
          for (final q in mdnsQueries) {
            try {
              s.send(q, mdnsTarget, _mdnsPort);
            } catch (_) {}
          }
        }
      });

      // Aguarda a janela de timeout configurada
      await Future.delayed(timeout);

      // Aguarda encerramento das probes pendentes
      await Future.wait(probeFutures).timeout(
        const Duration(seconds: 1),
        onTimeout: () => [],
      );

      // 8. Resolve descrições XML das TVs LG e Samsung descobertas via SSDP
      for (final entry in pendingLocations.entries) {
        final senderIp = entry.key;
        final locationUrl = entry.value['url'] as String;
        final brand = entry.value['brand'] as TvBrand;

        try {
          final tvInfo = await fetchDeviceInfoFromLocation(senderIp, locationUrl, brand: brand);
          discoveredMap[senderIp] = tvInfo;
          debugPrint('[Discovery] Identificado via XML: ${tvInfo.name} ($senderIp) [${brand.displayName}]');
        } catch (_) {
          if (!discoveredMap.containsKey(senderIp)) {
            discoveredMap[senderIp] = DiscoveredTv(
              ip: senderIp,
              name: brand == TvBrand.samsungTizen ? 'Samsung Smart TV ($senderIp)' : 'LG Smart TV ($senderIp)',
              brand: brand,
              location: locationUrl,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Discovery] Erro durante a varredura unificada: $e');
    } finally {
      for (final s in ssdpSockets) {
        s.close();
      }
      for (final s in mdnsSockets) {
        s.close();
      }
    }

    return discoveredMap.values.toList();
  }

  /// Realiza probe direto em um IP conhecido para identificar a marca e modelo.
  static Future<DiscoveredTv?> probeTvAtIp(
    String ip, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    // 1. Testa Google Chromecast / Google TV (porta 8008)
    final castDev = await _probeGoogleCast(ip, timeout: timeout);
    if (castDev != null) return castDev;

    // 2. Testa Samsung Tizen (porta 8001)
    final samsungDev = await _probeSamsungTizen(ip, timeout: timeout);
    if (samsungDev != null) return samsungDev;

    // 3. Testa LG webOS (portas UPnP 19531 e 8080)
    final lgDev = await _probeLgWebOs(ip, timeout: timeout);
    if (lgDev != null) return lgDev;

    return null;
  }

  static Future<DiscoveredTv?> _probeGoogleCast(
    String ip, {
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse('http://$ip:8008/setup/eureka_info')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final name = json['name'] as String? ?? 'Google Chromecast';
        final model = json['model_name'] as String? ?? 'Chromecast';
        return DiscoveredTv(
          ip: ip,
          name: name,
          brand: TvBrand.androidTv,
          modelName: model,
        );
      }
    } catch (_) {} finally {
      client.close(force: true);
    }
    return null;
  }

  static Future<DiscoveredTv?> _probeSamsungTizen(
    String ip, {
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse('http://$ip:8001/api/v2/')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final dev = json['device'] as Map<String, dynamic>?;
        final name = dev?['name'] as String? ?? 'Samsung Smart TV';
        final model = dev?['modelName'] as String? ?? 'Tizen TV';
        return DiscoveredTv(
          ip: ip,
          name: name,
          brand: TvBrand.samsungTizen,
          modelName: model,
        );
      }
    } catch (_) {} finally {
      client.close(force: true);
    }
    return null;
  }

  static Future<DiscoveredTv?> _probeLgWebOs(
    String ip, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final urls = [
      'http://$ip:19531/description.xml',
      'http://$ip:19531/',
      'http://$ip:8080/description.xml',
      'http://$ip:8080/',
    ];

    final client = HttpClient()..connectionTimeout = timeout;
    for (final url in urls) {
      try {
        final req = await client.getUrl(Uri.parse(url)).timeout(timeout);
        final res = await req.close().timeout(timeout);
        if (res.statusCode == 200) {
          final xml = await res.transform(utf8.decoder).join();
          final friendlyName = extractXmlTag(xml, 'friendlyName');
          final modelName = extractXmlTag(xml, 'modelName');
          client.close(force: true);
          return DiscoveredTv(
            ip: ip,
            name: friendlyName.isNotEmpty ? friendlyName : 'LG Smart TV ($ip)',
            modelName: modelName.isNotEmpty ? modelName : null,
            location: url,
            brand: TvBrand.lgWebOs,
          );
        }
      } catch (_) {}
    }
    client.close(force: true);
    return null;
  }

  /// Varre os IPs da sub-rede local ativa testando conexão TCP em portas conhecidas
  static Future<void> _sweepLocalSubnet(
    List<NetworkInterface> interfaces,
    Map<String, DiscoveredTv> discoveredMap,
  ) async {
    try {
      final targetIps = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4 && (parts[0] == '192' || parts[0] == '10')) {
            final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            for (int i = 1; i <= 254; i++) {
              final ip = '$prefix.$i';
              if (ip != addr.address && !discoveredMap.containsKey(ip)) {
                targetIps.add(ip);
              }
            }
          }
        }
      }

      if (targetIps.isEmpty) return;

      // Dispara teste de porta TCP rápido (300ms timeout) em blocos de 60
      const chunkSize = 60;
      for (int i = 0; i < targetIps.length; i += chunkSize) {
        final end = (i + chunkSize < targetIps.length) ? i + chunkSize : targetIps.length;
        final chunk = targetIps.sublist(i, end);

        await Future.wait(chunk.map((ip) async {
          if (discoveredMap.containsKey(ip)) return;

          // 1. Testa porta 8008 (Google Cast)
          try {
            final sCast = await Socket.connect(ip, 8008, timeout: const Duration(milliseconds: 300));
            sCast.destroy();
            final castDev = await _probeGoogleCast(ip);
            if (castDev != null) {
              discoveredMap[ip] = castDev;
              return;
            }
          } catch (_) {}

          // 2. Testa porta 8001 (Samsung Tizen)
          try {
            final sSam = await Socket.connect(ip, 8001, timeout: const Duration(milliseconds: 300));
            sSam.destroy();
            final samDev = await _probeSamsungTizen(ip);
            if (samDev != null) {
              discoveredMap[ip] = samDev;
              return;
            }
          } catch (_) {}
        }));
      }
    } catch (_) {}
  }

  /// Faz o download da descrição XML da TV e extrai `<friendlyName>` e `<modelName>`
  static Future<DiscoveredTv> fetchDeviceInfoFromLocation(
    String ip,
    String locationUrl, {
    Duration timeout = const Duration(seconds: 2),
    TvBrand brand = TvBrand.lgWebOs,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final uri = Uri.parse(locationUrl);
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);

      if (response.statusCode == 200) {
        final xml = await response.transform(utf8.decoder).join();
        final friendlyName = extractXmlTag(xml, 'friendlyName');
        final modelName = extractXmlTag(xml, 'modelName');

        final defaultName = brand == TvBrand.samsungTizen ? 'Samsung Smart TV ($ip)' : 'LG Smart TV ($ip)';

        return DiscoveredTv(
          ip: ip,
          name: friendlyName.isNotEmpty ? friendlyName : defaultName,
          modelName: modelName.isNotEmpty ? modelName : null,
          location: locationUrl,
          brand: brand,
        );
      }
    } finally {
      client.close(force: true);
    }

    return DiscoveredTv(
      ip: ip,
      name: brand == TvBrand.samsungTizen ? 'Samsung Smart TV ($ip)' : 'LG Smart TV ($ip)',
      location: locationUrl,
      brand: brand,
    );
  }

  /// Extrai o conteúdo de uma tag XML ignorando maiúsculas/minúsculas e blocos CDATA
  static String extractXmlTag(String xml, String tag) {
    final pattern = RegExp(
      '<$tag>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?<\\/$tag>',
      caseSensitive: false,
      dotAll: true,
    );
    final match = pattern.firstMatch(xml);
    return match?.group(1)?.trim() ?? '';
  }

  /// Monta um pacote de consulta DNS mDNS do tipo PTR para busca de serviços
  static List<int> _buildMdnsQuery(String serviceName) {
    final parts = serviceName.split('.');
    final bytes = <int>[
      0x00, 0x00, // Transaction ID
      0x00, 0x00, // Flags (standard query)
      0x00, 0x01, // Questions: 1
      0x00, 0x00, // Answer RRs: 0
      0x00, 0x00, // Authority RRs: 0
      0x00, 0x00, // Additional RRs: 0
    ];
    for (final p in parts) {
      bytes.add(p.length);
      bytes.addAll(utf8.encode(p));
    }
    bytes.add(0x00); // End of name
    bytes.addAll([0x00, 0x0C]); // Type PTR (12)
    bytes.addAll([0x00, 0x01]); // Class IN (1)
    return bytes;
  }
}
