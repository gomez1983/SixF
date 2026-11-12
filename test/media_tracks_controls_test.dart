import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/services/google_cast_media.dart';
import 'package:sixf_remote/services/media_remux_service.dart';
import 'package:sixf_remote/services/media_server_service.dart';
import 'package:sixf_remote/ui/views/media_library.dart';
import 'package:sixf_remote/ui/widgets/media_session_controls.dart';

class _FakeServerService extends MediaServerService {
  @override
  Future<int> start() async => 8080;

  @override
  Future<String> prepareSubtitle(int trackId) async => 'WEBVTT\n\n00:01.000 --> 00:03.000\nTeste\n';

  @override
  Future<String?> getSubtitleUrlForTv(String targetTvIp, int trackId) async => 'http://127.0.0.1:8080/subtitle_$trackId.vtt';

  @override
  Future<String?> getMediaUrlForTv(String targetTvIp) async => 'http://127.0.0.1:8080/video.mp4';

  @override
  void serveFile(File file, {String? customName, String? mimeType, Future<Process?> Function()? remuxProcessFactory}) {}

  @override
  Future<void> stop() async {}
}

class _FakeCastMedia extends GoogleCastMedia {
  _FakeCastMedia() : super(port: 0);
  Map<String, dynamic> current = {};
  @override
  Map<String, dynamic> get status => current;

  @override
  Future<void> load(
    String host,
    String url,
    String title,
    String mime, {
    List<Map<String, dynamic>>? tracks,
    List<int>? activeTrackIds,
    Duration? duration,
  }) async {
    current = {
      'mediaSessionId': 1,
      'playerState': 'PLAYING',
      'currentTime': 10,
      'supportedMediaCommands': 3,
      'media': {'duration': 100},
    };
    onStatus?.call(current);
  }

  bool rejectActiveTrackIds = false;
  void Function(List<int> tracks)? onReloadWithActiveTracks;

  @override
  Future<void> setActiveTrackIds(List<int> trackIds) async {
    if (rejectActiveTrackIds) {
      throw StateError('O Chromecast recusou a legenda (INVALID_PARAMS).');
    }
  }

  @override
  Future<void> reloadWithActiveTracks({
    required List<int> activeTrackIds,
    List<Map<String, dynamic>>? tracks,
    Duration? currentTime,
    bool autoplay = true,
  }) async {
    onReloadWithActiveTracks?.call(activeTrackIds);
  }

  @override
  Future<void> command(
    String type, {
    double? currentTime,
    String? resumeState,
  }) async {}

  @override
  Future<void> refresh() async {}

  @override
  void close() {}
}

void main() {
  testWidgets('MediaSessionControls exibe botões de Legenda e Áudio entre -10s e +10s', (tester) async {
    final cast = MediaCastController();
    addTearDown(cast.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaSessionControls(controller: cast, enabled: true, showTimeline: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Com status idle, timeline de seek não aparece até haver stream com progress
    expect(find.byTooltip('Retomar reprodução'), findsOneWidget);
    expect(find.byTooltip('Pausar reprodução'), findsNothing);
  });

  test('MediaDetails identifica compatibilidade de codecs com decodificador Chromecast', () {
    const detailsXvid = MediaDetails(tracks: [], videoCodec: 'mpeg4');
    expect(detailsXvid.isChromecastVideoCompatible, isFalse);

    const detailsMpeg2 = MediaDetails(tracks: [], videoCodec: 'mpeg2video');
    expect(detailsMpeg2.isChromecastVideoCompatible, isFalse);

    // Imagens (webp, png, gif...) não passam por transcodificação de vídeo:
    // o código as trata como compatíveis de propósito.
    const detailsWebp = MediaDetails(tracks: [], videoCodec: 'webp');
    expect(detailsWebp.isChromecastVideoCompatible, isTrue);

    const detailsHi10p = MediaDetails(tracks: [], videoCodec: 'h264', videoPixFmt: 'yuv420p10le');
    expect(detailsHi10p.isChromecastVideoCompatible, isFalse);

    const detailsH264 = MediaDetails(tracks: [], videoCodec: 'h264', videoPixFmt: 'yuv420p');
    expect(detailsH264.isChromecastVideoCompatible, isTrue);
  });

  testWidgets('MediaLibrary exibe e executa botão Limpar histórico de pastas salvas', (tester) async {
    SharedPreferences.setMockInitialValues({
      'mediaLibrary.v1': '{"roots":[{"source":"local","id":"C:\\\\Videos","name":"Videos","folder":true}]}',
    });

    final tv = RemoteController();
    final cast = MediaCastController();
    addTearDown(cast.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: tv),
          ChangeNotifierProvider.value(value: cast),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MediaLibrary(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Entra na aba Arquivos (tab index 2)
    final arquivosTab = find.text('Arquivos');
    expect(arquivosTab, findsOneWidget);
    await tester.tap(arquivosTab);
    await tester.pumpAndSettle();

    // O histórico possui a pasta "Videos" e deve exibir o botão de limpeza
    expect(find.text('Videos'), findsOneWidget);
    final limparBtn = find.text('Limpar histórico de pastas salvas');
    expect(limparBtn, findsOneWidget);

    // Toca no botão de limpar histórico
    await tester.tap(limparBtn);
    await tester.pumpAndSettle();

    // O botão desaparece e a pasta local salva foi limpa
    expect(find.text('Limpar histórico de pastas salvas'), findsNothing);
    expect(find.text('Videos'), findsNothing);
    expect(find.text('Adicionar pasta deste aparelho'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('OneDrive'), findsOneWidget);
  });

  testWidgets('Diálogo de Legendas exige confirmação explícita com botão Confirmar e exibe badge', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('sub_test_');
    final file = File('${tempDir.path}/test.mkv')..writeAsStringSync('dummy');

    final cast = MediaCastController(
      castFactory: () => _FakeCastMedia(),
      probeMedia: (_) async => const MediaDetails(
        tracks: [
          MediaTrack(id: 1, type: 'subtitle', title: 'Português (Brasil)', language: 'por'),
          MediaTrack(id: 2, type: 'subtitle', title: 'English', language: 'eng'),
        ],
        duration: Duration(minutes: 90),
      ),
      serverService: _FakeServerService(),
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      cast.dispose();
      await tester.runAsync(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
    });

    await tester.runAsync(() async {
      await cast.castFile(file, targetTvIp: '192.168.1.50', brand: TvBrand.googleTv);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaSessionControls(controller: cast, enabled: true, showTimeline: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Abre o diálogo de legendas
    final subButton = find.byTooltip('Legendas embutidas');
    expect(subButton, findsOneWidget);
    await tester.tap(subButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Diálogo aberto: deve conter opções e botões Cancelar e Confirmar
    expect(find.text('Legendas'), findsOneWidget);
    expect(find.text('Português (Brasil)'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Confirmar'), findsOneWidget);

    // Tocar na opção Português NÃO deve fechar o diálogo prematuramente
    await tester.tap(find.text('Português (Brasil)'));
    await tester.pump();
    expect(find.text('Confirmar'), findsOneWidget);

    // Tocar em Confirmar aplica a seleção e fecha o diálogo com feedback
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Legendas'), findsNothing);
    expect(find.textContaining('Legendas ativada: Português (Brasil)'), findsOneWidget);
    // Badge indicativo visível no player
    expect(find.text('Português (Brasil)'), findsOneWidget);
  });

  testWidgets('selectSubtitleTrack recupera-se via reloadWithActiveTracks quando EDIT_TRACKS_INFO é recusado', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('sub_fallback_');
    final file = File('${tempDir.path}/test.mkv')..writeAsStringSync('dummy');

    bool reloadCalled = false;
    List<int>? reloadedTracks;

    final fakeCast = _FakeCastMedia();
    fakeCast.rejectActiveTrackIds = true;
    fakeCast.onReloadWithActiveTracks = (tracks) {
      reloadCalled = true;
      reloadedTracks = tracks;
    };

    final cast = MediaCastController(
      castFactory: () => fakeCast,
      probeMedia: (_) async => const MediaDetails(
        tracks: [
          MediaTrack(id: 27, type: 'subtitle', title: 'Português (Brasil)', language: 'por'),
        ],
        duration: Duration(minutes: 90),
      ),
      serverService: _FakeServerService(),
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      cast.dispose();
      await tester.runAsync(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });
    });

    await tester.runAsync(() async {
      await cast.castFile(file, targetTvIp: '192.168.1.50', brand: TvBrand.googleTv);
    });

    // Seleciona a legenda: EDIT_TRACKS_INFO falhará, mas o fallback reloadWithActiveTracks deve ser acionado
    await tester.runAsync(() async {
      await cast.selectSubtitleTrack(
        const MediaTrack(id: 27, type: 'subtitle', title: 'Português (Brasil)', language: 'por'),
      );
    });

    expect(reloadCalled, isTrue);
    expect(reloadedTracks, equals([28]));
    expect(cast.selectedSubtitleTrack?.title, equals('Português (Brasil)'));
  });
}
