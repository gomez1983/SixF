import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/desktop_window_service.dart';
import 'package:sixf_remote/services/storage_service.dart';
import 'package:sixf_remote/ui/widgets/remote_button.dart';
import 'package:sixf_remote/ui/widgets/app_drawer_widget.dart';
import 'package:sixf_remote/ui/widgets/connection_diagnostic.dart';
import 'package:sixf_remote/main.dart';
import 'package:sixf_remote/ui/views/remote_view.dart';

import 'session_regression_test.dart' show RecordingDriver;
import 'dlna_media_cast_test.dart' show FakeTvDriver;

class SimulatedWindow extends Fake implements WindowManager {
  Rect bounds = const Rect.fromLTWH(25, 40, 1000, 900);
  bool maximized = true;
  bool onTop = false;
  bool failResize = false;
  @override
  Future<Rect> getBounds() async => bounds;
  @override
  Future<bool> isMaximized() async => maximized;
  @override
  Future<bool> isAlwaysOnTop() async => onTop;
  @override
  Future<void> setAlwaysOnTop(bool value) async {
    onTop = value;
  }

  @override
  Future<void> unmaximize() async {
    maximized = false;
  }

  @override
  Future<void> maximize({bool vertically = false}) async {
    maximized = true;
  }

  @override
  Future<void> setMinimumSize(Size size) async {}
  @override
  Future<void> setSize(Size size, {bool animate = false}) async {
    if (failResize) throw StateError('resize');
    bounds = bounds.topLeft & size;
  }

  @override
  Future<void> setBounds(
    Rect? value, {
    Offset? position,
    Size? size,
    bool animate = false,
  }) async {
    if (value != null) bounds = value;
  }
}

class FailingDriver extends RecordingDriver {
  FailingDriver() : super(TvBrand.lgWebOs);
  @override
  Future<bool> connect({
    required String ipAddress,
    String? authToken,
    Duration timeout = const Duration(seconds: 4),
  }) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'teclado repete direção mas não OK; troca de TV invalida tecla mantida',
    (tester) async {
      final first = FakeTvDriver();
      final c = RemoteController(
        initialDriver: first,
        driverFactory: (_) => FakeTvDriver(),
      );
      await c.ready;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: c,
          child: const MaterialApp(home: RemoteView()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      expect(
        first.sentKeys.where((key) => key == RemoteKey.dpadUp),
        hasLength(2),
      );
      await c.saveOrUpdateDevice(
        const SavedDevice(id: 'other', name: 'Outra', ip: '192.168.1.92'),
        makeActive: true,
      );
      await tester.pump();
      final second = c.driver as FakeTvDriver;
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      expect(second.sentKeys, isEmpty);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      expect(second.sentKeys, [RemoteKey.dpadOk]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  test(
    'favoritos persistem por aparelho e não migram ao trocar ou esquecer',
    () async {
      final c = RemoteController(driverFactory: RecordingDriver.new);
      await c.ready;
      final first = c.activeDevice!;
      await c.toggleFavoriteApp('netflix');
      final storage = StorageService();
      await storage.init();
      expect(storage.getFavoriteApps(first.id, first.brand), {'netflix'});
      final second = SavedDevice(
        id: 'second',
        name: 'Quarto',
        ip: '192.168.1.90',
      );
      await c.saveOrUpdateDevice(second, makeActive: true);
      expect(c.isFavoriteApp('netflix'), isFalse);
      await Future.wait([
        c.toggleFavoriteApp('youtube'),
        c.toggleFavoriteApp('youtube'),
      ]);
      expect(c.isFavoriteApp('youtube'), isFalse);
      c.setActiveDevice(first.id);
      expect(c.isFavoriteApp('netflix'), isTrue);
      await storage.removeDevice(first.id);
      expect(storage.getFavoriteApps(first.id, first.brand), isEmpty);
      c.dispose();
    },
  );

  test(
    'falha e pareamento pertencem à sessão; nome descoberto preserva apelido',
    () async {
      final c = RemoteController(driverFactory: (_) => FailingDriver());
      await c.ready;
      final first = c.activeDevice!;
      await c.connectDevice(first.id);
      expect(c.connectionStatusLabel, 'TV indisponível');
      expect(c.connectionGuidance, contains('rede'));
      final second = SavedDevice(
        id: 'second',
        name: 'Sala',
        ip: '192.168.1.91',
      );
      await c.saveOrUpdateDevice(second, makeActive: true);
      final driver = c.driver as RecordingDriver;
      expect(c.connectionStatusLabel, 'Desconectado');
      driver.connectionState = DeviceConnectionState.pairingPrompt;
      driver.onStateChanged!(driver.connectionState);
      expect(c.connectionStatusLabel, 'Confirme na tela da TV');
      driver.onDeviceNameResolved!('Nome do fabricante', 'Modelo');
      expect(c.activeDevice!.name, 'Sala');
      expect(c.activeDevice!.modelName, 'Modelo');
      driver.connectionState = DeviceConnectionState.connected;
      driver.onStateChanged!(driver.connectionState);
      expect(c.connectionStatusLabel, 'Conectado');
      c.setActiveDevice(first.id);
      expect(c.connectionStatusLabel, 'TV indisponível');
      c.dispose();
    },
  );

  testWidgets('pressionar repete; soltar e trocar sessão interrompem', (
    tester,
  ) async {
    var count = 0;
    var token = 1;
    Widget app() => MaterialApp(
      home: Scaffold(
        body: RemoteButton(
          onPressed: () => count++,
          label: 'Repetir',
          width: 80,
          height: 80,
          repeatOnHold: true,
          repeatToken: token,
        ),
      ),
    );
    await tester.pumpWidget(app());
    await tester.tap(find.text('Repetir'));
    expect(count, 1);
    var gesture = await tester.startGesture(
      tester.getCenter(find.text('Repetir')),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(count, greaterThan(2));
    await gesture.up();
    final released = count;
    await tester.pump(const Duration(seconds: 1));
    expect(count, released);
    gesture = await tester.startGesture(tester.getCenter(find.text('Repetir')));
    await tester.pump(const Duration(milliseconds: 650));
    token = 2;
    await tester.pumpWidget(app());
    final switched = count;
    await tester.pump(const Duration(seconds: 1));
    expect(count, switched);
    await gesture.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelamento e segundo plano encerram repetição', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteButton(
            onPressed: () => count++,
            label: 'Repetir',
            width: 80,
            height: 80,
            repeatOnHold: true,
          ),
        ),
      ),
    );
    var gesture = await tester.startGesture(
      tester.getCenter(find.text('Repetir')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.cancel();
    final cancelled = count;
    await tester.pump(const Duration(seconds: 1));
    expect(count, cancelled);
    gesture = await tester.startGesture(tester.getCenter(find.text('Repetir')));
    await tester.pump(const Duration(milliseconds: 700));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final inactive = count;
    await tester.pump(const Duration(seconds: 1));
    expect(count, inactive);
    await gesture.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final fail in [false, true]) {
    test(
      'janela restaura posição, maximização e sobreposição (falha=$fail)',
      () async {
        final window = SimulatedWindow()..failResize = fail;
        final service = DesktopWindowService(window: window);
        final original = window.bounds;
        if (fail) {
          await expectLater(service.setCompact(true), throwsStateError);
        } else {
          await service.setCompact(true);
          expect(window.bounds.size, const Size(360, 520));
          expect(window.onTop, isTrue);
          await service.setCompact(false);
        }
        expect(window.bounds, original);
        expect(window.onTop, isFalse);
        expect(window.maximized, isTrue);
      },
    );
  }

  testWidgets('favoritar pelo grid filtra sem abrir app', (tester) async {
    final driver = FakeTvDriver();
    final c = RemoteController(initialDriver: driver);
    await c.ready;
    c.activeSession!.installedApps = [
      const TvAppInfo(id: 'netflix', name: 'Netflix'),
      const TvAppInfo(id: 'youtube', name: 'YouTube'),
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: c,
        child: const MaterialApp(home: Scaffold(body: AppDrawerWidget())),
      ),
    );
    await tester.tap(find.byTooltip('Favoritar Netflix'));
    await tester.pumpAndSettle();
    expect(c.isFavoriteApp('netflix'), isTrue);
    await tester.tap(find.text('Favoritos'));
    await tester.pumpAndSettle();
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('YouTube'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('compacto acessível e diagnóstico funcionam na tela estreita', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SixFRemoteApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'layout inicial');
    await tester.tap(find.text('Desconectado'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionDiagnostic), findsOneWidget);
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    if (Platform.isWindows) {
      await tester.tap(find.byTooltip('Modo compacto'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Sair do modo compacto'), findsOneWidget);
      expect(find.byTooltip('Apps e favoritos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Sair do modo compacto'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Modo compacto'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
