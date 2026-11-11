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
import '../glass/glass_control_body.dart';
import '../glass/glass_flags.dart';
import '../glass/glass_remote_shell.dart';
import '../glass/liquid_glass.dart' show GlassBackdrop;
import '../theme/app_colors.dart';
import '../widgets/active_device_card.dart';
import '../widgets/app_drawer_widget.dart';
import '../widgets/color_buttons_row.dart';
import '../widgets/device_discovery_dialog.dart';
import '../widgets/device_selector_bar.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/header_bar.dart';
import '../widgets/multimedia_controls.dart';
import '../widgets/network_drawer.dart';
import '../widgets/numeric_keypad.dart';
import '../widgets/payno.dart';
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
        body: _withGlassBackdrop(
          SafeArea(
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
                    : isWideScreen && !kGlassUi
                    ? _buildDesktopShell()
                    : _buildMobileTabLayout(constraints),
              );
            },
          ),
        ),
        ),
      ),
    );
  }

  /// No modo Liquid Glass todos os layouts (largo, paisagem, compacto) ficam
  /// sobre o fundo ambiente, que é o que dá sentido ao vidro.
  Widget _withGlassBackdrop(Widget child) => Stack(
    fit: StackFit.expand,
    children: [
      kGlassUi ? const GlassBackdrop() : const PaynoBackdrop(),
      child,
    ],
  );

  /// Desktop / tablet largo (padrão Payno): trilho de ícones à esquerda,
  /// cabeçalho e aparelhos no topo, título da aba e o conteúdo em cards.
  Widget _buildDesktopShell() {
    final controller = context.watch<RemoteController>();
    const titles = ['Controle', 'Teclas', 'Trackpad', 'Mídia', 'Apps'];
    Widget? action;
    if (_selectedTabIndex == 0) {
      action = _navyPill(
        Icons.cast_rounded,
        'Buscar TVs',
        () => DeviceDiscoveryDialog.show(context),
      );
    } else if (_selectedTabIndex == 4 && controller.isConnected) {
      action = _navyPill(
        Icons.refresh_rounded,
        'Recarregar aplicativos',
        controller.isLoadingApps
            ? null
            : () => controller.fetchInstalledApps(forceRefresh: true),
      );
    }
    return Row(
      children: [
        _buildSideNavRail(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HeaderBar(
                  onToggleCompact: !kIsWeb && Platform.isWindows
                      ? _toggleCompact
                      : null,
                  onOpenDrawer: () =>
                      _scaffoldKey.currentState?.openEndDrawer(),
                ),
                SizedBox(
                  height: 60,
                  child: Row(
                    children: [
                      Text(
                        titles[_selectedTabIndex],
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          letterSpacing: -0.2,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Aparelhos salvos (pílulas) ao lado do título
                      const Expanded(child: DeviceSelectorBar()),
                      if (action != null) ...[const SizedBox(width: 12), action],
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTabIndex,
                    children: [
                      _buildDesktopControl(),
                      _buildDesktopKeys(),
                      controller.supportsTrackpad
                          ? _buildTab3Trackpad()
                          : const SizedBox.shrink(),
                      _materialCard(
                        MediaLibrary(key: _libraryKey, embedded: true),
                      ),
                      _buildDesktopApps(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Card Payno feito de [Material], para listas (ListTile) e efeitos de
  /// toque do conteúdo continuarem visíveis sobre o fundo do card.
  Widget _materialCard(Widget child) {
    final dark = AppColors.isDark(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadowOf(context),
      ),
      child: Material(
        color: AppColors.cardOf(context),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: dark ? const Color(0x10FFFFFF) : const Color(0xE6FFFFFF),
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _navyPill(IconData icon, String label, VoidCallback? onTap) {
    return Material(
      color: AppColors.accentFillOf(context),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Grade do desktop; rola quando a janela é baixa demais para os cards.
  Widget _desktopGrid(List<(int, Widget)> columns, {double minHeight = 600}) {
    return LayoutBuilder(
      builder: (context, box) {
        final grid = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(flex: columns[i].$1, child: columns[i].$2),
            ],
          ],
        );
        if (box.maxHeight >= minHeight) return grid;
        return SingleChildScrollView(
          child: SizedBox(height: minHeight, child: grid),
        );
      },
    );
  }

  /// Coluna de cards que nunca estoura: ocupa a altura disponível e, se o
  /// conteúdo for maior (janela baixa, fonte do sistema ampliada), rola.
  Widget _scrollColumn(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopControl() {
    return _desktopGrid([
      (
        10,
        LayoutBuilder(
          builder: (context, box) {
            // Volume e Canal dividem a altura que sobra das Ações rápidas;
            // a altura é só mínima — com mais conteúdo, o card cresce.
            const quick = 160.0;
            final card = ((box.maxHeight - quick - 28) / 2).clamp(0.0, 260.0);
            return _scrollColumn([
              VolumeChannelControls(axis: Axis.vertical, height: card),
              const SizedBox(height: 14),
              const PaynoCard(
                title: 'Ações rápidas',
                child: SystemNavigationControls(),
              ),
            ]);
          },
        ),
      ),
      (11, _buildNavigationCard(maxWheel: 300)),
      (
        10,
        _scrollColumn([
          const ActiveDeviceCard(),
          const SizedBox(height: 14),
          _buildKeyboardShortcutsHelpCard(),
        ]),
      ),
    ]);
  }

  /// Card "Navegação" com o D-pad do tamanho que couber (nunca estoura: em
  /// espaço pequeno a roda encolhe junto com os botões laterais).
  Widget _buildNavigationCard({
    double maxWheel = 300,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  }) {
    return PaynoCard(
      title: 'Navegação',
      padding: padding,
      trailing: Text(
        'D-pad',
        style: TextStyle(fontSize: 11, color: AppColors.textMutedOf(context)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final wheel = box.maxHeight.isFinite
              ? (box.maxHeight - 8).clamp(130.0, maxWheel).toDouble()
              : maxWheel;
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: box.maxWidth.isFinite ? box.maxWidth : null,
                child: DPadWidget(size: wheel),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDesktopKeys() {
    final controller = context.watch<RemoteController>();
    return _desktopGrid([
      (
        10,
        PaynoCard(
          title: 'Digitar canal',
          icon: Icons.dialpad_rounded,
          trailing: PaynoChip('CH ${controller.currentChannel}', accent: true),
          child: LayoutBuilder(
            builder: (context, box) {
              // Teclas ocupam a altura do card; se faltar espaço, rola.
              final keyHeight = ((box.maxHeight - 150) / 4).clamp(40.0, 76.0);
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Canal atual',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMutedOf(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    PaynoBigValue('${controller.currentChannel}', size: 50),
                    const SizedBox(height: 6),
                    Text(
                      'Use — para subcanal · 0–9 no teclado',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMutedOf(context),
                      ),
                    ),
                    const SizedBox(height: 18),
                    NumericKeypad(keyHeight: keyHeight),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      (
        11,
        _scrollColumn(const [
          PaynoCard(
            title: 'Controles multimídia',
            icon: Icons.movie_outlined,
            child: MultimediaControls(),
          ),
          SizedBox(height: 14),
          PaynoCard(
            title: 'Botões coloridos',
            icon: Icons.palette_outlined,
            child: ColorButtonsRow(columns: 2),
          ),
        ]),
      ),
      (10, _scrollColumn(const [VolumeChannelControls(axis: Axis.vertical)])),
    ]);
  }

  Widget _buildDesktopApps() {
    return _desktopGrid([
      (26, _materialCard(const AppDrawerWidget(isInCard: true))),
      (10, _scrollColumn(const [ActiveDeviceCard()])),
    ], minHeight: 480);
  }

  /// Layout em 4 Abas Responsivo para Mobile (Galaxy S23 Ultra e telas verticais):
  /// Aproveita 100% da largura e altura da tela sem compressão ou caixas fixas.
  Widget _buildMobileTabLayout(BoxConstraints constraints) {
    // Experimental (--dart-define=SIXF_GLASS_UI=true): mesma navegação e mesmas
    // abas, com moldura e aba Controle no estilo Liquid Glass.
    if (kGlassUi) {
      return GlassRemoteShell(
        selectedTab: _selectedTabIndex,
        onSelectTab: (i) {
          HapticService.selectionClick();
          setState(() => _selectedTabIndex = i);
        },
        onOpenDrawer: () => _scaffoldKey.currentState?.openEndDrawer(),
        onToggleCompact: !kIsWeb && Platform.isWindows ? _toggleCompact : null,
        body: IndexedStack(
          index: _selectedTabIndex,
          children: [
            const GlassControlBody(),
            _buildTab2KeypadAndMedia(),
            context.watch<RemoteController>().supportsTrackpad
                ? _buildTab3Trackpad()
                : const SizedBox.shrink(),
            MediaLibrary(key: _libraryKey, embedded: true),
            const AppDrawerWidget(),
          ],
        ),
      );
    }
    return Column(
      children: [
        // 1. Cabeçalho (logotipo, aparelho ativo e ações em círculos)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: HeaderBar(
            onToggleCompact: !kIsWeb && Platform.isWindows
                ? _toggleCompact
                : null,
            onOpenDrawer: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ),

        // Aparelhos salvos (pílulas)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: DeviceSelectorBar(),
        ),

        // 2. Conteúdo das abas
        Expanded(
          child: IndexedStack(
            index: _selectedTabIndex,
            children: [
              _buildTab1Control(),
              _buildTab2KeypadAndMedia(),
              context.watch<RemoteController>().supportsTrackpad
                  ? _buildTab3Trackpad()
                  : const SizedBox.shrink(),
              MediaLibrary(key: _libraryKey, embedded: true),
              const AppDrawerWidget(),
            ],
          ),
        ),

        // 3. Barra de navegação flutuante (pílula)
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

  /// Itens de navegação (mesma ordem no trilho lateral e na barra inferior).
  List<({int index, String title, IconData icon})> _navItems() {
    final supportsTrackpad = context.watch<RemoteController>().supportsTrackpad;
    return [
      // Ordem exibida: Controle, Mídia, (Trackpad na LG), Teclas, Apps.
      // O índice é o do conteúdo no IndexedStack, que não muda.
      (index: 0, title: 'Controle', icon: Icons.tv_rounded),
      (index: 3, title: 'Mídia', icon: Icons.video_library_outlined),
      if (supportsTrackpad)
        (index: 2, title: 'Trackpad', icon: Icons.near_me_outlined),
      (index: 1, title: 'Teclas', icon: Icons.dialpad_rounded),
      (index: 4, title: 'Apps', icon: Icons.grid_view_rounded),
    ];
  }

  void _selectTab(int index) {
    HapticService.selectionClick();
    setState(() => _selectedTabIndex = index);
  }

  /// Trilho lateral (paisagem e desktop) no padrão Payno: círculos com o
  /// rótulo abaixo; a aba ativa fica em azul-marinho sólido.
  Widget _buildSideNavRail() {
    final items = _navItems();
    return SizedBox(
      width: 84,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Tooltip(
                    message: item.title,
                    child: InkWell(
                      key: ValueKey('nav-${item.index}'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _selectTab(item.index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _navCircle(item.icon, _selectedTabIndex == item.index, 42),
                            const SizedBox(height: 4),
                            _navLabel(item.title, _selectedTabIndex == item.index),
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

  Widget _navCircle(IconData icon, bool active, double size) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.accentFillOf(context) : AppColors.circleOf(context),
        border: Border.all(
          color: active ? Colors.transparent : AppColors.borderSubtleOf(context),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.accentFillOf(context).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : AppColors.softShadowOf(context),
      ),
      child: Icon(
        icon,
        size: size * 0.44,
        color: active ? Colors.white : AppColors.textMutedOf(context),
      ),
    );
  }

  Widget _navLabel(String title, bool active) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: const TextScaler.linear(1.0),
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
        color: active
            ? AppColors.iconHighlightOf(context)
            : AppColors.textSecondaryOf(context),
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
                    const SizedBox(height: 14),
                    const PaynoCard(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: SystemNavigationControls(circleSize: 42),
                    ),
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

  /// Aba Controle (retrato), em cards: Ações rápidas (HOME/MENU/INPUT/EXIT),
  /// Volume e Canal, e Navegação (D-pad com VOLTAR, TV Digital e HDMI 1 — as
  /// entradas só aparecem nos aparelhos que as têm).
  Widget _buildTab1Control() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        // Ações rápidas e Volume/Canal têm a altura do próprio conteúdo; o
        // card de Navegação fica com o resto (mínimo de 220 px — abaixo
        // disso a aba rola, nunca estoura).
        const quick = 132.0;
        const volume = 196.0;
        final h = constraints.maxHeight - 16;
        final navHeight = (h - quick - volume - 2 * gap).clamp(220.0, 440.0);
        final wheel = (navHeight - 60).clamp(140.0, 300.0);
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PaynoCard(
                title: 'Ações rápidas',
                padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: SystemNavigationControls(),
              ),
              const SizedBox(height: gap),
              const VolumeChannelControls(),
              const SizedBox(height: gap),
              SizedBox(
                height: navHeight,
                child: _buildNavigationCard(
                  maxWheel: wheel,
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Aba Teclas: teclado numérico, controles multimídia e botões coloridos.
  Widget _buildTab2KeypadAndMedia() {
    final controller = context.watch<RemoteController>();
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaynoCard(
            title: 'Digitar canal',
            trailing: PaynoChip(
              'Canal ${controller.currentChannel}',
              accent: true,
            ),
            child: const NumericKeypad(keyHeight: 46),
          ),
          const SizedBox(height: 12),
          const PaynoCard(
            title: 'Controles multimídia',
            child: MultimediaControls(),
          ),
          const SizedBox(height: 12),
          const PaynoCard(
            title: 'Botões coloridos',
            child: ColorButtonsRow(columns: 2),
          ),
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

  /// Barra de navegação inferior: pílula flutuante no padrão Payno, com a
  /// aba ativa em azul-marinho.
  Widget _buildBottomTabBar() {
    final supportsTrackpad = context.watch<RemoteController>().supportsTrackpad;

    // Modo Liquid Glass: barra flutuante de vidro.
    if (kGlassUi) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: GlassTabBar(
            items: glassTabItems(supportsTrackpad: supportsTrackpad),
            selected: _selectedTabIndex,
            onSelect: _selectTab,
          ),
        ),
      );
    }

    final items = _navItems();
    final dark = AppColors.isDark(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: dark ? const Color(0xF21A2232) : const Color(0xF2FFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: dark ? const Color(0x14FFFFFF) : const Color(0xE6FFFFFF),
            ),
            boxShadow: [
              BoxShadow(
                color: dark ? const Color(0x66000000) : const Color(0x1F1E2D50),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: InkWell(
                    key: ValueKey('nav-${item.index}'),
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _selectTab(item.index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _selectedTabIndex == item.index ? 46 : 34,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _selectedTabIndex == item.index
                                ? AppColors.accentFillOf(context)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Icon(
                            item.icon,
                            size: 18,
                            color: _selectedTabIndex == item.index
                                ? Colors.white
                                : AppColors.textMutedOf(context),
                          ),
                        ),
                        const SizedBox(height: 3),
                        _navLabel(item.title, _selectedTabIndex == item.index),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Card de atalhos do teclado físico (desktop), no padrão de lista Payno.
  Widget _buildKeyboardShortcutsHelpCard() {
    return PaynoCard(
      title: 'Atalhos do teclado físico',
      icon: Icons.keyboard_outlined,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildShortcutRow('Setas ↑ ↓ ← →', 'Navegar D-Pad'),
          _buildShortcutRow('Enter / Espaço', 'Confirmar (OK)'),
          _buildShortcutRow('0 – 9', 'Digitar Canais'),
          _buildShortcutRow('+ / − / M', 'Controle de Áudio'),
          _buildShortcutRow('Backspace / Esc', 'Voltar (Back)'),
        ],
      ),
    );
  }

  Widget _buildShortcutRow(String keys, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceInteractiveOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.circleOf(context),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.borderSubtleOf(context)),
            ),
            child: Text(
              keys,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

}
