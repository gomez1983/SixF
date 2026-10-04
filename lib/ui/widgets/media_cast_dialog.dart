import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/media_cast_controller.dart';
import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_driver.dart';
import '../../services/haptic_service.dart';
import '../theme/app_colors.dart';

/// Modal interativo para seleção e transmissão de mídia local (Fotos, Vídeos e Áudio)
/// para a Smart TV conectada via protocolo aberto DLNA / UPnP AVTransport.
class MediaCastDialog extends StatelessWidget {
  const MediaCastDialog({super.key});

  /// Exibe o diálogo de transmissão de mídia.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const MediaCastDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteController = context.watch<RemoteController>();
    final castController = context.watch<MediaCastController>();

    final isDark = remoteController.isDarkMode;
    final chassisColor = isDark ? AppColors.remoteChassis : AppColors.lightRemoteChassis;
    final surfaceCard = isDark ? AppColors.surfaceCard : AppColors.lightSurfaceCard;
    final surfaceElevated = isDark ? AppColors.surfaceElevated : AppColors.lightSurfaceElevated;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;
    final borderSubtle = isDark ? AppColors.borderSubtle : AppColors.lightBorderSubtle;
    final highlight = isDark ? AppColors.iconHighlight : AppColors.lightIconHighlight;

    final targetIp = remoteController.ipAddress;
    final targetBrand = remoteController.currentBrand;
    final targetName = remoteController.connectedTvName ?? '${targetBrand.displayName} ($targetIp)';
    final isTvConnected = remoteController.isConnected;

    return Dialog(
      backgroundColor: chassisColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderSubtle, width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabeçalho
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: highlight.withValues(alpha: isDark ? 0.20 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.cast_connected_rounded, color: highlight, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Transmitir Mídia',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.statusConnected.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.statusConnected.withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Text(
                                'DLNA',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.statusConnected,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isTvConnected ? 'Destino: $targetName' : 'TV desconectada',
                          style: TextStyle(
                            fontSize: 12,
                            color: isTvConnected ? textSecondary : AppColors.powerRed,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fechar',
                  ),
                ],
              ),

              const Divider(height: 28),

              // Conteúdo Dinâmico conforme estado
              if (!isTvConnected) ...[
                _buildDisconnectedWarning(context, textPrimary, textSecondary, surfaceElevated),
              ] else if (castController.isStreaming) ...[
                _buildActivePlayerCard(
                  context,
                  castController,
                  textPrimary,
                  textSecondary,
                  surfaceCard,
                  surfaceElevated,
                  highlight,
                  borderSubtle,
                ),
              ] else if (castController.status == MediaCastStatus.picking ||
                  castController.status == MediaCastStatus.preparingServer ||
                  castController.status == MediaCastStatus.connectingTv) ...[
                _buildLoadingState(castController.status, textPrimary, textSecondary, highlight),
              ] else ...[
                Builder(
                  builder: (_) {
                    String? matchingLocation;
                    for (final tv in remoteController.discoveredTvs) {
                      if (tv.ip == targetIp && tv.location != null && tv.location!.isNotEmpty) {
                        matchingLocation = tv.location;
                        break;
                      }
                    }
                    return _buildMediaPickOptions(
                      context,
                      castController,
                      targetIp,
                      targetBrand,
                      targetName,
                      matchingLocation,
                      remoteController.isConnected ? remoteController.driver : null,
                      textPrimary,
                      textSecondary,
                      surfaceCard,
                      highlight,
                      borderSubtle,
                    );
                  },
                ),
              ],

              // Mensagem de Erro se houver
              if (castController.status == MediaCastStatus.error && castController.errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.powerRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.powerRed.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.powerRed, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          castController.errorMessage!,
                          style: const TextStyle(fontSize: 12, color: AppColors.powerRed),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisconnectedWarning(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color surfaceElevated,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(Icons.tv_off_rounded, color: AppColors.powerRed, size: 36),
          const SizedBox(height: 10),
          Text(
            'Conecte-se a uma Smart TV primeiro',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Para transmitir fotos e vídeos, verifique se a sua Smart TV LG ou Samsung está ligada na mesma rede Wi-Fi.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPickOptions(
    BuildContext context,
    MediaCastController castController,
    String targetIp,
    dynamic targetBrand,
    String targetName,
    String? locationUrl,
    TvDriver? activeDriver,
    Color textPrimary,
    Color textSecondary,
    Color surfaceCard,
    Color highlight,
    Color borderSubtle,
  ) {
    return Column(
      children: [
        _buildPickOptionTile(
          context,
          icon: Icons.photo_library_rounded,
          title: 'Fotos da Galeria',
          subtitle: 'Transmita imagens em alta resolução em tela cheia',
          accentColor: Colors.purpleAccent,
          onTap: () {
            castController.pickAndCastMedia(
              targetTvIp: targetIp,
              brand: targetBrand,
              tvName: targetName,
              locationUrl: locationUrl,
              activeDriver: activeDriver,
              fileType: FileType.image,
            );
          },
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          surfaceCard: surfaceCard,
          borderSubtle: borderSubtle,
        ),
        const SizedBox(height: 12),
        _buildPickOptionTile(
          context,
          icon: Icons.video_library_rounded,
          title: 'Vídeos do Celular / PC',
          subtitle: 'Streaming fluido com suporte a avanço e pausa',
          accentColor: highlight,
          onTap: () {
            castController.pickAndCastMedia(
              targetTvIp: targetIp,
              brand: targetBrand,
              tvName: targetName,
              locationUrl: locationUrl,
              activeDriver: activeDriver,
              fileType: FileType.video,
            );
          },
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          surfaceCard: surfaceCard,
          borderSubtle: borderSubtle,
        ),
        const SizedBox(height: 12),
        _buildPickOptionTile(
          context,
          icon: Icons.library_music_rounded,
          title: 'Músicas & Áudios',
          subtitle: 'Reproduza faixas e arquivos de áudio nos alto-falantes da TV',
          accentColor: Colors.amberAccent,
          onTap: () {
            castController.pickAndCastMedia(
              targetTvIp: targetIp,
              brand: targetBrand,
              tvName: targetName,
              locationUrl: locationUrl,
              activeDriver: activeDriver,
              fileType: FileType.audio,
            );
          },
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          surfaceCard: surfaceCard,
          borderSubtle: borderSubtle,
        ),
      ],
    );
  }

  Widget _buildPickOptionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required VoidCallback onTap,
    required Color textPrimary,
    required Color textSecondary,
    required Color surfaceCard,
    required Color borderSubtle,
  }) {
    return InkWell(
      onTap: () {
        HapticService.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: textSecondary, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildActivePlayerCard(
    BuildContext context,
    MediaCastController castController,
    Color textPrimary,
    Color textSecondary,
    Color surfaceCard,
    Color surfaceElevated,
    Color highlight,
    Color borderSubtle,
  ) {
    final fileName = castController.currentFileName ?? 'Mídia em reprodução';
    final isVideo = castController.isVideo;
    final isPhoto = castController.isPhoto;
    final isPlaying = castController.isPlaying;
    final sizeMb = (castController.currentFileSize != null)
        ? '${(castController.currentFileSize! / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: highlight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPhoto
                      ? Icons.image_rounded
                      : (isVideo ? Icons.movie_rounded : Icons.audiotrack_rounded),
                  color: highlight,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isPlaying ? AppColors.statusConnected : AppColors.buttonYellow,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPlaying ? 'Reproduzindo na TV' : 'Pausado',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isPlaying ? AppColors.statusConnected : AppColors.buttonYellow,
                          ),
                        ),
                        if (sizeMb.isNotEmpty) ...[
                          Text(' • $sizeMb', style: TextStyle(fontSize: 11, color: textSecondary)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Barra de Progresso / Timeline do Vídeo (Seek)
          if (!isPhoto) ...[
            const SizedBox(height: 12),
            Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: highlight,
                    inactiveTrackColor: highlight.withValues(alpha: 0.2),
                    thumbColor: highlight,
                  ),
                  child: Slider(
                    value: castController.currentPosition.inSeconds.toDouble().clamp(
                          0.0,
                          castController.totalDuration.inSeconds > 0
                              ? castController.totalDuration.inSeconds.toDouble()
                              : 100.0,
                        ),
                    max: castController.totalDuration.inSeconds > 0
                        ? castController.totalDuration.inSeconds.toDouble()
                        : 100.0,
                    onChanged: (val) {
                      castController.seekTo(Duration(seconds: val.toInt()));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(castController.currentPosition),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                      ),
                      Text(
                        castController.totalDuration > Duration.zero
                            ? _formatDuration(castController.totalDuration)
                            : '--:--',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // Barra de Controles (Play/Pause/Stop/Loop/Trocar)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Botão Repetir / Loop (apenas para vídeo e áudio)
              if (!isPhoto) ...[
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: castController.isLooping
                        ? highlight.withValues(alpha: 0.25)
                        : surfaceElevated,
                    foregroundColor: castController.isLooping ? highlight : textSecondary,
                  ),
                  icon: Icon(
                    Icons.repeat_rounded,
                    size: 20,
                    color: castController.isLooping ? highlight : textSecondary,
                  ),
                  tooltip: castController.isLooping ? 'Repetição Ativada' : 'Repetir Vídeo',
                  onPressed: () => castController.toggleLoop(),
                ),
                const SizedBox(width: 10),
              ],

              // Botão Parar (Stop)
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.powerRed.withValues(alpha: 0.15),
                  foregroundColor: AppColors.powerRed,
                ),
                icon: const Icon(Icons.stop_rounded, size: 24),
                tooltip: 'Parar Transmissão',
                onPressed: () => castController.stop(),
              ),

              const SizedBox(width: 12),

              // Botão Play / Pause
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: highlight,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.all(12),
                ),
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 28,
                ),
                tooltip: isPlaying ? 'Pausar' : 'Reproduzir',
                onPressed: () {
                  if (isPlaying) {
                    castController.pause();
                  } else {
                    castController.play();
                  }
                },
              ),

              const SizedBox(width: 12),

              // Botão Nova Mídia
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: surfaceElevated,
                  foregroundColor: textPrimary,
                ),
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 22),
                tooltip: 'Escolher outro arquivo',
                onPressed: () => castController.stop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildLoadingState(
    MediaCastStatus status,
    Color textPrimary,
    Color textSecondary,
    Color highlight,
  ) {
    String message = 'Conectando à Smart TV...';
    if (status == MediaCastStatus.picking) {
      message = 'Aguardando seleção do arquivo na galeria...';
    } else if (status == MediaCastStatus.preparingServer) {
      message = 'Iniciando servidor de streaming local...';
    } else if (status == MediaCastStatus.connectingTv) {
      message = 'Enviando comando DLNA para a TV...';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          CircularProgressIndicator(strokeWidth: 3, color: highlight),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'A TV irá carregar a mídia na resolução original',
            style: TextStyle(fontSize: 11, color: textSecondary),
          ),
        ],
      ),
    );
  }
}
