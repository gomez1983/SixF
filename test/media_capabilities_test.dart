import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/main.dart';
import 'package:sixf_remote/ui/widgets/media_cast_dialog.dart';
import 'package:sixf_remote/ui/widgets/trackpad_widget.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/models/dlna_renderer.dart';
import 'package:sixf_remote/services/dlna_service.dart';
import 'package:sixf_remote/services/dlna_transport.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/webos_service.dart';
import 'package:sixf_remote/ui/widgets/media_progress_slider.dart';

import 'dlna_media_cast_test.dart' show FakeTvDriver;
import 'security_lifecycle_test.dart'
    show TestSocket, LocalMediaServer, RealHttp;

class SimulatedTransport extends DlnaTransport {
  final calls = <String>[];
  bool rendererAvailable = true;
  String? transportState = 'PLAYING';
  Set<String>? available = {'Play', 'Pause', 'Seek', 'Stop'};
  DlnaPositionInfo? progress = const DlnaPositionInfo(
    position: Duration(seconds: 15),
    duration: Duration(minutes: 2),
  );
  DlnaResult playResult = DlnaResult.ok();
  DlnaResult seekResult = DlnaResult.ok();
  DlnaResult uriResult = DlnaResult.ok();
  Completer<String?>? pendingState;
  @override
  Future<DlnaRenderer?> resolveRenderer(
    String ip, {
    String? locationUrl,
    required TvBrand brand,
    String? tvName,
  }) async => !rendererAvailable
      ? null
      : DlnaRenderer(
          ip: ip,
          name: 'TV',
          controlUrl: 'http://127.0.0.1/avt',
          brand: brand,
        );
  @override
  Future<DlnaResult> setUri(
    String url,
    String mediaUrl, {
    required String title,
    required String mimeType,
    int? fileSize,
  }) async {
    calls.add('uri:$url');
    return uriResult;
  }

  @override
  Future<DlnaResult> play(String url) async {
    calls.add('play:$url');
    return playResult;
  }

  @override
  Future<DlnaResult> pause(String url) async {
    calls.add('pause:$url');
    return DlnaResult.ok();
  }

  @override
  Future<DlnaResult> stop(String url) async {
    calls.add('stop:$url');
    return DlnaResult.ok();
  }

  @override
  Future<DlnaResult> seek(String url, String target) async {
    calls.add('seek:$target');
    return seekResult;
  }

  @override
  Future<String?> state(String url) async {
    calls.add('state:$url');
    return pendingState?.future ?? transportState;
  }

  @override
  Future<Set<String>?> actions(String url) async => available;
  @override
  Future<DlnaPositionInfo?> position(String url) async => progress;
}

class RetryNativeDriver extends FakeTvDriver {
  int attempts = 0;
  @override
  Future<bool> openMediaUrl(
    String url, {
    required String title,
    String? mimeType,
  }) async => ++attempts > 1;
}

class RespondingSocket extends TestSocket {
  Map<String, dynamic>? response;
  int mediaRequests = 0;
  @override
  void add(dynamic data) {
    super.add(data);
    final request = jsonDecode(data.toString()) as Map<String, dynamic>;
    if (request['uri'] == 'ssap://media.viewer/open' ||
        request['uri'] == 'ssap://system.launcher/open') {
      mediaRequests++;
      if (response != null) {
        events.add(jsonEncode({...response!, 'id': request['id']}));
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Confirmação SSAP', () {
    testWidgets('abertura de vídeo não sobrepõe pausa com Play atrasado', (
      tester,
    ) async {
      final socket = RespondingSocket()
        ..response = {
          'type': 'response',
          'payload': {'returnValue': true},
        };
      final service = WebOsService(socketConnector: (_, _) async => socket);
      await service.connect(ipAddress: '192.168.1.10');
      socket.events.add(jsonEncode({'type': 'registered', 'payload': {}}));
      await tester.pump();
      final pending = service.openMedia(
        mediaUrl: 'http://127.0.0.1/video.mp4',
        title: 'Vídeo',
        mimeType: 'video/mp4',
      );
      await tester.pump();
      expect(await pending, isTrue);
      service.mediaPause();
      final count = socket.sent.length;
      await tester.pump(const Duration(seconds: 1));
      expect(socket.sent, hasLength(count));
      service.disconnect();
      await socket.events.close();
    });
    for (final entry in <String, Map<String, dynamic>>{
      'erro com ID e payload enganoso': {
        'type': 'error',
        'payload': {'returnValue': true},
      },
      'somente ID': {'type': 'response'},
      'recusa explícita': {
        'type': 'response',
        'payload': {'returnValue': false, 'id': 'app'},
      },
      'erro no envelope': {
        'type': 'response',
        'error': '403',
        'payload': {'returnValue': true},
      },
      'sucesso explícito': {
        'type': 'response',
        'payload': {'returnValue': true},
      },
    }.entries) {
      test(entry.key, () async {
        final socket = RespondingSocket()..response = entry.value;
        final service = WebOsService(socketConnector: (_, _) async => socket);
        await service.connect(ipAddress: '192.168.1.10');
        socket.events.add(jsonEncode({'type': 'registered', 'payload': {}}));
        await pumpEventQueue();
        final accepted = await service.openMedia(
          mediaUrl: 'http://127.0.0.1/photo.jpg',
          title: 'Foto',
          mimeType: 'image/jpeg',
        );
        expect(accepted, entry.key == 'sucesso explícito');
        expect(socket.mediaRequests, accepted ? 1 : 2);
        service.disconnect();
        await socket.events.close();
      });
    }
    testWidgets('timeout dos dois comandos não confirma sucesso', (
      tester,
    ) async {
      final socket = RespondingSocket();
      final service = WebOsService(socketConnector: (_, _) async => socket);
      await service.connect(ipAddress: '192.168.1.10');
      socket.events.add(jsonEncode({'type': 'registered', 'payload': {}}));
      await tester.pump();
      final pending = service.openMedia(
        mediaUrl: 'http://127.0.0.1/photo.jpg',
        title: 'Foto',
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      expect(await pending, isFalse);
      service.disconnect();
      await socket.events.close();
    });
  });

  group('Canal de mídia e capacidades', () {
    late Directory directory;
    late File file;
    late SimulatedTransport transport;
    late LocalMediaServer server;
    late MediaCastController controller;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sixf_capabilities_');
      file = await File('${directory.path}/video.mp4').writeAsString('media');
      transport = SimulatedTransport();
      server = LocalMediaServer();
      controller = MediaCastController(serverService: server, dlna: transport);
    });
    tearDown(() async {
      controller.dispose();
      await server.stop();
      await directory.delete(recursive: true);
    });
    Future<bool> cast({TvDriver? driver, String? name}) => controller.castFile(
      file,
      fileName: name,
      targetTvIp: '127.0.0.1',
      brand: TvBrand.lgWebOs,
      activeDriver: driver,
    );

    test(
      'nativo: aceitação e teclas não inventam estado, seek ou loop',
      () async {
        transport.rendererAvailable = false;
        final driver = FakeTvDriver();
        expect(await cast(driver: driver), isTrue);
        expect(controller.status, MediaCastStatus.sent);
        expect(controller.transport, MediaCastTransport.native);
        expect(controller.hasProgress, isFalse);
        expect(controller.canSeek, isFalse);
        controller.toggleLoop();
        expect(controller.isLooping, isFalse);
        await controller.pause();
        expect(controller.status, MediaCastStatus.sent);
        expect(controller.playbackLabel, 'Comando de pausa enviado');
        await controller.play();
        expect(controller.status, MediaCastStatus.sent);
        expect(driver.sentKeys, [RemoteKey.pause, RemoteKey.play]);
        expect(transport.calls, isEmpty);
      },
    );

    test('DLNA recusa Play: falha e revoga arquivo', () async {
      transport.playResult = const DlnaResult(
        success: false,
        upnpErrorCode: 701,
      );
      expect(await cast(), isFalse);
      expect(controller.status, MediaCastStatus.error);
      expect(controller.isPlaying, isFalse);
      expect(server.isRunning, isFalse);
    });

    test('vídeo LG carrega URI e envia Play mesmo com visualizador nativo disponível', () async {
      final driver = FakeTvDriver();
      expect(await cast(driver: driver), isTrue);
      expect(driver.openMediaUrlCalled, isFalse);
      expect(controller.transport, MediaCastTransport.dlna);
      expect(transport.calls.take(3), [
        'uri:http://127.0.0.1/avt',
        'play:http://127.0.0.1/avt',
        'state:http://127.0.0.1/avt',
      ]);
      expect(controller.status, MediaCastStatus.playing);
    });

    test('foto LG preserva visualizador nativo sem enviar Play DLNA', () async {
      final driver = FakeTvDriver();
      expect(await cast(driver: driver, name: 'foto.jpg'), isTrue);
      expect(driver.openMediaUrlCalled, isTrue);
      expect(controller.transport, MediaCastTransport.native);
      expect(transport.calls, isEmpty);
    });

    test(
      'recusa de Play DLNA usa alternativa nativa sem confirmar reprodução',
      () async {
        transport.playResult = const DlnaResult(
          success: false,
          upnpErrorCode: 701,
        );
        final driver = FakeTvDriver();
        expect(await cast(driver: driver), isTrue);
        expect(driver.openMediaUrlCalled, isTrue);
        expect(controller.transport, MediaCastTransport.native);
        expect(controller.status, MediaCastStatus.sent);
        expect(controller.activeRenderer, isNull);
        await controller.stop();
        expect(driver.sentKeys, [RemoteKey.stop, RemoteKey.back]);
        expect(
          transport.calls.where((call) => call.startsWith('stop:')),
          isEmpty,
        );
      },
    );

    test(
      'aceitação sem estado ou ações não habilita controles presumidos',
      () async {
        transport.transportState = null;
        transport.available = null;
        transport.progress = null;
        expect(await cast(), isTrue);
        expect(controller.status, MediaCastStatus.sent);
        expect(controller.canPause, isFalse);
        expect(controller.canSeek, isFalse);
        expect(controller.canLoop, isFalse);
      },
    );

    test(
      'foto DLNA envia URI sem Play, polling ou comandos de vídeo',
      () async {
        expect(await cast(name: 'foto.jpg'), isTrue);
        expect(controller.isPhoto, isTrue);
        expect(controller.status, MediaCastStatus.sent);
        expect(controller.canPlay, isFalse);
        expect(transport.calls, hasLength(1));
      },
    );

    test('estado e capacidades mudam apenas conforme resposta da TV', () async {
      await cast();
      expect(controller.isPlaying, isTrue);
      expect(controller.canSeek, isTrue);
      expect(controller.canLoop, isTrue);
      controller.toggleLoop();
      transport.transportState = 'PAUSED_PLAYBACK';
      transport.available = {'Play'};
      await controller.pause();
      expect(controller.isPaused, isTrue);
      expect(controller.canPause, isFalse);
      expect(controller.canSeek, isFalse);
      expect(controller.canPlay, isTrue);
      transport.transportState = null;
      transport.available = null;
      await controller.play();
      expect(controller.status, MediaCastStatus.sent);
      expect(controller.canPlay, isFalse);
    });

    test('seek recusado preserva posição confirmada e informa erro', () async {
      await cast();
      transport.seekResult = const DlnaResult(
        success: false,
        upnpErrorCode: 710,
      );
      expect(await controller.seekTo(const Duration(seconds: 60)), isFalse);
      expect(controller.currentPosition, const Duration(seconds: 15));
      expect(controller.isSeeking, isFalse);
      expect(controller.errorMessage, contains('710'));
    });

    test(
      'fallback nativo elimina endpoint DLNA e stop usa apenas driver',
      () async {
        final driver = FakeTvDriver();
        transport.uriResult = DlnaResult.networkFailure('refused');
        expect(await cast(driver: driver), isTrue);
        expect(controller.transport, MediaCastTransport.native);
        expect(controller.activeRenderer, isNull);
        await controller.stop();
        expect(driver.sentKeys, [RemoteKey.stop, RemoteKey.back]);
        expect(
          transport.calls.where((call) => call.startsWith('stop:')),
          isEmpty,
        );
      },
    );

    test(
      'endpoint alternativo que aceitou URI recebe Play, consulta e Stop',
      () async {
        transport.uriResult = const DlnaResult(
          success: true,
          controlUrl: 'http://127.0.0.1/alternative',
        );
        await cast();
        expect(controller.activeRenderer!.controlUrl, endsWith('/alternative'));
        await controller.stop();
        expect(
          transport.calls,
          containsAll([
            'play:http://127.0.0.1/alternative',
            'state:http://127.0.0.1/alternative',
            'stop:http://127.0.0.1/alternative',
          ]),
        );
      },
    );

    test('troca e stop removem loop e capacidades anteriores', () async {
      await cast();
      controller.toggleLoop();
      expect(controller.isLooping, isTrue);
      transport.rendererAvailable = false;
      await cast(driver: FakeTvDriver());
      expect(controller.isLooping, isFalse);
      expect(controller.canSeek, isFalse);
      await controller.stop();
      expect(controller.canPlay, isFalse);
      expect(controller.transport, MediaCastTransport.none);
    });

    test(
      'Stop durante consulta invalida resposta tardia sem ressuscitar sessão',
      () async {
        transport.pendingState = Completer<String?>();
        final pending = cast();
        while (!transport.calls.any((call) => call.startsWith('state:'))) {
          await pumpEventQueue();
        }
        await controller.stop();
        expect(await pending, isFalse);
        transport.pendingState!.complete('PLAYING');
        await pumpEventQueue();
        expect(controller.status, MediaCastStatus.idle);
        expect(controller.canSeek, isFalse);
        expect(server.isRunning, isFalse);
      },
    );

    test('DLNA usa só seu canal mesmo com driver nativo conectado', () async {
      final driver = RetryNativeDriver();
      await cast(driver: driver);
      await controller.pause();
      await controller.stop();
      expect(driver.sentKeys, isEmpty);
      expect(transport.calls, contains('pause:http://127.0.0.1/avt'));
      expect(transport.calls, contains('stop:http://127.0.0.1/avt'));
    });

    test('loop aguarda fim confirmado e reinicia uma única vez', () async {
      await cast();
      controller.toggleLoop();
      transport.progress = const DlnaPositionInfo(
        position: Duration(seconds: 119),
        duration: Duration(seconds: 120),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
        transport.calls.where((call) => call.startsWith('seek:')),
        isEmpty,
      );
      transport.transportState = 'STOPPED';
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
        transport.calls.where((call) => call.startsWith('seek:')),
        hasLength(1),
      );
      await controller.stop();
    });

    testWidgets(
      'dialog mostra envio nativo sem progresso ou repetição e mantém Stop',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final remote = RemoteController();
        transport.rendererAvailable = false;
        await tester.runAsync(() async {
          await remote.ready;
          await cast(driver: FakeTvDriver());
        });
        tester.view.physicalSize = const Size(400, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: remote),
              ChangeNotifierProvider.value(value: controller),
            ],
            child: const MaterialApp(home: Scaffold(body: MediaCastDialog())),
          ),
        );
        expect(find.text('Mídia enviada à TV'), findsOneWidget);
        expect(find.text('Nativo'), findsOneWidget);
        expect(find.byType(Slider), findsNothing);
        expect(find.byIcon(Icons.repeat_rounded), findsNothing);
        expect(find.byTooltip('Enviar pausa'), findsOneWidget);
        expect(find.byTooltip('Parar Transmissão'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        remote.dispose();
        await tester.runAsync(() => controller.stop());
      },
    );

    testWidgets('arrastar slider envia um Seek somente ao soltar', (
      tester,
    ) async {
      await tester.runAsync(() => cast());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MediaProgressSlider(controller: controller)),
        ),
      );
      final slider = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      expect(
        transport.calls.where((call) => call.startsWith('seek:')),
        isEmpty,
      );
      await gesture.up();
      await tester.pump();
      expect(
        transport.calls.where((call) => call.startsWith('seek:')),
        hasLength(1),
      );
      await tester.runAsync(() => controller.stop());
    });
  });

  for (final width in [400.0, 1200.0]) {
    testWidgets('Samsung oculta trackpad e entradas LG na largura $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();
      final remote = tester.element(find.text('SixF')).read<RemoteController>();
      expect(find.byType(TrackpadWidget, skipOffstage: false), findsOneWidget);
      if (width < 840) {
        await tester.tap(find.text('Magic Trackpad'));
        await tester.pumpAndSettle();
      }
      remote.selectBrand(TvBrand.samsungTizen);
      await tester.pumpAndSettle();
      expect(find.byType(TrackpadWidget, skipOffstage: false), findsNothing);
      expect(find.text('HDMI 1', skipOffstage: false), findsNothing);
      expect(find.text('TV Digital', skipOffstage: false), findsNothing);
      expect(find.text('OK'), findsOneWidget);
      final lastAction = remote.lastActionMessage;
      remote.switchHdmi1();
      remote.switchTvDigital();
      remote.sendTrackpadClick();
      expect(remote.lastActionMessage, lastAction);
      expect(tester.takeException(), isNull);
      remote.selectBrand(TvBrand.lgWebOs);
      await tester.pumpAndSettle();
      expect(find.byType(TrackpadWidget, skipOffstage: false), findsOneWidget);
      expect(find.text('HDMI 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('SOAP Fault com HTTP 200 continua sendo falha', () {
    final result = DlnaResult.fromResponse(
      statusCode: 200,
      responseBody: '<s:Fault><u:errorCode>701</u:errorCode></s:Fault>',
    );
    expect(result.success, isFalse);
    expect(result.upnpErrorCode, 701);
  });

  test(
    'consulta de ações interpreta resposta SOAP real e erro opcional',
    () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var failed = false;
        server.listen((request) async {
          expect(
            request.headers.value('SOAPACTION'),
            contains('GetCurrentTransportActions'),
          );
          await request.drain<void>();
          request.response.statusCode = failed ? 500 : 200;
          request.response.write(
            failed ? '<s:Fault/>' : '<u:Actions>Play, Pause,Seek</u:Actions>',
          );
          await request.response.close();
        });
        final url = 'http://127.0.0.1:${server.port}/avt';
        expect(await DlnaService.getCurrentTransportActions(url), {
          'Play',
          'Pause',
          'Seek',
        });
        failed = true;
        expect(await DlnaService.getCurrentTransportActions(url), isNull);
        await server.close(force: true);
      }, createHttpClient: (_) => RealHttp().createHttpClient(null));
    },
  );
}
