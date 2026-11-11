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
        icon: local ? Icons.replay_10 : Icons.fast_rewind_rounded,
        tooltip: local ? 'Recuar 10 segundos' : 'Retroceder (<<)',
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
        icon:
            (local ? media.isPlaying : controller.selectedMediaAction == 'play')
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded,
        tooltip:
            (local ? media.isPlaying : controller.selectedMediaAction == 'play')
            ? 'Pausar (Pause)'
            : 'Reproduzir (Play)',
        isPrimary: local && media.isPlaying,
        onPressed: local && !(media.isPlaying ? media.canPause : media.canPlay)
            ? null
            : () {
                final pause = local
                    ? media.isPlaying
                    : controller.selectedMediaAction == 'play';
                if (local) {
                  pause ? media.pause() : media.play();
                } else {
                  pause ? controller.mediaPause() : controller.mediaPlay();
                }
                controller.selectMediaAction(pause ? 'pause' : 'play');
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
        icon: local ? Icons.forward_10 : Icons.fast_forward_rounded,
        tooltip: local ? 'Avançar 10 segundos' : 'Avançar (>>)',
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
      _MediaButtonData(
        icon: Icons.repeat,
        tooltip: 'Repetir arquivo',
        isPrimary: local && media.isLooping,
        onPressed: local && (media.canLoop || media.isLooping)
            ? media.toggleLoop
            : null,
      ),
      _MediaButtonData(
        icon: Icons.shuffle,
        tooltip: 'Ordem aleatória dos arquivos selecionados',
        isPrimary: local && media.isShuffling,
        onPressed: local && media.canShuffle ? media.toggleShuffle : null,
      ),
    ];

    // Padrão Payno: círculos cinza-claros; o ativo em azul-marinho sólido.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 8,
          children: mediaActions.map((item) {
            return RemoteButton(
              width: 44,
              height: 44,
              isCircular: true,
              isSelected: item.isPrimary,
              backgroundColor: AppColors.surfaceInteractiveOf(context),
              foregroundColor: AppColors.textPrimaryOf(context),
              icon: item.icon,
              iconSize: 20,
              tooltip: item.tooltip,
              onPressed: item.onPressed,
            );
          }).toList(),
        ),
        if (media != null)
          MediaSessionControls(
            controller: media,
            enabled: local,
            showTransportControls: false,
            showPlaybackModes: false,
          ),
        if (!local)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Linha do tempo e repetição: transmita um arquivo pelo SixF.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textMutedOf(context),
              ),
            ),
          ),
      ],
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
