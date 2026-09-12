import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';

/// Área dedicada de Trackpad virtual que simula o Magic Remote da LG.
///
/// Utiliza [GestureDetector] para capturar eventos de arrasto (deltas dx, dy)
/// e toques/cliques rápidos de confirmação na tela da Smart TV.
class TrackpadWidget extends StatefulWidget {
  final double height;

  const TrackpadWidget({
    super.key,
    this.height = 180,
  });

  @override
  State<TrackpadWidget> createState() => _TrackpadWidgetState();
}

class _TrackpadWidgetState extends State<TrackpadWidget> {
  Offset? _pointerPos;
  bool _isDragging = false;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _pointerPos = details.localPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, RemoteController controller) {
    setState(() {
      _pointerPos = details.localPosition;
    });

    // Envia os deltas de deslocamento diretamente para o controlador
    controller.sendTrackpadDelta(details.delta.dx, details.delta.dy);
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
      _pointerPos = null;
    });
  }

  void _onTap(RemoteController controller) {
    HapticFeedback.selectionClick();
    controller.sendTrackpadClick();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<RemoteController>();
    final isDark = AppColors.isDark(context);

    final surfaceColor = AppColors.trackpadSurfaceOf(context);
    final borderColor = _isDragging
        ? AppColors.iconHighlightOf(context)
        : AppColors.trackpadBorderOf(context);
    final indicatorColor = AppColors.iconHighlightOf(context);

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _isDragging
                ? indicatorColor.withValues(alpha: 0.2)
                : (isDark ? Colors.black26 : Colors.black12),
            blurRadius: 10,
            spreadRadius: _isDragging ? 1 : 0,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onPanStart,
          onPanUpdate: (details) => _onPanUpdate(details, controller),
          onPanEnd: _onPanEnd,
          onTap: () => _onTap(controller),
          child: Stack(
            children: [
              // Grid de textura sutil de fundo
              CustomPaint(
                size: Size.infinite,
                painter: _TrackpadGridPainter(
                  gridColor: AppColors.borderSubtleOf(context),
                ),
              ),

              // Rótulo central de ajuda quando inativo
              if (!_isDragging)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 28,
                        color: AppColors.textSecondaryOf(context).withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Magic Trackpad',
                        style: TextStyle(
                          color: AppColors.textSecondaryOf(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Arraste para mover o cursor • Toque para clicar',
                        style: TextStyle(
                          color: AppColors.textMutedOf(context),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              // Indicador visual que acompanha o dedo/cursor em tempo real
              if (_pointerPos != null)
                Positioned(
                  left: _pointerPos!.dx - 18,
                  top: _pointerPos!.dy - 18,
                  child: IgnorePointer(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: indicatorColor.withValues(alpha: 0.25),
                        border: Border.all(
                          color: indicatorColor,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: indicatorColor.withValues(alpha: 0.6),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
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
}

/// Desenha linhas guias e pontos sutis no fundo do trackpad
class _TrackpadGridPainter extends CustomPainter {
  final Color gridColor;

  _TrackpadGridPainter({required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    // Linha central horizontal e vertical
    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.5),
      Offset(size.width * 0.8, size.height * 0.5),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.2),
      Offset(size.width * 0.5, size.height * 0.8),
      paint,
    );

    // Círculo concêntrico sutil
    final circlePaint = Paint()
      ..color = gridColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      size.height * 0.3,
      circlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TrackpadGridPainter oldDelegate) =>
      oldDelegate.gridColor != gridColor;
}
