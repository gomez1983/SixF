import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/ui/views/media_library.dart';
import 'package:sixf_remote/ui/widgets/media_session_controls.dart';

import 'dlna_media_cast_test.dart' show FakeTvDriver;

void main() {
  testWidgets(
    'Fila de execução temporária reordena itens com drag & drop, recolhe/expande e persiste',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'mediaLibrary.v1': jsonEncode({
          'lists': [],
          'queueTitle': 'Rested',
          'queue': [
            {'source': 'drive', 'id': 'ep1', 'name': 'Episódio 1.mp4'},
            {'source': 'drive', 'id': 'ep2', 'name': 'Episódio 2.mp4'},
            {'source': 'drive', 'id': 'ep3', 'name': 'Episódio 3.mp4'},
          ],
        }),
      });

      final tv = RemoteController(initialDriver: FakeTvDriver());
      final cast = MediaCastController();
      await tv.ready;
      addTearDown(tv.dispose);
      addTearDown(cast.dispose);

      Widget buildApp() => MultiProvider(
        providers: [
          ChangeNotifierProvider<RemoteController>.value(value: tv),
          ChangeNotifierProvider<MediaCastController>.value(value: cast),
        ],
        child: const MaterialApp(home: MediaLibrary()),
      );

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Muda para a aba de Fila (Fila (3))
      expect(find.text('Fila (3)'), findsOneWidget);
      await tester.tap(find.text('Fila (3)'));
      await tester.pumpAndSettle();

      // Verifica cabeçalho retrátil com o nome da playlist
      expect(find.text('Rested'), findsOneWidget);

      // Confirma que os itens estão visíveis na ordem inicial
      expect(find.text('Episódio 1.mp4'), findsOneWidget);
      expect(find.text('Episódio 2.mp4'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Episódio 1.mp4')).dy,
        lessThan(tester.getTopLeft(find.text('Episódio 2.mp4')).dy),
      );

      // Testa recolher (collapse) e expandir o cabeçalho retrátil da fila
      await tester.tap(find.text('Rested'));
      await tester.pumpAndSettle();
      expect(find.text('Episódio 1.mp4'), findsNothing);
      expect(find.textContaining('Lista recolhida'), findsOneWidget);

      await tester.tap(find.text('Rested'));
      await tester.pumpAndSettle();
      expect(find.text('Episódio 1.mp4'), findsOneWidget);

      // Reordena Episódio 1 para baixo via drag handle
      final drag = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.drag_handle).first),
      );
      await tester.pump();
      await drag.moveBy(const Offset(0, 118));
      await tester.pumpAndSettle();
      await drag.up();
      await tester.pumpAndSettle();

      // Confirma que agora Episódio 1 está abaixo de Episódio 2
      expect(
        tester.getTopLeft(find.text('Episódio 1.mp4')).dy,
        greaterThan(tester.getTopLeft(find.text('Episódio 2.mp4')).dy),
      );

      // Remove o primeiro item da fila atual (que agora é Episódio 2)
      final removeButtons = find.byIcon(Icons.remove_circle_outline);
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();
      expect(find.text('Episódio 2.mp4'), findsNothing);

      // Recarrega o app e verifica se a nova fila persistiu
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Abre aba Fila
      expect(find.text('Fila (2)'), findsOneWidget);
      await tester.tap(find.text('Fila (2)'));
      await tester.pumpAndSettle();

      expect(find.text('Episódio 2.mp4'), findsNothing);
      expect(find.text('Episódio 1.mp4'), findsOneWidget);
      expect(find.text('Episódio 3.mp4'), findsOneWidget);
    },
  );

  testWidgets(
    'Permite renomear e excluir uma playlist salva (ex: Rested)',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'mediaLibrary.v1': jsonEncode({
          'lists': [
            {
              'name': 'Rested',
              'favorite': false,
              'items': [
                {'source': 'drive', 'id': 'ep1', 'name': 'Piloto.mp4'},
              ],
            },
          ],
        }),
      });

      final tv = RemoteController(initialDriver: FakeTvDriver());
      final cast = MediaCastController();
      await tv.ready;
      addTearDown(tv.dispose);
      addTearDown(cast.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RemoteController>.value(value: tv),
            ChangeNotifierProvider<MediaCastController>.value(value: cast),
          ],
          child: const MaterialApp(home: MediaLibrary()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rested'), findsOneWidget);

      // Renomeia a playlist
      await tester.tap(find.byTooltip('Renomear playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Rested Oficial');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(find.text('Rested Oficial'), findsOneWidget);
      expect(find.text('Rested'), findsNothing);

      // Exclui a playlist
      await tester.tap(find.byTooltip('Excluir playlist'));
      await tester.pumpAndSettle();
      expect(
        find.text('Deseja realmente excluir a playlist "Rested Oficial"?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();

      expect(find.text('Rested Oficial'), findsNothing);
      expect(find.text('Sua primeira playlist'), findsOneWidget);
    },
  );

  testWidgets(
    'MediaSessionControls apresenta botões de Play e Pausar na pastilha',
    (tester) async {
      final cast = MediaCastController();
      addTearDown(cast.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaSessionControls(controller: cast, enabled: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Retomar reprodução'), findsOneWidget);
      expect(find.byTooltip('Pausar reprodução'), findsNothing);
      expect(find.byTooltip('Parar transmissão'), findsOneWidget);
    },
  );

  testWidgets(
    'Fila de execução vazia exibe estado amigável e botão para ir a Arquivos',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final tv = RemoteController(initialDriver: FakeTvDriver());
      final cast = MediaCastController();
      await tv.ready;
      addTearDown(tv.dispose);
      addTearDown(cast.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RemoteController>.value(value: tv),
            ChangeNotifierProvider<MediaCastController>.value(value: cast),
          ],
          child: const MaterialApp(home: MediaLibrary()),
        ),
      );
      await tester.pumpAndSettle();

      // Toca na aba Fila
      expect(find.text('Fila'), findsOneWidget);
      await tester.tap(find.text('Fila'));
      await tester.pumpAndSettle();

      // Confirma mensagem e botão
      expect(find.text('Fila de execução temporária vazia'), findsOneWidget);
      expect(find.text('Navegar em Arquivos'), findsOneWidget);

      // Toca em Navegar em Arquivos e verifica se mudou para a aba de Arquivos
      await tester.tap(find.text('Navegar em Arquivos'));
      await tester.pumpAndSettle();

      expect(find.text('Adicionar pasta deste aparelho'), findsOneWidget);
    },
  );

  testWidgets(
    'MediaLibrary exibe cabeçalho do destino ativo',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final tv = RemoteController(initialDriver: FakeTvDriver());
      final cast = MediaCastController();
      await tv.ready;
      addTearDown(tv.dispose);
      addTearDown(cast.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RemoteController>.value(value: tv),
            ChangeNotifierProvider<MediaCastController>.value(value: cast),
          ],
          child: const MaterialApp(home: MediaLibrary()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Biblioteca de mídia ·'), findsOneWidget);
      expect(find.textContaining('Destino ativo:'), findsOneWidget);
    },
  );
}
