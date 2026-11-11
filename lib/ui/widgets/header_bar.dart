import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'device_discovery_dialog.dart';
import 'device_selector_bar.dart' show shortDeviceName;
import 'payno.dart';
import 'remote_button.dart';
import 'connection_diagnostic.dart';

/// Barra Superior do controle remoto.
///
/// Contém o botão de Power, indicador interativo de status de conexão,
/// botão de busca e conexão de dispositivos (Cast/TV), alternador de Tema e abertura da gaveta.
class HeaderBar extends StatelessWidget {
  final VoidCallback onOpenDrawer;
  final VoidCallback? onToggleCompact;

  const HeaderBar({
    super.key,
    required this.onOpenDrawer,
    this.onToggleCompact,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();

    final isConnected = controller.isConnected;
    final isConnecting = controller.isConnecting;
    final isWaitingPairing = controller.isWaitingPairing;
    final statusColor = isConnecting
        ? AppColors.statusConnecting
        : (isWaitingPairing
              ? AppColors.buttonYellow
              : (isConnected
                    ? AppColors.statusConnected
                    : AppColors.statusDisconnected));

    final statusText = isConnected
        ? shortDeviceName(controller.connectedTvName ?? 'Conectado')
        : controller.connectionStatusLabel;

    // Padrão Payno: logotipo circular, saudação pequena ("SixF Remote") sobre
    // o nome do aparelho em destaque e ações em círculos brancos à direita.
    return LayoutBuilder(
      builder: (context, box) {
        // Janela/tela estreita: círculos e logotipo menores para o nome do
        // aparelho continuar legível.
        final narrow = box.maxWidth < 430;
        final c = narrow ? 32.0 : 36.0;
        final gap = narrow ? 4.0 : 6.0;
        return _build(
          context,
          controller,
          statusColor,
          statusText,
          c,
          gap,
          narrow,
        );
      },
    );
  }

  Widget _build(
    BuildContext context,
    RemoteController controller,
    Color statusColor,
    String statusText,
    double c,
    double gap,
    bool narrow,
  ) {
    final isConnected = controller.isConnected;
    final isConnecting = controller.isConnecting;
    final isPoweredOn = controller.isPoweredOn;
    final isDarkMode = controller.isDarkMode;

    Widget circle({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      Color? fg,
      HapticType haptic = HapticType.light,
    }) => Padding(
      padding: EdgeInsets.only(left: gap),
      child: RemoteButton(
        width: c,
        height: c,
        isCircular: true,
        hapticType: haptic,
        foregroundColor: fg ?? AppColors.textPrimaryOf(context),
        icon: icon,
        iconSize: 18,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          // Logotipo e status (clicável para abrir o diagnóstico de conexão)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const ConnectionDiagnostic(),
              ),
              child: Row(
                children: [
                  PaynoLogo(size: narrow ? 34 : 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'SixF',
                                style: TextStyle(
                                  color: AppColors.textPrimaryOf(context),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Remote',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondaryOf(context),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: AppColors.textPrimaryOf(context),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: -0.2,
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
                ],
              ),
            ),
          ),

          if (onToggleCompact != null)
            circle(
              icon: Icons.picture_in_picture_alt_rounded,
              tooltip: 'Modo compacto',
              onPressed: onToggleCompact,
            ),

          circle(
            icon: Icons.power_settings_new_rounded,
            tooltip: isPoweredOn ? 'Desligar TV' : 'Ligar TV (Wake-on-LAN)',
            haptic: HapticType.medium,
            fg: isPoweredOn
                ? AppColors.powerRed
                : AppColors.textMutedOf(context),
            onPressed: () => controller.powerToggle(),
          ),

          // Botão Buscar / Conectar TVs (Cast)
          SizedBox(width: gap),
          RemoteButton(
            width: c,
            height: c,
            isCircular: true,
            foregroundColor: isConnected
                ? AppColors.okOf(context)
                : (isConnecting
                      ? AppColors.statusConnecting
                      : AppColors.textPrimaryOf(context)),
            icon: isConnected ? Icons.tv_rounded : Icons.cast_rounded,
            iconSize: 18,
            tooltip: isConnected
                ? 'TV Conectada: ${controller.connectedTvName ?? controller.ipAddress}'
                : (isConnecting
                      ? 'Conectando à TV...'
                      : 'Desconectado - Clique para Buscar e Conectar TVs LG'),
            onPressed: () => DeviceDiscoveryDialog.show(context),
          ),

          // Alternância de Tema (Modo Claro / Modo Escuro)
          circle(
            icon: isDarkMode
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            tooltip: isDarkMode
                ? 'Mudar para Modo Claro'
                : 'Mudar para Modo Escuro',
            onPressed: () => controller.toggleTheme(),
          ),

          // Gaveta de configurações
          circle(
            icon: Icons.tune_rounded,
            tooltip: 'Configurações de Rede (IP / MAC)',
            onPressed: onOpenDrawer,
          ),
        ],
      ),
    );
  }
}
