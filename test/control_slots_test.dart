import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/ui/views/media_library.dart';
import 'package:sixf_remote/ui/widgets/control_slots.dart';
import 'package:sixf_remote/ui/widgets/system_navigation_controls.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ControlSlot', () {
    test('codifica e decodifica ação, app e vazio', () {
      expect(ControlSlot.decode('key:home'), const ControlSlot.action('home'));
      expect(
        ControlSlot.decode(const ControlSlot.app('netflix', 'Netflix').encode()),
        const ControlSlot.app('netflix', 'Netflix'),
      );
      expect(ControlSlot.decode('').isEmpty, isTrue);
      // Ação desconhecida (versão futura ou dado corrompido) vira slot vazio.
      expect(ControlSlot.decode('key:nao-existe').isEmpty, isTrue);
      expect(ControlSlot.decode('app:sem-nome').isEmpty, isTrue);
    });

    test('todas as ações do catálogo têm id único', () {
      final ids = kControlSlotActions.map((a) => a.id).toSet();
      expect(ids.length, kControlSlotActions.length);
    });
  });

  test('linha do tempo de toque sobe sem estourar cards baixos', () {
    expect(touchSeekBarLift(320), 14);
    expect(touchSeekBarLift(150), 8);
    expect(touchSeekBarLift(96), 0);
    for (final h in [120.0, 150.0, 199.0, 200.0, 213.0]) {
      final lift = touchSeekBarLift(h);
      final sizes = compactVideoControlSizes(h - lift);
      final bar = sizes?.bar ?? 56;
      final seek = sizes?.seek ?? 36;
      expect(bar * 2 + seek + lift, lessThanOrEqualTo(h), reason: 'altura $h');
    }
  });

  testWidgets('slot troca de função só depois de Confirmar', (tester) async {
    final controller = RemoteController();
    await controller.ready;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: SystemNavigationControls())),
        ),
      ),
    );
    await tester.pump();

    // Padrão: as antigas "Ações rápidas".
    for (final label in ['HOME', 'MENU', 'INPUT', 'EXIT']) {
      expect(find.text(label), findsOneWidget);
    }

    // Toque longo abre o seletor; escolher não aplica nada ainda.
    await tester.longPress(find.text('EXIT'));
    await tester.pumpAndSettle();
    expect(find.text('Slot 4 de 4 (faixa de cima)'), findsOneWidget);
    await tester.tap(find.text('Voltar'));
    await tester.pump();
    expect(controller.controlSlots('top'), isNull);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(controller.controlSlots('top'), [
      'key:home',
      'key:menu',
      'key:input',
      'key:back',
    ]);
    expect(find.text('EXIT'), findsNothing);
    expect(find.text('VOLTAR'), findsOneWidget);

    // Cancelar não muda nada.
    await tester.longPress(find.text('HOME'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mudo'));
    await tester.pump();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);

    // Restaurar o padrão da faixa.
    await tester.longPress(find.text('HOME'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurar padrão da faixa'));
    await tester.pumpAndSettle();
    expect(controller.controlSlots('top'), isNull);
    expect(find.text('EXIT'), findsOneWidget);
  });
}
