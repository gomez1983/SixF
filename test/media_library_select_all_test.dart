import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/media_remux_service.dart';
import 'package:sixf_remote/ui/theme/app_theme.dart';
import 'package:sixf_remote/ui/views/media_library.dart';

import 'dlna_media_cast_test.dart' show FakeTvDriver;

/// "Selecionar todos" na barra de seleção e Shift + clique para marcar um
/// intervalo, na biblioteca de mídia.
void main() {
  late Directory dir;
  final culprits = <String>{};
  Future<void> pumpLibrary(WidgetTester tester, Size size) async {
    // Sem FFmpeg: as miniaturas de vídeo não disparam processos externos.
    MediaRemuxService.setFfmpegAvailableForTesting(false);
    addTearDown(() => MediaRemuxService.setFfmpegAvailableForTesting(null));
    culprits.clear();
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final m = RegExp(r'lib/[a-z_/]+[.]dart:[0-9]+').firstMatch(details.toString());
      if (m != null) culprits.add(m.group(0)!);
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    dir = Directory.systemTemp.createTempSync('sixf-selectall-');
    for (final n in ['a1.mp4', 'a2.mp4', 'a3.mp4', 'a4.mp4', 'a5.mp4', 'b.mp3']) {
      File('${dir.path}/$n').writeAsBytesSync([1, 2, 3]);
    }
    Directory('${dir.path}/Subpasta').createSync();
    SharedPreferences.setMockInitialValues({
      'mediaLibrary.v1': jsonEncode({
        'trail': [
          {'source': 'local', 'id': dir.path, 'name': 'Pasta', 'folder': true},
        ],
      }),
    });
    final remote = RemoteController(initialDriver: FakeTvDriver());
    final cast = MediaCastController();
    await remote.ready;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      remote.dispose();
      cast.dispose();
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<RemoteController>.value(value: remote),
          ChangeNotifierProvider<MediaCastController>.value(value: cast),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MediaLibrary(),
        ),
      ),
    );
    // Espera a biblioteca carregar (mais lenta com a suíte em carga).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('Arquivos').evaluate().isNotEmpty) break;
    }
    await tester.tap(find.text('Arquivos').first);
    // Espera a listagem da pasta terminar (mais lenta com a suíte em carga).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byTooltip('Selecionar').evaluate().isNotEmpty) break;
    }
  }

  testWidgets('Selecionar todos marca os arquivos e alterna para Desmarcar', (
    tester,
  ) async {
    await pumpLibrary(tester, const Size(400, 860));
    expect(find.byTooltip('Selecionar todos os arquivos da pasta'), findsNothing);

    // Marca um arquivo: a barra de ações aparece com o novo botão.
    await tester.tap(find.byTooltip('Selecionar').first);
    await tester.pump();
    expect(find.text('1 selecionado'), findsOneWidget);
    expect(find.text('Selecionar todos'), findsOneWidget);

    await tester.tap(find.text('Selecionar todos'));
    await tester.pump();
    // 5 vídeos + 1 áudio; a subpasta não entra.
    expect(find.text('6 selecionados'), findsOneWidget);
    expect(find.text('Desmarcar todos'), findsOneWidget);

    await tester.tap(find.text('Desmarcar todos'));
    await tester.pump();
    expect(find.textContaining('selecionado'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selecionar todos respeita o filtro de tipo', (tester) async {
    await pumpLibrary(tester, const Size(400, 860));
    await tester.tap(find.textContaining('Vídeos'));
    await tester.pump();
    await tester.tap(find.byTooltip('Selecionar').first);
    await tester.pump();
    await tester.tap(find.text('Selecionar todos'));
    await tester.pump();
    // Com o filtro "Vídeos", só os 5 vídeos entram (o áudio fica de fora).
    expect(find.text('5 selecionados'), findsOneWidget);
    expect(find.text('Desmarcar todos'), findsOneWidget);
  });
  testWidgets('Shift + clique marca o intervalo entre dois arquivos', (
    tester,
  ) async {
    await pumpLibrary(tester, const Size(400, 860));
    final circles = find.byTooltip('Selecionar');
    expect(circles, findsWidgets);
    await tester.tap(circles.at(0));
    await tester.pump();
    expect(find.text('1 selecionado'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    // Os círculos restantes seguem em ordem; o 4º à frente do primeiro.
    await tester.tap(find.byTooltip('Selecionar').at(2));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    // Primeiro + dois sem marcação no meio + o clicado = 4 no total.
    expect(find.text('4 selecionados'), findsOneWidget);
  });

  for (final size in const [Size(320, 568), Size(360, 640), Size(740, 360)]) {
    testWidgets('barra de seleção sem estouro em $size', (tester) async {
      await pumpLibrary(tester, size);
      // Em tela baixa o primeiro círculo pode estar abaixo da dobra.
      await tester.ensureVisible(find.byTooltip('Selecionar').first);
      await tester.pump();
      await tester.tap(find.byTooltip('Selecionar').first);
      await tester.pump();
      await tester.tap(find.text('Selecionar todos'));
      await tester.pump();
      for (final scale in [1.0, 1.5]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size x$scale $culprits');
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }
}
