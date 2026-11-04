// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../../controllers/media_cast_controller.dart';
import '../../services/media_remux_service.dart';
import 'media_progress_slider.dart';
import '../theme/app_colors.dart';

/// Commands are scoped to the file session, never guessed from a TV's brand.
class MediaSessionControls extends StatelessWidget {
  const MediaSessionControls({
    super.key,
    required this.controller,
    this.showTimeline = true,
    this.enabled = true,
    this.showTransportControls = true,
  });
  final MediaCastController controller;
  final bool showTimeline;
  final bool enabled;
  final bool showTransportControls;
  static String time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  void _showTracksDialog(
    BuildContext context, {
    required String title,
    required List<MediaTrack> tracks,
    required MediaTrack? selected,
    required Future<void> Function(MediaTrack?) onConfirm,
  }) {
    MediaTrack? currentChoice = selected;
    bool isApplying = false;
    String? dialogError;

    showDialog<void>(
      context: context,
      barrierDismissible: !isApplying,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text(title),
          content: tracks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Nenhuma faixa alternativa identificada no arquivo.',
                  ),
                )
              : SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dialogError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .errorContainer
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 16,
                                  color: Theme.of(ctx).colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    dialogError!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(ctx).colorScheme.error,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (isApplying)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  title == 'Legendas'
                                      ? 'Extraindo e ativando legenda...'
                                      : 'Aplicando faixa de áudio...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(ctx).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            RadioListTile<MediaTrack?>(
                              value: null,
                              groupValue: currentChoice,
                              title: const Text('Padrão / Desativado'),
                              onChanged: isApplying
                                  ? null
                                  : (val) {
                                      setDialogState(() {
                                        currentChoice = null;
                                        dialogError = null;
                                      });
                                    },
                            ),
                            for (final track in tracks)
                              RadioListTile<MediaTrack?>(
                                value: track,
                                groupValue: currentChoice,
                                title: Text(track.title),
                                subtitle: track.codec != null
                                    ? Text('Codec: ${track.codec}')
                                    : null,
                                onChanged: isApplying
                                    ? null
                                    : (val) {
                                        setDialogState(() {
                                          currentChoice = track;
                                          dialogError = null;
                                        });
                                      },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          actions: [
            TextButton(
              onPressed: isApplying ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            if (tracks.isNotEmpty)
              FilledButton.icon(
                icon: isApplying
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(isApplying ? 'Aplicando...' : 'Confirmar'),
                onPressed: isApplying
                    ? null
                    : () async {
                        setDialogState(() {
                          isApplying = true;
                          dialogError = null;
                        });
                        try {
                          await onConfirm(currentChoice);
                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).removeCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  currentChoice != null
                                      ? '$title ativada: ${currentChoice!.title}'
                                      : '$title desativada.',
                                ),
                                duration: const Duration(seconds: 3),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (dialogCtx.mounted) {
                            setDialogState(() {
                              isApplying = false;
                              dialogError = e
                                  .toString()
                                  .replaceFirst('Exception: ', '')
                                  .replaceFirst('StateError: ', '');
                            });
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).removeCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Falha ao ativar: $e'),
                                backgroundColor:
                                    Theme.of(context).colorScheme.error,
                                duration: const Duration(seconds: 4),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
    final audios = c.audioTracks;
    final subtitles = c.subtitleTracks;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: AppColors.glassCardDecoration(context, borderRadius: 14),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: [
              if (showTransportControls) ...[
                IconButton(
                  tooltip: 'Arquivo anterior',
                  onPressed: enabled && c.canPrevious ? c.previous : null,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton(
                  tooltip: c.isPlaying
                      ? 'Pausar reprodução'
                      : 'Retomar reprodução',
                  isSelected: enabled && c.isPlaying,
                  onPressed: enabled && (c.isPlaying ? c.canPause : c.canPlay)
                      ? (c.isPlaying ? c.pause : c.play)
                      : null,
                  icon: Icon(
                    c.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Parar transmissão',
                  onPressed: enabled && c.isStreaming ? c.stop : null,
                  icon: const Icon(Icons.stop_rounded),
                ),
                IconButton(
                  tooltip: 'Próximo arquivo',
                  onPressed: enabled && c.canNext ? c.next : null,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
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
            ],
          ),
        ),
        if (enabled && c.playlistCount > 1)
          Text('${c.playlistPosition} de ${c.playlistCount} arquivos'),
        if (enabled && showTimeline && c.hasProgress)
          ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MediaProgressSlider(
                  key: ValueKey(c.currentFilePath),
                  controller: c,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(time(c.currentPosition)),
                    Text(time(c.totalDuration)),
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showTransportControls)
                      TextButton.icon(
                        onPressed: c.canSeek
                            ? () => c.seekTo(
                                c.currentPosition - const Duration(seconds: 10),
                              )
                            : null,
                        icon: const Icon(Icons.replay_10),
                        label: const Text('−10 s'),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: c.selectedSubtitleTrack != null
                              ? 'Legenda: ${c.selectedSubtitleTrack!.title}'
                              : 'Legendas embutidas',
                          icon: Icon(
                            c.selectedSubtitleTrack != null
                                ? Icons.subtitles_rounded
                                : Icons.subtitles_outlined,
                            size: 20,
                          ),
                          color: c.selectedSubtitleTrack != null
                              ? Theme.of(context).colorScheme.primary
                              : null,
                          onPressed: enabled && c.isStreaming
                              ? () => _showTracksDialog(
                                  context,
                                  title: 'Legendas',
                                  tracks: subtitles,
                                  selected: c.selectedSubtitleTrack,
                                  onConfirm: c.selectSubtitleTrack,
                                )
                              : null,
                        ),
                        if (c.selectedSubtitleTrack != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                c.selectedSubtitleTrack!.title,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                    IconButton(
                      tooltip: c.selectedAudioTrack != null
                          ? 'Áudio: ${c.selectedAudioTrack!.title}'
                          : 'Faixa de áudio',
                      icon: Icon(
                        c.selectedAudioTrack != null
                            ? Icons.audiotrack_rounded
                            : Icons.audiotrack_outlined,
                        size: 20,
                      ),
                      color: c.selectedAudioTrack != null
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      onPressed: enabled && c.isStreaming
                          ? () => _showTracksDialog(
                              context,
                              title: 'Faixas de Áudio',
                              tracks: audios,
                              selected: c.selectedAudioTrack,
                              onConfirm: c.selectAudioTrack,
                            )
                          : null,
                    ),
                    if (showTransportControls)
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
            ),
          ),
      ],
    );
      },
    );
  }
}
