import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

/// Controles Multimídia dedicados: Retroceder (<<), Play, Pause, Stop e Avançar (>>).
class MultimediaControls extends StatelessWidget {
  const MultimediaControls({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<RemoteController>();

    final mediaActions = [
      _MediaButtonData(
        icon: Icons.fast_rewind_rounded,
        tooltip: 'Retroceder (<<)',
        onPressed: () => controller.mediaRewind(),
      ),
      _MediaButtonData(
        icon: Icons.play_arrow_rounded,
        tooltip: 'Reproduzir (Play)',
        isPrimary: true,
        onPressed: () => controller.mediaPlay(),
      ),
      _MediaButtonData(
        icon: Icons.pause_rounded,
        tooltip: 'Pausar (Pause)',
        onPressed: () => controller.mediaPause(),
      ),
      _MediaButtonData(
        icon: Icons.stop_rounded,
        tooltip: 'Parar (Stop)',
        onPressed: () => controller.mediaStop(),
      ),
      _MediaButtonData(
        icon: Icons.fast_forward_rounded,
        tooltip: 'Avançar (>>)',
        onPressed: () => controller.mediaFastForward(),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: mediaActions.map((item) {
          return RemoteButton(
            width: item.isPrimary ? 46 : 40,
            height: item.isPrimary ? 46 : 40,
            isCircular: true,
            backgroundColor: item.isPrimary
                ? AppColors.iconHighlightOf(context).withValues(alpha: 0.18)
                : AppColors.surfaceInteractiveOf(context),
            borderColor: item.isPrimary
                ? AppColors.iconHighlightOf(context)
                : AppColors.borderSubtleOf(context),
            foregroundColor: item.isPrimary
                ? AppColors.iconHighlightOf(context)
                : AppColors.textPrimaryOf(context),
            icon: item.icon,
            iconSize: item.isPrimary ? 24 : 20,
            tooltip: item.tooltip,
            onPressed: item.onPressed,
          );
        }).toList(),
      ),
    );
  }
}

class _MediaButtonData {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isPrimary;

  const _MediaButtonData({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isPrimary = false,
  });
}
