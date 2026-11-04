import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

/// D-Pad ergonômico padronizado em Liquid Glass com direcionais (Cima, Baixo, Esquerda, Direita),
/// botão central OK / Enter e posicionamento simétrico consistente entre todas as marcas de dispositivos.
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
      (c) => c.supportsDirectInputs,
    );
    final right = context.select<RemoteController, bool>(
      (c) => c.backButtonOnRight,
    );
    final isDark = AppColors.isDark(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        const sideSlotWidth = 58.0;
        const sideGap = 12.0;
        const totalHorizontalExtras = (sideSlotWidth + sideGap) * 2;

        final maxAvailableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : (size + totalHorizontalExtras);
        final effectiveSize = (maxAvailableWidth - totalHorizontalExtras)
            .clamp(120.0, size);

        final buttonSize = effectiveSize * 0.28;
        final centerSize = effectiveSize * 0.36;

        final backButton = KeyedSubtree(
          key: const Key('chromecast-back'),
          child: RemoteButton(
            width: sideSlotWidth,
            height: 64,
            borderRadius: 16,
            foregroundColor: AppColors.textPrimaryOf(context),
            icon: Icons.undo_rounded,
            label: 'VOLTAR',
            iconSize: 22,
            tooltip: 'Voltar à tela anterior (Esc ou Backspace)',
            onPressed: () => controller.pressBack(),
          ),
        );

        final inputsColumn = supportsInputs
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RemoteButton(
                    width: sideSlotWidth,
                    height: 52,
                    borderRadius: 14,
                    foregroundColor: AppColors.textPrimaryOf(context),
                    icon: Icons.live_tv_rounded,
                    label: 'TV Digital',
                    iconSize: 20,
                    tooltip: 'Sintonizar TV Digital / Antena',
                    onPressed: () => controller.switchTvDigital(),
                  ),
                  const SizedBox(height: 8),
                  RemoteButton(
                    width: sideSlotWidth,
                    height: 52,
                    borderRadius: 14,
                    foregroundColor: AppColors.textPrimaryOf(context),
                    icon: Icons.settings_input_hdmi_rounded,
                    label: 'HDMI 1',
                    iconSize: 20,
                    tooltip: 'Alternar Entrada para HDMI 1',
                    onPressed: () => controller.switchHdmi1(),
                  ),
                ],
              )
            : const SizedBox(width: sideSlotWidth, height: 64);

        final wheel = Container(
          key: const Key('chromecast-dpad'),
          width: effectiveSize,
          height: effectiveSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [Color(0xF52D273B), Color(0xE6211D2C)]
                  : const [Color(0xFAFFFFFF), Color(0xE6F2EDF9)],
            ),
            border: Border.all(
              color: isDark ? const Color(0x28FFFFFF) : const Color(0xFFDCD3EC),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? const Color(0x45000000) : const Color(0x1448406C),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: isDark ? const Color(0x10FFFFFF) : const Color(0xCCFFFFFF),
                blurRadius: 1,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Anel decorativo sutil Liquid Glass
              Container(
                width: effectiveSize * 0.82,
                height: effectiveSize * 0.82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.borderSubtleOf(context).withValues(alpha: 0.6),
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

              // Botão Central OK / Enter (Liquid Glass Wheel)
              Container(
                width: centerSize,
                height: centerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? const [Color(0xFF3E3552), Color(0xFF2B243A)]
                        : const [Color(0xFFFFFFFF), Color(0xFFEBE3F7)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? const Color(0x40000000)
                          : const Color(0x187441A5),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: RemoteButton(
                  isCircular: true,
                  backgroundColor: Colors.transparent,
                  borderColor: AppColors.borderActiveOf(context)
                      .withValues(alpha: isDark ? 0.55 : 0.65),
                  foregroundColor: AppColors.textPrimaryOf(context),
                  label: 'OK',
                  tooltip: 'Confirmar / OK (Enter ou Espaço)',
                  onPressed: () => controller.dpadOk(),
                ),
              ),
            ],
          ),
        );

        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Slot Lateral Esquerdo (58px fixos)
              right ? inputsColumn : backButton,

              const SizedBox(width: sideGap),

              // Roda D-Pad Centralizada
              wheel,

              const SizedBox(width: sideGap),

              // Slot Lateral Direito (58px fixos para simetria absoluta)
              right ? backButton : inputsColumn,
            ],
          ),
        );
      },
    );
  }
}
