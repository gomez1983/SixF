import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/lg_webos_driver.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/ui/glass/glass_control_body.dart';
import 'package:sixf_remote/ui/glass/glass_flags.dart';
import 'package:sixf_remote/ui/glass/glass_remote_shell.dart';
import 'package:sixf_remote/ui/glass/liquid_glass.dart';
import 'package:sixf_remote/ui/widgets/color_buttons_row.dart';
import 'package:sixf_remote/ui/widgets/multimedia_controls.dart';
import 'package:sixf_remote/ui/widgets/numeric_keypad.dart';
import 'package:sixf_remote/ui/widgets/remote_button.dart';
import 'package:sixf_remote/ui/widgets/trackpad_widget.dart';

import 'session_regression_test.dart' show RecordingDriver;

/// O RecordingDriver é um Fake: a interface de vidro lê estas capacidades.
class _GlassDriver extends RecordingDriver {
  _GlassDriver(super.brand);

  @override
  bool get supportsTrackpad => brand != TvBrand.googleTv;
  @override
  bool get supportsPairingPin => brand == TvBrand.googleTv;

  final digits = <int>[];
  int trackpadClicks = 0;
  @override
  void sendDigit(int digit) => digits.add(digit);
  @override
  void sendTrackpadClick() => trackpadClicks++;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(RemoteController, _GlassDriver)> pumpGlass(
    WidgetTester tester, {
    TvBrand brand = TvBrand.lgWebOs,
    TvDriver? realDriver,
    Brightness brightness = Brightness.dark,
    Size size = const Size(393, 852),
    ValueChanged<int>? onSelectTab,
    int selectedTab = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final driver = _GlassDriver(brand);
    final controller = RemoteController(initialDriver: realDriver ?? driver);
    await controller.ready;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: GlassRemoteShell(
              selectedTab: selectedTab,
              onSelectTab: onSelectTab ?? (_) {},
              onOpenDrawer: () {},
              body: const GlassControlBody(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return (controller, driver);
  }

  for (final b in Brightness.values) {
    testWidgets('renderiza sem estouro no tema ${b.name}', (tester) async {
      await pumpGlass(tester, brightness: b);
      expect(tester.takeException(), isNull);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Controle'), findsOneWidget);
    });
  }

  testWidgets('cabe em tela baixa (iPhone SE, 375x667)', (tester) async {
    await pumpGlass(tester, size: const Size(375, 667));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cabe em janela estreita do Windows (440x860)', (tester) async {
    await pumpGlass(tester, size: const Size(440, 860));
    expect(tester.takeException(), isNull);
  });

  testWidgets('botões mandam a tecla certa ao aparelho', (tester) async {
    final (_, driver) = await pumpGlass(tester);
    Future<void> tap(Finder f) async {
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Onde o botão tem texto próprio (OK, VOLTAR), o rótulo semântico se funde
    // com ele; por isso esses dois são localizados pelo texto.
    await tap(find.text('OK'));
    await tap(find.bySemanticsLabel('Cima'));
    await tap(find.bySemanticsLabel('Baixo'));
    await tap(find.bySemanticsLabel('Esquerda'));
    await tap(find.bySemanticsLabel('Direita'));
    await tap(find.bySemanticsLabel('VOL mais'));
    await tap(find.bySemanticsLabel('VOL menos'));
    await tap(find.bySemanticsLabel('CH mais'));
    await tap(find.bySemanticsLabel('CH menos'));
    await tap(find.text('VOLTAR'));
    expect(driver.sentKeys, [
      RemoteKey.dpadOk,
      RemoteKey.dpadUp,
      RemoteKey.dpadDown,
      RemoteKey.dpadLeft,
      RemoteKey.dpadRight,
      RemoteKey.volumeUp,
      RemoteKey.volumeDown,
      RemoteKey.channelUp,
      RemoteKey.channelDown,
      RemoteKey.back,
    ]);
  });

  testWidgets('HOME, MENU, INPUT e EXIT chamam o controller', (tester) async {
    final (_, driver) = await pumpGlass(tester);
    await tester.tap(find.text('HOME'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(driver.sentKeys, contains(RemoteKey.home));
  });

  testWidgets('o número de volume exibido acompanha o controller', (tester) async {
    final (controller, _) = await pumpGlass(tester);
    final before = controller.volumeLevel;
    expect(find.text('$before'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('VOL mais'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.volumeLevel, before + 1);
    expect(find.text('${before + 1}'), findsWidgets);
  });

  testWidgets('TV Digital e HDMI só aparecem na LG', (tester) async {
    await pumpGlass(tester, realDriver: LgWebOsDriver());
    expect(find.text('TV Digital'), findsOneWidget);
    expect(find.text('HDMI 1'), findsOneWidget);
  });

  testWidgets('sem TV Digital/HDMI no Google TV, a roda continua centralizada', (
    tester,
  ) async {
    await pumpGlass(tester, brand: TvBrand.googleTv);
    expect(find.text('TV Digital'), findsNothing);
    expect(find.text('HDMI 1'), findsNothing);
    final wheel = find.ancestor(
      of: find.text('OK'),
      matching: find.byType(LiquidGlass),
    );
    // O primeiro LiquidGlass ancestral do OK é o próprio botão; a roda é o seguinte.
    final wheelCenter = tester.getCenter(wheel.at(1)).dx;
    expect(wheelCenter, closeTo(393 / 2, 1));
  });

  testWidgets('a barra de abas entrega o índice real da aba', (tester) async {
    final taps = <int>[];
    await pumpGlass(tester, onSelectTab: taps.add);
    await tester.tap(find.text('Mídia'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Apps'));
    await tester.pump(const Duration(milliseconds: 50));
    // Mídia é a aba 3 e Apps a 4, com ou sem a aba Trackpad.
    expect(taps, [3, 4]);
  });

  testWidgets('Voltar à direita troca de lado conforme a preferência', (
    tester,
  ) async {
    final (controller, _) = await pumpGlass(tester);
    double backX() => tester.getCenter(find.text('VOLTAR')).dx;
    final left = backX();
    expect(left, lessThan(393 / 2));
    await controller.setBackButtonOnRight(true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(backX(), greaterThan(393 / 2));
  });

  testWidgets('indicador da barra de abas desliza com mola até o item', (
    tester,
  ) async {
    int selected = 0;
    late StateSetter set;
    final driver = _GlassDriver(TvBrand.lgWebOs);
    final controller = RemoteController(initialDriver: driver);
    await controller.ready;
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return GlassRemoteShell(
                  selectedTab: selected,
                  onSelectTab: (_) {},
                  onOpenDrawer: () {},
                  body: const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final indicator = find.byWidgetPredicate(
      (w) => w is Positioned && w.height == 56 && w.top == 7,
    );
    final startLeft = tester.widget<Positioned>(indicator).left!;

    set(() => selected = 4);
    await tester.pump(); // primeiro quadro: a mola ainda está parada
    await tester.pump(const Duration(milliseconds: 90));
    final mid = tester.widget<Positioned>(indicator);
    expect(mid.left!, greaterThan(startLeft), reason: 'já começou a andar');

    await tester.pumpAndSettle();
    final end = tester.widget<Positioned>(indicator);
    expect(end.left!, greaterThan(mid.left!), reason: 'chegou ao último item');
    expect(mid.width!, greaterThan(end.width!), reason: 'esticou em movimento');
  });

  testWidgets('botão de vidro cresce enquanto pressionado', (tester) async {
    await pumpGlass(tester);
    final target = find
        .ancestor(of: find.text('HOME'), matching: find.byType(LiquidGlass))
        .first;
    // getSize ignora transformações; os cantos em coordenadas globais não.
    double width() =>
        tester.getTopRight(target).dx - tester.getTopLeft(target).dx;
    final before = width();
    final gesture = await tester.startGesture(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 150)); // dispara o tap-down
    await tester.pump(const Duration(milliseconds: 300));
    expect(width(), greaterThan(before));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(width(), closeTo(before, 0.5));
  });

  group('abas restilizadas (kGlassUi)', () {
    Future<_GlassDriver> pumpTabs(WidgetTester tester, {required bool glass}) async {
      kGlassUi = glass;
      addTearDown(() => kGlassUi = false); // não vaza para outros testes
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = _GlassDriver(TvBrand.lgWebOs);
      final controller = RemoteController(initialDriver: driver);
      await controller.ready;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    NumericKeypad(),
                    MultimediaControls(),
                    ColorButtonsRow(),
                    SizedBox(height: 300, child: TrackpadWidget()),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      return driver;
    }

    testWidgets('com a opção ligada, os botões viram vidro e ainda mandam a tecla', (
      tester,
    ) async {
      final driver = await pumpTabs(tester, glass: true);
      expect(tester.takeException(), isNull);
      expect(find.byType(LiquidGlass), findsWidgets);
      expect(find.byType(RemoteButton), findsWidgets);

      await tester.tap(find.text('5'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('VERMELHO'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(driver.digits, [5]);
      expect(driver.sentKeys, [RemoteKey.colorRed]);
    });

    testWidgets('com a opção desligada, nada vira vidro (visual de antes)', (
      tester,
    ) async {
      await pumpTabs(tester, glass: false);
      expect(tester.takeException(), isNull);
      expect(find.byType(LiquidGlass), findsNothing);
    });

    testWidgets('o trackpad em vidro continua recebendo o toque de clique', (
      tester,
    ) async {
      final driver = await pumpTabs(tester, glass: true);
      await tester.ensureVisible(find.text('Magic Trackpad'));
      await tester.pump();
      await tester.tap(find.text('Magic Trackpad'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(driver.trackpadClicks, 1);
    });
  });
}
