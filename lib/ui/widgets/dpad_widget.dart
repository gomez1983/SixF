import '../../services/drivers/tv_driver.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

/// D-Pad clássico ergonômico com direcionais (Cima, Baixo, Esquerda, Direita)
/// e botão central OK / Enter simulando o disco do Magic Remote da LG.
class DPadWidget extends StatelessWidget {
  final double size;

  const DPadWidget({super.key, this.size = 210});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<RemoteController>();
    context.select<RemoteController, (bool, Object)>(
      (c) => (c.isConnected, c.driver),
    );
    final supportsInputs = context.select<RemoteController, bool>(
      (controller) => controller.supportsDirectInputs,
    );
    final buttonSize = size * 0.28;
    final centerSize = size * 0.36;

    final google = context.select<RemoteController, bool>(
      (c) => c.currentBrand == TvBrand.googleTv,
    );
    final right = context.select<RemoteController, bool>(
      (c) => c.backButtonOnRight,
    );
    Widget buildBack({double width = 58, double height = 64}) => RemoteButton(
      width: width,
      height: height,
      borderRadius: google ? 12 : 16,
      backgroundColor: AppColors.surfaceCardOf(context),
      borderColor: AppColors.borderSubtleOf(context),
      foregroundColor: AppColors.textPrimaryOf(context),
      icon: Icons.undo_rounded,
      label: 'VOLTAR',
      iconSize: google ? 18 : 22,
      tooltip: 'Voltar à tela anterior (Esc ou Backspace)',
      onPressed: () => controller.pressBack(),
    );
    final wheel = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceCardOf(context),
        border: Border.all(
          color: AppColors.borderSubtleOf(context),
          width: 1.5,
        ),
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
              repeatOnHold: controller.isConnected,
              repeatToken: controller.driver,
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
              repeatOnHold: controller.isConnected,
              repeatToken: controller.driver,
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
              repeatOnHold: controller.isConnected,
              repeatToken: controller.driver,
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
              repeatOnHold: controller.isConnected,
              repeatToken: controller.driver,
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
                  color: AppColors.isDark(context)
                      ? Colors.black38
                      : Colors.black12,
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
    );
    if (google) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : size;
          return SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  key: const Key('chromecast-dpad'),
                  width: size,
                  height: size,
                  child: wheel,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: right
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: KeyedSubtree(
                      key: const Key('chromecast-back'),
                      child: buildBack(width: width / 4 - 8, height: 52),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Botão Lateral Esquerdo: VOLTAR
          buildBack(),

          const SizedBox(width: 12),

          // Roda D-Pad Central
          wheel,

          if (supportsInputs) ...[
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
        ],
      ),
    );
  }
}
