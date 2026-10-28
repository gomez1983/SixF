import 'package:flutter/material.dart';

import '../../controllers/media_cast_controller.dart';
import 'media_progress_slider.dart';

/// Commands are scoped to the file session, never guessed from a TV's brand.
class MediaSessionControls extends StatelessWidget {
  const MediaSessionControls({
    super.key,
    required this.controller,
    this.showTimeline = true,
    this.enabled = true,
  });
  final MediaCastController controller;
  final bool showTimeline;
  final bool enabled;
  static String time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Arquivo anterior',
              onPressed: enabled && c.canPrevious ? c.previous : null,
              icon: const Icon(Icons.skip_previous),
            ),
            IconButton(
              tooltip: 'Repetir arquivo',
              isSelected: enabled && c.isLooping,
              onPressed: enabled && (c.canLoop || c.isLooping)
                  ? c.toggleLoop
                  : null,
              icon: const Icon(Icons.repeat),
            ),
            IconButton(
              tooltip: 'Ordem aleatória dos arquivos selecionados',
              isSelected: enabled && c.isShuffling,
              onPressed: enabled && c.canShuffle ? c.toggleShuffle : null,
              icon: const Icon(Icons.shuffle),
            ),
            IconButton(
              tooltip: 'Próximo arquivo',
              onPressed: enabled && c.canNext ? c.next : null,
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
        if (enabled && c.playlistCount > 1)
          Text('${c.playlistPosition} de ${c.playlistCount} arquivos'),
        if (enabled && showTimeline && c.hasProgress) ...[
          MediaProgressSlider(key: ValueKey(c.currentFilePath), controller: c),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(time(c.currentPosition)),
              Text(time(c.totalDuration)),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton.icon(
                onPressed: c.canSeek
                    ? () => c.seekTo(
                        c.currentPosition - const Duration(seconds: 10),
                      )
                    : null,
                icon: const Icon(Icons.replay_10),
                label: const Text('−10 s'),
              ),
              TextButton.icon(
                onPressed: c.canSeek
                    ? () => c.seekTo(
                        c.currentPosition + const Duration(seconds: 10),
                      )
                    : null,
                icon: const Icon(Icons.forward_10),
                label: const Text('+10 s'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
