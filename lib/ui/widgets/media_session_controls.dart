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
    this.showPlaybackModes = true,
    this.showTrackButtons = true,
  });
  final MediaCastController controller;
  final bool showTimeline;
  final bool enabled;
  final bool showTransportControls;
  final bool showPlaybackModes;

  /// Botões Legenda/Áudio abaixo da linha do tempo. O visualizador da Mídia
  /// os desliga e usa [trackIconButtons] na própria linha de transporte, para
  /// não gastar uma linha inteira de altura.
  final bool showTrackButtons;

  /// Legenda e Áudio da transmissão como botões só de ícone, para entrar na
  /// linha de transporte do visualizador. Mesma escolha com confirmação.
  static List<Widget> trackIconButtons(
    BuildContext context,
    MediaCastController c,
  ) {
    void pick({
      required String title,
      required List<MediaTrack> tracks,
      required MediaTrack? selected,
      required Future<void> Function(MediaTrack?) onConfirm,
    }) => showTrackPickerDialog<MediaTrack>(
      context,
      title: title,
      tracks: tracks,
      selected: selected,
      labelOf: (t) => t.title,
      detailOf: (t) => t.codec != null ? 'Codec: ${t.codec}' : null,
      onConfirm: onConfirm,
    );
    return [
      MediaTrackButton(
        iconOnly: true,
        icon: Icons.subtitles_outlined,
        activeIcon: Icons.subtitles_rounded,
        label: 'Legenda',
        selectedTitle: c.selectedSubtitleTrack?.title,
        tooltip: c.selectedSubtitleTrack != null
            ? 'Legenda: ${c.selectedSubtitleTrack!.title}'
            : 'Legendas embutidas',
        onPressed: c.isStreaming
            ? () => pick(
                title: 'Legendas',
                tracks: c.subtitleTracks,
                selected: c.selectedSubtitleTrack,
                onConfirm: c.selectSubtitleTrack,
              )
            : null,
      ),
      MediaTrackButton(
        iconOnly: true,
        icon: Icons.audiotrack_outlined,
        activeIcon: Icons.audiotrack_rounded,
        label: 'Áudio',
        selectedTitle: c.selectedAudioTrack?.title,
        tooltip: c.selectedAudioTrack != null
            ? 'Áudio: ${c.selectedAudioTrack!.title}'
            : 'Faixa de áudio',
        onPressed: c.isStreaming
            ? () => pick(
                title: 'Faixas de Áudio',
                tracks: c.audioTracks,
                selected: c.selectedAudioTrack,
                onConfirm: c.selectAudioTrack,
              )
            : null,
      ),
      if (c.selectedSubtitleTrack != null &&
          c.transport == MediaCastTransport.cast)
        IconButton(
          tooltip: 'Sincronia da legenda',
          icon: const Icon(Icons.sync_alt_rounded, size: 20),
          onPressed: c.canAdjustSubtitleOffset
              ? () =>
                    MediaSessionControls(controller: c)
                        ._showSubtitleSync(context)
              : null,
        ),
    ];
  }

  void _showSubtitleSync(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final seconds = controller.subtitleOffset.inMilliseconds / 1000;
          Future<void> adjust(Duration delta) async {
            try {
              await controller.adjustSubtitleOffset(delta);
            } catch (_) {
              // The controller exposes the failure below and restores the offset.
            }
          }

          return AlertDialog(
            title: const Text('Sincronia da legenda'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Negativo: adiantar. Positivo: atrasar. Ajuste de até ±60 s.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${seconds >= 0 ? '+' : ''}${seconds.toStringAsFixed(1)} s',
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      for (final ms in [-1000, -500, 500, 1000])
                        TextButton(
                          onPressed: controller.canAdjustSubtitleOffset
                              ? () => adjust(Duration(milliseconds: ms))
                              : null,
                          child: Text(
                            '${ms > 0 ? '+' : '−'}${(ms.abs() / 1000).toStringAsFixed(1)} s',
                          ),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed:
                        controller.canAdjustSubtitleOffset && seconds != 0
                        ? () =>
                              adjust(Duration.zero - controller.subtitleOffset)
                        : null,
                    child: const Text('Restaurar 0 s'),
                  ),
                  if (controller.errorMessage != null)
                    Text(
                      controller.errorMessage!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  void _showTracksDialog(
    BuildContext context, {
    required String title,
    required List<MediaTrack> tracks,
    required MediaTrack? selected,
    required Future<void> Function(MediaTrack?) onConfirm,
  }) => showTrackPickerDialog<MediaTrack>(
    context,
    title: title,
    tracks: tracks,
    selected: selected,
    labelOf: (t) => t.title,
    detailOf: (t) => t.codec != null ? 'Codec: ${t.codec}' : null,
    onConfirm: onConfirm,
  );

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
            if (showTransportControls || showPlaybackModes)
              Container(
                decoration: AppColors.glassCardDecoration(
                  context,
                  borderRadius: 14,
                ),
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
                        onPressed:
                            enabled && (c.isPlaying ? c.canPause : c.canPlay)
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
                    if (showPlaybackModes)
                      IconButton(
                        tooltip: 'Repetir arquivo',
                        isSelected: enabled && c.isLooping,
                        style: modeToggleStyle(context, enabled && c.isLooping),
                        onPressed: enabled && (c.canLoop || c.isLooping)
                            ? c.toggleLoop
                            : null,
                        icon: const Icon(Icons.repeat),
                      ),
                    if (showPlaybackModes)
                      IconButton(
                        tooltip: 'Ordem aleatória dos arquivos selecionados',
                        isSelected: enabled && c.isShuffling,
                        style: modeToggleStyle(
                          context,
                          enabled && c.isShuffling,
                        ),
                        onPressed: enabled && c.canShuffle
                            ? c.toggleShuffle
                            : null,
                        icon: const Icon(Icons.shuffle),
                      ),
                  ],
                ),
              ),
            if (enabled && c.playlistCount > 1)
              Text('${c.playlistPosition} de ${c.playlistCount} arquivos'),
            // A linha do tempo depende do progresso informado pela TV; os
            // botões de legenda e áudio não — aparecem durante toda a
            // transmissão, mesmo que a TV ainda não informe a posição.
            if (enabled && showTimeline && (c.hasProgress || c.isStreaming))
              ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.hasProgress) ...[
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
                    ],
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (showTransportControls && c.hasProgress)
                          TextButton.icon(
                            onPressed: c.canSeek
                                ? () => c.seekTo(
                                    c.currentPosition -
                                        const Duration(seconds: 10),
                                  )
                                : null,
                            icon: const Icon(Icons.replay_10),
                            label: const Text('−10 s'),
                          ),
                        if (showTrackButtons)
                          MediaTrackButton(
                            icon: Icons.subtitles_outlined,
                            activeIcon: Icons.subtitles_rounded,
                            label: 'Legenda',
                            selectedTitle: c.selectedSubtitleTrack?.title,
                            tooltip: c.selectedSubtitleTrack != null
                                ? 'Legenda: ${c.selectedSubtitleTrack!.title}'
                                : 'Legendas embutidas',
                            onPressed: c.isStreaming
                                ? () => _showTracksDialog(
                                    context,
                                    title: 'Legendas',
                                    tracks: subtitles,
                                    selected: c.selectedSubtitleTrack,
                                    onConfirm: c.selectSubtitleTrack,
                                  )
                                : null,
                          ),
                        if (showTrackButtons &&
                            c.selectedSubtitleTrack != null &&
                            c.transport == MediaCastTransport.cast)
                          IconButton(
                            tooltip: 'Sincronia da legenda',
                            icon: const Icon(Icons.sync_alt_rounded, size: 20),
                            onPressed: c.canAdjustSubtitleOffset
                                ? () => _showSubtitleSync(context)
                                : null,
                          ),
                        if (showTrackButtons)
                          MediaTrackButton(
                            icon: Icons.audiotrack_outlined,
                            activeIcon: Icons.audiotrack_rounded,
                            label: 'Áudio',
                            selectedTitle: c.selectedAudioTrack?.title,
                            tooltip: c.selectedAudioTrack != null
                                ? 'Áudio: ${c.selectedAudioTrack!.title}'
                                : 'Faixa de áudio',
                            onPressed: c.isStreaming
                                ? () => _showTracksDialog(
                                    context,
                                    title: 'Faixas de Áudio',
                                    tracks: audios,
                                    selected: c.selectedAudioTrack,
                                    onConfirm: c.selectAudioTrack,
                                  )
                                : null,
                          ),
                        if (showTransportControls && c.hasProgress)
                          TextButton.icon(
                            onPressed: c.canSeek
                                ? () => c.seekTo(
                                    c.currentPosition +
                                        const Duration(seconds: 10),
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

/// Padrão de escolha de faixa (legenda ou áudio): abre a lista, o usuário
/// seleciona uma opção e só então aperta **Confirmar**. Usado tanto na
/// transmissão para a TV quanto no player deste aparelho.
void showTrackPickerDialog<T>(
  BuildContext context, {
  required String title,
  required List<T> tracks,
  required T? selected,
  required String Function(T) labelOf,
  String? Function(T)? detailOf,
  required Future<void> Function(T?) onConfirm,
}) {
  T? currentChoice = selected;
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
                            color: Theme.of(ctx).colorScheme.errorContainer
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
                                  color: Theme.of(ctx).colorScheme.secondary,
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
                          RadioListTile<T?>(
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
                            RadioListTile<T?>(
                              value: track,
                              groupValue: currentChoice,
                              title: Text(labelOf(track)),
                              subtitle: detailOf?.call(track) != null
                                  ? Text(detailOf!(track)!)
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
                                    ? '$title ativada: ${labelOf(currentChoice as T)}'
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
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .error,
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

/// Estilo dos botões Repetir e Aleatório: ligados ficam num círculo sólido
/// no destaque do tema (grafite no claro), para o estado ser visível.
ButtonStyle modeToggleStyle(BuildContext context, bool on) =>
    IconButton.styleFrom(
      backgroundColor: on ? AppColors.accentFillOf(context) : null,
      foregroundColor: on ? AppColors.onAccentOf(context) : null,
    );

/// Botão rotulado de faixa de mídia ("Legenda" / "Áudio"). Abre a lista de
/// faixas; a escolha só vale depois de confirmada no diálogo. Com uma faixa
/// ativa, o rótulo passa a ser o nome dela e o botão fica em destaque.
/// Com [iconOnly], vira um botão redondo só de ícone (linha de transporte).
class MediaTrackButton extends StatelessWidget {
  const MediaTrackButton({
    super.key,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.tooltip,
    this.selectedTitle,
    this.onPressed,
    this.iconOnly = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String tooltip;
  final String? selectedTitle;
  final VoidCallback? onPressed;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final active = selectedTitle != null;
    if (iconOnly) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(active ? activeIcon : icon),
        style: IconButton.styleFrom(
          backgroundColor: active ? AppColors.accentSoftOf(context) : null,
        ),
      );
    }
    final color = active
        ? AppColors.iconHighlightOf(context)
        : AppColors.textPrimaryOf(context);
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(active ? activeIcon : icon, size: 18),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            selectedTitle ?? label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: const StadiumBorder(),
          side: BorderSide(
            color: active ? color : AppColors.borderSubtleOf(context),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
