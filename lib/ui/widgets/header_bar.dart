import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'device_discovery_dialog.dart';
import 'remote_button.dart';

/// Barra Superior do controle remoto.
///
/// Contém o botão de Power, indicador interativo de status de conexão,
/// botão de busca e conexão de dispositivos (Cast/TV), alternador de Tema e abertura da gaveta.
class HeaderBar extends StatelessWidget {
  final VoidCallback onOpenDrawer;

  const HeaderBar({
    super.key,
    required this.onOpenDrawer,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();

    final isConnected = controller.isConnected;
    final isConnecting = controller.isConnecting;
    final isWaitingPairing = controller.isWaitingPairing;
    final isPoweredOn = controller.isPoweredOn;
    final isDarkMode = controller.isDarkMode;

    final statusColor = isConnecting
        ? AppColors.statusConnecting
        : (isWaitingPairing
            ? AppColors.buttonYellow
            : (isConnected ? AppColors.statusConnected : AppColors.statusDisconnected));

    final statusText = isConnecting
        ? 'Conectando...'
        : (isWaitingPairing
            ? 'Confirme na tela da TV'
            : (isConnected
                ? (controller.connectedTvName ?? 'Conectado (WebOS)')
                : 'Desconectado'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: Row(
        children: [
          // Botão Power com realce vermelho sutil
          RemoteButton(
            width: 42,
            height: 42,
            isCircular: true,
            hapticType: HapticType.medium,
            backgroundColor: isPoweredOn
                ? AppColors.powerRed.withValues(alpha: 0.15)
                : AppColors.surfaceInteractiveOf(context),
            borderColor: isPoweredOn ? AppColors.powerRed : AppColors.borderSubtleOf(context),
            foregroundColor: isPoweredOn ? AppColors.powerRed : AppColors.textMutedOf(context),
            icon: Icons.power_settings_new_rounded,
            iconSize: 22,
            tooltip: isPoweredOn ? 'Desligar TV' : 'Ligar TV (Wake-on-LAN)',
            onPressed: () => controller.powerToggle(),
          ),

          const SizedBox(width: 12),

          // Título e Status interativo (clicável para abrir a lista de dispositivos)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => DeviceDiscoveryDialog.show(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            'assets/icons/SixF_Logo_01.png',
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SixF',
                          style: TextStyle(
                            color: Color(0xFF00E5FF),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Remote',
                            style: TextStyle(
                              color: AppColors.textPrimaryOf(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        // LED indicador de conexão
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                            boxShadow: isConnected
                                ? [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.6),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Botão Buscar / Conectar TVs (Cast)
          RemoteButton(
            width: 38,
            height: 38,
            isCircular: true,
            backgroundColor: isConnected
                ? AppColors.statusConnected.withValues(alpha: 0.15)
                : (isConnecting
                    ? AppColors.statusConnecting.withValues(alpha: 0.15)
                    : AppColors.surfaceInteractiveOf(context)),
            borderColor: isConnected
                ? AppColors.statusConnected
                : (isConnecting
                    ? AppColors.statusConnecting
                    : AppColors.borderSubtleOf(context)),
            foregroundColor: isConnected
                ? AppColors.statusConnected
                : (isConnecting
                    ? AppColors.statusConnecting
                    : AppColors.textMutedOf(context)),
            icon: isConnected ? Icons.tv_rounded : Icons.cast_rounded,
            iconSize: 19,
            tooltip: isConnected
                ? 'TV Conectada: ${controller.connectedTvName ?? controller.ipAddress}'
                : (isConnecting
                    ? 'Conectando à TV...'
                    : 'Desconectado - Clique para Buscar e Conectar TVs LG'),
            onPressed: () => DeviceDiscoveryDialog.show(context),
          ),

          const SizedBox(width: 8),

          // Botão de alternância de Tema (Modo Claro / Modo Escuro)
          RemoteButton(
            width: 38,
            height: 38,
            isCircular: true,
            backgroundColor: AppColors.surfaceInteractiveOf(context),
            borderColor: AppColors.borderSubtleOf(context),
            foregroundColor: isDarkMode ? AppColors.buttonYellow : AppColors.iconHighlightOf(context),
            icon: isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            iconSize: 19,
            tooltip: isDarkMode ? 'Mudar para Modo Claro' : 'Mudar para Modo Escuro',
            onPressed: () => controller.toggleTheme(),
          ),

          const SizedBox(width: 8),

          // Botão para abrir o Drawer de configurações
          RemoteButton(
            width: 38,
            height: 38,
            isCircular: true,
            backgroundColor: AppColors.surfaceInteractiveOf(context),
            borderColor: AppColors.borderSubtleOf(context),
            foregroundColor: AppColors.textSecondaryOf(context),
            icon: Icons.tune_rounded,
            iconSize: 19,
            tooltip: 'Configurações de Rede (IP / MAC)',
            onPressed: onOpenDrawer,
          ),
        ],
      ),
    );
  }
}
