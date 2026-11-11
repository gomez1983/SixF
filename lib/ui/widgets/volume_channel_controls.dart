import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../../services/haptic_service.dart';
import '../theme/app_colors.dart';
import 'payno.dart';
import 'remote_button.dart';
import 'voice_listening_dialog.dart';

/// Volume e Canal no padrão Payno: dois cards com o valor em destaque, barra
/// hachurada do volume, botões −/+ (com repetição ao segurar), Mudo e Voz.
class VolumeChannelControls extends StatelessWidget {
  /// Altura mínima de cada card. O card nunca fica menor que o conteúdo:
  /// se a fonte do sistema for maior, ele cresce em vez de estourar.
  final double? height;

  /// [Axis.horizontal]: cards lado a lado (celular). [Axis.vertical]: um
  /// sobre o outro (coluna do desktop).
  final Axis axis;

  const VolumeChannelControls({
    super.key,
    this.height,
    this.axis = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final isMuted = controller.isMuted;
    final volumeLevel = controller.volumeLevel;
    final repeat = controller.isConnected;
    // Mesmo diâmetro dos círculos de "Ações rápidas" (HOME, MENU...).
    const circle = 48.0;
    final token = controller.driver;

    // −/+ e ∨/∧ no mesmo padrão dos círculos de "Ações rápidas": fundo
    // branco com sombra suave, ícone escuro.
    Widget step(IconData icon, String tooltip, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 10),
      child: RemoteButton(
        width: 44,
        height: 44,
        isCircular: true,
        foregroundColor: AppColors.textPrimaryOf(context),
        icon: icon,
        iconSize: 22,
        tooltip: tooltip,
        onPressed: onTap,
        repeatOnHold: repeat,
        repeatToken: token,
      ),
    );

    Widget card({
      required IconData icon,
      required String title,
      required Widget action,
      required Widget value,
      required Widget middle,
      required List<Widget> buttons,
    }) {
      // Altura sempre >= conteúdo (IntrinsicHeight + minHeight): o espaço
      // extra fica entre o valor e os botões, nunca falta.
      return IntrinsicHeight(
        child: Container(
          constraints: BoxConstraints(minHeight: height ?? 0),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: AppColors.paynoCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PaynoCardHeader(icon: icon, title: title, trailing: action),
              const SizedBox(height: 8),
              value,
              const SizedBox(height: 10),
              middle,
              const Spacer(),
              const SizedBox(height: 12),
              Row(children: buttons),
            ],
          ),
        ),
      );
    }

    final volumeCard = card(
      icon: Icons.volume_up_outlined,
      title: 'VOL',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RemoteButton(
            width: circle,
            height: circle,
            isCircular: true,
            backgroundColor: isMuted
                ? AppColors.powerRed.withValues(alpha: 0.16)
                : null,
            foregroundColor: isMuted
                ? AppColors.powerRed
                : AppColors.textMutedOf(context),
            icon: isMuted ? Icons.volume_off_rounded : Icons.volume_off_outlined,
            iconSize: circle * 0.42,
            tooltip: isMuted ? 'Desmutar Áudio' : 'Mutar Áudio',
            onPressed: () => controller.muteToggle(),
          ),
        ],
      ),
      value: PaynoBigValue(
        '$volumeLevel',
        unit: isMuted ? 'MUTE' : '/100',
        size: 36,
      ),
      middle: PaynoHatchedBar(value: volumeLevel / 100, height: 8),
      buttons: [
        step(Icons.remove_rounded, 'Diminuir Volume (-)', controller.volumeDown),
        step(Icons.add_rounded, 'Aumentar Volume (+)', controller.volumeUp),
      ],
    );

    final channelCard = card(
      icon: Icons.tv_outlined,
      title: 'CH',
      action: VoicePttButton(
        controller: controller,
        size: circle,
        builder: (context, pressed, locked) => Container(
          width: circle,
          height: circle,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accentFillOf(context),
            boxShadow: pressed || locked
                ? [
                    BoxShadow(
                      color: AppColors.accentFillOf(context).withValues(alpha: 0.55),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            locked ? Icons.lock_open_rounded : Icons.mic_rounded,
            size: circle * 0.42,
            color: Colors.white,
          ),
        ),
      ),
      value: PaynoBigValue('${controller.currentChannel}', unit: 'Canal', size: 36),
      middle: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Segure '),
            TextSpan(
              text: 'VOZ',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const TextSpan(text: ' para falar'),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, color: AppColors.textMutedOf(context)),
      ),
      buttons: [
        step(Icons.keyboard_arrow_down_rounded, 'Voltar Canal (-)', controller.channelDown),
        step(Icons.keyboard_arrow_up_rounded, 'Avançar Canal (+)', controller.channelUp),
      ],
    );

    if (axis == Axis.vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [volumeCard, const SizedBox(height: 14), channelCard],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: volumeCard),
          const SizedBox(width: 12),
          Expanded(child: channelCard),
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

