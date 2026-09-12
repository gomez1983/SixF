import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

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

        // Botão Central de Mute
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RemoteButton(
              width: 54,
              height: 54,
              isCircular: true,
              backgroundColor: isMuted
                  ? AppColors.powerRed.withValues(alpha: 0.2)
                  : AppColors.surfaceInteractiveOf(context),
              borderColor: isMuted ? AppColors.powerRed : AppColors.borderSubtleOf(context),
              foregroundColor: isMuted ? AppColors.powerRed : AppColors.textPrimaryOf(context),
              icon: isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              iconSize: 24,
              tooltip: isMuted ? 'Desmutar Áudio' : 'Mutar Áudio',
              onPressed: () => controller.muteToggle(),
            ),
            const SizedBox(height: 6),
            Text(
              'MUTE',
              style: TextStyle(
                color: isMuted ? AppColors.powerRed : AppColors.textSecondaryOf(context),
                fontSize: 10,
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
