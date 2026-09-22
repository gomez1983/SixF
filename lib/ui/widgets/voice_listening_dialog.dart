import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_driver.dart';
import '../../services/haptic_service.dart';
import '../../services/voice_service.dart';
import '../theme/app_colors.dart';

/// Modal animado que sinaliza visualmente a escuta ativa de comando de voz,
/// exibe a transcrição em tempo real, permite edição via teclado e injeção na TV.
///
/// Suporta:
/// - Push-to-Talk (Pressione e Segure para falar).
/// - Slide-to-Lock (Deslize para travar no modo Mãos Livres 🔒).
/// - Entrada de texto manual com teclado virtual do celular ou PC.
/// - Comandos inteligentes de controle (Volume 5x, Apps, Mudo, Power).
/// - Seletor rápido de idiomas (🇧🇷 PT / 🇺🇸 EN).
/// - Envio de texto sem auto-enter para conferência prévia na tela da TV.
class VoiceListeningDialog extends StatefulWidget {
  final Duration timeoutDuration;
  final bool isPushToTalk;
  final bool isLocked;
  final VoidCallback? onClose;

  const VoiceListeningDialog({
    super.key,
    this.timeoutDuration = const Duration(seconds: 14),
    this.isPushToTalk = false,
    this.isLocked = false,
    this.onClose,
  });

  static Future<void> show(
    BuildContext context, {
    Duration timeoutDuration = const Duration(seconds: 14),
    bool isPushToTalk = false,
    bool isLocked = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => VoiceListeningDialog(
        timeoutDuration: timeoutDuration,
        isPushToTalk: isPushToTalk,
        isLocked: isLocked,
      ),
    );
  }

  @override
  State<VoiceListeningDialog> createState() => _VoiceListeningDialogState();
}

class _VoiceListeningDialogState extends State<VoiceListeningDialog>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _waveController;
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  Timer? _dismissTimer;
  Timer? _progressTimer;
  double _progress = 1.0;
  final int _progressIntervalMs = 50;

  VoiceIntent? _classifiedIntent;
  String _selectedLocale = 'pt_BR';
  bool _isMicListening = false;
  String? _executionFeedback;

  @override
  void initState() {
    super.initState();
    VoiceListeningOverlay.onPttReleaseCallback = handlePttRelease;

    _textController = TextEditingController();
    _focusNode = FocusNode();
    _textController.addListener(_onTextChanged);

    // Animação dos anéis pulsantes de áudio
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    // Animação das barras do equalizador de voz
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Timer de progresso decrescente da janela de escuta
    final totalMs = widget.timeoutDuration.inMilliseconds;
    var elapsedMs = 0;
    _progressTimer = Timer.periodic(
      Duration(milliseconds: _progressIntervalMs),
      (timer) {
        elapsedMs += _progressIntervalMs;
        if (mounted) {
          setState(() {
            _progress = (1.0 - (elapsedMs / totalMs)).clamp(0.0, 1.0);
          });
        }
      },
    );

    // Auto-fechamento do popup ao término da janela (se não estiver travado)
    if (!widget.isLocked) {
      _dismissTimer = Timer(widget.timeoutDuration, () {
        _close();
      });
    }

    // Inicialização assíncrona do microfone
    _startAudioCapture();
  }

  void _startAudioCapture() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = Provider.of<RemoteController>(context, listen: false);

      final ok = await controller.voiceService.startListening(
        localeId: _selectedLocale,
        onResult: (words) {
          if (!mounted) return;
          setState(() {
            _textController.text = words;
            _textController.selection = TextSelection.fromPosition(
              TextPosition(offset: words.length),
            );
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _isMicListening = false;
          });
        },
      );

      if (mounted) {
        setState(() {
          _isMicListening = ok;
        });
      }
    });
  }

  void _stopListeningAudio() {
    try {
      final controller = Provider.of<RemoteController>(context, listen: false);
      controller.voiceService.stopListening();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isMicListening = false;
      });
    }
  }

  void _onTextChanged() {
    final text = _textController.text;
    if (!mounted) return;
    final controller = Provider.of<RemoteController>(context, listen: false);
    setState(() {
      _classifiedIntent = text.trim().isEmpty
          ? null
          : VoiceService.classifyIntent(
              text,
              installedApps: controller.installedApps,
            );
    });
  }

  /// Trata a liberação do botão Push-to-Talk disparada pelo overlay
  void handlePttRelease() {
    _stopListeningAudio();
    final text = _textController.text.trim();

    // Se nada foi falado, fecha imediatamente
    if (text.isEmpty) {
      _close();
      return;
    }

    final controller = Provider.of<RemoteController>(context, listen: false);
    final intent = _classifiedIntent ??
        VoiceService.classifyIntent(
          text,
          installedApps: controller.installedApps,
        );

    if (intent.isCommand) {
      // Executa ação direta
      controller.executeVoiceIntent(intent);
      setState(() {
        _executionFeedback = 'Comando "${intent.displayDescription}" executado!';
      });
      Future.delayed(const Duration(milliseconds: 700), () {
        _close();
      });
    } else {
      // É texto de pesquisa: trava para revisão e edição manual
      VoiceListeningOverlay.lock();
    }
  }

  void _toggleLocale(String newLocale) {
    if (_selectedLocale == newLocale) return;
    setState(() {
      _selectedLocale = newLocale;
    });
    _stopListeningAudio();
    _startAudioCapture();
  }

  void _sendToTv() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final controller = Provider.of<RemoteController>(context, listen: false);
    if (_classifiedIntent != null && _classifiedIntent!.isCommand) {
      controller.executeVoiceIntent(_classifiedIntent!);
    } else {
      // Injeta texto na TV sem enter automático
      controller.sendText(text);
    }
    HapticService.selectionClick();
    _close();
  }

  void _close() {
    _stopListeningAudio();
    if (VoiceListeningOverlay.onPttReleaseCallback == handlePttRelease) {
      VoiceListeningOverlay.onPttReleaseCallback = null;
    }
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    if (VoiceListeningOverlay.onPttReleaseCallback == handlePttRelease) {
      VoiceListeningOverlay.onPttReleaseCallback = null;
    }
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    _dismissTimer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final brandName = controller.currentBrand.displayName;
    final tvName = controller.connectedTvName ?? 'Smart TV';
    final isConnected = controller.isConnected;
    final highlightColor = AppColors.iconHighlightOf(context);
    final isLocked = widget.isLocked;

    final intent = _classifiedIntent;
    final hasText = _textController.text.trim().isNotEmpty;

    return Dialog(
      backgroundColor: AppColors.remoteChassisOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isLocked
              ? highlightColor
              : highlightColor.withValues(alpha: 0.35),
          width: isLocked ? 1.8 : 1.2,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cabeçalho: Status Badge + Seletor de Idioma
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Badge superior indicativo
                  Flexible(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? highlightColor.withValues(alpha: 0.18)
                            : highlightColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isLocked
                              ? highlightColor
                              : highlightColor.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isConnected
                                  ? AppColors.statusConnected
                                  : highlightColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (isConnected
                                          ? AppColors.statusConnected
                                          : highlightColor)
                                      .withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              isLocked
                                  ? '🔒 MÃOS LIVRES (TRAVADO)'
                                  : (widget.isPushToTalk
                                      ? 'PUSH-TO-TALK ATIVO'
                                      : 'MICROFONE ATIVO'),
                              style: TextStyle(
                                color: highlightColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Seletor de Idioma (PT / EN)
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceInteractiveOf(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.borderSubtleOf(context),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLocaleChip('pt_BR', '🇧🇷 PT', highlightColor),
                        _buildLocaleChip('en_US', '🇺🇸 EN', highlightColor),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Microfone central com anéis pulsantes concêntricos
              GestureDetector(
                onTap: () {
                  if (_isMicListening) {
                    _stopListeningAudio();
                  } else {
                    _startAudioCapture();
                  }
                },
                child: Tooltip(
                  message: _isMicListening
                      ? 'Toque para pausar microfone'
                      : 'Toque para escutar novamente',
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_isMicListening) ...[
                              _buildPulseRing(
                                progress: _pulseController.value,
                                delay: 0.4,
                                color: highlightColor,
                                maxRadius: 48,
                              ),
                              _buildPulseRing(
                                progress: _pulseController.value,
                                delay: 0.0,
                                color: highlightColor,
                                maxRadius: 40,
                              ),
                            ],
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    highlightColor.withValues(alpha: 0.28),
                                    highlightColor.withValues(alpha: 0.08),
                                  ],
                                ),
                                border: Border.all(
                                  color: highlightColor,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        highlightColor.withValues(alpha: 0.35),
                                    blurRadius: 14,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  _isMicListening
                                      ? Icons.mic_rounded
                                      : Icons.mic_none_rounded,
                                  size: 30,
                                  color: highlightColor,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Ondas sonoras animadas (Equalizador)
              AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(7, (index) {
                      final factor = _isMicListening
                          ? math
                              .sin((_waveController.value * math.pi) +
                                  (index * 0.5))
                              .abs()
                          : 0.15;
                      final height = 6.0 + (factor * 14.0);
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.0),
                        width: 3.0,
                        height: height,
                        decoration: BoxDecoration(
                          color: highlightColor.withValues(
                            alpha: 0.3 + (factor * 0.7),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  );
                },
              ),

              const SizedBox(height: 8),

              // Título "Ouvindo..."
              Text(
                'Ouvindo...',
                style: TextStyle(
                  color: AppColors.textPrimaryOf(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),

              Text(
                isLocked
                    ? 'Modo mãos livres ativo.\nFale livremente ou digite com o teclado.'
                    : (widget.isPushToTalk
                        ? 'Segure enquanto fala.\nSolte para enviar ou revisar o comando.'
                        : 'Fale ou digite para pesquisar ou controlar sua $brandName.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondaryOf(context),
                  fontSize: 12,
                  height: 1.25,
                ),
              ),

              const SizedBox(height: 12),

              // Campo de Texto Editável em Tempo Real
              TextField(
                controller: _textController,
                focusNode: _focusNode,
                style: TextStyle(
                  color: AppColors.textPrimaryOf(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Fale ou digite para enviar à TV...',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondaryOf(context)
                        .withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(
                    hasText
                        ? Icons.keyboard_alt_outlined
                        : Icons.mic_none_rounded,
                    size: 18,
                    color: highlightColor,
                  ),
                  suffixIcon: hasText
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          color: AppColors.textSecondaryOf(context),
                          onPressed: () {
                            _textController.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surfaceInteractiveOf(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppColors.borderSubtleOf(context),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: highlightColor,
                      width: 1.5,
                    ),
                  ),
                ),
                onSubmitted: (_) => _sendToTv(),
              ),

              const SizedBox(height: 10),

              // Feedback de Classificação de Intenção ou Execução
              if (_executionFeedback != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.statusConnected.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.statusConnected.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: AppColors.statusConnected,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _executionFeedback!,
                          style: TextStyle(
                            color: AppColors.statusConnected,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else if (intent != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: intent.isCommand
                        ? Colors.amber.withValues(alpha: 0.15)
                        : highlightColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: intent.isCommand
                          ? Colors.amber.withValues(alpha: 0.4)
                          : highlightColor.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        intent.isCommand
                            ? Icons.bolt_rounded
                            : Icons.search_rounded,
                        size: 15,
                        color: intent.isCommand ? Colors.amber : highlightColor,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          intent.isCommand
                              ? '⚡ Ação detectada: ${intent.displayDescription}'
                              : '📺 Inserir texto na pesquisa da TV',
                          style: TextStyle(
                            color: intent.isCommand
                                ? Colors.amber
                                : AppColors.textPrimaryOf(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else if (!isLocked && widget.isPushToTalk)
                Text(
                  'Deslize para travar 🔒 no modo mãos livres',
                  style: TextStyle(
                    color: highlightColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else ...[
                Text(
                  isConnected
                      ? '$tvName ($brandName)'
                      : '$brandName (Pronta)',
                  style: TextStyle(
                    color: AppColors.textSecondaryOf(context),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildCommandHintChip('🔊 Volume +5 / -5', highlightColor),
                    _buildCommandHintChip('🔇 Mudo', highlightColor),
                    _buildCommandHintChip('🚀 Abrir YouTube / Netflix', highlightColor),
                    _buildCommandHintChip('⚡ Desligar TV', highlightColor),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Barra de contagem regressiva da janela de escuta
              if (!isLocked)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 2.5,
                    backgroundColor: AppColors.borderSubtleOf(context),
                    valueColor: AlwaysStoppedAnimation<Color>(highlightColor),
                  ),
                ),

              const SizedBox(height: 14),

              // Botões de Ação
              Row(
                children: [
                  // Botão Cancelar
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _close,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondaryOf(context),
                        side:
                            BorderSide(color: AppColors.borderSubtleOf(context)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text(
                        'Cancelar',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Botão "Parar Microfone" se estiver no modo mãos livres
                  if (isLocked) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          HapticService.voiceRelease();
                          _stopListeningAudio();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: highlightColor,
                          side: BorderSide(
                            color: highlightColor.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.stop_circle_rounded, size: 16),
                        label: const Text(
                          'Parar Microfone',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Botão Enviar para a TV em destaque
                  Expanded(
                    flex: isLocked ? 1 : 2,
                    child: ElevatedButton.icon(
                      onPressed: hasText ? _sendToTv : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: highlightColor,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor:
                            highlightColor.withValues(alpha: 0.25),
                        disabledForegroundColor: Colors.black38,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text(
                        'Enviar para a TV',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocaleChip(String localeCode, String label, Color highlightColor) {
    final isSelected = _selectedLocale == localeCode;
    return GestureDetector(
      onTap: () => _toggleLocale(localeCode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? highlightColor.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? highlightColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? highlightColor
                : AppColors.textSecondaryOf(context),
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildCommandHintChip(String label, Color highlightColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceInteractiveOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.borderSubtleOf(context),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textSecondaryOf(context),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPulseRing({
    required double progress,
    required double delay,
    required Color color,
    required double maxRadius,
  }) {
    final effectiveProgress = ((progress - delay) % 1.0).clamp(0.0, 1.0);
    final currentRadius = 32.0 + ((maxRadius - 32.0) * effectiveProgress);
    final opacity = (1.0 - effectiveProgress).clamp(0.0, 1.0) * 0.45;

    return Container(
      width: currentRadius * 2,
      height: currentRadius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withValues(alpha: opacity),
          width: 1.5,
        ),
      ),
    );
  }
}

/// Gerenciador de overlay para exibição Push-to-Talk e Slide-to-Lock instantânea.
class VoiceListeningOverlay {
  static OverlayEntry? _entry;
  static final ValueNotifier<bool> isLockedNotifier =
      ValueNotifier<bool>(false);
  static VoidCallback? onPttReleaseCallback;

  static bool get isVisible => _entry != null;
  static bool get isLocked => isLockedNotifier.value;

  static void show(
    BuildContext context, {
    Duration maxDuration = const Duration(seconds: 14),
  }) {
    hide();
    isLockedNotifier.value = false;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (ctx) => ValueListenableBuilder<bool>(
        valueListenable: isLockedNotifier,
        builder: (context, locked, _) {
          return IgnorePointer(
            ignoring: !locked,
            child: Material(
              color: Colors.black.withValues(alpha: locked ? 0.55 : 0.40),
              type: MaterialType.canvas,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (locked)
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: hide,
                    ),
                  VoiceListeningDialog(
                    isPushToTalk: true,
                    isLocked: locked,
                    timeoutDuration: maxDuration,
                    onClose: hide,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    overlay.insert(_entry!);
  }

  static void lock() {
    isLockedNotifier.value = true;
  }

  static void onPttRelease() {
    if (_entry == null) return;
    if (onPttReleaseCallback != null) {
      onPttReleaseCallback!();
    } else {
      hide();
    }
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
    onPttReleaseCallback = null;
    isLockedNotifier.value = false;
  }
}
