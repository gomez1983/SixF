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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Botão Lateral Esquerdo: VOLTAR
          RemoteButton(
            width: 58,
            height: 64,
            borderRadius: 16,
            backgroundColor: AppColors.surfaceCardOf(context),
            borderColor: AppColors.borderSubtleOf(context),
            foregroundColor: AppColors.textPrimaryOf(context),
            icon: Icons.undo_rounded,
            label: 'VOLTAR',
            iconSize: 22,
            tooltip: 'Voltar à tela anterior (Esc ou Backspace)',
            onPressed: () => controller.pressBack(),
          ),

          const SizedBox(width: 12),

          // Roda D-Pad Central
          Container(
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

          const SizedBox(width: 12),

          // Botões Laterais Direitos: TV Digital e HDMI 1
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botão Superior: TV Digital
              RemoteButton(
                width: 58,
                height: 52,
                borderRadius: 14,
                backgroundColor: AppColors.surfaceCardOf(context),
                borderColor: AppColors.borderSubtleOf(context),
                foregroundColor: AppColors.textPrimaryOf(context),
                icon: Icons.live_tv_rounded,
                label: 'TV Digital',
                iconSize: 20,
                tooltip: 'Sintonizar TV Digital / Antena',
                onPressed: () => controller.switchTvDigital(),
              ),

              const SizedBox(height: 8),

              // Botão Inferior: HDMI 1
              RemoteButton(
                width: 58,
                height: 52,
                borderRadius: 14,
                backgroundColor: AppColors.surfaceCardOf(context),
                borderColor: AppColors.borderSubtleOf(context),
                foregroundColor: AppColors.textPrimaryOf(context),
                icon: Icons.settings_input_hdmi_rounded,
                label: 'HDMI 1',
                iconSize: 20,
                tooltip: 'Alternar Entrada para HDMI 1',
                onPressed: () => controller.switchHdmi1(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
