import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../../services/haptic_service.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';
import 'voice_listening_dialog.dart';

/// Volume e Canal em duas "pílulas" altas com botões grandes (como nas
/// primeiras versões do app): volume à esquerda (+ / valor / −) e canal à
/// direita (∧ / número / ∨). Entre elas, Mudo em cima e Microfone embaixo.
///
/// Não desenha card próprio: fica dentro do card único da aba Controle, junto
/// com o D-pad. Se a largura for menor que o conjunto, tudo encolhe junto.
class VolumeChannelControls extends StatelessWidget {
  /// Altura das pílulas. Os botões grandes acompanham a largura.
  final double height;

  const VolumeChannelControls({super.key, this.height = 210});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final isMuted = controller.isMuted;
    final repeat = controller.isConnected;
    final token = controller.driver;

    final pillHeight = height.clamp(132.0, 260.0).toDouble();
    // Pílula mais baixa → mais estreita, para os dois botões e o valor
    // continuarem cabendo.
    final pillWidth = (pillHeight * 0.41).clamp(64.0, 90.0).toDouble();
    final big = pillWidth - 16;
    final round = (pillHeight * 0.26).clamp(42.0, 56.0).toDouble();

    Widget bigButton(IconData icon, String tooltip, VoidCallback onTap) =>
        RemoteButton(
          width: big,
          height: big,
          isCircular: true,
          foregroundColor: AppColors.textPrimaryOf(context),
          icon: icon,
          iconSize: big * 0.5,
          tooltip: tooltip,
          onPressed: onTap,
          repeatOnHold: repeat,
          repeatToken: token,
        );

    Widget pill({
      required Key key,
      required String caption,
      required String value,
      required Color valueColor,
      required Widget up,
      required Widget down,
    }) => Container(
      key: key,
      width: pillWidth,
      height: pillHeight,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceInteractiveOf(context),
        borderRadius: BorderRadius.circular(pillWidth / 2),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          up,
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.05,
                      fontWeight: FontWeight.w600,
                      color: valueColor,
                    ),
                  ),
                  Text(
                    caption,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMutedOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          down,
        ],
      ),
    );

    final volumePill = pill(
      key: const Key('volume-pill'),
      caption: 'VOL',
      value: '${controller.volumeLevel}',
      valueColor: isMuted
          ? AppColors.powerRed
          : AppColors.textPrimaryOf(context),
      up: bigButton(
        Icons.add_rounded,
        'Aumentar Volume (+)',
        controller.volumeUp,
      ),
      down: bigButton(
        Icons.remove_rounded,
        'Diminuir Volume (-)',
        controller.volumeDown,
      ),
    );

    final channelPill = pill(
      key: const Key('channel-pill'),
      caption: 'CH',
      value: '${controller.currentChannel}',
      valueColor: AppColors.textPrimaryOf(context),
      up: bigButton(
        Icons.keyboard_arrow_up_rounded,
        'Avançar Canal (+)',
        controller.channelUp,
      ),
      down: bigButton(
        Icons.keyboard_arrow_down_rounded,
        'Voltar Canal (-)',
        controller.channelDown,
      ),
    );

    final mute = RemoteButton(
      width: round,
      height: round,
      isCircular: true,
      backgroundColor: isMuted
          ? AppColors.powerRed.withValues(alpha: 0.16)
          : null,
      foregroundColor: isMuted
          ? AppColors.powerRed
          : AppColors.textMutedOf(context),
      icon: isMuted ? Icons.volume_off_rounded : Icons.volume_off_outlined,
      iconSize: round * 0.44,
      tooltip: isMuted ? 'Desmutar Áudio' : 'Mutar Áudio',
      onPressed: () => controller.muteToggle(),
    );

    final mic = VoicePttButton(
      controller: controller,
      size: round,
      builder: (context, pressed, locked) => Container(
        width: round,
        height: round,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accentFillOf(context),
          boxShadow: pressed || locked
              ? [
                  BoxShadow(
                    color: AppColors.accentFillOf(
                      context,
                    ).withValues(alpha: 0.55),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Icon(
          locked ? Icons.lock_open_rounded : Icons.mic_rounded,
          size: round * 0.44,
          color: AppColors.onAccentOf(context),
        ),
      ),
    );

    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            volumePill,
            const SizedBox(width: 22),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                mute,
                SizedBox(height: (pillHeight * 0.12).clamp(12.0, 26.0)),
                mic,
              ],
            ),
            const SizedBox(width: 22),
            channelPill,
          ],
        ),
      ),
    );
  }
}

/// Botão dedicado de microfone com suporte a Push-to-Talk (PTT).
///
/// Ao pressionar: vibração mecânica pesada e abertura do popup animado.
/// Ao soltar: vibração mecânica de desengate e fechamento instantâneo.
class VoicePttButton extends StatefulWidget {
  final RemoteController controller;
  final double size;

  /// Visual alternativo (ex.: Liquid Glass). A lógica de Push-to-Talk, travamento
  /// e vibração é a mesma; só o desenho do botão muda.
  final Widget Function(BuildContext context, bool isPressed, bool isLocked)?
  builder;

  const VoicePttButton({
    super.key,
    required this.controller,
    this.size = 50,
    this.builder,
  });

  @override
  State<VoicePttButton> createState() => _VoicePttButtonState();
}

class _VoicePttButtonState extends State<VoicePttButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  bool _isLocked = false;
  Offset? _downPosition;
  late final AnimationController _scaleController;

  static const double _lockDragThreshold = 30.0;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      lowerBound: 0.88,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_isPressed) return;
    setState(() {
      _isPressed = true;
      _isLocked = false;
      _downPosition = event.position;
    });
    _scaleController.reverse();

    // 1. Vibração forte de acionamento mecânico (sensação física ao pressionar)
    HapticService.voicePress();

    // 2. Dispara o sinal de voz para a TV
    widget.controller.triggerVoice();

    // 3. Exibe o overlay de escuta Push-to-Talk
    VoiceListeningOverlay.show(context);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isPressed || _isLocked || _downPosition == null) return;

    final delta = event.position - _downPosition!;
    // Deslizar para os lados ou para cima ativa a trava do modo mãos livres
    if (delta.dx.abs() >= _lockDragThreshold || delta.dy <= -_lockDragThreshold) {
      setState(() {
        _isLocked = true;
      });

      // Vibração mecânica tátil de travamento da trava
      HapticService.voiceLock();

      // Sinaliza ao overlay que o modo mãos livres foi ativado
      VoiceListeningOverlay.lock();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _handleRelease();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _handleRelease();
  }

  void _handleRelease() {
    if (!_isPressed) return;
    _scaleController.forward();

    if (_isLocked) {
      // O usuário travou no modo Mãos Livres:
      // Libera o estado do botão físico, mas MANTÉM o overlay ativo na tela.
      setState(() {
        _isPressed = false;
        _isLocked = false;
        _downPosition = null;
      });
      // Emite clique sutil de liberação do dedo
      HapticService.selectionClick();
    } else {
      // Push-to-Talk padrão (não arrastou para travar): fecha na hora
      setState(() {
        _isPressed = false;
        _isLocked = false;
        _downPosition = null;
      });
      HapticService.voiceRelease();
      VoiceListeningOverlay.onPttRelease();
    }
  }

  @override
  Widget build(BuildContext context) {
    final highlightColor = AppColors.iconHighlightOf(context);
    final isPressed = _isPressed;
    final isLocked = _isLocked;

    if (widget.builder != null) {
      return Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Tooltip(
          message: 'Comando de Voz (Segure para falar • Deslize para travar 🔒)',
          child: AnimatedBuilder(
            animation: _scaleController,
            builder: (context, child) =>
                Transform.scale(scale: _scaleController.value, child: child),
            child: widget.builder!(context, isPressed, isLocked),
          ),
        ),
      );
    }

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Tooltip(
        message: 'Comando de Voz (Segure para falar • Deslize para travar 🔒)',
        child: AnimatedBuilder(
          animation: _scaleController,
          builder: (context, child) => Transform.scale(
            scale: _scaleController.value,
            child: child,
          ),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPressed
                  ? highlightColor.withValues(alpha: 0.25)
                  : AppColors.surfaceInteractiveOf(context),
              border: Border.all(
                color: (isPressed || isLocked)
                    ? highlightColor
                    : AppColors.borderSubtleOf(context),
                width: (isPressed || isLocked) ? 2.0 : 1.0,
              ),
              boxShadow: (isPressed || isLocked)
                  ? [
                      BoxShadow(
                        color: highlightColor.withValues(alpha: 0.5),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Icon(
                isLocked ? Icons.lock_open_rounded : Icons.mic_rounded,
                size: widget.size * 0.44,
                color: (isPressed || isLocked)
                    ? highlightColor
                    : AppColors.iconHighlightOf(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

