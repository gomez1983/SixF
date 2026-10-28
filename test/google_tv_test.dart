import 'google_tv_voice_session_test.dart' show FakeAudioSource;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/drivers/google_tv/credentials.dart';
import 'package:sixf_remote/services/drivers/google_tv/wire.dart';
import 'package:sixf_remote/services/drivers/google_tv_driver.dart';
import 'package:sixf_remote/services/drivers/driver_factory.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> eventually(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (!condition() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GoogleTvCredentials client;
  late GoogleTvCredentials server;
  setUpAll(() {
    client = GoogleTvCredentials.generate();
    server = GoogleTvCredentials.generate();
  });

  test(
    'protobuf signed int32 fixtures: -1 and minimum int32 survive re-encoding',
    () {
      // protobuf int32 negative values are sign-extended to ten-byte varints.
      const negativeOne = [8, 255, 255, 255, 255, 255, 255, 255, 255, 255, 1];
      const minimumInt32 = [8, 128, 128, 128, 128, 248, 255, 255, 255, 255, 1];
      expect(TvWire.decode(negativeOne)[1], -1);
      expect(TvWire.number(1, -1), negativeOne);
      expect(TvWire.decode(minimumInt32)[1], -2147483648);
      expect(TvWire.number(1, -2147483648), minimumInt32);
      expect(
        () => TvWire.decode([8, ...List.filled(9, 255), 2]),
        throwsFormatException,
      );
    },
  );

  test('protobuf handles fragmented varints, coalesced frames and UTF-8', () {
    final payload = TvWire.text(90, 'á😀' * 40);
    final frame = TvWire.frame(payload);
    final decoder = TvFrameDecoder();
    expect(decoder.add(frame.sublist(0, 1)).toList(), isEmpty);
    expect(decoder.add(frame.sublist(1, 8)).toList(), isEmpty);
    final frames = decoder.add([
      ...frame.sublist(8),
      ...TvWire.frame([8, 1]),
    ]).toList();
    expect(frames, [
      payload,
      [8, 1],
    ]);
    expect(TvWire.string(TvWire.decode(frames.first), 90), 'á😀' * 40);
    expect(
      () => TvFrameDecoder().add([255, 255, 255, 127]).toList(),
      throwsFormatException,
    );
    expect(() => TvWire.decode([10, 5, 1]), throwsFormatException);
    expect(TvWire.bytes(10, [8, 19, 16, 3]), [82, 4, 8, 19, 16, 3]);
  });

  test('pairing secret validates the first byte and rejects invalid codes', () {
    final cert = CryptoUtils.getBytesFromPEMString(server.certificate);
    final c = GoogleTvCredentials.publicKey(
      CryptoUtils.getBytesFromPEMString(client.certificate),
    );
    final s = GoogleTvCredentials.publicKey(cert);
    final expected = sha256.convert([
      ...GoogleTvCredentials.unsigned(c.modulus!),
      ...GoogleTvCredentials.unsigned(c.exponent!),
      ...GoogleTvCredentials.unsigned(s.modulus!),
      ...GoogleTvCredentials.unsigned(s.exponent!),
      0x12,
      0x34,
    ]).bytes;
    final code = '${expected[0].toRadixString(16).padLeft(2, '0')}1234';
    expect(client.secret(code, cert), expected);
    expect(() => client.secret('XYZ123', cert), throwsFormatException);
    expect(
      () => client.secret(
        '${(expected[0] ^ 1).toRadixString(16).padLeft(2, '0')}1234',
        cert,
      ),
      throwsFormatException,
    );
    expect(
      GoogleTvCredentials.decode(client.encode()).certificate,
      client.certificate,
    );
  });

  test(
    'TLS pairing, persistent reconnect, ping echo, keys and text counters',
    () async {
      final context = server.context()
        ..setTrustedCertificatesBytes(utf8.encode(client.certificate));
      final pairing = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
        requestClientCertificate: true,
        requireClientCertificate: true,
      );
      final control = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
        requestClientCertificate: true,
        requireClientCertificate: true,
      );
      final sockets = <SecureSocket>[];
      final received = <Map<int, Object>>[];
      var pairConnections = 0;
      var controlConnections = 0;
      final pairingSub = pairing.listen(
        (socket) {
          pairConnections++;
          sockets.add(socket);
          final frames = TvFrameDecoder();
          void reply(int field, List<int> inner) => socket.add(
            TvWire.frame([
              ...TvWire.number(1, 2),
              ...TvWire.number(2, 200),
              ...TvWire.bytes(field, inner),
            ]),
          );
          socket.listen((data) {
            for (final raw in frames.add(data)) {
              final message = TvWire.decode(raw);
              if (message.containsKey(10)) {
                reply(11, []);
              }
              if (message.containsKey(20)) {
                reply(20, []);
              }
              if (message.containsKey(30)) {
                reply(31, []);
              }
              if (message.containsKey(40)) {
                expect(TvWire.message(message, 40)[1], hasLength(32));
                reply(41, []);
              }
            }
          }, onError: (Object _) {});
        },
        onError: (Object error) {
          fail('Pair server: $error');
        },
      );
      final controlSub = control.listen(
        (socket) {
          controlConnections++;
          sockets.add(socket);
          expect(socket.peerCertificate, isNotNull);
          socket.add(
            TvWire.frame(
              TvWire.bytes(1, [
                ...TvWire.number(1, 623),
                ...TvWire.bytes(2, TvWire.text(1, 'Test Google TV')),
              ]),
            ),
          );
          final decoder = TvFrameDecoder();
          socket.listen((data) {
            for (final raw in decoder.add(data)) {
              final message = TvWire.decode(raw);
              received.add(message);
              if (message.containsKey(10) &&
                  TvWire.integer(TvWire.message(message, 10), 1) == 84) {
                Timer(const Duration(milliseconds: 80), () {
                  socket.add(
                    TvWire.frame(TvWire.bytes(30, TvWire.number(1, -9))),
                  );
                });
              }

              if (message.containsKey(1)) {
                socket.add(
                  TvWire.frame(TvWire.bytes(2, TvWire.number(1, 615))),
                );
              }
              if (message.containsKey(2)) {
                socket.add([
                  ...TvWire.frame(TvWire.bytes(40, TvWire.number(1, 1))),
                  ...TvWire.frame(TvWire.bytes(8, TvWire.number(1, -197))),
                  ...TvWire.frame(
                    TvWire.bytes(21, [
                      ...TvWire.number(1, 7),
                      ...TvWire.number(2, 9),
                    ]),
                  ),
                  ...TvWire.frame(
                    TvWire.bytes(50, [
                      ...TvWire.number(6, 20),
                      ...TvWire.number(7, 8),
                      ...TvWire.number(8, 1),
                    ]),
                  ),
                ]);
              }
            }
          }, onError: (Object _) {});
        },
        onError: (Object error) {
          fail('Control server: $error');
        },
      );
      var generated = 0;
      final audioSource = FakeAudioSource();
      final driver = GoogleTvDriver(
        controlPort: control.port,
        audioSourceFactory: () => audioSource,
        pairingPort: pairing.port,
        credentialsFactory: () async {
          generated++;
          return client;
        },
      );
      addTearDown(() async {
        driver.disconnect();
        for (final socket in sockets) {
          socket.destroy();
        }
        await pairingSub.cancel();
        await controlSub.cancel();
        await pairing.close();
        await control.close();
      });
      String? saved;
      int? volume;
      driver.onAuthTokenReceived = (value) => saved = value;
      driver.onVolumeStatusChanged = (value, muted) {
        volume = value;
        expect(muted, isTrue);
      };
      expect(await driver.connect(ipAddress: '127.0.0.1'), isFalse);
      expect(driver.connectionState, DeviceConnectionState.pairingPrompt);
      expect(saved, isNull);
      await expectLater(driver.sendPairingPin('WRONG!'), throwsFormatException);
      expect(driver.connectionState, DeviceConnectionState.pairingPrompt);
      final c = GoogleTvCredentials.publicKey(
        CryptoUtils.getBytesFromPEMString(client.certificate),
      );
      final s = GoogleTvCredentials.publicKey(
        CryptoUtils.getBytesFromPEMString(server.certificate),
      );
      final hash = sha256.convert([
        ...GoogleTvCredentials.unsigned(c.modulus!),
        ...GoogleTvCredentials.unsigned(c.exponent!),
        ...GoogleTvCredentials.unsigned(s.modulus!),
        ...GoogleTvCredentials.unsigned(s.exponent!),
        0x12,
        0x34,
      ]).bytes;
      await driver.sendPairingPin(
        '${hash[0].toRadixString(16).padLeft(2, '0')}1234',
      );
      expect(driver.isConnected, isTrue);
      expect(saved, client.encode());
      await eventually(
        () => received.any((m) => m.containsKey(9)) && volume == 40,
      );
      expect(
        TvWire.integer(
          TvWire.message(received.firstWhere((m) => m.containsKey(9)), 9),
          1,
        ),
        -197,
      );
      driver.sendKey(RemoteKey.dpadUp);
      driver.sendKey(RemoteKey.menu);
      driver.sendText('Ação 😀');
      driver.openApp('youtube');
      driver.openApp('netflix');
      await eventually(() => received.any((m) => m.containsKey(90)));
      expect(
        TvWire.message(received.firstWhere((m) => m.containsKey(10)), 10),
        {1: 19, 2: 3},
      );
      expect(
        received
            .where((m) => m.containsKey(10))
            .map((m) => TvWire.message(m, 10)[1]),
        [19, 176],
      );
      final edit = TvWire.message(
        received.firstWhere((m) => m.containsKey(21)),
        21,
      );
      expect(edit[1], 7);
      expect(edit[2], 9);
      expect(
        TvWire.string(TvWire.message(TvWire.message(edit, 3), 2), 3),
        'Ação 😀',
      );
      driver.disconnect();
      expect(
        await driver.connect(ipAddress: '127.0.0.1', authToken: saved),
        isTrue,
      );
      expect(pairConnections, 1);
      expect(controlConnections, 2);
      expect(generated, 1);
      final startingVoice = driver.startVoice();
      await eventually(
        () => received.any(
          (m) => m.containsKey(10) && TvWire.message(m, 10)[1] == 84,
        ),
      );
      audioSource.stream.add([1, 0, 2, 0]);
      await driver.stopVoice();
      await startingVoice;
      await eventually(() => received.any((m) => m.containsKey(32)));
      expect(
        TvWire.message(received.lastWhere((m) => m.containsKey(32)), 32)[1],
        -9,
      );
      expect(
        (received.firstWhere((m) => m.containsKey(31))[31] as List<int>).take(
          6,
        ),
        [1, 0, 2, 0, 0x34, 0x12],
      );
    },
  );

  test(
    'saved identity rejected asynchronously by TLS returns to PIN pairing',
    () async {
      // Trust no client certificate on the control endpoint, simulating a revoked pairing.
      final control = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        server.context(),
        requestClientCertificate: true,
        requireClientCertificate: true,
      );
      final pairingContext = server.context()
        ..setTrustedCertificatesBytes(utf8.encode(client.certificate));
      final pairing = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        pairingContext,
        requestClientCertificate: true,
        requireClientCertificate: true,
      );
      final sockets = <SecureSocket>[];
      final controlSub = control.listen(sockets.add, onError: (Object _) {});
      final pairingSub = pairing.listen((socket) {
        sockets.add(socket);
        final decoder = TvFrameDecoder();
        socket.listen((data) {
          for (final raw in decoder.add(data)) {
            if (TvWire.decode(raw).containsKey(10)) {
              socket.add(
                TvWire.frame([
                  ...TvWire.number(1, 2),
                  ...TvWire.number(2, 200),
                  ...TvWire.bytes(31, []),
                ]),
              );
            }
          }
        }, onError: (Object _) {});
      }, onError: (Object _) {});
      var generated = 0;
      final driver = GoogleTvDriver(
        controlPort: control.port,
        pairingPort: pairing.port,
        credentialsFactory: () async {
          generated++;
          return client;
        },
      );
      addTearDown(() async {
        driver.disconnect();
        for (final socket in sockets) {
          socket.destroy();
        }
        await controlSub.cancel();
        await pairingSub.cancel();
        await control.close();
        await pairing.close();
      });
      expect(
        await driver.connect(
          ipAddress: '127.0.0.1',
          authToken: client.encode(),
        ),
        isFalse,
      );
      expect(driver.connectionState, DeviceConnectionState.pairingPrompt);
      expect(generated, 0);
    },
  );

  test('connection recovers after a drop, keeps identity, and explicit disconnect cancels retry', () async {
    final context = server.context()
      ..setTrustedCertificatesBytes(utf8.encode(client.certificate));
    final control = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      context,
      requestClientCertificate: true,
      requireClientCertificate: true,
    );
    final sockets = <SecureSocket>[];
    final sub = control.listen((socket) {
      sockets.add(socket);
      socket.listen((_) {}, onError: (Object _) {});
      socket.add(TvWire.frame(TvWire.bytes(40, TvWire.number(1, 1))));
    }, onError: (Object _) {});
    final driver = GoogleTvDriver(
      controlPort: control.port,
      reconnectDelays: const [Duration(milliseconds: 80)],
    );
    addTearDown(() async {
      driver.disconnect();
      for (final socket in sockets) {
        socket.destroy();
      }
      await sub.cancel();
      await control.close();
    });
    expect(
      await driver.connect(ipAddress: '127.0.0.1', authToken: client.encode()),
      isTrue,
    );
    sockets.first.destroy();
    await eventually(() => sockets.length == 2 && driver.isConnected);
    driver.disconnect();
    expect(
      await driver.connect(ipAddress: '127.0.0.1', authToken: client.encode()),
      isTrue,
    );
    sockets.last.destroy();
    await eventually(
      () => driver.connectionState == DeviceConnectionState.connecting,
    );
    driver.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(sockets, hasLength(3));
    expect(driver.isConnected, isFalse);
  });

  test('outgoing commands prevent idle timeout; real idle disconnect remains bounded', () async {
    final context = server.context()
      ..setTrustedCertificatesBytes(utf8.encode(client.certificate));
    final control = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      context,
      requestClientCertificate: true,
      requireClientCertificate: true,
    );
    final sockets = <SecureSocket>[];
    final sub = control.listen((socket) {
      sockets.add(socket);
      socket.listen((_) {}, onError: (Object _) {});
      socket.add(TvWire.frame(TvWire.bytes(40, TvWire.number(1, 1))));
    }, onError: (Object _) {});
    final driver = GoogleTvDriver(
      controlPort: control.port,
      idleTimeout: const Duration(milliseconds: 300),
      reconnectDelays: const [],
    );
    addTearDown(() async {
      driver.disconnect();
      for (final socket in sockets) {
        socket.destroy();
      }
      await sub.cancel();
      await control.close();
    });
    expect(
      await driver.connect(ipAddress: '127.0.0.1', authToken: client.encode()),
      isTrue,
    );
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      driver.sendKey(RemoteKey.dpadUp);
      expect(driver.isConnected, isTrue);
    }
    await eventually(() => !driver.isConnected);
  });

  test(
    'disconnect cancels pending identity creation without late callbacks',
    () async {
      final pending = Completer<GoogleTvCredentials>();
      final driver = GoogleTvDriver(credentialsFactory: () => pending.future);
      final attempt = driver.connect(ipAddress: '127.0.0.1');
      driver.disconnect();
      pending.complete(client);
      expect(await attempt, isFalse);
      expect(driver.connectionState, DeviceConnectionState.disconnected);
    },
  );

  test(
    'factory and credential storage keep Google TV isolated from LG',
    () async {
      final driver = DriverFactory.create(TvBrand.googleTv);
      expect(driver, isA<GoogleTvDriver>());
      driver.disconnect();
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      await storage.setClientKey(
        client.encode(),
        brand: TvBrand.googleTv,
        ip: '192.168.1.2',
      );
      await storage.setClientKey(
        'lg-token',
        brand: TvBrand.lgWebOs,
        ip: '192.168.1.2',
      );
      expect(
        storage.getClientKey(brand: TvBrand.googleTv, ip: '192.168.1.2'),
        client.encode(),
      );
      expect(
        storage.getClientKey(brand: TvBrand.lgWebOs, ip: '192.168.1.2'),
        'lg-token',
      );
    },
  );
}
