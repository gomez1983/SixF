import 'dart:convert';
import 'dart:io';
import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gerenciador de certificado e chave criptográfica para o protocolo Android TV Remote v2.
/// Gera e armazena par RSA 2048-bit autoassinado x509 necessário para TLS mútuo (mTLS).
class AndroidTvCertificateManager {
  static const String _prefCertKey = 'atv_client_cert_pem';
  static const String _prefPrivateKeyKey = 'atv_client_key_pem';

  static String? _cachedCertPem;
  static String? _cachedKeyPem;
  static BigInt? _cachedModulus;
  static BigInt? _cachedExponent;

  /// Obtém ou gera os certificados PEM
  static Future<Map<String, String>> getOrCreateCertificate({String clientName = 'SixF Remote'}) async {
    if (_cachedCertPem != null && _cachedKeyPem != null) {
      return {'cert': _cachedCertPem!, 'key': _cachedKeyPem!};
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCert = prefs.getString(_prefCertKey);
      final savedKey = prefs.getString(_prefPrivateKeyKey);

      if (savedCert != null && savedKey != null) {
        _cachedCertPem = savedCert;
        _cachedKeyPem = savedKey;
        _extractModulusExponent(savedCert);
        return {'cert': savedCert, 'key': savedKey};
      }
    } catch (e) {
      debugPrint('[AndroidTvCertificateManager] Aviso ao ler do storage: $e');
    }

    // Se existir cert.pem e key.pem locais gerados previamente, reutiliza
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        [File('cert.pem'), File('key.pem')],
        [File('$exeDir\\cert.pem'), File('$exeDir\\key.pem')],
        [File(r'c:\Projetos\SixF\cert.pem'), File(r'c:\Projetos\SixF\key.pem')],
      ];

      for (final pair in candidates) {
        if (await pair[0].exists() && await pair[1].exists()) {
          final certContent = await pair[0].readAsString();
          final keyContent = await pair[1].readAsString();
          _cachedCertPem = certContent;
          _cachedKeyPem = keyContent;
          _extractModulusExponent(certContent);
          await _persist(_cachedCertPem!, _cachedKeyPem!);
          debugPrint('[AndroidTvCertificateManager] Certificados carregados com sucesso de ${pair[0].path}');
          return {'cert': certContent, 'key': keyContent};
        }
      }
    } catch (e) {
      debugPrint('[AndroidTvCertificateManager] Erro ao buscar arquivos de certificado locais: $e');
    }

    // Gera via OpenSSL se disponível no sistema ou cria fallback
    final generated = await _generateWithOpenSsl(clientName);
    _cachedCertPem = generated['cert']!;
    _cachedKeyPem = generated['key']!;
    _extractModulusExponent(_cachedCertPem!);
    await _persist(_cachedCertPem!, _cachedKeyPem!);
    return generated;
  }

  static Future<void> _persist(String cert, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefCertKey, cert);
      await prefs.setString(_prefPrivateKeyKey, key);
    } catch (e) {
      debugPrint('[AndroidTvCertificateManager] Não foi possível persistir no SharedPreferences: $e');
    }
  }

  static Future<Map<String, String>> _generateWithOpenSsl(String clientName) async {
    final opensslPaths = [
      'openssl',
      r'C:\Program Files\Git\usr\bin\openssl.exe',
      r'C:\Program Files\OpenSSL-Win64\bin\openssl.exe',
    ];

    String? foundPath;
    for (final p in opensslPaths) {
      try {
        final res = await Process.run(p, ['version']);
        if (res.exitCode == 0) {
          foundPath = p;
          break;
        }
      } catch (_) {}
    }

    if (foundPath != null) {
      final tempDir = Directory.systemTemp.createTempSync('atv_cert_');
      final keyPath = '${tempDir.path}\\key.pem';
      final certPath = '${tempDir.path}\\cert.pem';

      await Process.run(foundPath, [
        'req',
        '-x509',
        '-nodes',
        '-days',
        '3650',
        '-newkey',
        'rsa:2048',
        '-keyout',
        keyPath,
        '-out',
        certPath,
        '-subj',
        '/CN=$clientName',
      ]);

      final certPem = await File(certPath).readAsString();
      final keyPem = await File(keyPath).readAsString();

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}

      return {'cert': certPem, 'key': keyPem};
    }

    throw UnsupportedError('OpenSSL não encontrado para geração de certificados Android TV.');
  }

  /// Retorna o modulus (N) e exponent (E) da chave pública do cliente
  static (BigInt, BigInt) getClientModulusAndExponent() {
    if (_cachedModulus != null && _cachedExponent != null) {
      return (_cachedModulus!, _cachedExponent!);
    }
    if (_cachedCertPem != null) {
      _extractModulusExponent(_cachedCertPem!);
      return (_cachedModulus!, _cachedExponent!);
    }
    return (BigInt.zero, BigInt.from(65537));
  }

  static void _extractModulusExponent(String certPem) {
    try {
      final clean = certPem
          .replaceAll('-----BEGIN CERTIFICATE-----', '')
          .replaceAll('-----END CERTIFICATE-----', '')
          .replaceAll(RegExp(r'\s+'), '');
      final bytes = base64.decode(clean);
      final (mod, exp) = extractModulusExponentFromDer(Uint8List.fromList(bytes));
      _cachedModulus = mod;
      _cachedExponent = exp;
    } catch (e) {
      debugPrint('[AndroidTvCertificateManager] Falha ao extrair modulus via ASN1: $e');
    }
  }

  /// Extrai modulus e exponent de um certificado X.509 em formato DER (Uint8List)
  static (BigInt, BigInt) extractModulusExponentFromDer(Uint8List derBytes) {
    try {
      final asn1Parser = ASN1Parser(derBytes);
      final topSeq = asn1Parser.nextObject() as ASN1Sequence;
      final tbsSeq = topSeq.elements[0] as ASN1Sequence;

      for (final el in tbsSeq.elements) {
        if (el is ASN1Sequence && el.elements.length >= 2) {
          if (el.elements[1] is ASN1BitString) {
            final bitStr = el.elements[1] as ASN1BitString;
            final keyBytes = bitStr.stringValue;
            final innerParser = ASN1Parser(Uint8List.fromList(keyBytes));
            final keySeq = innerParser.nextObject() as ASN1Sequence;
            final modObj = keySeq.elements[0] as ASN1Integer;
            final expObj = keySeq.elements[1] as ASN1Integer;
            return (modObj.valueAsBigInteger, expObj.valueAsBigInteger);
          }
        }
      }
    } catch (e) {
      debugPrint('[AndroidTvCertificateManager] Erro ao extrair modulus DER: $e');
    }
    return (BigInt.zero, BigInt.from(65537));
  }

  /// Calcula o Secret Hash SHA256 para o código de 6 dígitos mostrado na TV
  static Uint8List computeSecretHash({
    required BigInt clientModulus,
    required BigInt clientExponent,
    required BigInt serverModulus,
    required BigInt serverExponent,
    required String pinHex,
  }) {
    // Android TV Remote v2 Secret Hash algorithm:
    // hash = SHA256(
    //   hex(client_modulus) +
    //   hex(client_exponent, padded) +
    //   hex(server_modulus) +
    //   hex(server_exponent, padded) +
    //   hex(pin[2:])
    // )
    final clientModHex = clientModulus.toRadixString(16).toUpperCase();
    final clientExpHex = '0${clientExponent.toRadixString(16).toUpperCase()}';
    final serverModHex = serverModulus.toRadixString(16).toUpperCase();
    final serverExpHex = '0${serverExponent.toRadixString(16).toUpperCase()}';
    final pinSubHex = pinHex.substring(2).toUpperCase();

    final fullHex = '$clientModHex$clientExpHex$serverModHex$serverExpHex$pinSubHex';
    final payloadBytes = <int>[];
    for (int i = 0; i < fullHex.length; i += 2) {
      payloadBytes.add(int.parse(fullHex.substring(i, i + 2), radix: 16));
    }

    final digest = crypto.sha256.convert(payloadBytes);
    return Uint8List.fromList(digest.bytes);
  }
}
