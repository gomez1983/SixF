import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'connection_diagnostic.dart';
import 'device_discovery_dialog.dart';
import 'device_selector_bar.dart';
import 'payno.dart';

/// Card "Aparelho ativo" do desktop, no lugar do cartão de crédito do padrão
/// Payno: gradiente azul-aço com nome, marca, IP e status do aparelho, e
/// atalhos para diagnóstico, busca, opções do aparelho e energia.
class ActiveDeviceCard extends StatelessWidget {
  const ActiveDeviceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final device = controller.activeDevice;
    final dark = AppColors.isDark(context);
    final ink = dark ? Colors.white : const Color(0xFF2A2A29);
    final connected = controller.isConnected;
    final status = connected
        ? 'Conectado'
        : controller.isConnecting
        ? 'Conectando...'
        : 'Desconectado';

    final visual = Container(
      height: 150,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF232322), Color(0xFF333332), Color(0xFF545451), Color(0xFF8A8A85)]
              : const [Color(0xFFF4F4F2), Color(0xFFDADAD6), Color(0xFF8E8E89), Color(0xFF414140)],
          stops: const [0, 0.32, 0.66, 1],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x40282826), blurRadius: 30, offset: Offset(0, 14)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Icon(Icons.tv_rounded, size: 22, color: ink.withValues(alpha: 0.8)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected
                          ? AppColors.okOf(context)
                          : controller.isConnecting
                          ? AppColors.statusConnecting
                          : ink.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: ink.withValues(alpha: 0.85)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                shortDeviceName(
                  device?.name ?? controller.connectedTvName ?? 'Nenhum aparelho',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, color: ink, letterSpacing: -0.2),
              ),
              const SizedBox(height: 3),
              Text(
                '${controller.driver.brandDisplayName} · ${controller.ipAddress}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: ink.withValues(alpha: 0.75)),
              ),
            ],
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Text(
              controller.driver.brandDisplayName.split(' ').first,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceInteractiveOf(context),
                    border: Border.all(color: AppColors.borderSubtleOf(context)),
                  ),
                  child: Icon(icon, size: 17, color: AppColors.textPrimaryOf(context)),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: AppColors.textMutedOf(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return PaynoCard(
      title: 'Aparelho ativo',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          visual,
          const SizedBox(height: 12),
          Row(
            children: [
              action(
                Icons.monitor_heart_outlined,
                'Diagnóstico',
                () => showDialog<void>(
                  context: context,
                  builder: (_) => const ConnectionDiagnostic(),
                ),
              ),
              action(
                Icons.wifi_find_rounded,
                'Buscar',
                () => DeviceDiscoveryDialog.show(context),
              ),
              if (device != null)
                action(
                  Icons.more_horiz_rounded,
                  'Opções',
                  () => const DeviceSelectorBar().showDeviceOptions(
                    context,
                    controller,
                    device,
                  ),
                ),
              action(
                Icons.power_settings_new_rounded,
                controller.isPoweredOn ? 'Desligar' : 'Ligar',
                controller.powerToggle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
