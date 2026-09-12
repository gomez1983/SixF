import 'dart:io';
import 'package:flutter/foundation.dart';

/// Serviço para ligar a TV LG que está em modo de espera (Standby) via Wake-on-LAN (WoL).
///
/// Monta o "Magic Packet" binário de 102 bytes e transmite via broadcast UDP na rede local.
class WakeOnLanService {
  WakeOnLanService._();

  /// Converte uma string de endereço MAC (com ou sem separadores ':' ou '-') em bytes.
  static List<int>? parseMacAddress(String mac) {
    final cleanMac = mac.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleanMac.length != 12) {
      return null;
    }

    final bytes = <int>[];
    for (var i = 0; i < 12; i += 2) {
      final byteString = cleanMac.substring(i, i + 2);
      final byteVal = int.tryParse(byteString, radix: 16);
      if (byteVal == null) return null;
      bytes.add(byteVal);
    }
    return bytes;
  }

  /// Constrói o "Magic Packet" padrão Wake-on-LAN (102 bytes):
  /// - 6 bytes de 0xFF
  /// - 16 repetições dos 6 bytes do MAC Address
  static Uint8List? buildMagicPacket(String macAddress) {
    final macBytes = parseMacAddress(macAddress);
    if (macBytes == null || macBytes.length != 6) {
      return null;
    }

    final packet = Uint8List(102);

    // 6 primeiros bytes com 0xFF
    for (var i = 0; i < 6; i++) {
      packet[i] = 0xFF;
    }

    // 16 repetições do MAC
    for (var i = 0; i < 16; i++) {
      for (var j = 0; j < 6; j++) {
        packet[6 + (i * 6) + j] = macBytes[j];
      }
    }

    return packet;
  }

  /// Dispara o pacote Wake-on-LAN via broadcast UDP nas portas padrão 9 e 7.
  static Future<bool> wake(String macAddress) async {
    if (kIsWeb) {
      debugPrint('[WOL] Wake-on-LAN via UDP broadcast não é suportado no navegador Web.');
      return false;
    }

    final packet = buildMagicPacket(macAddress);
    if (packet == null) {
      debugPrint('[WOL] Endereço MAC inválido para Wake-on-LAN: $macAddress');
      return false;
    }

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // Dispara para o broadcast da rede nas portas 9 e 7
      final target = InternetAddress('255.255.255.255');
      socket.send(packet, target, 9);
      socket.send(packet, target, 7);

      socket.close();
      debugPrint('[WOL] Magic Packet enviado com sucesso para $macAddress');
      return true;
    } catch (e) {
      debugPrint('[WOL] Erro ao enviar pacote Wake-on-LAN: $e');
      return false;
    }
  }
}
