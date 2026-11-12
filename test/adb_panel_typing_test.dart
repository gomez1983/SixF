import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/google_tv_apps_adb.dart';
import 'package:sixf_remote/ui/widgets/google_tv_adb_dialog.dart';

void main() {
  testWidgets('digita nos campos do painel ADB dentro da estrutura da tela', (
    tester,
  ) async {
    final handled = <LogicalKeyboardKey>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final ctx = FocusManager.instance.primaryFocus?.context;
            if (ctx != null &&
                (ctx.widget is EditableText ||
                    ctx.findAncestorWidgetOfExactType<EditableText>() !=
                        null)) {
              return KeyEventResult.ignored;
            }
            handled.add(event.logicalKey);
            return KeyEventResult.handled;
          },
          child: Scaffold(
            body: IndexedStack(
              index: 1,
              children: [
                Focus(autofocus: true, child: const SizedBox()),
                SingleChildScrollView(
                  child: GoogleTvAdbPanel(
                    host: '192.168.0.10',
                    wasConfigured: true,
                    onConnected: () async {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('adb-pair-port')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.pump();
    expect(handled, isEmpty);
  });

  Future<void> pumpPanel(
    WidgetTester tester,
    Future<void> Function(String, int?, {int? pairingPort, String? code})
    configure, {
    bool wasConfigured = false,
    Future<void> Function()? onConnected,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GoogleTvAdbPanel(
            host: '192.168.0.10',
            wasConfigured: wasConfigured,
            onConnected: onConnected ?? () async {},
            configure: configure,
          ),
        ),
      ),
    ),
  );

  final pairPort = find.byKey(const ValueKey('adb-pair-port'));
  final pairCode = find.byKey(const ValueKey('adb-pair-code'));
  final connPort = find.byKey(const ValueKey('adb-conn-port'));

  testWidgets('etapa 1 mostra só a porta do código e o código', (tester) async {
    final calls = <String>[];
    await pumpPanel(tester, (host, port, {pairingPort, code}) async {
      calls.add('$port/$pairingPort/$code');
    });
    expect(pairPort, findsOneWidget);
    expect(pairCode, findsOneWidget);
    expect(connPort, findsNothing);

    // Código sem a porta do código: avisa e não tenta conectar.
    await tester.enterText(pairCode, '854187');
    await tester.tap(find.text('Conectar'));
    await tester.pump();
    expect(find.textContaining('Informe a porta do código'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('pareou sem achar a porta: etapa 2 pede só a porta de conexão', (
    tester,
  ) async {
    final calls = <String>[];
    var connected = 0;
    await pumpPanel(tester, (host, port, {pairingPort, code}) async {
      calls.add('$port/$pairingPort/$code');
      if (port == null) {
        throw const AdbConnectionPortException(
          paired: true,
          message: 'O SixF não achou a porta de conexão sozinho.',
        );
      }
    }, onConnected: () async => connected++);
    await tester.enterText(pairPort, '46139');
    await tester.enterText(pairCode, '073083');
    await tester.tap(find.text('Conectar'));
    await tester.pump();
    await tester.pump();

    // Sucesso do pareamento em destaque, sem mensagem de erro, e só o campo
    // que falta preencher.
    expect(find.text('Pareado com a TV'), findsOneWidget);
    expect(pairPort, findsNothing);
    expect(pairCode, findsNothing);
    expect(connPort, findsOneWidget);
    expect(find.textContaining('não achou a porta'), findsOneWidget);
    expect(calls, ['null/46139/073083']);
    expect(connected, 0);

    await tester.enterText(connPort, '192.168.0.10:46761');
    await tester.tap(find.text('Conectar'));
    await tester.pump();
    await tester.pump();
    expect(calls.last, '46761/null/null');
    expect(connected, 1);
  });

  testWidgets('Tentar de novo sem achar a porta também cai na etapa 2', (
    tester,
  ) async {
    await pumpPanel(tester, (host, port, {pairingPort, code}) async {
      throw const AdbConnectionPortException(
        paired: false,
        message: 'O SixF não achou a porta de conexão sozinho.',
      );
    }, wasConfigured: true);
    await tester.tap(find.text('Tentar de novo'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Falta a porta de conexão'), findsOneWidget);
    expect(find.text('Pareado com a TV'), findsNothing);
    expect(connPort, findsOneWidget);
    expect(pairPort, findsNothing);

    // Dá para voltar ao pareamento se a TV não estiver mais autorizada.
    await tester.tap(find.text('Parear de novo'));
    await tester.pump();
    expect(pairPort, findsOneWidget);
    expect(connPort, findsNothing);
  });
}
