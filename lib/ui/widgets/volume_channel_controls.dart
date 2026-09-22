import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../../services/haptic_service.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';
import 'voice_listening_dialog.dart';

/// Controles Verticais de Volume (+/-), Canal (+/-) e botão central de Mudo.
class VolumeChannelControls extends StatelessWidget {
  const VolumeChannelControls({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final isMuted = controller.isMuted;
    final volumeLevel = controller.volumeLevel;
    final currentChannel = controller.currentChannel;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Coluna Vertical de Volume (VOL)
        _buildVerticalRocker(
          context: context,
          title: 'VOL',
          valueDisplay: '$volumeLevel',
          onPlus: () => controller.volumeUp(),
          onMinus: () => controller.volumeDown(),
          plusTooltip: 'Aumentar Volume (+)',
          minusTooltip: 'Diminuir Volume (-)',
        ),

        // Coluna Central: Botão Mute e Botão de Microfone (Voz)
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RemoteButton(
              width: 50,
              height: 50,
              isCircular: true,
              backgroundColor: isMuted
                  ? AppColors.powerRed.withValues(alpha: 0.2)
                  : AppColors.surfaceInteractiveOf(context),
              borderColor: isMuted ? AppColors.powerRed : AppColors.borderSubtleOf(context),
              foregroundColor: isMuted ? AppColors.powerRed : AppColors.textPrimaryOf(context),
              icon: isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              iconSize: 22,
              tooltip: isMuted ? 'Desmutar Áudio' : 'Mutar Áudio',
              onPressed: () => controller.muteToggle(),
            ),
            const SizedBox(height: 3),
            Text(
              'MUTE',
              style: TextStyle(
                color: isMuted ? AppColors.powerRed : AppColors.textSecondaryOf(context),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            VoicePttButton(controller: controller),
            const SizedBox(height: 3),
            Text(
              'VOZ',
              style: TextStyle(
                color: AppColors.textSecondaryOf(context),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),

        // Coluna Vertical de Canal (CH)
        _buildVerticalRocker(
          context: context,
          title: 'CH',
          valueDisplay: 'CH $currentChannel',
          onPlus: () => controller.channelUp(),
          onMinus: () => controller.channelDown(),
          plusTooltip: 'Avançar Canal (+)',
          minusTooltip: 'Voltar Canal (-)',
        ),
      ],
    );
  }

  Widget _buildVerticalRocker({
    required BuildContext context,
    required String title,
    required String valueDisplay,
    required VoidCallback onPlus,
    required VoidCallback onMinus,
    required String plusTooltip,
    required String minusTooltip,
  }) {
    final isDark = AppColors.isDark(context);

    return Container(
      width: 58,
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black12,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botão Superior (+)
          RemoteButton(
            width: 54,
            height: 48,
            backgroundColor: Colors.transparent,
            borderColor: Colors.transparent,
            borderRadius: 24,
            icon: Icons.add_rounded,
            iconSize: 22,
            tooltip: plusTooltip,
            onPressed: onPlus,
          ),

          // Título central da coluna
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textSecondaryOf(context),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  valueDisplay,
                  style: TextStyle(
                    color: AppColors.iconHighlightOf(context),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Botão Inferior (-)
          RemoteButton(
            width: 54,
            height: 48,
            backgroundColor: Colors.transparent,
            borderColor: Colors.transparent,
            borderRadius: 24,
            icon: Icons.remove_rounded,
            iconSize: 22,
            tooltip: minusTooltip,
            onPressed: onMinus,
          ),
        ],
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

  const VoicePttButton({super.key, required this.controller});

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
            width: 50,
            height: 50,
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
                size: 22,
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

