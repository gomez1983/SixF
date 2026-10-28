import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/asn1.dart';
import 'package:crypto/crypto.dart';

/// Persistent client identity, reused for pairing AND every control connection.
class GoogleTvCredentials {
  final String certificate;
  final String privateKey;
  const GoogleTvCredentials(this.certificate, this.privateKey);
  String encode() =>
      jsonEncode({'certificate': certificate, 'privateKey': privateKey});
  factory GoogleTvCredentials.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return GoogleTvCredentials(
      data['certificate'] as String,
      data['privateKey'] as String,
    );
  }
  static GoogleTvCredentials generate() {
    final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final subject = {'CN': 'SixF Remote', 'O': 'SixF'};
    final csr = X509Utils.generateRsaCsrPem(
      subject,
      pair.privateKey as RSAPrivateKey,
      pair.publicKey as RSAPublicKey,
    );
    final random = Random.secure();
    final serial = BigInt.parse(
      List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      radix: 16,
    );
    final cert = X509Utils.generateSelfSignedCertificate(
      pair.privateKey,
      csr,
      3650,
      serialNumber: serial.toString(),
      issuer: subject,
      notBefore: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    );
    return GoogleTvCredentials(
      cert,
      CryptoUtils.encodeRSAPrivateKeyToPem(pair.privateKey as RSAPrivateKey),
    );
  }

  SecurityContext context() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificate))
    ..usePrivateKeyBytes(utf8.encode(privateKey));

  static RSAPublicKey publicKey(List<int> der) {
    final cert =
        ASN1Parser(Uint8List.fromList(der)).nextObject() as ASN1Sequence;
    final tbs = cert.elements!.first as ASN1Sequence;
    final index = tbs.elements!.first.tag == 0xa0 ? 6 : 5;
    final spki = tbs.elements![index] as ASN1Sequence;
    final bits = spki.elements![1] as ASN1BitString;
    final rsa =
        ASN1Parser(Uint8List.fromList(bits.stringValues!)).nextObject()
            as ASN1Sequence;
    return RSAPublicKey(
      (rsa.elements![0] as ASN1Integer).integer!,
      (rsa.elements![1] as ASN1Integer).integer!,
    );
  }

  static List<int> unsigned(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    return [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }

  List<int> secret(String code, List<int> serverDer) {
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(code)) {
      throw const FormatException(
        'Digite os 6 caracteres (0–9 e A–F) exibidos na TV.',
      );
    }
    final client = publicKey(CryptoUtils.getBytesFromPEMString(certificate));
    final server = publicKey(serverDer);
    final hash = sha256.convert([
      ...unsigned(client.modulus!),
      ...unsigned(client.exponent!),
      ...unsigned(server.modulus!),
      ...unsigned(server.exponent!),
      int.parse(code.substring(2, 4), radix: 16),
      int.parse(code.substring(4, 6), radix: 16),
    ]).bytes;
    if (hash[0] != int.parse(code.substring(0, 2), radix: 16)) {
      throw const FormatException(
        'Código incorreto. Confira o código na TV e tente novamente.',
      );
    }
    return hash;
  }
}
