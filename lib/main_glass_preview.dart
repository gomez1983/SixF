import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'controllers/remote_controller.dart';
import 'ui/glass/glass_control_body.dart';
import 'ui/glass/glass_flags.dart';
import 'ui/glass/glass_remote_shell.dart';
import 'ui/widgets/app_drawer_widget.dart';
import 'ui/widgets/color_buttons_row.dart';
import 'ui/widgets/multimedia_controls.dart';
import 'ui/widgets/numeric_keypad.dart';
import 'ui/widgets/remote_button.dart';
import 'ui/widgets/trackpad_widget.dart';

/// Vitrine de design do Liquid Glass: duas telas (escura e clara) lado a lado,
/// usando o RemoteController real (aparelhos salvos, volume, canal...).
///
///   flutter run -d windows -t lib/main_glass_preview.dart
///
/// Para ver dentro do app de verdade (com todas as abas, pareamento, atalhos
/// etc.), use a opção experimental no main normal:
///
///   flutter run -d windows --dart-define=SIXF_GLASS_UI=true
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kGlassUi = true; // a vitrine sempre mostra o modo Liquid Glass
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1060, 1000),
        center: true,
        title: 'SixF Liquid Glass',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  runApp(const GlassPreviewApp());
}

ThemeData _theme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  brightness: brightness,
  // Windows não tem SF Pro; em iOS/macOS o padrão do sistema já é a SF.
  fontFamily: defaultTargetPlatform == TargetPlatform.windows
      ? 'Segoe UI'
      : null,
);

class GlassPreviewApp extends StatelessWidget {
  const GlassPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RemoteController(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SixF Liquid Glass',
        theme: _theme(Brightness.dark),
        home: Scaffold(
          backgroundColor: const Color(0xFF0D0D12),
          body: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    _PhoneFrame(brightness: Brightness.dark),
                    SizedBox(width: 72),
                    _PhoneFrame(brightness: Brightness.light),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Moldura 393x852 (iPhone 17 Pro) com barra de status simulada.
class _PhoneFrame extends StatefulWidget {
  const _PhoneFrame({required this.brightness});

  final Brightness brightness;

  @override
  State<_PhoneFrame> createState() => _PhoneFrameState();
}

class _PhoneFrameState extends State<_PhoneFrame> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final dark = widget.brightness == Brightness.dark;
    final fg = dark ? Colors.white : const Color(0xFF101319);
    return Theme(
      data: _theme(widget.brightness),
      child: Builder(
        builder: (context) => Container(
          width: 393,
          height: 852,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(58),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 70,
                offset: Offset(0, 36),
              ),
            ],
            border: Border.all(color: const Color(0xFF3A3A42), width: 10),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(48),
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: const EdgeInsets.fromLTRB(0, 54, 0, 34)),
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GlassRemoteShell(
                      selectedTab: _tab,
                      onSelectTab: (i) => setState(() => _tab = i),
                      onOpenDrawer: () {},
                      showTrackpad: true,
                      body: switch (_tab) {
                        0 => const GlassControlBody(),
                        1 => const _KeysTab(),
                        2 => const _TrackpadTab(),
                        4 => const AppDrawerWidget(),
                        _ => Center(
                          child: Text(
                            'A Biblioteca de mídia só aparece no app completo',
                            style: TextStyle(color: fg.withValues(alpha: 0.6)),
                          ),
                        ),
                      },
                    ),
                    _StatusBar(color: fg),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        width: 130,
                        height: 5,
                        decoration: BoxDecoration(
                          color: fg.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mesmo conteúdo da aba "Teclas & Mídia" do RemoteView.
class _KeysTab extends StatelessWidget {
  const _KeysTab();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NumericKeypad(),
          SizedBox(height: 16),
          MultimediaControls(),
          SizedBox(height: 14),
          ColorButtonsRow(),
        ],
      ),
    );
  }
}

/// Mesmo conteúdo da aba "Trackpad" do RemoteView.
class _TrackpadTab extends StatelessWidget {
  const _TrackpadTab();

  @override
  Widget build(BuildContext context) {
    final c = context.read<RemoteController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: TrackpadWidget()),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: RemoteButton(
                  height: 50,
                  borderRadius: 14,
                  icon: Icons.undo_rounded,
                  label: 'VOLTAR',
                  iconSize: 18,
                  onPressed: c.pressBack,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: RemoteButton(
                  height: 50,
                  borderRadius: 14,
                  isSelected: true,
                  icon: Icons.mouse_rounded,
                  label: 'CLIQUE / OK',
                  iconSize: 20,
                  onPressed: c.sendTrackpadClick,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RemoteButton(
                  height: 50,
                  borderRadius: 14,
                  icon: Icons.home_rounded,
                  label: 'HOME',
                  iconSize: 18,
                  onPressed: c.pressHome,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 54,
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: 40,
              top: 16,
              child: Text(
                '9:41',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 112,
                height: 33,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            Positioned(
              right: 32,
              top: 15,
              child: Row(
                children: [
                  Icon(Icons.signal_cellular_alt_rounded, size: 18, color: color),
                  const SizedBox(width: 5),
                  Icon(Icons.wifi_rounded, size: 18, color: color),
                  const SizedBox(width: 5),
                  Icon(Icons.battery_full_rounded, size: 20, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
