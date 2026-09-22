import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/voice_service.dart';
import 'package:sixf_remote/ui/widgets/voice_listening_dialog.dart';

class MockTestDriver implements TvDriver {
  @override
  TvBrand get brand => TvBrand.lgWebOs;

  @override
  String get brandDisplayName => 'LG webOS';

  @override
  DeviceConnectionState connectionState = DeviceConnectionState.connected;

  @override
  bool get isConnected => true;

  @override
  bool get supportsTrackpad => true;

  @override
  bool get supportsPairingPin => false;

  final List<String> sentKeys = [];
  final List<String> sentTexts = [];
  final List<String> launchedApps = [];
  bool isMuted = false;
  int volumeCount = 0;

  @override
  void Function(DeviceConnectionState p1)? onStateChanged;

  @override
  void Function(String p1)? onError;

  @override
  void Function(String p1, String? p2)? onDeviceNameResolved;

  @override
  void Function(String p1)? onAuthTokenReceived;

  @override
  void Function(int p1, bool p2)? onVolumeStatusChanged;

  @override
  void Function(bool p1)? onPinPromptRequested;

  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    return true;
  }

  @override
  void disconnect() {}

  @override
  void sendKey(RemoteKey key) {
    sentKeys.add(key.name);
    if (key == RemoteKey.volumeUp) volumeCount++;
    if (key == RemoteKey.volumeDown) volumeCount--;
  }

  @override
  void sendText(String text) {
    sentTexts.add(text);
  }

  @override
  void openApp(String appId) {
    launchedApps.add(appId);
  }

  @override
  void setMute(bool mute) {
    isMuted = mute;
  }

  @override
  void setVolume(int volume) {}

  @override
  void triggerVoice() {
    sentKeys.add('voice');
  }

  @override
  Future<List<TvAppInfo>> getInstalledApps() async => [];

  @override
  void sendDigit(int digit) {}

  @override
  Future<void> sendPairingPin(String pin) async {}

  @override
  void sendTrackpadClick() {}

  @override
  void sendTrackpadDelta(double dx, double dy) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Voice & Text Input Widget & Controller Tests', () {
    late MockTestDriver mockDriver;
    late RemoteController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockDriver = MockTestDriver();
      controller = RemoteController(initialDriver: mockDriver);
    });

    testWidgets('VoiceListeningDialog exibe campo de texto, chips de idioma e botão Enviar para a TV', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<RemoteController>.value(
            value: controller,
            child: const Scaffold(
              body: VoiceListeningDialog(isLocked: true),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Verifica presença dos elementos essenciais
      expect(find.text('🇧🇷 PT'), findsOneWidget);
      expect(find.text('🇺🇸 EN'), findsOneWidget);
      expect(find.text('Enviar para a TV'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Digitação de texto manual no campo atualiza o badge e permite envio à TV', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<RemoteController>.value(
            value: controller,
            child: const Scaffold(
              body: VoiceListeningDialog(isLocked: true),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Digita um termo de pesquisa
      await tester.enterText(find.byType(TextField), 'receita de pudim');
      await tester.pump(const Duration(milliseconds: 50));

      // Verifica indicador de busca
      expect(find.textContaining('Inserir texto na pesquisa da TV'), findsOneWidget);

      // Clica no botão "Enviar para a TV"
      await tester.tap(find.text('Enviar para a TV'));
      await tester.pump(const Duration(milliseconds: 100));

      // Verifica que o texto foi despachado para o driver sem auto-enter
      expect(mockDriver.sentTexts, contains('receita de pudim'));
    });

    test('Comando falado de Volume (+5) executa 5 passos no controller', () async {
      final intent = VoiceService.classifyIntent('aumentar volume');
      expect(intent.type, VoiceIntentType.volumeUp);

      final executed = await controller.executeVoiceIntent(intent);
      expect(executed, isTrue);
      expect(mockDriver.volumeCount, equals(5));
      expect(mockDriver.sentKeys.where((k) => k == 'volumeUp').length, equals(5));
    });

    test('Comando falado de Volume (-5) executa 5 passos para baixo', () async {
      final intent = VoiceService.classifyIntent('diminuir volume');
      expect(intent.type, VoiceIntentType.volumeDown);

      final executed = await controller.executeVoiceIntent(intent);
      expect(executed, isTrue);
      expect(mockDriver.volumeCount, equals(-5));
      expect(mockDriver.sentKeys.where((k) => k == 'volumeDown').length, equals(5));
    });

    test('Comando falado de Mudo alterna o estado no driver', () async {
      final intent = VoiceService.classifyIntent('mudo');
      expect(intent.type, VoiceIntentType.toggleMute);

      final executed = await controller.executeVoiceIntent(intent);
      expect(executed, isTrue);
      expect(mockDriver.isMuted, isTrue);
    });

    test('Comando falado de Desligar TV desliga o dispositivo', () async {
      final intent = VoiceService.classifyIntent('desligar tv');
      expect(intent.type, VoiceIntentType.powerOff);

      final executed = await controller.executeVoiceIntent(intent);
      expect(executed, isTrue);
    });

    test('Comando falado de Abrir YouTube despacha o lançamento do app', () async {
      final intent = VoiceService.classifyIntent('abrir youtube');
      expect(intent.type, VoiceIntentType.openApp);

      final executed = await controller.executeVoiceIntent(intent);
      expect(executed, isTrue);
      expect(mockDriver.launchedApps, contains('youtube.leanback.v4'));
    });

    testWidgets('Alternância de idioma entre PT e EN nos chips funciona ao toque', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<RemoteController>.value(
            value: controller,
            child: const Scaffold(
              body: VoiceListeningDialog(isLocked: true),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Toca no chip EN
      await tester.tap(find.text('🇺🇸 EN'));
      await tester.pump(const Duration(milliseconds: 50));

      // Toca de volta no chip PT
      await tester.tap(find.text('🇧🇷 PT'));
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
