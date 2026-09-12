import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/color_buttons_row.dart';
import '../widgets/dpad_widget.dart';
import '../widgets/header_bar.dart';
import '../widgets/multimedia_controls.dart';
import '../widgets/network_drawer.dart';
import '../widgets/numeric_keypad.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FocusNode _focusNode = FocusNode();
  int _directionalModeIndex = 0; // 0: D-Pad, 1: Magic Trackpad

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Trata teclas do teclado físico do Windows
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // Se o aplicativo não estiver em foco ou se um campo de texto estiver focado, ignora completamente
    if (!node.hasFocus) {
      return KeyEventResult.ignored;
    }

    final primaryFocusWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (primaryFocusWidget is EditableText) {
      return KeyEventResult.ignored;
    }

    final controller = context.read<RemoteController>();
    final key = event.logicalKey;

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
    if (key == LogicalKeyboardKey.mediaPlay || key == LogicalKeyboardKey.mediaPlayPause) {
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
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.escape) {
      controller.pressBack();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
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

              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: isWideScreen
                    ? _buildDualPaneLayout(constraints)
                    : _buildSingleChassisLayout(constraints),
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
                SizedBox(
                  width: 400,
                  child: _buildRemoteChassis(showTrackpadInChassis: false),
                ),

                const SizedBox(width: 20),

                // Coluna 2: Painel Magic Remote & Telemetria
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTrackpadExpandedCard(),
                      const SizedBox(height: 14),
                      _buildConsoleFeedbackCard(),
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

  /// Layout para formato de controle clássico:
  /// Utiliza FittedBox para que o controle SEMPRE caiba 100% na altura e largura
  /// da janela sem precisar de barra de rolagem.
  Widget _buildSingleChassisLayout(BoxConstraints constraints) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRemoteChassis(showTrackpadInChassis: true),
                const SizedBox(height: 8),
                _buildConsoleFeedbackCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Estrutura física estilizada do controle remoto
  Widget _buildRemoteChassis({required bool showTrackpadInChassis}) {
    final isDark = AppColors.isDark(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.remoteChassisOf(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.borderSubtleOf(context), width: 1.5),
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
            onOpenDrawer: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),

          const SizedBox(height: 12),

          // 2. Navegação do Sistema (Home, Menu, Back, Exit)
          const SystemNavigationControls(),

          const SizedBox(height: 12),

          // 3. Controles de Volume, Canal e Mudo
          const VolumeChannelControls(),

          const SizedBox(height: 14),

          // 4. Seletor Direcional / Magic Remote (se em modo de chassi único)
          if (showTrackpadInChassis) ...[
            _buildModeSelector(),
            const SizedBox(height: 12),
            AnimatedCrossFade(
              firstChild: const DPadWidget(size: 190),
              secondChild: const TrackpadWidget(height: 190),
              crossFadeState: _directionalModeIndex == 0
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 250),
            ),
          ] else ...[
            // Em modo dual pane, o D-Pad fica sempre visível no chassi
            const DPadWidget(size: 195),
          ],

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

  /// Alternador entre D-Pad Clássico e Magic Trackpad
  Widget _buildModeSelector() {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSelectorTab(
              title: 'D-Pad',
              icon: Icons.gamepad_rounded,
              isSelected: _directionalModeIndex == 0,
              onTap: () => setState(() => _directionalModeIndex = 0),
            ),
          ),
          Expanded(
            child: _buildSelectorTab(
              title: 'Magic Trackpad',
              icon: Icons.touch_app_rounded,
              isSelected: _directionalModeIndex == 1,
              onTap: () => setState(() => _directionalModeIndex = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorTab({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceElevatedOf(context) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: AppColors.borderActiveOf(context), width: 1)
              : null,
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? AppColors.iconHighlightOf(context)
                    : AppColors.textSecondaryOf(context),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.textPrimaryOf(context)
                      : AppColors.textMutedOf(context),
                ),
              ),
            ],
          ),
        ),
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
              Icon(Icons.mouse_rounded, color: AppColors.iconHighlightOf(context), size: 20),
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

  /// Card que exibe o último comando registrado no console com animação
  Widget _buildConsoleFeedbackCard() {
    final controller = context.watch<RemoteController>();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevatedOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.terminal_rounded,
                size: 16, color: AppColors.iconHighlightOf(context)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ÚLTIMO COMANDO EXECUTADO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: AppColors.textMutedOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  controller.lastActionMessage,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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
              Icon(Icons.keyboard_outlined, color: AppColors.textSecondaryOf(context), size: 18),
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
