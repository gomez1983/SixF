import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/models/dlna_renderer.dart';
import 'package:sixf_remote/services/dlna_service.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/media_server_service.dart';

void main() {
  group('MediaServerService (Streaming HTTP com Suporte a Range)', () {
    late MediaServerService serverService;
    late Directory tempDir;
    late File testFile;
    const testContent = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

    setUp(() async {
      serverService = MediaServerService();
      tempDir = await Directory.systemTemp.createTemp('sixf_media_test_');
      testFile = File('${tempDir.path}/sample_video.mp4');
      await testFile.writeAsString(testContent);
    });

    tearDown(() async {
      await serverService.stop();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Inicia e interrompe o servidor HTTP local dinamicamente', () async {
      expect(serverService.isRunning, isFalse);
      expect(serverService.port, isNull);

      final port = await serverService.start();
      expect(port, isPositive);
      expect(serverService.isRunning, isTrue);
      expect(serverService.port, equals(port));

      await serverService.stop();
      expect(serverService.isRunning, isFalse);
    });

    test('Serve arquivo com status 200 OK e cabeçalhos adequados', () async {
      final port = await serverService.start();
      serverService.serveFile(testFile, customName: 'video_teste.mp4');

      expect(serverService.currentFileName, equals('video_teste.mp4'));
      expect(serverService.currentMimeType, equals('video/mp4'));

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/media'));
      final res = await req.close();

      expect(res.statusCode, equals(HttpStatus.ok));
      expect(res.headers.value(HttpHeaders.contentTypeHeader), equals('video/mp4'));
      expect(res.headers.value(HttpHeaders.acceptRangesHeader), equals('bytes'));
      expect(res.headers.value('Access-Control-Allow-Origin'), equals('*'));

      final body = await utf8.decodeStream(res);
      expect(body, equals(testContent));
      client.close();
    });

    test('Responde a requisição HEAD com Content-Length correto', () async {
      final port = await serverService.start();
      serverService.serveFile(testFile);

      final client = HttpClient();
      final req = await client.headUrl(Uri.parse('http://127.0.0.1:$port/media'));
      final res = await req.close();

      expect(res.statusCode, equals(HttpStatus.ok));
      expect(res.headers.contentLength, equals(testContent.length));
      client.close();
    });

    test('Responde a requisição OPTIONS para CORS preflight', () async {
      final port = await serverService.start();
      serverService.serveFile(testFile);

      final client = HttpClient();
      final req = await client.openUrl('OPTIONS', Uri.parse('http://127.0.0.1:$port/media'));
      final res = await req.close();

      expect(res.statusCode, equals(HttpStatus.ok));
      expect(res.headers.value('Access-Control-Allow-Methods'), contains('GET'));
      client.close();
    });

    test('Responde com 206 Partial Content para requisição HTTP Range válida', () async {
      final port = await serverService.start();
      serverService.serveFile(testFile);

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/media'));
      // Solicita os primeiros 10 bytes: '0123456789'
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-9');
      final res = await req.close();

      expect(res.statusCode, equals(HttpStatus.partialContent));
      expect(res.headers.value(HttpHeaders.contentRangeHeader), equals('bytes 0-9/${testContent.length}'));
      expect(res.headers.contentLength, equals(10));

      final body = await utf8.decodeStream(res);
      expect(body, equals('0123456789'));
      client.close();
    });

    test('Responde com 206 Partial Content para range aberto (ex: bytes=10-)', () async {
      final port = await serverService.start();
      serverService.serveFile(testFile);

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/media'));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=10-');
      final res = await req.close();

      expect(res.statusCode, equals(HttpStatus.partialContent));
      final expectedLength = testContent.length - 10;
      expect(res.headers.contentLength, equals(expectedLength));

      final body = await utf8.decodeStream(res);
      expect(body, equals(testContent.substring(10)));
      client.close();
    });

    test('Retorna 416 Range Not Satisfiable quando range está fora dos limites', () async {
      final port = await serverService.start();
      serverService.serveFile(testFile);

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/media'));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=9999-10000');
      final res = await req.close();

      expect(res.statusCode, equals(HttpStatus.requestedRangeNotSatisfiable));
      client.close();
    });

    test('Retorna 404 quando nenhum arquivo estiver associado', () async {
      final port = await serverService.start();

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/media'));
      final res = await req.close();

      expect(res.statusCode, equals(HttpStatus.notFound));
      client.close();
    });
  });

  group('DlnaService & Protocolo UPnP AVTransport', () {
    test('Bloqueia controlUrl com endereço de internet pública contra SSRF', () async {
      final result = await DlnaService.setAVTransportURI(
        'http://8.8.8.8:8080/avt',
        'http://192.168.1.100:8000/media',
        title: 'Teste',
      );
      expect(result.success, isFalse);
      expect(result.networkError, contains('não é permitido'));

      final playResult = await DlnaService.play('http://google.com/control');
      expect(playResult.success, isFalse);

      final stopResult = await DlnaService.stop('http://malicious.com:8080/stop');
      expect(stopResult.success, isFalse);

      final infoResult = await DlnaService.getTransportInfo('http://1.1.1.1:8080/info');
      expect(infoResult, isNull);
    });

    test('Monta protocolo DLNA correto para fotos JPEG, PNG e vídeos', () {
      final jpegProto = DlnaService.buildProtocolInfo('image/jpeg');
      expect(jpegProto, contains('DLNA.ORG_PN=JPEG_LRG'));

      final pngProto = DlnaService.buildProtocolInfo('image/png');
      expect(pngProto, contains('DLNA.ORG_PN=PNG_LRG'));

      final mp4Proto = DlnaService.buildProtocolInfo('video/mp4');
      expect(mp4Proto, contains('DLNA.ORG_PN=AVC_MP4'));
    });

    test('DlnaResult decodifica SOAP Fault com códigos UPnP com mensagens amigáveis', () {
      const soapFault714 = '''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <s:Fault>
      <faultcode>s:Client</faultcode>
      <faultstring>UPnPError</faultstring>
      <detail>
        <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
          <errorCode>714</errorCode>
          <errorDescription>Illegal MIME-Type</errorDescription>
        </UPnPError>
      </detail>
    </s:Fault>
  </s:Body>
</s:Envelope>
''';
      final result714 = DlnaResult.fromResponse(statusCode: 500, responseBody: soapFault714);
      expect(result714.success, isFalse);
      expect(result714.upnpErrorCode, equals(714));
      expect(result714.upnpErrorDescription, equals('Illegal MIME-Type'));
      expect(result714.userFriendlyMessage, contains('Erro UPnP 714'));

      const soapFault716 = '''
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <s:Fault>
      <detail>
        <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
          <errorCode>716</errorCode>
          <errorDescription>Resource not found</errorDescription>
        </UPnPError>
      </detail>
    </s:Fault>
  </s:Body>
</s:Envelope>
''';
      final result716 = DlnaResult.fromResponse(statusCode: 500, responseBody: soapFault716);
      expect(result716.upnpErrorCode, equals(716));
      expect(result716.userFriendlyMessage, contains('Firewall do Windows'));
    });

    test('Executa comandos SOAP com sucesso contra um servidor Mock UPnP local', () async {
      final mockUpnpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? lastSoapAction;
      String? lastRequestBody;

      mockUpnpServer.listen((HttpRequest request) async {
        lastSoapAction = request.headers.value('SOAPACTION');
        lastRequestBody = await utf8.decodeStream(request);

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
        request.response.write('''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <CurrentTransportState>PLAYING</CurrentTransportState>
      <CurrentTransportStatus>OK</CurrentTransportStatus>
      <CurrentSpeed>1</CurrentSpeed>
    </u:GetTransportInfoResponse>
  </s:Body>
</s:Envelope>
''');
        await request.response.close();
      });

      final controlUrl = 'http://127.0.0.1:${mockUpnpServer.port}/upnp/control/AVTransport';

      // 1. Testa SetAVTransportURI com imagem JPEG
      final setUriResult = await DlnaService.setAVTransportURI(
        controlUrl,
        'http://127.0.0.1:9090/media/foto.jpg',
        title: 'Foto Teste',
        mimeType: 'image/jpeg',
      );
      expect(setUriResult.success, isTrue);
      expect(lastSoapAction, equals('"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"'));
      expect(lastRequestBody, contains('<CurrentURI>http://127.0.0.1:9090/media/foto.jpg</CurrentURI>'));
      expect(lastRequestBody, contains('JPEG_LRG'));

      // 2. Testa Play
      final playResult = await DlnaService.play(controlUrl);
      expect(playResult.success, isTrue);
      expect(lastSoapAction, equals('"urn:schemas-upnp-org:service:AVTransport:1#Play"'));

      // 3. Testa Pause
      final pauseResult = await DlnaService.pause(controlUrl);
      expect(pauseResult.success, isTrue);
      expect(lastSoapAction, equals('"urn:schemas-upnp-org:service:AVTransport:1#Pause"'));

      // 4. Testa Stop
      final stopResult = await DlnaService.stop(controlUrl);
      expect(stopResult.success, isTrue);
      expect(lastSoapAction, equals('"urn:schemas-upnp-org:service:AVTransport:1#Stop"'));

      // 5. Testa GetTransportInfo
      final transportState = await DlnaService.getTransportInfo(controlUrl);
      expect(transportState, equals('PLAYING'));

      await mockUpnpServer.close(force: true);
    });
  });

  group('DlnaRenderer Model', () {
    test('Cria modelo com atributos corretos', () {
      final renderer = DlnaRenderer(
        ip: '192.168.1.50',
        name: 'LG OLED Sala',
        controlUrl: 'http://192.168.1.50:19531/avt',
        locationUrl: 'http://192.168.1.50:19531/desc.xml',
        brand: TvBrand.lgWebOs,
      );

      expect(renderer.ip, equals('192.168.1.50'));
      expect(renderer.name, equals('LG OLED Sala'));
      expect(renderer.controlUrl, equals('http://192.168.1.50:19531/avt'));
      expect(renderer.locationUrl, equals('http://192.168.1.50:19531/desc.xml'));
      expect(renderer.brand, equals(TvBrand.lgWebOs));
      expect(renderer.toString(), contains('LG OLED Sala'));
    });
  });

  group('MediaCastController State Management', () {
    test('Inicia no estado idle sem mídias carregadas', () {
      final controller = MediaCastController();
      expect(controller.status, equals(MediaCastStatus.idle));
      expect(controller.isStreaming, isFalse);
      expect(controller.isPlaying, isFalse);
      expect(controller.isPaused, isFalse);
      expect(controller.currentFileName, isNull);
      expect(controller.currentFilePath, isNull);
      expect(controller.errorMessage, isNull);
      controller.dispose();
    });

    test('Stop limpa dados e reseta status para idle', () async {
      final controller = MediaCastController();
      await controller.stop();
      expect(controller.status, equals(MediaCastStatus.idle));
      expect(controller.isStreaming, isFalse);
      expect(controller.currentFileName, isNull);
      controller.dispose();
    });

    test('Transmissão e controles de reprodução (pause, play, stop) via driver nativo conectado', () async {
      final fakeDriver = FakeTvDriver();
      final controller = MediaCastController();

      final tempDir = await Directory.systemTemp.createTemp('sixf_controller_test_');
      final sampleFile = File('${tempDir.path}/foto_teste.jpg');
      await sampleFile.writeAsString('fake_image_bytes');

      try {
        final success = await controller.castFile(
          sampleFile,
          fileName: 'foto_teste.jpg',
          targetTvIp: '127.0.0.1',
          brand: TvBrand.lgWebOs,
          activeDriver: fakeDriver,
        );

        expect(success, isTrue);
        expect(controller.isPlaying, isTrue);
        expect(fakeDriver.openMediaUrlCalled, isTrue);
        expect(fakeDriver.lastOpenedUrl, contains('http://'));

        await controller.pause();
        expect(fakeDriver.sentKeys, contains(RemoteKey.pause));
        expect(controller.isPaused, isTrue);

        await controller.play();
        expect(fakeDriver.sentKeys, contains(RemoteKey.play));
        expect(controller.isPlaying, isTrue);

        await controller.stop();
        expect(fakeDriver.sentKeys, contains(RemoteKey.stop));
        expect(fakeDriver.sentKeys, contains(RemoteKey.back));
        expect(controller.status, equals(MediaCastStatus.idle));
      } finally {
        controller.dispose();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('DlnaPositionInfo faz o parse correto de durações e posições UPnP', () {
      final pos = DlnaPositionInfo.parse(
        trackDuration: '01:23:45.500',
        relTime: '00:05:30',
      );
      expect(pos.duration.inHours, equals(1));
      expect(pos.duration.inMinutes, equals(83));
      expect(pos.duration.inSeconds, equals(5025));
      expect(pos.position.inMinutes, equals(5));
      expect(pos.position.inSeconds, equals(330));
    });

    test('Alterna estado de loop repeat do vídeo no controller', () {
      final controller = MediaCastController();
      expect(controller.isLooping, isFalse);
      controller.toggleLoop();
      expect(controller.isLooping, isTrue);
      controller.toggleLoop();
      expect(controller.isLooping, isFalse);
      controller.dispose();
    });
  });
}

class FakeTvDriver extends TvDriver {
  final List<RemoteKey> sentKeys = [];
  bool openMediaUrlCalled = false;
  String? lastOpenedUrl;

  void clearKeys() => sentKeys.clear();

  @override
  TvBrand get brand => TvBrand.lgWebOs;

  @override
  DeviceConnectionState get connectionState => DeviceConnectionState.connected;

  @override
  bool get isConnected => true;

  @override
  bool get supportsTrackpad => true;

  @override
  bool get supportsPairingPin => false;

  @override
  Future<void> sendPairingPin(String pin) async {}

  @override
  Future<bool> connect({required String ipAddress, String? authToken, Duration timeout = const Duration(seconds: 4)}) async => true;

  @override
  void disconnect() {}

  @override
  void sendKey(RemoteKey key) {
    sentKeys.add(key);
  }

  @override
  void sendDigit(int digit) {}

  @override
  void setMute(bool mute) {}

  @override
  void setVolume(int volume) {}

  @override
  void sendTrackpadDelta(double dx, double dy) {}

  @override
  void sendTrackpadClick() {}

  @override
  void sendText(String text) {}

  @override
  void openApp(String appId) {}

  @override
  Future<List<TvAppInfo>> getInstalledApps() async => [];

  @override
  Future<bool> openMediaUrl(String mediaUrl, {required String title, String? mimeType}) async {
    openMediaUrlCalled = true;
    lastOpenedUrl = mediaUrl;
    return true;
  }
}

