import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_adb/flutter_adb.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_security_utils.dart';
import 'drivers/tv_driver.dart';

/// A conexão ADB por Depuração por Wi-Fi não está ativa (TV com a depuração
/// desligada, porta nova não anunciada ou pareamento revogado). O controle
/// remoto continua funcionando; só a lista de aplicativos depende dela.
class AdbUnavailableException implements Exception {
  const AdbUnavailableException();
  @override
  String toString() => 'A conexão ADB com o Chromecast não está ativa.';
}

/// Optional, separately authorized ADB channel for installed launcher activities.
class GoogleTvAppsAdb {
  static final _identities = <String, Future<AdbCrypto>>{};
  static Future<AdbCrypto> _identity(String host) =>
      _identities.putIfAbsent(host, () => _loadIdentity(host));
  static Future<AdbCrypto> _loadIdentity(String host) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'sixf_adb_identity_$host';
    var encoded = prefs.getString(key);
    if (encoded == null) {
      encoded = await Isolate.run(
        () => jsonEncode(
          AdbCrypto(adbKeyName: 'sixf@remote').exportKeyPairForStorage(),
        ),
      );
      await prefs.setString(key, encoded!);
    }
    return AdbCrypto(
      keyPair: AdbCrypto.keyPairFromStorageMap(
        Map<String, dynamic>.from(jsonDecode(encoded)),
      ),
      adbKeyName: 'sixf@remote',
    );
  }

  static void _validate(String host, int port) {
    if (!NetworkSecurityUtils.isLocalNetworkHost(host) ||
        port < 1 ||
        port > 65535) {
      throw StateError('Informe o IP local e uma porta válida.');
    }
  }

  static Future<bool> configured(String host) async =>
      (await SharedPreferences.getInstance()).containsKey(
        'sixf_adb_port_$host',
      );

  /// Aceita "37123" ou "192.168.0.50:37123" (como a TV exibe "Endereço IP e porta").
  static int? parsePort(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    final port = int.tryParse(value.split(':').last.trim());
    return port != null && port >= 1 && port <= 65535 ? port : null;
  }

  /// Pareia (quando [pairingPort] e [code] são informados) e confirma o acesso.
  /// Sem [port], a porta de conexão — que a TV sorteia a cada ativação da
  /// Depuração por Wi-Fi — é descoberta automaticamente via mDNS.
  static Future<void> configure(
    String host,
    int? port, {
    int? pairingPort,
    String? code,
  }) async {
    final identity = await _identity(host);
    if (pairingPort != null) {
      _validate(host, pairingPort);
      if (!RegExp(r'^\d{6}$').hasMatch(code ?? '')) {
        throw StateError('Informe os seis dígitos do código de pareamento.');
      }
      final bool paired;
      try {
        paired = await AdbPairing.pair(
          host,
          pairingPort,
          code!,
          identity,
        ).timeout(const Duration(seconds: 30));
      } catch (_) {
        throw StateError(
          'A TV não respondeu ao pareamento. Confira a porta e o código, que '
          'mudam sempre que a janela de pareamento é reaberta.',
        );
      }
      if (!paired) {
        throw StateError('Código de pareamento recusado. Gere um novo na TV.');
      }
    }
    port ??= await discoverPort(host);
    if (port == null) {
      throw StateError(
        'Pareado, mas a porta de conexão não foi encontrada. Informe a porta '
        'mostrada em "Endereço IP e porta" na tela de Depuração por Wi-Fi.',
      );
    }
    _validate(host, port);
    final reply = await _command(host, port, identity, 'echo SIXF_ADB_OK');
    if (!reply
        .split(RegExp(r'[\r\n]+'))
        .any((line) => line.trim() == 'SIXF_ADB_OK')) {
      throw StateError('O Chromecast não confirmou o acesso ADB.');
    }
    await (await SharedPreferences.getInstance()).setInt(
      'sixf_adb_port_$host',
      port,
    );
  }

  static Future<String> _command(
    String host,
    int port,
    AdbCrypto identity,
    String command,
  ) async {
    _validate(host, port);
    final connection = AdbConnection(host, port, identity);
    try {
      var connected = false;
      for (var attempt = 0; attempt < 3 && !connected; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        connected = await connection.connect().timeout(
          const Duration(seconds: 15),
        );
        if (!connected) await connection.disconnect();
      }
      if (!connected) {
        throw StateError('Autorize o SixF na TV e confira a porta ADB.');
      }
      final shell = await connection.openShell();
      final bytes = <int>[];
      final output = shell.onPayload.fold<List<int>>(bytes, (all, chunk) {
        if (all.length + chunk.length > 2097152) {
          throw StateError('Resposta ADB muito grande.');
        }
        all.addAll(chunk);
        return all;
      });
      await shell.writeString('$command; exit\n');
      return utf8.decode(
        await output.timeout(const Duration(seconds: 20)),
        allowMalformed: true,
      );
    } finally {
      await connection.disconnect();
    }
  }

  static Future<String> command(String host, String command) async {
    final port = (await SharedPreferences.getInstance()).getInt(
      'sixf_adb_port_$host',
    );
    if (port == null) {
      throw StateError('Configure o acesso aos aplicativos por ADB.');
    }
    final identity = await _identity(host);
    try {
      return await _command(host, port, identity, command);
    } catch (_) {
      // A Depuração por Wi-Fi sorteia uma nova porta de conexão sempre que é
      // reativada (reinício do Chromecast, troca de rede). Recusa, timeout ou
      // EOF não provam revogação do pareamento (ver BPM-009): redescobre a
      // porta e tenta de novo com a MESMA identidade, sem apagar nada.
      final discovered = await discoverPort(host);
      if (discovered == null || discovered == port) {
        throw const AdbUnavailableException();
      }
      final String result;
      try {
        result = await _command(host, discovered, identity, command);
      } catch (_) {
        throw const AdbUnavailableException();
      }
      await (await SharedPreferences.getInstance()).setInt(
        'sixf_adb_port_$host',
        discovered,
      );
      return result;
    }
  }

  /// Resolve only the selected TV: never fall back to another ADB device.
  static Future<int?> discoverPort(String host) async {
    // Android descarta multicast recebido sem um MulticastLock do Wi-Fi.
    var locked = false;
    if (Platform.isAndroid) {
      try {
        locked = await _platform.invokeMethod<bool>('multicastLock') ?? false;
      } catch (_) {}
    }
    try {
      return await _discoverPort(host);
    } finally {
      if (locked) {
        try {
          await _platform.invokeMethod<void>('multicastUnlock');
        } catch (_) {}
      }
    }
  }

  static const _platform = MethodChannel('sixf/library');

  static Future<int?> _discoverPort(String host) async {
    final client = MDnsClient(
      rawDatagramSocketFactory:
          (host, port, {reuseAddress = true, reusePort = true, ttl = 1}) =>
              RawDatagramSocket.bind(
                host,
                port,
                reuseAddress: reuseAddress,
                reusePort: Platform.isWindows ? false : reusePort,
                ttl: ttl,
              ),
    );
    var closed = false;
    final result = Completer<int?>();
    Future<void> resolve(PtrResourceRecord ptr) async {
      await for (final srv in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      )) {
        if (closed) return;
        await for (final addr in client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
        )) {
          if (closed) return;
          if (addr.address.address == host && !result.isCompleted) {
            result.complete(srv.port);
          }
        }
      }
    }

    Future<void> scan() async {
      try {
        await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer('_adb-tls-connect._tcp.local'),
        )) {
          if (closed) return;
          unawaited(resolve(ptr).catchError((Object _) {}));
        }
      } catch (_) {
        if (!result.isCompleted) result.complete(null);
      }
    }

    try {
      await client.start();
      unawaited(scan());
      return await result.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      closed = true;
      client.stop();
    }
  }

  // Labels only: the inventory always comes from the device, never this map.
  static const _labels = <String, String>{
    'com.android.tv.settings': 'Configurações',
    'com.android.vending': 'Play Store',
    'com.google.android.youtube.tv': 'YouTube',
    'com.google.android.youtube.tvmusic': 'YouTube Music',
    'com.plexapp.android': 'Plex',
    'dev.dworks.apps.anexplorer': 'AnExplorer',
    'org.smarttube.stable': 'SmartTube',
    'com.google.android.play.games': 'Google Play Games',
    'com.google.android.videos': 'Google TV',
    'com.alphainventor.filemanager': 'Gerenciador de arquivos',
    'com.amazon.amazonvideo.livingroom': 'Prime Video',
    'com.apple.atve.androidtv.appletv': 'Apple TV',
    'com.cxinventor.file.explorer': 'Cx File Explorer',
    'com.disney.disneyplus': 'Disney+',
    'com.globo.globotv': 'Globoplay',
    'com.instantbits.cast.receiver': 'Web Video Caster Receiver',
    'com.mercadolibre.android.mplay_tv': 'Mercado Play',
    'com.netflix.ninja': 'Netflix',
    'com.spotify.tv.android': 'Spotify',
    'com.wbd.stream': 'HBO Max',
    'org.localsend.localsend_app': 'LocalSend',
    'org.videolan.vlc': 'VLC',
    'tunein.player': 'TuneIn',
  };

  static List<TvAppInfo> parseApps(String output) {
    final components = <String, String>{};
    for (final line in output.split(RegExp(r'[\r\n]+'))) {
      final value = line.trim();
      if (RegExp(r'^[A-Za-z][A-Za-z0-9_.]*/[A-Za-z0-9_.$]+$').hasMatch(value)) {
        components.putIfAbsent(value.split('/').first, () => value);
      }
    }
    return components.entries
        .map(
          (e) => TvAppInfo.fromRaw(
            id: 'adb:${e.value}',
            name: _labels[e.key] ?? e.key,
          ),
        )
        .toList();
  }

  static Future<List<TvAppInfo>> apps(String host) async {
    final output = await command(
      host,
      'cmd package query-activities --brief --components -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER; cmd package query-activities --brief --components -a android.intent.action.MAIN -c android.intent.category.LAUNCHER',
    );
    final result = parseApps(output);
    if (result.isEmpty) {
      throw StateError(
        'O Chromecast não retornou aplicativos. Confira a autorização ADB.',
      );
    }
    return result;
  }

  static Future<void> launch(String host, String component) async {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.]*/[A-Za-z0-9_.$]+$')
        .hasMatch(component)) {
      throw StateError('Aplicativo inválido.');
    }
    final output = await command(host, 'am start -W -n $component');
    if (output.contains('Error:') || output.contains('Exception')) {
      throw StateError('O Chromecast recusou abrir o aplicativo.');
    }
  }
}
