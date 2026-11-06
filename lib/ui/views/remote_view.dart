import '../widgets/google_tv_pairing_dialog.dart';
import '../../services/drivers/tv_driver.dart';
import '../../services/desktop_window_service.dart';
import '../widgets/compact_remote.dart';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'media_library.dart';
import '../../controllers/remote_controller.dart';
import '../../services/haptic_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_drawer_widget.dart';
import '../widgets/color_buttons_row.dart';
import '../widgets/device_selector_bar.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/header_bar.dart';
import '../widgets/multimedia_controls.dart';
import '../widgets/network_drawer.dart';
import '../widgets/numeric_keypad.dart';
import '../widgets/remote_button.dart';
import '../widgets/system_navigation_controls.dart';
import '../widgets/trackpad_widget.dart';
import '../widgets/volume_channel_controls.dart';

/// Tela principal do controle remoto para Desktop Windows.
///
/// Implementa captura global de atalhos do teclado físico, alternância de tema
/// e layout responsivo com auto-ajuste (FittedBox) para caber 100% na janela sem barra de rolagem.
class RemoteView extends StatefulWidget {
  const RemoteView({super.key});

  @override
  State<RemoteView> createState() => _RemoteViewState();
}

class _RemoteViewState extends State<RemoteView> {
  final GlobalKey _libraryKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FocusNode _focusNode = FocusNode();
  final Stopwatch _repeatClock = Stopwatch()..start();
  int _lastRepeat = -120;
  final Map<LogicalKeyboardKey, Object> _heldKeyTargets = {};
  final DesktopWindowService _windowService = DesktopWindowService();
  RemoteController? _pairingController;
  bool _pairingDialogOpen = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<RemoteController>();
    if (identical(_pairingController, controller)) return;
    _pairingController?.onPinPromptRequested = null;
    _pairingController = controller;
    controller.onPinPromptRequested = _onPairingPrompt;
  }

  void _onPairingPrompt(bool prompt) {
    final controller = _pairingController;
    if (!prompt ||
        controller == null ||
        controller.currentBrand != TvBrand.googleTv ||
        _pairingDialogOpen) {
      return;
    }
    final deviceId = controller.activeDeviceId;
    final driver = controller.driver;
    if (deviceId == null) return;
    _pairingDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: GoogleTvPairingDialog(
            controller: controller,
            deviceId: deviceId,
            driver: driver,
          ),
        ),
      );
      _pairingDialogOpen = false;
    });
  }

  bool _compact = false;
  bool _changingWindow = false;

  Future<void> _toggleCompact() async {
    if (_changingWindow) return;
    _changingWindow = true;
    try {
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        await _windowService.setCompact(!_compact);
      }
      if (mounted) setState(() => _compact = !_compact);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível alterar a janela.')),
        );
      }
    } finally {
      _changingWindow = false;
    }
  }

  int _selectedTabIndex =
      0; // 0: Controle, 1: Teclas & Mídia, 2: Magic Trackpad

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _pairingController?.onPinPromptRequested = null;
    _focusNode.dispose();
    super.dispose();
  }

  /// Trata teclas do teclado físico do Windows
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) _heldKeyTargets.remove(event.logicalKey);
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Se o aplicativo não estiver em foco ou se um campo de texto estiver focado, ignora completamente
    if (!node.hasFocus) {
      return KeyEventResult.ignored;
    }

    final primaryFocusWidget =
        FocusManager.instance.primaryFocus?.context?.widget;
    if (primaryFocusWidget is EditableText) {
      return KeyEventResult.ignored;
    }

    final controller = context.read<RemoteController>();
    final key = event.logicalKey;
    if (event is KeyDownEvent) _heldKeyTargets[key] = controller.driver;

    if (event is KeyRepeatEvent) {
      final repeatable = {
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.add,
        LogicalKeyboardKey.numpadAdd,
        LogicalKeyboardKey.numpadSubtract,
        LogicalKeyboardKey.audioVolumeUp,
        LogicalKeyboardKey.audioVolumeDown,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
      };
      if (!controller.isConnected ||
          !identical(_heldKeyTargets[key], controller.driver) ||
          !repeatable.contains(key)) {
        return KeyEventResult.ignored;
      }
      final now = _repeatClock.elapsedMilliseconds;
      if (now - _lastRepeat < 120) return KeyEventResult.handled;
      _lastRepeat = now;
    }

    // 1. Setas do teclado -> D-Pad
    if (key == LogicalKeyboardKey.arrowUp) {
      controller.dpadUp();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      controller.dpadDown();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      controller.dpadLeft();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      controller.dpadRight();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.pageUp) {
      controller.channelUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      controller.channelDown();
      return KeyEventResult.handled;
    }

    // 2. Enter / Espaço -> Botão OK
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      controller.dpadOk();
      return KeyEventResult.handled;
    }

    // 3. Teclas numéricas (0 a 9)
    final digitMap = {
      LogicalKeyboardKey.digit0: 0,
      LogicalKeyboardKey.numpad0: 0,
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.numpad5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.numpad7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.numpad8: 8,
      LogicalKeyboardKey.digit9: 9,
      LogicalKeyboardKey.numpad9: 9,
    };

    if (digitMap.containsKey(key)) {
      controller.sendDigit(digitMap[key]!);
      return KeyEventResult.handled;
    }

    // 4. Traço (-)
    if (key == LogicalKeyboardKey.minus) {
      controller.sendDash();
      return KeyEventResult.handled;
    }

    final isWin = !kIsWeb && Platform.isWindows;

    // 5. Volume e Mute
    // No Windows, as teclas de hardware de volume (audioVolumeUp/Down/Mute) são tratadas exclusivamente
    // pelo VolumeKeyService via Win32 WH_KEYBOARD_LL para evitar conflito com o mixer do sistema.
    if ((!isWin && key == LogicalKeyboardKey.audioVolumeUp) ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      controller.volumeUp();
      return KeyEventResult.handled;
    } else if ((!isWin && key == LogicalKeyboardKey.audioVolumeDown) ||
        key == LogicalKeyboardKey.numpadSubtract) {
      controller.volumeDown();
      return KeyEventResult.handled;
    } else if ((!isWin && key == LogicalKeyboardKey.audioVolumeMute) ||
        key == LogicalKeyboardKey.keyM) {
      controller.muteToggle();
      return KeyEventResult.handled;
    }

    // 6. Mídia
    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      controller.mediaPlay();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.mediaPause) {
      controller.mediaPause();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.mediaStop) {
      controller.mediaStop();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.mediaTrackPrevious ||
        key == LogicalKeyboardKey.mediaRewind) {
      controller.mediaRewind();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.mediaFastForward) {
      controller.mediaFastForward();
      return KeyEventResult.handled;
    }

    // 7. Voltar (Backspace / Esc)
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.escape) {
      controller.pressBack();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final supportsTrackpad = context.watch<RemoteController>().supportsTrackpad;
    if (!supportsTrackpad && _selectedTabIndex == 2) _selectedTabIndex = 0;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppColors.backgroundOf(context),
        endDrawer: const NetworkDrawer(),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWideScreen = constraints.maxWidth >= 840;
              // Celular deitado (ou janela baixa e larga): layout próprio de
              // paisagem. Vem antes do modo desktop, pois o S23 Ultra deitado
              // passa de 840 dp e antes caía no layout de PC encolhido.
              final isCompactLandscape =
                  constraints.maxWidth > constraints.maxHeight &&
                  constraints.maxHeight < 560;

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: _compact
                    ? CompactRemote(onExpand: _toggleCompact)
                    : isCompactLandscape
                    ? _buildLandscapeShell()
                    : isWideScreen && _selectedTabIndex == 0
                    ? Column(
                        children: [
                          Expanded(child: _buildDualPaneLayout(constraints)),
                          _buildBottomTabBar(),
                        ],
                      )
                    : _buildMobileTabLayout(constraints),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Layout em duas colunas para telas Desktop largas:
  /// Adapta-se perfeitamente à largura e altura da janela sem transbordar.
  Widget _buildDualPaneLayout(BoxConstraints constraints) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: SizedBox(
            width: 880,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Coluna 1: Chassi do Controle Remoto
                SizedBox(width: 400, child: _buildRemoteChassis()),

                const SizedBox(width: 20),

                // Coluna 2: Painel Magic Remote e Aplicativos
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (context
                          .read<RemoteController>()
                          .supportsTrackpad) ...[
                        _buildTrackpadExpandedCard(),
                        const SizedBox(height: 14),
                      ],
                      _buildDesktopAppsCard(),
                      const SizedBox(height: 14),
                      _buildKeyboardShortcutsHelpCard(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Layout em 4 Abas Responsivo para Mobile (Galaxy S23 Ultra e telas verticais):
  /// Aproveita 100% da largura e altura da tela sem compressão ou caixas fixas.
  Widget _buildMobileTabLayout(BoxConstraints constraints) {
    return Column(
      children: [
        // 1. Cabeçalho persistente no topo (Status, Cast, Power, Tema, Menu)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: HeaderBar(
            onToggleCompact: !kIsWeb && Platform.isWindows
                ? _toggleCompact
                : null,
            onOpenDrawer: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ),

        // Barra de Seleção / Alternância Rápida de Aparelhos (Multi-Device Pills)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: DeviceSelectorBar(),
        ),

        // 2. Conteúdo das 4 Abas
        Expanded(
          child: IndexedStack(
            index: _selectedTabIndex,
            children: [
              // Aba 1: Controle Principal
              _buildTab1Control(),

              // Aba 2: Teclas Numéricas & Demais Botões
              _buildTab2KeypadAndMedia(),

              // Aba 3: Magic Trackpad em Tela Cheia
              context.watch<RemoteController>().supportsTrackpad
                  ? _buildTab3Trackpad()
                  : const SizedBox.shrink(),

              // Aba 4: Biblioteca de Mídia
              MediaLibrary(key: _libraryKey, embedded: true),

              // Aba 5: Gaveta e Atalhos de Aplicativos
              const AppDrawerWidget(),
            ],
          ),
        ),

        // 3. Barra de Navegação Inferior das 4 Abas
        _buildBottomTabBar(),
      ],
    );
  }

  /// Estrutura em paisagem (padrão Material para telas largas e baixas):
  /// navegação em trilho lateral, cabeçalho e aparelhos numa única faixa e
  /// todo o resto da altura para o conteúdo da aba.
  Widget _buildLandscapeShell() {
    final controller = context.watch<RemoteController>();
    return Row(
      children: [
        _buildSideNavRail(),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 16, 2),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final header = HeaderBar(
                      onToggleCompact: !kIsWeb && Platform.isWindows
                          ? _toggleCompact
                          : null,
                      onOpenDrawer: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                    );
                    // Largura suficiente: cabeçalho e aparelhos lado a lado,
                    // poupando altura. Senão, um sobre o outro.
                    if (c.maxWidth < 620) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [header, const DeviceSelectorBar()],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 5, child: header),
                        const SizedBox(width: 12),
                        const Expanded(flex: 6, child: DeviceSelectorBar()),
                      ],
                    );
                  },
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _selectedTabIndex,
                  children: [
                    _buildTab1ControlLandscape(),
                    _buildTab2KeypadAndMedia(),
                    controller.supportsTrackpad
                        ? _buildTab3Trackpad()
                        : const SizedBox.shrink(),
                    MediaLibrary(key: _libraryKey, embedded: true),
                    const AppDrawerWidget(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Trilho de navegação vertical (substitui a barra inferior na paisagem).
  Widget _buildSideNavRail() {
    final supportsTrackpad = context.watch<RemoteController>().supportsTrackpad;
    final items = <({int index, String title, IconData icon})>[
      (index: 0, title: 'Controle', icon: Icons.tv_rounded),
      (index: 1, title: 'Teclas', icon: Icons.dialpad_rounded),
      if (supportsTrackpad)
        (index: 2, title: 'Trackpad', icon: Icons.touch_app_rounded),
      (index: 3, title: 'Mídia', icon: Icons.video_library_outlined),
      (index: 4, title: 'Apps', icon: Icons.apps_rounded),
    ];
    final active = AppColors.iconHighlightOf(context);
    final inactive = AppColors.textSecondaryOf(context);

    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        border: Border(
          right: BorderSide(color: AppColors.borderSubtleOf(context)),
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Tooltip(
                    message: item.title,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticService.selectionClick();
                        setState(() => _selectedTabIndex = item.index);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 64,
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _selectedTabIndex == item.index
                              ? active.withValues(alpha: 0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.icon,
                              size: 22,
                              color: _selectedTabIndex == item.index
                                  ? active
                                  : inactive,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textScaler: const TextScaler.linear(1.0),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: _selectedTabIndex == item.index
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _selectedTabIndex == item.index
                                    ? active
                                    : inactive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Aba Controle em paisagem: duas metades simétricas.
  /// Esquerda — VOL, MUTE/VOZ e CH (mesma disposição do retrato) com a fileira
  /// Home/Menu/Entrada/Sair logo abaixo. Direita — D-pad com VOLTAR, TV Digital
  /// e HDMI (no Chromecast, o mesmo arranjo sem as entradas, que ele não tem).
  /// Cada metade escala junto (FittedBox), então nada transborda em telas
  /// baixas e as proporções ficam idênticas às do controle vertical.
  Widget _buildTab1ControlLandscape() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final halfWidth = (constraints.maxWidth - 32 - 1) / 2;
        final height = constraints.maxHeight;
        // D-pad: ocupa a altura disponível, sem passar do tamanho do retrato.
        final wheel = (height - 20).clamp(130.0, 260.0);
        final volumeHeight = (height * 0.55).clamp(130.0, 220.0);
        const leftWidth = 300.0;
        final dpadWidth = wheel + 140;

        Widget half(Widget child, double naturalWidth) => SizedBox(
          width: halfWidth,
          height: height,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(width: naturalWidth, child: child),
              ),
            ),
          ),
        );

        return Padding(
          key: const ValueKey('control-landscape'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              half(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    VolumeChannelControls(height: volumeHeight),
                    const SizedBox(height: 18),
                    const SystemNavigationControls(),
                  ],
                ),
                leftWidth,
              ),
              Container(
                width: 1,
                height: height * 0.62,
                color: AppColors.borderSubtleOf(context),
              ),
              half(DPadWidget(size: wheel), dpadWidth),
            ],
          ),
        );
      },
    );
  }

  /// Aba 1: Apenas Volume, Canais, D-Pad, HDMI 1, TV Digital, Home, Menu, Voltar e Exit
  Widget _buildTab1Control() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tamanhos modulares: a altura útil (abaixo de Home/Menu/Input/Exit) é
        // repartida entre o bloco VOL/MUTE/CH (~42%) e o D-pad (o restante),
        // com limites para telas muito baixas ou muito altas. Mesmo arranjo
        // para qualquer aparelho; só somem as funções que ele não tem.
        final body = constraints.maxHeight - 16 - 52 - 3 * 12;
        final volumeHeight = (body * 0.42).clamp(130.0, 300.0);
        final dpadSize = (body - volumeHeight).clamp(150.0, 300.0);
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Navegação do Sistema: Home, Menu, Voltar, Exit
                const SystemNavigationControls(),

                const SizedBox(height: 12),

                // 2. Controles de Volume, Canal e Mudo (altura proporcional)
                VolumeChannelControls(height: volumeHeight),

                const SizedBox(height: 12),

                // 3. Roda D-Pad com HDMI 1 à esquerda e TV Digital à direita
                DPadWidget(size: dpadSize),

                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Aba 2: Teclas numéricas de canais e os demais botões já existentes
  Widget _buildTab2KeypadAndMedia() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Teclado Numérico
          const NumericKeypad(),

          const SizedBox(height: 16),

          // 2. Controles Multimídia (Play, Pause, Stop, Rewind, Fast Forward)
          const MultimediaControls(),

          const SizedBox(height: 14),

          // 3. Botões Coloridos WebOS (Vermelho, Verde, Amarelo, Azul)
          const ColorButtonsRow(),

          const SizedBox(height: 14),

          // Feedback da última ação discreto
        ],
      ),
    );
  }

  /// Aba 3: Magic Trackpad aproveitando ao MÁXIMO o tamanho da tela
  Widget _buildTab3Trackpad() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. O Trackpad ocupa TODO o espaço disponível
          const Expanded(child: TrackpadWidget()),

          const SizedBox(height: 12),

          // 2. Barra de Ações Rápidas no Rodapé do Trackpad para máxima agilidade
          Row(
            children: [
              Expanded(
                child: RemoteButton(
                  height: 50,
                  borderRadius: 14,
                  backgroundColor: AppColors.surfaceInteractiveOf(context),
                  foregroundColor: AppColors.textPrimaryOf(context),
                  icon: Icons.undo_rounded,
                  label: 'VOLTAR',
                  iconSize: 18,
                  tooltip: 'Voltar',
                  onPressed: () => context.read<RemoteController>().pressBack(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: RemoteButton(
                  height: 50,
                  borderRadius: 14,
                  backgroundColor: AppColors.iconHighlightOf(context)
                      .withValues(alpha: 0.22),
                  borderColor: AppColors.iconHighlightOf(context),
                  foregroundColor: AppColors.iconHighlightOf(context),
                  icon: Icons.mouse_rounded,
                  label: 'CLIQUE / OK',
                  iconSize: 20,
                  tooltip: 'Clique do Mouse / Confirmar',
                  onPressed: () =>
                      context.read<RemoteController>().sendTrackpadClick(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RemoteButton(
                  height: 50,
                  borderRadius: 14,
                  backgroundColor: AppColors.surfaceInteractiveOf(context),
                  foregroundColor: AppColors.textPrimaryOf(context),
                  icon: Icons.home_rounded,
                  label: 'HOME',
                  iconSize: 18,
                  tooltip: 'Página Inicial',
                  onPressed: () => context.read<RemoteController>().pressHome(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Barra de Navegação Inferior
  Widget _buildBottomTabBar() {
    final isDark = AppColors.isDark(context);
    final supportsTrackpad = context.watch<RemoteController>().supportsTrackpad;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        border: Border(
          top: BorderSide(color: AppColors.borderSubtleOf(context), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black38 : Colors.black12,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              _buildBottomNavItem(
                index: 0,
                title: 'Controle',
                icon: Icons.tv_rounded,
              ),
              _buildBottomNavItem(
                index: 1,
                title: 'Teclas & Mídia',
                icon: Icons.dialpad_rounded,
              ),
              if (supportsTrackpad)
                _buildBottomNavItem(
                  index: 2,
                  title: 'Magic Trackpad',
                  icon: Icons.touch_app_rounded,
                ),
              _buildBottomNavItem(
                index: 3,
                title: 'Biblioteca de mídia',
                icon: Icons.video_library_outlined,
              ),
              _buildBottomNavItem(
                index: 4,
                title: 'Apps',
                icon: Icons.apps_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required int index,
    required String title,
    required IconData icon,
  }) {
    final isSelected = _selectedTabIndex == index;
    final activeColor = AppColors.iconHighlightOf(context);
    final inactiveColor = AppColors.textSecondaryOf(context);

    return Expanded(
      child: InkWell(
        onTap: () {
          HapticService.selectionClick();
          setState(() => _selectedTabIndex = index);
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? activeColor : inactiveColor,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? activeColor : inactiveColor,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Estrutura física estilizada para coluna do controle no modo dual pane (Desktop)
  Widget _buildRemoteChassis() {
    final isDark = AppColors.isDark(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.remoteChassisOf(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.borderSubtleOf(context),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : Colors.black12,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Cabeçalho / Barra Superior
          HeaderBar(
            onToggleCompact: !kIsWeb && Platform.isWindows
                ? _toggleCompact
                : null,
            onOpenDrawer: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),

          const SizedBox(height: 6),

          // Barra de Seleção / Alternância Rápida de Aparelhos (Desktop)
          const DeviceSelectorBar(),

          const SizedBox(height: 10),

          // 2. Navegação do Sistema (Home, Menu, Back, Exit)
          const SystemNavigationControls(),

          const SizedBox(height: 12),

          // 3. Controles de Volume, Canal e Mudo
          const VolumeChannelControls(),

          const SizedBox(height: 14),

          // 4. D-Pad com HDMI 1 e TV Digital
          const DPadWidget(size: 195),

          const SizedBox(height: 14),

          // 5. Teclado Numérico
          const NumericKeypad(),

          const SizedBox(height: 12),

          // 6. Controles Multimídia
          const MultimediaControls(),

          const SizedBox(height: 12),

          // 7. Rodapé com Botões Coloridos
          const ColorButtonsRow(),
        ],
      ),
    );
  }

  /// Card dedicado de Magic Trackpad expandido (modo tela ampla)
  Widget _buildTrackpadExpandedCard() {
    final isDark = AppColors.isDark(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black12,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.mouse_rounded,
                color: AppColors.iconHighlightOf(context),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'LG Magic Pointer (Trackpad Virtual)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const TrackpadWidget(height: 260),
        ],
      ),
    );
  }

  /// Card dedicado para exibição e acionamento de aplicativos instalados no layout Desktop
  Widget _buildDesktopAppsCard() {
    final isDark = AppColors.isDark(context);

    return Container(
      height: 295,
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black12,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(24)),
        child: AppDrawerWidget(isEmbeddedInDesktop: true),
      ),
    );
  }

  /// Card informativo de atalhos de teclado desktop
  Widget _buildKeyboardShortcutsHelpCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.keyboard_outlined,
                color: AppColors.textSecondaryOf(context),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Atalhos de Teclado Físico (Desktop)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildShortcutRow('Setas (↑ ↓ ← →)', 'Navegar D-Pad'),
          _buildShortcutRow('Enter / Barra de Espaço', 'Confirmar (OK)'),
          _buildShortcutRow('Teclado Numérico (0-9)', 'Digitar Canais'),
          _buildShortcutRow('Vol + / Vol - / Mute', 'Controle de Áudio'),
          _buildShortcutRow('Backspace / Esc', 'Voltar (Back)'),
        ],
      ),
    );
  }

  Widget _buildShortcutRow(String keys, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceInteractiveOf(context),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderSubtleOf(context)),
            ),
            child: Text(
              keys,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11,
                color: AppColors.iconHighlightOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              description,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondaryOf(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
