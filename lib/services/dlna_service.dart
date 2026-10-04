import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/dlna_renderer.dart';
import 'drivers/tv_driver.dart';
import 'network_security_utils.dart';

/// Resultado detalhado de uma ação executada via DLNA / UPnP na TV.
class DlnaResult {
  final bool success;
  final int? statusCode;
  final int? upnpErrorCode;
  final String? upnpErrorDescription;
  final String? faultString;
  final String? rawResponse;
  final String? networkError;

  const DlnaResult({
    required this.success,
    this.statusCode,
    this.upnpErrorCode,
    this.upnpErrorDescription,
    this.faultString,
    this.rawResponse,
    this.networkError,
  });

  factory DlnaResult.ok([int statusCode = 200]) => DlnaResult(
        success: true,
        statusCode: statusCode,
      );

  factory DlnaResult.networkFailure(String error) => DlnaResult(
        success: false,
        networkError: error,
      );

  factory DlnaResult.fromResponse({
    required int statusCode,
    required String responseBody,
  }) {
    if (statusCode >= 200 && statusCode < 300) {
      return DlnaResult(
        success: true,
        statusCode: statusCode,
        rawResponse: responseBody,
      );
    }

    int? errCode;
    final codeStr = DlnaService.extractTag(responseBody, 'errorCode');
    if (codeStr.isNotEmpty) {
      errCode = int.tryParse(codeStr);
    }

    final errDesc = DlnaService.extractTag(responseBody, 'errorDescription');
    final fault = DlnaService.extractTag(responseBody, 'faultstring');

    return DlnaResult(
      success: false,
      statusCode: statusCode,
      upnpErrorCode: errCode,
      upnpErrorDescription: errDesc.isNotEmpty ? errDesc : null,
      faultString: fault.isNotEmpty ? fault : null,
      rawResponse: responseBody,
    );
  }

  /// Retorna uma mensagem de erro compreensível para exibição ao usuário final.
  String get userFriendlyMessage {
    if (networkError != null) {
      if (networkError!.contains('timed out') || networkError!.contains('Timeout')) {
        return 'Tempo de resposta esgotado: a TV não respondeu na porta configurada.';
      }
      if (networkError!.contains('Connection refused') || networkError!.contains('refused')) {
        return 'Conexão recusada pela TV na porta do serviço DLNA.';
      }
      return 'Falha de rede com a Smart TV ($networkError).';
    }

    if (upnpErrorCode != null) {
      switch (upnpErrorCode) {
        case 714:
          return 'A TV não aceitou o formato ou perfil DLNA do arquivo (Erro UPnP 714: Formato/MIME inválido para a TV).';
        case 716:
          return 'A TV não conseguiu acessar o arquivo no seu computador (Erro UPnP 716: Recurso não encontrado ou bloqueado pelo Firewall do Windows).';
        case 701:
          return 'Comando de reprodução não aplicável para fotos estáticas (Erro UPnP 701: Transição não suportada).';
        case 705:
          return 'Acesso negado pela Smart TV (Erro UPnP 705: Permissão necessária na TV).';
        case 501:
          return 'Ação recusada pela TV (Erro UPnP 501: Falha na execução da ação).';
        default:
          final desc = upnpErrorDescription ?? faultString ?? 'Falha UPnP';
          return 'A TV recusou o comando (Erro UPnP $upnpErrorCode: $desc).';
      }
    }

    if (faultString != null && faultString!.isNotEmpty) {
      return 'Erro retornado pela TV: $faultString (HTTP $statusCode).';
    }

    if (statusCode != null) {
      if (statusCode == 404) {
        return 'Endpoint de mídia não encontrado na TV (HTTP 404).';
      }
      return 'A TV respondeu com código de erro HTTP $statusCode.';
    }

    return 'A TV recusou a transmissão da mídia.';
  }

  @override
  String toString() =>
      'DlnaResult(success: $success, statusCode: $statusCode, upnpErrorCode: $upnpErrorCode, desc: $upnpErrorDescription, netErr: $networkError)';
}

/// Serviço para controle e transmissão de mídia para Smart TVs via protocolo DLNA / UPnP AVTransport 1.0.
///
/// Compatível nativamente com LG webOS, Samsung Tizen e reprodutores UPnP da rede local sem depender
/// de chaves de nuvem ou do protocolo Google Cast v2.
class DlnaService {
  static const String avTransportServiceType = 'urn:schemas-upnp-org:service:AVTransport:1';

  /// Descobre ou resolve o endpoint AVTransport de uma TV com base em seu IP ou URL de descrição UPnP.
  static Future<DlnaRenderer?> resolveRenderer(
    String tvIp, {
    String? locationUrl,
    TvBrand brand = TvBrand.lgWebOs,
    String? tvName,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    // 1. Se possuir URL de localização XML do SSDP, tenta fazer parse dos serviços anunciados
    if (locationUrl != null && locationUrl.isNotEmpty) {
      final renderer = await _fetchRendererFromLocation(
        tvIp,
        locationUrl,
        brand: brand,
        tvName: tvName,
        timeout: timeout,
      );
      if (renderer != null) return renderer;
    }

    // 2. Busca por probe direto nos endpoints conhecidos de UPnP da marca
    final candidateUrls = _getCandidateControlUrls(tvIp, brand);
    for (final url in candidateUrls) {
      final isAlive = await _probeSoapEndpoint(url, timeout: const Duration(milliseconds: 1200));
      if (isAlive) {
        debugPrint('[DLNA] Endpoint AVTransport identificado por probe: $url');
        return DlnaRenderer(
          ip: tvIp,
          name: tvName ?? '${brand.displayName} ($tvIp)',
          controlUrl: url,
          locationUrl: locationUrl,
          brand: brand,
        );
      }
    }

    // 3. Fallback padrão arquitetural
    final fallbackUrl = candidateUrls.isNotEmpty
        ? candidateUrls.first
        : (brand == TvBrand.samsungTizen
            ? 'http://$tvIp:9197/upnp/control/AVTransport1'
            : 'http://$tvIp:19531/udap/api/data?target=avtransport.xml');

    return DlnaRenderer(
      ip: tvIp,
      name: tvName ?? '${brand.displayName} ($tvIp)',
      controlUrl: fallbackUrl,
      locationUrl: locationUrl,
      brand: brand,
    );
  }

  /// Faz o parse do XML de descrição do dispositivo UPnP para localizar o serviço AVTransport e seu controlURL.
  static Future<DlnaRenderer?> _fetchRendererFromLocation(
    String tvIp,
    String locationUrl, {
    required TvBrand brand,
    String? tvName,
    required Duration timeout,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (cert, host, port) => NetworkSecurityUtils.isLocalNetworkHost(host);

    try {
      var targetUrl = locationUrl;
      // Para LG webOS: Se a URL fornecida estiver em porta efêmera (> 1024 e != 19531 e != 8080),
      // direciona imediatamente para a porta DLNA oficial 19531.
      if (brand == TvBrand.lgWebOs) {
        final parsedLoc = Uri.tryParse(locationUrl);
        if (parsedLoc != null && parsedLoc.hasPort && parsedLoc.port != 19531 && parsedLoc.port != 8080) {
          targetUrl = 'http://${parsedLoc.host}:19531${parsedLoc.path}${parsedLoc.hasQuery ? '?${parsedLoc.query}' : ''}';
          debugPrint('[DLNA] locationUrl LG normalizado de porta efêmera ${parsedLoc.port} para oficial 19531: $targetUrl');
        }
      }

      final uri = Uri.tryParse(targetUrl);
      if (uri == null || !NetworkSecurityUtils.isLocalNetworkHost(uri.host)) {
        debugPrint('[DLNA] locationUrl rejeitado por segurança (host não-local): $targetUrl');
        return null;
      }
      final req = await client.getUrl(uri).timeout(timeout);
      final res = await req.close().timeout(timeout);

      if (res.statusCode == 200) {
        final xml = await res.transform(utf8.decoder).join();
        final friendlyName = extractTag(xml, 'friendlyName');
        final resolvedName = (friendlyName.isNotEmpty) ? friendlyName : (tvName ?? brand.displayName);

        // Procura bloco do serviço AVTransport com flexibilidade de versões
        final servicePattern = RegExp(r'<service>[\s\S]*?<\/service>', caseSensitive: false);
        final matches = servicePattern.allMatches(xml);

        for (final m in matches) {
          final serviceXml = m.group(0) ?? '';
          if (serviceXml.contains(avTransportServiceType) ||
              serviceXml.toLowerCase().contains('service:avtransport')) {
            final controlUrlTag = extractTag(serviceXml, 'controlURL');
            if (controlUrlTag.isNotEmpty) {
              final resolvedControlUri = uri.resolve(controlUrlTag);
              var candidateUrl = resolvedControlUri.toString();

              // Se a controlURL extraída estiver em porta efêmera na LG, troca pela porta 19531
              if (brand == TvBrand.lgWebOs && resolvedControlUri.hasPort && resolvedControlUri.port != 19531 && resolvedControlUri.port != 8080) {
                candidateUrl = 'http://$tvIp:19531${resolvedControlUri.path}${resolvedControlUri.hasQuery ? '?${resolvedControlUri.query}' : ''}';
              }

              // 1. Testa se o endpoint extraído está de fato aberto e respondendo a conexões
              final isAlive = await _probeSoapEndpoint(candidateUrl, timeout: const Duration(milliseconds: 1000));
              if (isAlive) {
                debugPrint('[DLNA] controlURL resolvido e validado com sucesso via SSDP XML: $candidateUrl');
                return DlnaRenderer(
                  ip: tvIp,
                  name: resolvedName,
                  controlUrl: candidateUrl,
                  locationUrl: targetUrl,
                  brand: brand,
                );
              }

              // 2. Se a porta falhou, testa as rotas nas portas permanentes oficiais da LG: 19531 e 8080!
              if (brand == TvBrand.lgWebOs) {
                final port19531Url = 'http://$tvIp:19531${resolvedControlUri.path}${resolvedControlUri.hasQuery ? '?${resolvedControlUri.query}' : ''}';
                debugPrint('[DLNA] Testando porta oficial LG 19531: $port19531Url');
                if (await _probeSoapEndpoint(port19531Url, timeout: const Duration(milliseconds: 1000))) {
                  debugPrint('[DLNA] Endpoint validado com sucesso na porta oficial 19531: $port19531Url');
                  return DlnaRenderer(
                    ip: tvIp,
                    name: resolvedName,
                    controlUrl: port19531Url,
                    locationUrl: targetUrl,
                    brand: brand,
                  );
                }

                final port8080Url = 'http://$tvIp:8080${resolvedControlUri.path}${resolvedControlUri.hasQuery ? '?${resolvedControlUri.query}' : ''}';
                debugPrint('[DLNA] Testando porta oficial LG 8080: $port8080Url');
                if (await _probeSoapEndpoint(port8080Url, timeout: const Duration(milliseconds: 1000))) {
                  debugPrint('[DLNA] Endpoint validado com sucesso na porta oficial 8080: $port8080Url');
                  return DlnaRenderer(
                    ip: tvIp,
                    name: resolvedName,
                    controlUrl: port8080Url,
                    locationUrl: targetUrl,
                    brand: brand,
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DLNA] Erro ao obter XML de localização em $locationUrl: $e');
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Retorna lista de endpoints prováveis para o serviço AVTransport em cada ecossistema.
  static List<String> _getCandidateControlUrls(String ip, TvBrand brand) {
    if (brand == TvBrand.samsungTizen) {
      return [
        'http://$ip:9197/upnp/control/AVTransport1',
        'http://$ip:7676/smp_24_',
        'http://$ip:7676/smp_4_',
        'http://$ip:7676/upnp/control/AVTransport1',
        'http://$ip:7676/upnp/control/AVTransport',
        'http://$ip:9197/upnp/control/AVTransport',
      ];
    } else {
      // LG webOS
      return [
        'http://$ip:19531/udap/api/data?target=avtransport.xml',
        'http://$ip:19531/upnp/control/AVTransport',
        'http://$ip:8080/avt',
        'http://$ip:8080/upnp/control/AVTransport',
        'http://$ip:19531/udap/api/data?target=AVTransport.xml',
        'http://$ip:19531/avt',
        'http://$ip:19531/udap/api/data?target=avtransport',
        'http://$ip:8080/avt/avt.xml',
      ];
    }
  }

  /// Testa se o endpoint responde a uma consulta SOAP de verificação.
  static Future<bool> _probeSoapEndpoint(String url, {Duration timeout = const Duration(seconds: 1)}) async {
    try {
      final status = await getTransportInfo(url, timeout: timeout);
      return status != null;
    } catch (_) {
      return false;
    }
  }

  // --- Comandos de Controle de Mídia (SOAP / XML) ---

  /// Monta o protocolo DLNA protocolInfo adequado para cada tipo MIME.
  static String buildProtocolInfo(String mime) {
    switch (mime) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_LRG;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=00D00000000000000000000000000000';
      case 'image/png':
        return 'http-get:*:image/png:DLNA.ORG_PN=PNG_LRG;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=00D00000000000000000000000000000';
      case 'image/webp':
        return 'http-get:*:image/webp:DLNA.ORG_CI=0;DLNA.ORG_FLAGS=00D00000000000000000000000000000';
      case 'video/mp4':
        return 'http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_MP_SD_AAC_MULT5;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000';
      case 'video/x-matroska':
      case 'video/mkv':
        return 'http-get:*:video/x-matroska:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000';
      case 'video/webm':
        return 'http-get:*:video/webm:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000';
      case 'audio/mpeg':
      case 'audio/mp3':
        return 'http-get:*:audio/mpeg:DLNA.ORG_PN=MP3;DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01500000000000000000000000000000';
      default:
        return 'http-get:*:$mime:*';
    }
  }

  /// Configura a URI da mídia e seus metadados DIDL-Lite no renderizador da TV com retorno detalhado.
  static Future<DlnaResult> setAVTransportURI(
    String controlUrl,
    String mediaUrl, {
    String title = 'Mídia SixF',
    String mimeType = 'video/mp4',
    int? fileSize,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final upnpClass = _getUpnpClass(mimeType);

    // 1ª Tentativa: Envia com Perfil DLNA estruturado
    final primaryProtocolInfo = buildProtocolInfo(mimeType);
    final primaryBody = _buildSetUriSoapBody(
      mediaUrl: mediaUrl,
      title: title,
      upnpClass: upnpClass,
      protocolInfo: primaryProtocolInfo,
      fileSize: fileSize,
    );

    var attempt = await _sendSoapAction(
      controlUrl: controlUrl,
      action: 'SetAVTransportURI',
      body: primaryBody,
      timeout: timeout,
    );

    if (attempt.success) {
      return attempt;
    }

    // Se falhou por recusa de rede / porta (errno 1225 / Connection refused / SocketException),
    // tenta os endpoints alternativos conhecidos da LG (porta 19531 e 8080)
    if (attempt.networkError != null &&
        (attempt.networkError!.contains('1225') ||
            attempt.networkError!.toLowerCase().contains('refused') ||
            attempt.networkError!.toLowerCase().contains('recusou'))) {
      final parsedUri = Uri.tryParse(controlUrl);
      if (parsedUri != null) {
        final host = parsedUri.host;
        final candidateAlternativeUrls = [
          'http://$host:19531/udap/api/data?target=avtransport.xml',
          'http://$host:19531/upnp/control/AVTransport',
          'http://$host:8080/avt',
          'http://$host:8080/upnp/control/AVTransport',
        ];

        for (final altUrl in candidateAlternativeUrls) {
          if (altUrl == controlUrl) continue;
          debugPrint('[DLNA] Tentando endpoint alternativo de resiliência: $altUrl');
          final altAttempt = await _sendSoapAction(
            controlUrl: altUrl,
            action: 'SetAVTransportURI',
            body: primaryBody,
            timeout: const Duration(seconds: 3),
          );
          if (altAttempt.success) {
            debugPrint('[DLNA] Sucesso com endpoint alternativo: $altUrl');
            return altAttempt;
          }
        }
      }
    }

    // Se falhou com erro 714 (Illegal MIME-Type) ou 501, tenta fallback com protocolInfo genérico 'http-get:*:$mime:*'
    if (attempt.upnpErrorCode == 714 || attempt.upnpErrorCode == 501) {
      debugPrint('[DLNA] Tentando fallback de protocolInfo genérico para $mimeType...');
      final fallbackProtocolInfo = 'http-get:*:$mimeType:*';
      final fallbackBody = _buildSetUriSoapBody(
        mediaUrl: mediaUrl,
        title: title,
        upnpClass: upnpClass,
        protocolInfo: fallbackProtocolInfo,
        fileSize: fileSize,
      );

      final secondAttempt = await _sendSoapAction(
        controlUrl: controlUrl,
        action: 'SetAVTransportURI',
        body: fallbackBody,
        timeout: timeout,
      );

      if (secondAttempt.success) {
        return secondAttempt;
      }
    }

    return attempt;
  }

  static String _buildSetUriSoapBody({
    required String mediaUrl,
    required String title,
    required String upnpClass,
    required String protocolInfo,
    int? fileSize,
  }) {
    final sizeAttr = (fileSize != null && fileSize > 0) ? ' size="$fileSize"' : '';

    final didlLite =
        '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>${_xmlEscape(title)}</dc:title>'
        '<upnp:class>$upnpClass</upnp:class>'
        '<res protocolInfo="${_xmlEscape(protocolInfo)}"$sizeAttr>${_xmlEscape(mediaUrl)}</res>'
        '</item>'
        '</DIDL-Lite>';

    final escapedDidl = _xmlEscape(didlLite);

    return '<?xml version="1.0" encoding="utf-8"?>\r\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\r\n'
        '  <s:Body>\r\n'
        '    <u:SetAVTransportURI xmlns:u="$avTransportServiceType">\r\n'
        '      <InstanceID>0</InstanceID>\r\n'
        '      <CurrentURI>${_xmlEscape(mediaUrl)}</CurrentURI>\r\n'
        '      <CurrentURIMetaData>$escapedDidl</CurrentURIMetaData>\r\n'
        '    </u:SetAVTransportURI>\r\n'
        '  </s:Body>\r\n'
        '</s:Envelope>';
  }

  /// Inicia a reprodução na TV.
  static Future<DlnaResult> play(
    String controlUrl, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final soapBody =
        '<?xml version="1.0" encoding="utf-8"?>\r\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\r\n'
        '  <s:Body>\r\n'
        '    <u:Play xmlns:u="$avTransportServiceType">\r\n'
        '      <InstanceID>0</InstanceID>\r\n'
        '      <Speed>1</Speed>\r\n'
        '    </u:Play>\r\n'
        '  </s:Body>\r\n'
        '</s:Envelope>';

    final res = await _sendSoapAction(
      controlUrl: controlUrl,
      action: 'Play',
      body: soapBody,
      timeout: timeout,
    );

    if (res.success) return res;

    // Se a porta falhou com erro 1225/recusa, tenta portas oficiais alternativas LG
    if (res.networkError != null &&
        (res.networkError!.contains('1225') ||
            res.networkError!.toLowerCase().contains('refused') ||
            res.networkError!.toLowerCase().contains('recusou'))) {
      final parsedUri = Uri.tryParse(controlUrl);
      if (parsedUri != null) {
        final host = parsedUri.host;
        final candidateAlternativeUrls = [
          'http://$host:19531/udap/api/data?target=avtransport.xml',
          'http://$host:19531/upnp/control/AVTransport',
          'http://$host:8080/avt',
          'http://$host:8080/upnp/control/AVTransport',
        ];

        for (final altUrl in candidateAlternativeUrls) {
          if (altUrl == controlUrl) continue;
          final altRes = await _sendSoapAction(
            controlUrl: altUrl,
            action: 'Play',
            body: soapBody,
            timeout: const Duration(seconds: 2),
          );
          if (altRes.success) return altRes;
        }
      }
    }

    return res;
  }

  /// Pausa a reprodução na TV.
  static Future<DlnaResult> pause(
    String controlUrl, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final soapBody =
        '<?xml version="1.0" encoding="utf-8"?>\r\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\r\n'
        '  <s:Body>\r\n'
        '    <u:Pause xmlns:u="$avTransportServiceType">\r\n'
        '      <InstanceID>0</InstanceID>\r\n'
        '    </u:Pause>\r\n'
        '  </s:Body>\r\n'
        '</s:Envelope>';

    return _sendSoapAction(
      controlUrl: controlUrl,
      action: 'Pause',
      body: soapBody,
      timeout: timeout,
    );
  }

  /// Interrompe e encerra a reprodução na TV.
  static Future<DlnaResult> stop(
    String controlUrl, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final soapBody =
        '<?xml version="1.0" encoding="utf-8"?>\r\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\r\n'
        '  <s:Body>\r\n'
        '    <u:Stop xmlns:u="$avTransportServiceType">\r\n'
        '      <InstanceID>0</InstanceID>\r\n'
        '    </u:Stop>\r\n'
        '  </s:Body>\r\n'
        '</s:Envelope>';

    return _sendSoapAction(
      controlUrl: controlUrl,
      action: 'Stop',
      body: soapBody,
      timeout: timeout,
    );
  }

  /// Busca o estado atual de transporte da TV (PLAYING, PAUSED_PLAYBACK, STOPPED, NO_MEDIA_PRESENT).
  static Future<String?> getTransportInfo(
    String controlUrl, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final soapBody =
        '<?xml version="1.0" encoding="utf-8"?>\r\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\r\n'
        '  <s:Body>\r\n'
        '    <u:GetTransportInfo xmlns:u="$avTransportServiceType">\r\n'
        '      <InstanceID>0</InstanceID>\r\n'
        '    </u:GetTransportInfo>\r\n'
        '  </s:Body>\r\n'
        '</s:Envelope>';

    final uri = Uri.tryParse(controlUrl);
    if (uri == null || !NetworkSecurityUtils.isLocalNetworkHost(uri.host)) {
      debugPrint('[DLNA] controlUrl rejeitado por segurança (host não-local): $controlUrl');
      return null;
    }

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (cert, host, port) => NetworkSecurityUtils.isLocalNetworkHost(host);

    try {
      final req = await client.postUrl(uri).timeout(timeout);
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPACTION', '"$avTransportServiceType#GetTransportInfo"');
      req.write(soapBody);

      final res = await req.close().timeout(timeout);
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        return extractTag(body, 'CurrentTransportState');
      }
    } catch (_) {} finally {
      client.close(force: true);
    }
    return null;
  }

  /// Busca a posição e duração atual da mídia (GetPositionInfo).
  static Future<DlnaPositionInfo?> getPositionInfo(
    String controlUrl, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final soapBody =
        '<?xml version="1.0" encoding="utf-8"?>\r\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\r\n'
        '  <s:Body>\r\n'
        '    <u:GetPositionInfo xmlns:u="$avTransportServiceType">\r\n'
        '      <InstanceID>0</InstanceID>\r\n'
        '    </u:GetPositionInfo>\r\n'
        '  </s:Body>\r\n'
        '</s:Envelope>';

    final uri = Uri.tryParse(controlUrl);
    if (uri == null || !NetworkSecurityUtils.isLocalNetworkHost(uri.host)) {
      return null;
    }

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (cert, host, port) => NetworkSecurityUtils.isLocalNetworkHost(host);

    try {
      final req = await client.postUrl(uri).timeout(timeout);
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPACTION', '"$avTransportServiceType#GetPositionInfo"');
      req.headers.set('Connection', 'close');
      req.write(soapBody);

      final res = await req.close().timeout(timeout);
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final trackDuration = extractTag(body, 'TrackDuration');
        final relTime = extractTag(body, 'RelTime');
        return DlnaPositionInfo.parse(trackDuration: trackDuration, relTime: relTime);
      }
    } catch (_) {} finally {
      client.close(force: true);
    }
    return null;
  }

  /// Realiza Seek para uma posição de tempo no formato HH:MM:SS.
  static Future<DlnaResult> seek(
    String controlUrl,
    String targetTime, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final soapBody =
        '<?xml version="1.0" encoding="utf-8"?>\r\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\r\n'
        '  <s:Body>\r\n'
        '    <u:Seek xmlns:u="$avTransportServiceType">\r\n'
        '      <InstanceID>0</InstanceID>\r\n'
        '      <Unit>REL_TIME</Unit>\r\n'
        '      <Target>$targetTime</Target>\r\n'
        '    </u:Seek>\r\n'
        '  </s:Body>\r\n'
        '</s:Envelope>';

    return _sendSoapAction(
      controlUrl: controlUrl,
      action: 'Seek',
      body: soapBody,
      timeout: timeout,
    );
  }

  /// Envia envelope SOAP formatado via HTTP POST e retorna objeto DlnaResult com diagnóstico.
  static Future<DlnaResult> _sendSoapAction({
    required String controlUrl,
    required String action,
    required String body,
    required Duration timeout,
  }) async {
    final uri = Uri.tryParse(controlUrl);
    if (uri == null || !NetworkSecurityUtils.isLocalNetworkHost(uri.host)) {
      debugPrint('[DLNA] controlUrl rejeitado por segurança para ação $action: $controlUrl');
      return DlnaResult.networkFailure('Endereço IP de destino não é permitido (não é rede local).');
    }

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (cert, host, port) => NetworkSecurityUtils.isLocalNetworkHost(host);

    try {
      final req = await client.postUrl(uri).timeout(timeout);
      req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      req.headers.set('SOAPACTION', '"$avTransportServiceType#$action"');
      req.headers.set('Connection', 'close');
      req.write(body);

      final res = await req.close().timeout(timeout);
      final resBody = await res.transform(utf8.decoder).join();

      final result = DlnaResult.fromResponse(statusCode: res.statusCode, responseBody: resBody);

      if (result.success) {
        debugPrint('[DLNA] Ação SOAP $action executada com sucesso na TV.');
      } else {
        debugPrint('[DLNA] Falha SOAP $action (${res.statusCode}): UPnP ${result.upnpErrorCode} - ${result.upnpErrorDescription}');
        debugPrint('[DLNA] Resposta bruta da TV: $resBody');
      }

      return result;
    } catch (e) {
      debugPrint('[DLNA] Erro de rede ao enviar ação SOAP $action para $controlUrl: $e');
      return DlnaResult.networkFailure(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      client.close(force: true);
    }
  }

  static String _getUpnpClass(String mime) {
    if (mime.startsWith('image/')) return 'object.item.imageItem.photo';
    if (mime.startsWith('audio/')) return 'object.item.audioItem.musicTrack';
    return 'object.item.videoItem';
  }

  static String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Utilitário público para extração de tags XML.
  static String extractTag(String xml, String tag) {
    final pattern = RegExp(
      '<$tag>(?:<!\\[CDATA\\[)?(.*?)(?:\\]\\]>)?<\\/$tag>',
      caseSensitive: false,
      dotAll: true,
    );
    final match = pattern.firstMatch(xml);
    return match?.group(1)?.trim() ?? '';
  }
}

/// Representa a informação de progresso e duração obtida da TV via GetPositionInfo.
class DlnaPositionInfo {
  final Duration position;
  final Duration duration;

  const DlnaPositionInfo({
    required this.position,
    required this.duration,
  });

  /// Converte strings UPnP como '00:03:42' ou '00:03:42.000' em Duration.
  static DlnaPositionInfo parse({
    required String trackDuration,
    required String relTime,
  }) {
    return DlnaPositionInfo(
      position: _parseDuration(relTime),
      duration: _parseDuration(trackDuration),
    );
  }

  static Duration _parseDuration(String timeStr) {
    if (timeStr.isEmpty || timeStr == 'NOT_IMPLEMENTED') return Duration.zero;
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 3) {
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;
        final secondsPart = parts[2].split('.');
        final seconds = int.tryParse(secondsPart[0]) ?? 0;
        final millis = (secondsPart.length > 1) ? int.tryParse(secondsPart[1]) ?? 0 : 0;
        return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: millis);
      }
    } catch (_) {}
    return Duration.zero;
  }
}
