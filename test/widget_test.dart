import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/main.dart';
import 'package:sixf_remote/ui/widgets/trackpad_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RemoteController Unit Tests', () {
    late RemoteController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      controller = RemoteController();
    });

    test('Valores iniciais do controle remoto (estritamente desconectado)', () {
      expect(controller.isConnected, isFalse);
      expect(controller.isConnecting, isFalse);
      expect(controller.isPoweredOn, isFalse);
      expect(controller.isMuted, isFalse);
      expect(controller.volumeLevel, 18);
      expect(controller.currentChannel, 5);
      expect(controller.ipAddress, '192.168.1.150');
      expect(controller.macAddress, 'A4:77:33:B2:9C:10');
      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.isDarkMode, isTrue);
    });

    test('Alternância de Tema Claro e Escuro', () {
      expect(controller.themeMode, ThemeMode.dark);
      controller.toggleTheme();
      expect(controller.themeMode, ThemeMode.light);
      expect(controller.isDarkMode, isFalse);

      controller.toggleTheme();
      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.isDarkMode, isTrue);

      controller.setThemeMode(ThemeMode.light);
      expect(controller.themeMode, ThemeMode.light);
    });

    test('Volume up, volume down e mute toggle', () {
      final initialVol = controller.volumeLevel;
      controller.volumeUp();
      expect(controller.volumeLevel, initialVol + 1);

      controller.volumeDown();
      expect(controller.volumeLevel, initialVol);

      expect(controller.isMuted, isFalse);
      controller.toggleMute();
      expect(controller.isMuted, isTrue);
      controller.toggleMute();
      expect(controller.isMuted, isFalse);
    });

    test('Canal up e down', () {
      final initialCh = controller.currentChannel;
      controller.channelUp();
      expect(controller.currentChannel, initialCh + 1);

      controller.channelDown();
      expect(controller.currentChannel, initialCh);
    });

    test('Power toggle altera estado de energia', () {
      expect(controller.isPoweredOn, isFalse);
      controller.powerToggle();
      expect(controller.isPoweredOn, isTrue);
      controller.powerToggle();
      expect(controller.isPoweredOn, isFalse);
    });

    test('Conexão e desconexão atualizam estados', () async {
      controller.disconnect();
      expect(controller.isConnected, isFalse);

      await controller.connect(ip: '192.168.1.200', mac: 'BB:CC:DD:EE:FF:00', tvName: 'André TV');
      expect(controller.ipAddress, '192.168.1.200');
      expect(controller.macAddress, 'BB:CC:DD:EE:FF:00');
      expect(controller.connectedTvName, 'André TV');
      expect(controller.isConnected, isFalse); // Sem TV física respondendo no teste, permanece falso
    });

    test('Disparo de trackpad registra ação', () {
      controller.onTrackpadPan(12.5, -8.2);
      expect(controller.lastActionMessage, contains('Trackpad Move'));

      controller.onTrackpadTap();
      expect(controller.lastActionMessage, contains('Trackpad Click'));
    });
  });

  group('Widget Tests & Responsividade', () {
    testWidgets('Carrega a interface do controle remoto LG sem erros em tela padrão', (WidgetTester tester) async {
      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();

      // Verifica presença dos textos da marca e cabeçalho
      expect(find.text('SixF'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('Desconectado'), findsOneWidget);

      // Verifica presença de botões essenciais
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('MENU'), findsOneWidget);
      expect(find.text('VOLTAR'), findsOneWidget);
      expect(find.text('EXIT'), findsOneWidget);
      expect(find.text('VOL'), findsOneWidget);
      expect(find.text('CH'), findsOneWidget);
      expect(find.text('MUTE'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      // Verifica botões de entrada ao lado do D-Pad (Aba 1)
      expect(find.text('HDMI 1'), findsOneWidget);
      expect(find.text('TV Digital'), findsOneWidget);

      // Alterna para a Aba 2 (Teclas & Mídia) e verifica botões coloridos
      await tester.tap(find.text('Teclas & Mídia'));
      await tester.pumpAndSettle();

      expect(find.text('VERMELHO'), findsOneWidget);
      expect(find.text('VERDE'), findsOneWidget);
      expect(find.text('AMARELO'), findsOneWidget);
      expect(find.text('AZUL'), findsOneWidget);
    });

    testWidgets('Alterna entre Tema Escuro e Claro pelo botão do cabeçalho', (WidgetTester tester) async {
      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();

      // Encontra o botão de alternar tema no cabeçalho
      final themeBtnFinder = find.byTooltip('Mudar para Modo Claro');
      expect(themeBtnFinder, findsOneWidget);

      // Clica para mudar para modo claro
      await tester.tap(themeBtnFinder);
      await tester.pumpAndSettle();

      // Agora o botão deve oferecer retorno ao modo escuro
      expect(find.byTooltip('Mudar para Modo Escuro'), findsOneWidget);

      // Clica novamente para retornar ao modo escuro
      await tester.tap(find.byTooltip('Mudar para Modo Escuro'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Mudar para Modo Claro'), findsOneWidget);
    });

    testWidgets('Abre o modal de busca de dispositivos pelo botão Cast do cabeçalho', (WidgetTester tester) async {
      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();

      final castBtn = find.byTooltip('Desconectado - Clique para Buscar e Conectar TVs LG');
      expect(castBtn, findsOneWidget);

      await tester.tap(castBtn);
      await tester.pump(const Duration(milliseconds: 300));

      // Modal de descoberta aberto
      expect(find.text('Dispositivos na Rede'), findsOneWidget);
      expect(find.text('Aparelhos compatíveis'), findsOneWidget);
      expect(find.text('Buscar'), findsOneWidget);

      // Fecha o modal
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Dispositivos na Rede'), findsNothing);
    });

    testWidgets('Auto-ajuste à janela (sem overflow em janelas compactas)', (WidgetTester tester) async {
      // Simula uma janela com altura baixa de 580px
      tester.view.physicalSize = const Size(400, 580);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();

      // O controle deve estar presente na tela com as abas e sem erros
      expect(find.text('SixF'), findsOneWidget);
      expect(find.text('HDMI 1'), findsOneWidget);
      expect(find.text('TV Digital'), findsOneWidget);

      await tester.tap(find.text('Teclas & Mídia'));
      await tester.pumpAndSettle();
      expect(find.text('VERMELHO'), findsOneWidget);
      expect(find.text('AZUL'), findsOneWidget);
    });

    testWidgets('Suporta redimensionamento para tela ampla (Desktop Dual-Pane)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();

      expect(find.text('LG Magic Pointer (Trackpad Virtual)'), findsOneWidget);
      expect(find.text('Atalhos de Teclado Físico (Desktop)'), findsOneWidget);
      expect(find.byType(TrackpadWidget), findsOneWidget);
    });

    testWidgets('Abre e interage com o NetworkDrawer e switch de tema', (WidgetTester tester) async {
      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();

      // Clica no botão de configurações da barra superior
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      // Verifica elementos do drawer
      expect(find.text('Configurações'), findsOneWidget);
      expect(find.text('Modo Escuro (Dark)'), findsOneWidget);
      expect(find.text('Buscar TVs na Rede'), findsOneWidget);
      expect(find.text('Endereço IP da TV'), findsOneWidget);
      expect(find.text('MAC Address'), findsOneWidget);
      expect(find.text('Conectar'), findsOneWidget);
      expect(find.text('Desconectar'), findsOneWidget);
      expect(find.text('Vibração nos Botões'), findsOneWidget);

      // Alterna tema pelo switch do drawer
      await tester.tap(find.byKey(const Key('drawer_theme_switch')));
      await tester.pumpAndSettle();
      expect(find.text('Modo Claro (Light)'), findsOneWidget);

      // Fecha o drawer
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('Alterna entre modo D-Pad e Magic Trackpad no modo compacto', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(480, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();

      // Clica no seletor "Magic Trackpad"
      await tester.tap(find.text('Magic Trackpad').first);
      await tester.pumpAndSettle();

      expect(find.text('Arraste para mover o cursor • Toque para clicar'), findsOneWidget);

      // Simula gesto de arrasto no Trackpad
      await tester.drag(find.byType(TrackpadWidget), const Offset(40, -30));
      await tester.pumpAndSettle();

      // Simula toque no trackpad
      await tester.tap(find.byType(TrackpadWidget));
      await tester.pumpAndSettle();
    });

    testWidgets('Responde a atalhos do teclado físico', (WidgetTester tester) async {
      await tester.pumpWidget(const SixFRemoteApp());
      await tester.pumpAndSettle();

      // Dispara seta para cima
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(find.textContaining('D-Pad UP'), findsOneWidget);

      // Dispara número 7
      await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
      await tester.pumpAndSettle();
      expect(find.textContaining('Keypad Digit'), findsOneWidget);

      // Dispara Enter
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining('D-Pad OK'), findsOneWidget);
    });
  });
}
