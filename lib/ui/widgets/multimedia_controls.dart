import '../../controllers/media_cast_controller.dart';
import 'media_session_controls.dart';

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
    final controller = context.watch<RemoteController>();
    final media = context.watch<MediaCastController?>();
    final local =
        media != null &&
        media.isStreaming &&
        media.isTarget(controller.ipAddress, controller.currentBrand);

    final mediaActions = [
      _MediaButtonData(
        icon: Icons.fast_rewind_rounded,
        tooltip: 'Retroceder (<<)',
        onPressed: local && !media.canSeek
            ? null
            : () {
                if (local) {
                  media.seekTo(
                    media.currentPosition - const Duration(seconds: 10),
                  );
                } else {
                  controller.mediaRewind();
                }
              },
      ),
      _MediaButtonData(
        icon: Icons.play_arrow_rounded,
        tooltip: 'Reproduzir (Play)',
        isPrimary: controller.selectedMediaAction == 'play',
        onPressed: local && !media.canPlay
            ? null
            : () {
                if (local) {
                  media.play();
                  controller.selectMediaAction('play');
                } else {
                  controller.mediaPlay();
                  controller.selectMediaAction('play');
                }
              },
      ),
      _MediaButtonData(
        icon: Icons.pause_rounded,
        tooltip: 'Pausar (Pause)',
        isPrimary: controller.selectedMediaAction == 'pause',
        onPressed: local && !media.canPause
            ? null
            : () {
                if (local) {
                  media.pause();
                  controller.selectMediaAction('pause');
                } else {
                  controller.mediaPause();
                  controller.selectMediaAction('pause');
                }
              },
      ),
      _MediaButtonData(
        icon: Icons.stop_rounded,
        tooltip: 'Parar (Stop)',
        isPrimary: controller.selectedMediaAction == 'stop',
        onPressed: () {
          if (local) {
            media.stop();
            controller.selectMediaAction('stop');
          } else {
            controller.mediaStop();
            controller.selectMediaAction('stop');
          }
        },
      ),
      _MediaButtonData(
        icon: Icons.fast_forward_rounded,
        tooltip: 'Avançar (>>)',
        onPressed: local && !media.canSeek
            ? null
            : () {
                if (local) {
                  media.seekTo(
                    media.currentPosition + const Duration(seconds: 10),
                  );
                } else {
                  controller.mediaFastForward();
                }
              },
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: mediaActions.map((item) {
              return RemoteButton(
                width: 46,
                height: 46,
                isCircular: true,
                isSelected: item.isPrimary,
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
          if (media != null)
            MediaSessionControls(controller: media, enabled: local),
          if (!local)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Linha do tempo e repetição: transmita um arquivo pelo SixF.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaButtonData {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isPrimary;

  const _MediaButtonData({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isPrimary = false,
  });
}
