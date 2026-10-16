import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/samsung_tizen_driver.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/media_server_service.dart';
import 'package:sixf_remote/services/network_operation.dart';
import 'package:sixf_remote/services/storage_service.dart';
import 'package:sixf_remote/services/dlna_service.dart';
import 'package:sixf_remote/services/webos_service.dart';

import 'session_regression_test.dart' show RecordingDriver;

class TestSocket extends Fake implements WebSocket {
  final events = StreamController<dynamic>();
  bool closed = false;
  final sent = <dynamic>[];
  @override
  Duration? pingInterval;
  @override
  void add(dynamic data) => sent.add(data);
  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class PendingDriver extends RecordingDriver {
  PendingDriver() : super(TvBrand.lgWebOs);
  final connecting = Completer<bool>();
  final apps = Completer<List<TvAppInfo>>();
  int disconnects = 0;
  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 4),
  }) => connecting.future;
  @override
  Future<List<TvAppInfo>> getInstalledApps() => apps.future;
  @override
  void disconnect() {
    disconnects++;
    super.disconnect();
  }
}

class MediaDriver extends RecordingDriver {
  MediaDriver() : super(TvBrand.lgWebOs) {
    connectionState = DeviceConnectionState.connected;
  }
  final opened = Completer<void>();
  Completer<bool>? pending;
  @override
  Future<bool> openMediaUrl(
    String url, {
    String? title,
    String? mimeType,
  }) async {
    if (!opened.isCompleted) opened.complete();
    return pending?.future ?? true;
  }
}

class LocalMediaServer extends MediaServerService {
  bool failUrl = false;
  @override
  Future<String?> getMediaUrlForTv(String targetTvIp) async =>
      failUrl ? null : 'http://127.0.0.1:$port$mediaPath';
}

class RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Credenciais individuais', () {
    for (final brand in TvBrand.values) {
      test(
        '${brand.name}: outra TV não herda chave e esquecer remove só a própria',
        () async {
          final storage = StorageService();
          await storage.init();
          final a = SavedDevice(
            id: 'a',
            name: 'A',
            ip: '192.168.1.10',
            brand: brand,
          );
          final b = SavedDevice(
            id: 'b',
            name: 'B',
            ip: '192.168.1.11',
            brand: brand,
          );
          await storage.saveDevices([a, b]);
          await storage.setClientKey('token-a', brand: brand, ip: a.ip);
          expect(storage.getClientKey(brand: brand, ip: b.ip), isNull);
          await storage.setClientKey('token-b', brand: brand, ip: b.ip);
          await storage.removeDevice(a.id);
          expect(storage.getClientKey(brand: brand, ip: a.ip), isNull);
          expect(storage.getClientKey(brand: brand, ip: b.ip), 'token-b');
          await storage.saveDevice(a);
          expect(storage.getClientKey(brand: brand, ip: a.ip), isNull);
        },
      );
    }

    test('Migra legado uma vez para o único aparelho identificado', () async {
      SharedPreferences.setMockInitialValues({
        'pref_tv_ip': '192.168.1.10',
        'pref_tv_client_key': 'legacy',
      });
      final storage = StorageService();
      await storage.init();
      expect(
        storage.getClientKey(brand: TvBrand.lgWebOs, ip: '192.168.1.10'),
        'legacy',
      );
      expect(
        storage.getClientKey(brand: TvBrand.lgWebOs, ip: '192.168.1.11'),
        isNull,
      );
      await storage.setClientKey(
        null,
        brand: TvBrand.lgWebOs,
        ip: '192.168.1.10',
      );
      final reloaded = StorageService();
      await reloaded.init();
      expect(
        reloaded.getClientKey(brand: TvBrand.lgWebOs, ip: '192.168.1.10'),
        isNull,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('pref_tv_client_key'),
        isNull,
      );
    });

    test('Cadastro multiaparelho não atribui chave global ambígua', () async {
      SharedPreferences.setMockInitialValues({
        'pref_tv_ip': '192.168.1.10',
        'pref_tv_client_key_lg_webos': 'ambiguous',
        'pref_tv_client_key_lg_webos_192.168.1.11': 'individual',
        'pref_saved_devices_v1': '[]',
      });
      final storage = StorageService();
      await storage.init();
      expect(
        storage.getClientKey(brand: TvBrand.lgWebOs, ip: '192.168.1.10'),
        isNull,
      );
      expect(
        storage.getClientKey(brand: TvBrand.lgWebOs, ip: '192.168.1.11'),
        'individual',
      );
    });
  });

  group('Ciclo de vida do controlador', () {
    test('Descarte durante inicialização não cria novas sessões', () async {
      final drivers = <RecordingDriver>[];
      final controller = RemoteController(
        driverFactory: (brand) {
          final driver = RecordingDriver(brand);
          drivers.add(driver);
          return driver;
        },
      );
      controller.dispose();
      await controller.ready;
      expect(drivers.length, 1);
      expect(controller.activeSession, isNull);
      expect(drivers.single.onAuthTokenReceived, isNull);
    });

    test('Cadastro imediato aguarda carga sem perder aparelhos', () async {
      final controller = RemoteController(driverFactory: RecordingDriver.new);
      addTearDown(controller.dispose);
      const device = SavedDevice(id: 'new', name: 'Nova', ip: '192.168.1.23');
      await controller.saveOrUpdateDevice(device, makeActive: true);
      expect(controller.activeDeviceId, device.id);
      expect(controller.savedDevices, contains(device));
    });

    test(
      'Descarte cancela espera e ignora callbacks e resultado tardios',
      () async {
        final driver = PendingDriver();
        final controller = RemoteController(initialDriver: driver);
        await controller.ready;
        final lateToken = driver.onAuthTokenReceived!;
        final lateVolume = driver.onVolumeStatusChanged!;
        final connecting = controller.connectDevice(controller.activeDeviceId!);
        await pumpEventQueue();
        controller.dispose();
        await connecting.timeout(const Duration(seconds: 1));
        lateToken('stale');
        lateVolume(99, true);
        driver.connecting.complete(true);
        await pumpEventQueue();
        expect(driver.disconnects, greaterThan(0));
        expect(
          controller.storageService.getClientKey(
            brand: driver.brand,
            ip: '192.168.1.150',
          ),
          isNull,
        );
      },
    );

    test(
      'Resposta de apps da sessão removida não modifica a nova sessão',
      () async {
        final driver = PendingDriver();
        final controller = RemoteController(initialDriver: driver);
        addTearDown(controller.dispose);
        await controller.ready;
        final oldSession = controller.activeSession!;
        final pending = controller.fetchInstalledApps();
        await controller.removeSavedDevice(oldSession.device.id);
        await pending.timeout(const Duration(seconds: 1));
        driver.apps.complete([TvAppInfo.fromRaw(id: 'late', name: 'Tardio')]);
        await pumpEventQueue();
        expect(oldSession.installedApps, isEmpty);
      },
    );

    test('Pareamento pendente não inicia outra conexão', () async {
      final driver = RecordingDriver(TvBrand.samsungTizen);
      final controller = RemoteController(initialDriver: driver);
      addTearDown(controller.dispose);
      await controller.ready;
      driver.connectionState = DeviceConnectionState.pairingPrompt;
      await controller.connectDevice(controller.activeDeviceId!);
      expect(driver.connectedIps, isEmpty);
    });
  });

  group('Sockets antigos e cancelamento', () {
    test('Cancelar operação aborta HTTP aguardando resposta', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        final received = Completer<void>();
        final disconnected = Completer<void>();
        server.listen((socket) {
          addTearDown(socket.destroy);
          socket.listen(
            (data) {
              if (!received.isCompleted) {
                socket.write(
                  'HTTP/1.1 200 OK\r\nContent-Length: 1000\r\nContent-Type: text/xml\r\n\r\n<partial>',
                );
                received.complete();
              }
            },
            onDone: () {
              if (!disconnected.isCompleted) disconnected.complete();
            },
            onError: (Object error) {
              if (!disconnected.isCompleted) disconnected.complete();
            },
          );
        });
        final operation = NetworkOperation();
        final result = operation.run(
          () => DlnaService.getPositionInfo(
            'http://127.0.0.1:${server.port}/control',
          ),
        );
        final cancelled = expectLater(
          result,
          throwsA(isA<OperationCancelled>()),
        );
        await received.future;
        operation.cancel();
        await cancelled;
        await disconnected.future.timeout(const Duration(seconds: 2));
      }, RealHttp());
    });

    test('Samsung cancelado durante handshake não restaura conexão', () async {
      final socket = TestSocket();
      final driver = SamsungTizenDriver(
        socketConnector: (_, _) async => socket,
      );
      final result = driver.connect(
        ipAddress: '192.168.1.10',
        authToken: 'saved',
      );
      await pumpEventQueue();
      driver.disconnect();
      expect(await result.timeout(const Duration(seconds: 1)), isFalse);
      socket.events.add(
        jsonEncode({
          'event': 'ms.channel.connect',
          'data': {'token': 'late'},
        }),
      );
      await pumpEventQueue();
      expect(driver.isConnected, isFalse);
      expect(socket.closed, isTrue);
      await socket.events.close();
    });

    test(
      'Samsung só limpa token após recusa explícita e permite novo pareamento',
      () async {
        final sockets = [TestSocket(), TestSocket()];
        final urls = <String>[];
        final driver = SamsungTizenDriver(
          socketConnector: (url, _) async {
            urls.add(url);
            return sockets[urls.length - 1];
          },
        );
        addTearDown(driver.disconnect);
        final keys = <String>[];
        driver.onAuthTokenReceived = keys.add;
        final result = driver.connect(
          ipAddress: '192.168.1.10',
          authToken: 'saved',
        );
        await pumpEventQueue();
        sockets.first.events.add(
          jsonEncode({'event': 'ms.channel.unauthorized'}),
        );
        expect(await result, isTrue);
        expect(keys, ['']);
        expect(urls.first, contains('token=saved'));
        expect(urls.last, isNot(contains('token=')));
        sockets.last.events.add(
          jsonEncode({
            'event': 'ms.channel.connect',
            'data': {'token': 'new'},
          }),
        );
        await pumpEventQueue();
        expect(keys, ['', 'new']);
        expect(driver.isConnected, isTrue);
        driver.disconnect();
        await sockets.first.events.close();
        await sockets.last.events.close();
      },
    );

    test(
      'LG fecha socket que chega após desconectar e não tenta fallback',
      () async {
        final opened = Completer<WebSocket>();
        var attempts = 0;
        final service = WebOsService(
          socketConnector: (_, _) {
            attempts++;
            return opened.future;
          },
        );
        final connecting = service.connect(ipAddress: '192.168.1.10');
        await pumpEventQueue();
        service.disconnect();
        expect(await connecting.timeout(const Duration(seconds: 1)), isFalse);
        final socket = TestSocket();
        opened.complete(socket);
        await pumpEventQueue();
        expect(socket.closed, isTrue);
        expect(service.state, WebOsConnectionState.disconnected);
        expect(attempts, 1);
        if (!socket.events.hasListener) socket.events.stream.listen((_) {});
        await socket.events.close();
      },
    );

    test('LG ignora encerramento e credencial do socket anterior', () async {
      final sockets = [TestSocket(), TestSocket()];
      var index = 0;
      final service = WebOsService(
        socketConnector: (_, _) async => sockets[index++],
      );
      addTearDown(service.disconnect);
      final keys = <String>[];
      service.onClientKeyReceived = keys.add;
      await service.connect(ipAddress: '192.168.1.10');
      await service.connect(ipAddress: '192.168.1.11');
      sockets.first.events.add(
        jsonEncode({
          'type': 'registered',
          'payload': {'client-key': 'old'},
        }),
      );
      await sockets.first.events.close();
      sockets.last.events.add(
        jsonEncode({
          'type': 'registered',
          'payload': {'client-key': 'new'},
        }),
      );
      await pumpEventQueue();
      expect(service.isConnected, isTrue);
      expect(keys, ['new']);
      expect(sockets.last.closed, isFalse);
      service.disconnect();
      await sockets.last.events.close();
    });

    test('Samsung ignora encerramento do socket anterior', () async {
      final sockets = [TestSocket(), TestSocket()];
      var index = 0;
      final driver = SamsungTizenDriver(
        socketConnector: (_, _) async => sockets[index++],
      );
      addTearDown(driver.disconnect);
      await driver.connect(ipAddress: '192.168.1.10');
      await driver.connect(ipAddress: '192.168.1.11');
      await sockets.first.events.close();
      sockets.last.events.add(
        jsonEncode({
          'event': 'ms.channel.connect',
          'data': {'token': 'new'},
        }),
      );
      await pumpEventQueue();
      expect(driver.isConnected, isTrue);
      expect(sockets.last.closed, isFalse);
      driver.disconnect();
      await sockets.last.events.close();
    });

    test('Samsung preserva token quando falha é de rede', () async {
      final driver = SamsungTizenDriver(
        socketConnector: (_, _) async => throw const SocketException('offline'),
      );
      addTearDown(driver.disconnect);
      final keys = <String>[];
      driver.onAuthTokenReceived = keys.add;
      expect(
        await driver.connect(ipAddress: '192.168.1.10', authToken: 'saved'),
        isFalse,
      );
      expect(keys, isEmpty);
      expect(driver.connectionState, DeviceConnectionState.disconnected);
    });

    test('Timeout fecha também socket que abriu tardiamente', () async {
      final operation = NetworkOperation();
      final pending = Completer<WebSocket>();
      final opened = operation.openWebSocket(
        'ws://127.0.0.1',
        const Duration(milliseconds: 10),
        connector: (_, _) => pending.future,
      );
      await expectLater(opened, throwsA(isA<TimeoutException>()));
      final socket = TestSocket();
      pending.complete(socket);
      await pumpEventQueue();
      expect(socket.closed, isTrue);
      operation.cancel();
      if (!socket.events.hasListener) socket.events.stream.listen((_) {});
      await socket.events.close();
    });
  });

  group('Mídia protegida e encerramento', () {
    late Directory dir;
    late File file;
    late LocalMediaServer server;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sixf_lifecycle_');
      file = await File('${dir.path}/video.mp4').writeAsString('0123456789');
      server = LocalMediaServer();
    });
    tearDown(() async {
      await server.stop();
      await dir.delete(recursive: true);
    });

    test(
      'Só rota atual e GET/HEAD/OPTIONS; Range continua funcionando',
      () async {
        await HttpOverrides.runWithHttpOverrides(() async {
          final port = await server.start();
          server.serveFile(file);
          final path = server.mediaPath!;
          final client = HttpClient();
          addTearDown(() => client.close(force: true));
          Future<(int, String)> request(
            String method,
            String route, {
            String? range,
          }) async {
            final req = await client.openUrl(
              method,
              Uri.parse('http://127.0.0.1:$port$route'),
            );
            if (range != null) req.headers.set('Range', range);
            final res = await req.close();
            return (res.statusCode, await utf8.decodeStream(res));
          }

          expect(await request('GET', '/wrong'), (404, ''));
          expect(await request('GET', '/media'), (404, ''));
          expect(await request('POST', path), (405, ''));
          expect(await request('OPTIONS', path), (200, ''));
          expect(await request('HEAD', path), (200, ''));
          expect(await request('GET', path, range: 'bytes=2-4'), (206, '234'));
          server.serveFile(file);
          expect(server.mediaPath, isNot(path));
          expect(await request('GET', path), (404, ''));
          expect(await request('GET', server.mediaPath!), (200, '0123456789'));
          await server.stop();
          expect(server.mediaPath, isNull);
        }, RealHttp());
      },
    );

    test(
      'Parar durante bind cancela inicialização e fecha porta tardia',
      () async {
        final starting = server.start();
        final failure = expectLater(
          starting,
          throwsA(isA<OperationCancelled>()),
        );
        await server.stop();
        await failure;
        await pumpEventQueue();
        expect(server.isRunning, isFalse);
      },
    );

    test('Falha de preparação fecha servidor e revoga URL', () async {
      server.failUrl = true;
      final controller = MediaCastController(serverService: server);
      addTearDown(controller.dispose);
      expect(
        await controller.castFile(
          file,
          targetTvIp: '127.0.0.1',
          brand: TvBrand.lgWebOs,
        ),
        isFalse,
      );
      expect(controller.status, MediaCastStatus.error);
      expect(server.isRunning, isFalse);
      expect(server.mediaPath, isNull);
    });

    for (final dispose in [false, true]) {
      test(
        '${dispose ? 'Descarte' : 'Stop'} cancela abertura nativa pendente',
        () async {
          final driver = MediaDriver()..pending = Completer<bool>();
          final controller = MediaCastController(serverService: server);
          final casting = controller.castFile(
            file,
            targetTvIp: '127.0.0.1',
            brand: TvBrand.lgWebOs,
            activeDriver: driver,
          );
          await driver.opened.future;
          if (dispose) {
            controller.dispose();
          } else {
            await controller.stop();
          }
          expect(await casting.timeout(const Duration(seconds: 1)), isFalse);
          driver.pending!.complete(true);
          await pumpEventQueue();
          expect(server.isRunning, isFalse);
          expect(driver.sentKeys, isNot(contains(RemoteKey.play)));
          if (!dispose) {
            expect(controller.status, MediaCastStatus.idle);
            controller.dispose();
          }
        },
      );
    }

    test('Stop cancela Play atrasado de uma transmissão concluída', () async {
      final driver = MediaDriver();
      final controller = MediaCastController(serverService: server);
      addTearDown(controller.dispose);
      expect(
        await controller.castFile(
          file,
          targetTvIp: '127.0.0.1',
          brand: TvBrand.lgWebOs,
          activeDriver: driver,
        ),
        isTrue,
      );
      await controller.stop();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(driver.sentKeys, isNot(contains(RemoteKey.play)));
      expect(server.mediaPath, isNull);
    });

    test('Resposta de transmissão substituída não altera a atual', () async {
      final first = MediaDriver()..pending = Completer<bool>();
      final second = MediaDriver();
      final controller = MediaCastController(serverService: server);
      addTearDown(controller.dispose);
      final oldCast = controller.castFile(
        file,
        targetTvIp: '127.0.0.1',
        brand: TvBrand.lgWebOs,
        activeDriver: first,
      );
      await first.opened.future;
      expect(
        await controller.castFile(
          file,
          fileName: 'nova.mp4',
          targetTvIp: '127.0.0.1',
          brand: TvBrand.lgWebOs,
          activeDriver: second,
        ),
        isTrue,
      );
      final path = server.mediaPath;
      first.pending!.complete(true);
      expect(await oldCast, isFalse);
      await pumpEventQueue();
      expect(controller.currentFileName, 'nova.mp4');
      expect(server.mediaPath, path);
      expect(server.isRunning, isTrue);
    });
  });
}
