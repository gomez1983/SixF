import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'drivers/tv_driver.dart';

/// Informações de uma TV descoberta na rede local.
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

/// Serviço de Descoberta Automática de Smart TVs LG na rede local via SSDP (UPnP/UDP) e Probe Direto.
class SsdpDiscoveryService {
  static const String _multicastAddress = '239.255.255.250';
  static const int _multicastPort = 1900;

  /// Realiza uma varredura na rede local durante [timeout] à procura de TVs LG WebOS.
  /// Faz bind em todas as interfaces de rede IPv4 ativas para contornar roteamento de adaptadores virtuais no Windows.
  static Future<List<DiscoveredTv>> discoverTvs({
    Duration timeout = const Duration(seconds: 4),
    String? knownIp,
  }) async {
    if (kIsWeb) {
      debugPrint('[SSDP] Descoberta UDP não é suportada diretamente no navegador Web.');
      return [];
    }

    final discoveredMap = <String, DiscoveredTv>{};
    final sockets = <RawDatagramSocket>[];

    try {
      // 1. Tenta vincular sockets a todas as interfaces de rede IPv4 ativas do Windows
      try {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            if (!addr.isLoopback) {
              try {
                final s = await RawDatagramSocket.bind(addr, 0);
                s.broadcastEnabled = true;
                s.multicastLoopback = false;
                sockets.add(s);
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        debugPrint('[SSDP] Erro ao listar interfaces: $e');
      }

      // Fallback genérico se nenhuma interface específica pôde ser vinculada
      if (sockets.isEmpty) {
        try {
          final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
          s.broadcastEnabled = true;
          sockets.add(s);
        } catch (_) {}
      }

      // Consultas M-SEARCH direcionadas à LG WebOS e serviços de renderização de mídia
      final searchQueries = [
        'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_multicastAddress:$_multicastPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: urn:lge-com:service:webos-second-screen:1\r\n\r\n',
        'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_multicastAddress:$_multicastPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n',
        'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_multicastAddress:$_multicastPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: urn:dial-multiscreen-org:service:dial:1\r\n\r\n',
        'M-SEARCH * HTTP/1.1\r\n'
            'HOST: $_multicastAddress:$_multicastPort\r\n'
            'MAN: "ssdp:discover"\r\n'
            'MX: 2\r\n'
            'ST: ssdp:all\r\n\r\n',
      ];

      final target = InternetAddress(_multicastAddress);
      final pendingLocations = <String, String>{};

      // Dispara as consultas de busca em todas as interfaces
      for (final s in sockets) {
        for (final query in searchQueries) {
          final data = utf8.encode(query);
          s.send(data, target, _multicastPort);
        }

        s.listen((RawSocketEvent event) {
          if (event == RawSocketEvent.read) {
            final datagram = s.receive();
            if (datagram != null) {
              final response = utf8.decode(datagram.data, allowMalformed: true);
              final senderIp = datagram.address.address;

              final isLg = response.toLowerCase().contains('lg') ||
                  response.toLowerCase().contains('webos') ||
                  response.toLowerCase().contains('second-screen') ||
                  response.toLowerCase().contains('lge');

              if (isLg) {
                String? locationUrl;
                for (final line in response.split('\r\n')) {
                  if (line.toUpperCase().startsWith('LOCATION:')) {
                    locationUrl = line.substring(9).trim();
                    break;
                  }
                }

                if (locationUrl != null && locationUrl.isNotEmpty) {
                  pendingLocations[senderIp] = locationUrl;
                } else if (!discoveredMap.containsKey(senderIp)) {
                  discoveredMap[senderIp] = DiscoveredTv(
                    ip: senderIp,
                    name: 'LG Smart TV ($senderIp)',
                  );
                }
              }
            }
          }
        });
      }

      // Se houver um knownIp (ex: IP salvo da TV), executa probe paralelo via HTTP
      Future<DiscoveredTv?>? probeFuture;
      if (knownIp != null && knownIp.trim().isNotEmpty && knownIp != '192.168.1.150') {
        probeFuture = probeTvAtIp(knownIp.trim());
      }

      // Aguarda o término da janela de busca
      await Future.delayed(timeout);

      // Processa probe direto se retornou
      if (probeFuture != null) {
        try {
          final directTv = await probeFuture;
          if (directTv != null) {
            discoveredMap[directTv.ip] = directTv;
          }
        } catch (_) {}
      }

      // Para cada dispositivo com LOCATION, busca o XML e extrai o nome amigável (ex: "André TV")
      for (final entry in pendingLocations.entries) {
        final senderIp = entry.key;
        final locationUrl = entry.value;

        try {
          final tvInfo = await fetchDeviceInfoFromLocation(senderIp, locationUrl);
          discoveredMap[senderIp] = tvInfo;
          debugPrint('[SSDP] Dispositivo identificado: ${tvInfo.name} no IP $senderIp');
        } catch (e) {
          discoveredMap[senderIp] = DiscoveredTv(
            ip: senderIp,
            name: 'LG Smart TV ($senderIp)',
            location: locationUrl,
          );
        }
      }
    } catch (e) {
      debugPrint('[SSDP] Erro durante a varredura SSDP: $e');
    } finally {
      for (final s in sockets) {
        s.close();
      }
    }

    return discoveredMap.values.toList();
  }

  /// Realiza um probe HTTP direto nas portas UPnP conhecidas da LG (19531, 8080)
  static Future<DiscoveredTv?> probeTvAtIp(
    String ip, {
    Duration timeout = const Duration(seconds: 2),
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
        final uri = Uri.parse(url);
        final request = await client.getUrl(uri).timeout(timeout);
        final response = await request.close().timeout(timeout);
        if (response.statusCode == 200) {
          final xml = await response.transform(utf8.decoder).join();
          final friendlyName = extractXmlTag(xml, 'friendlyName');
          final modelName = extractXmlTag(xml, 'modelName');
          client.close(force: true);
          return DiscoveredTv(
            ip: ip,
            name: friendlyName.isNotEmpty ? friendlyName : 'LG Smart TV ($ip)',
            modelName: modelName.isNotEmpty ? modelName : null,
            location: url,
          );
        }
      } catch (_) {}
    }
    client.close(force: true);
    return null;
  }

  /// Faz o download da descrição XML da TV e extrai `<friendlyName>` e `<modelName>`
  static Future<DiscoveredTv> fetchDeviceInfoFromLocation(
    String ip,
    String locationUrl, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;

    try {
      final uri = Uri.parse(locationUrl);
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);

      if (response.statusCode == 200) {
        final xml = await response.transform(utf8.decoder).join();
        final friendlyName = extractXmlTag(xml, 'friendlyName');
        final modelName = extractXmlTag(xml, 'modelName');

        return DiscoveredTv(
          ip: ip,
          name: friendlyName.isNotEmpty ? friendlyName : 'LG Smart TV ($ip)',
          modelName: modelName.isNotEmpty ? modelName : null,
          location: locationUrl,
        );
      }
    } finally {
      client.close(force: true);
    }

    return DiscoveredTv(
      ip: ip,
      name: 'LG Smart TV ($ip)',
      location: locationUrl,
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
}
