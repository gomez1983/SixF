import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

/// D-Pad clássico ergonômico com direcionais (Cima, Baixo, Esquerda, Direita)
/// e botão central OK / Enter simulando o disco do Magic Remote da LG.
class DPadWidget extends StatelessWidget {
  final double size;

  const DPadWidget({
    super.key,
    this.size = 210,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.read<RemoteController>();
    final buttonSize = size * 0.28;
    final centerSize = size * 0.36;

    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceCardOf(context),
          border: Border.all(color: AppColors.borderSubtleOf(context), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.isDark(context) ? Colors.black26 : Colors.black12,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Anel decorativo sutil
            Container(
              width: size * 0.82,
              height: size * 0.82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.borderSubtleOf(context).withValues(alpha: 0.5),
                ),
              ),
            ),

            // Botão CIMA
            Positioned(
              top: 8,
              child: RemoteButton(
                width: buttonSize * 1.5,
                height: buttonSize,
                borderRadius: 14,
                backgroundColor: Colors.transparent,
                borderColor: Colors.transparent,
                foregroundColor: AppColors.textPrimaryOf(context),
                icon: Icons.keyboard_arrow_up_rounded,
                iconSize: 28,
                tooltip: 'Navegar para Cima (Seta Cima)',
                onPressed: () => controller.dpadUp(),
              ),
            ),

            // Botão BAIXO
            Positioned(
              bottom: 8,
              child: RemoteButton(
                width: buttonSize * 1.5,
                height: buttonSize,
                borderRadius: 14,
                backgroundColor: Colors.transparent,
                borderColor: Colors.transparent,
                foregroundColor: AppColors.textPrimaryOf(context),
                icon: Icons.keyboard_arrow_down_rounded,
                iconSize: 28,
                tooltip: 'Navegar para Baixo (Seta Baixo)',
                onPressed: () => controller.dpadDown(),
              ),
            ),

            // Botão ESQUERDA
            Positioned(
              left: 8,
              child: RemoteButton(
                width: buttonSize,
                height: buttonSize * 1.5,
                borderRadius: 14,
                backgroundColor: Colors.transparent,
                borderColor: Colors.transparent,
                foregroundColor: AppColors.textPrimaryOf(context),
                icon: Icons.keyboard_arrow_left_rounded,
                iconSize: 28,
                tooltip: 'Navegar para Esquerda (Seta Esquerda)',
                onPressed: () => controller.dpadLeft(),
              ),
            ),

            // Botão DIREITA
            Positioned(
              right: 8,
              child: RemoteButton(
                width: buttonSize,
                height: buttonSize * 1.5,
                borderRadius: 14,
                backgroundColor: Colors.transparent,
                borderColor: Colors.transparent,
                foregroundColor: AppColors.textPrimaryOf(context),
                icon: Icons.keyboard_arrow_right_rounded,
                iconSize: 28,
                tooltip: 'Navegar para Direita (Seta Direita)',
                onPressed: () => controller.dpadRight(),
              ),
            ),

            // Botão Central OK / Enter (Magic Wheel)
            Container(
              width: centerSize,
              height: centerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.surfaceElevatedOf(context),
                    AppColors.surfaceInteractiveOf(context),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.isDark(context) ? Colors.black38 : Colors.black12,
                    blurRadius: 6,
                    spreadRadius: -1,
                  ),
                ],
              ),
              child: RemoteButton(
                isCircular: true,
                backgroundColor: Colors.transparent,
                borderColor: AppColors.borderActiveOf(context),
                foregroundColor: AppColors.textPrimaryOf(context),
                label: 'OK',
                tooltip: 'Confirmar / OK (Enter ou Espaço)',
                onPressed: () => controller.dpadOk(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
