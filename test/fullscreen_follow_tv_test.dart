import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/library_sources.dart';
import 'package:sixf_remote/ui/widgets/image_fullscreen_viewer.dart';

/// Item 15: ao deslizar na tela cheia, o visualizador avisa cada troca de
/// foto, para a biblioteca espelhar a nova foto na TV sem sair da tela cheia.
void main() {
  testWidgets('tela cheia avisa a troca de foto ao deslizar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const items = [
      LibraryEntry(LibrarySource.local, 'a', 'a.jpg'),
      LibraryEntry(LibrarySource.local, 'b', 'b.jpg'),
      LibraryEntry(LibrarySource.local, 'c', 'c.jpg'),
    ];
    final changes = <int>[];
    // A imagem nunca termina de carregar: o teste só observa a navegação.
    final never = Completer<File>();

    await tester.pumpWidget(
      MaterialApp(
        home: ImageFullscreenViewer(
          items: items,
          initialIndex: 0,
          resolve: (_) => never.future,
          onIndexChanged: changes.add,
        ),
      ),
    );
    await tester.pump();

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
    await tester.pump(const Duration(seconds: 1));
    expect(changes, [1]);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
    await tester.pump(const Duration(seconds: 1));
    expect(changes, [1, 2]);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1500);
    await tester.pump(const Duration(seconds: 1));
    expect(changes, [1, 2, 1]);
  });
}
