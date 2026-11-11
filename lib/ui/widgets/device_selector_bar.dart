import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_driver.dart';
import '../../services/haptic_service.dart';
import '../theme/app_colors.dart';
import 'device_discovery_dialog.dart';

/// Nome curto para exibição: sem o IP entre parênteses nem o complemento
/// depois de " / " ("Smart TV (192.168.15.4)" → "Smart TV";
/// "Chromecast / Google TV" → "Chromecast"). O apelido salvo não muda.
String shortDeviceName(String name) {
  var out = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
  final slash = out.indexOf(' / ');
  if (slash > 0) out = out.substring(0, slash);
  out = out.trim();
  return out.isEmpty ? name.trim() : out;
}

/// Ícone do tipo de aparelho (TV LG, TV Samsung ou Chromecast).
IconData brandIcon(TvBrand brand) => switch (brand) {
  TvBrand.lgWebOs => Icons.tv_rounded,
  TvBrand.samsungTizen => Icons.connected_tv_rounded,
  TvBrand.googleTv => Icons.cast_rounded,
};

/// Barra horizontal de seleção e alternância rápida entre múltiplos dispositivos Smart TV (Pills/Chips).
///
/// Permite alternar o controle ativo com 1 clique (hot-switch), visualizar o status
/// de conexão simultânea de cada aparelho (LED verde/amarelo/cinza) e adicionar novos aparelhos.
class DeviceSelectorBar extends StatelessWidget {
  const DeviceSelectorBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final devices = controller.savedDevices;
    final activeId = controller.activeDeviceId;

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: devices.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == devices.length) {
            return _buildAddDevicePill(context, controller);
          }

          final device = devices[index];
          final isActive = device.id == activeId;
          final isConnected = controller.isDeviceConnected(device.id);
          final isConnecting = controller.isDeviceConnecting(device.id);

          return _buildDevicePill(
            context,
            controller: controller,
            device: device,
            isActive: isActive,
            isConnected: isConnected,
            isConnecting: isConnecting,
          );
        },
      ),
    );
  }

  Widget _buildDevicePill(
    BuildContext context, {
    required RemoteController controller,
    required SavedDevice device,
    required bool isActive,
    required bool isConnected,
    required bool isConnecting,
  }) {
    // Padrão Payno: pílulas brancas translúcidas; a ativa em texto escuro e
    // borda azul-marinho, as demais em cinza.
    // Cor do texto pelo tema salvo no controller (contraste garantido mesmo
    // antes de o MaterialApp trocar o tema).
    final isDark = controller.isDarkMode;
    final textColor = isActive
        ? (isDark ? AppColors.textPrimary : AppColors.lightTextPrimary)
        : (isDark ? AppColors.textMuted : AppColors.lightTextMuted);
    final iconColor = isActive
        ? AppColors.iconHighlightOf(context)
        : AppColors.textMutedOf(context);
    final borderColor = isActive
        ? AppColors.iconHighlightOf(context).withValues(alpha: 0.55)
        : AppColors.borderSubtleOf(context);
    final bgColor = isActive
        ? AppColors.circleOf(context)
        : AppColors.cardOf(context);

    final statusColor = isConnected
        ? AppColors.okOf(context)
        : (isConnecting
            ? AppColors.statusConnecting
            : AppColors.textMutedOf(context).withValues(alpha: 0.6));

    return InkWell(
      onTap: () {
        if (!isActive) {
          controller.setActiveDevice(device.id);
        }
        if (!isConnected && !isConnecting) {
          HapticService.selectionClick();
          controller.connectDevice(device.id);
        }
      },
      onLongPress: () {
        HapticService.heavyPress();
        _showDeviceOptionsModal(context, controller, device);
      },
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
          boxShadow: isActive ? AppColors.softShadowOf(context) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // LED de conexão
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 8),

            // Ícone da Marca (LG ou Samsung)
            Icon(brandIcon(device.brand), size: 15, color: iconColor),
            const SizedBox(width: 6),

            // Nome curto do aparelho (o nome completo fica na dica)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Tooltip(
                message: device.name,
                child: Text(
                  shortDeviceName(device.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
            ),

            if (device.isDefault) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.star_rounded,
                size: 13,
                color: Colors.amber.shade400,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAddDevicePill(BuildContext context, RemoteController controller) {
    final highlightColor = AppColors.textMutedOf(context);

    return InkWell(
      onTap: () {
        HapticService.selectionClick();
        DeviceDiscoveryDialog.show(context);
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.textMutedOf(context).withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: 16,
              color: highlightColor,
            ),
            const SizedBox(width: 4),
            Text(
              'Novo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: highlightColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Abre o menu de opções do aparelho (conectar, renomear, remover...).
  /// Público para a interface Liquid Glass reaproveitar o mesmo menu.
  void showDeviceOptions(
    BuildContext context,
    RemoteController controller,
    SavedDevice device,
  ) => _showDeviceOptionsModal(context, controller, device);

  void _showDeviceOptionsModal(
    BuildContext context,
    RemoteController controller,
    SavedDevice device,
  ) {
    final isConnected = controller.isDeviceConnected(device.id);
    final isDark = controller.isDarkMode;
    final modalBg = isDark ? AppColors.remoteChassis : AppColors.lightRemoteChassis;
    final cardBg = isDark ? AppColors.surfaceElevated : AppColors.lightSurfaceElevated;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;
    final highlight = isDark ? AppColors.iconHighlight : AppColors.lightIconHighlight;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: modalBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        device.brand == TvBrand.lgWebOs
                            ? Icons.smart_screen_rounded
                            : Icons.tv_rounded,
                        color: highlight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            '${device.brand.displayName} • IP: ${device.ip}',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Conectar / Desconectar
                ListTile(
                  leading: Icon(
                    isConnected ? Icons.link_off_rounded : Icons.link_rounded,
                    color: isConnected ? AppColors.powerRed : AppColors.statusConnected,
                  ),
                  title: Text(isConnected ? 'Desconectar aparelho' : 'Conectar agora'),
                  onTap: () {
                    Navigator.of(modalContext).pop();
                    if (isConnected) {
                      controller.disconnectDevice(device.id);
                    } else {
                      controller.connectDevice(device.id);
                    }
                  },
                ),

                if (device.brand == TvBrand.googleTv)
                  ListTile(
                    leading: const Icon(Icons.phonelink_lock_rounded),
                    title: const Text('Refazer pareamento'),
                    onTap: () {
                      Navigator.of(modalContext).pop();
                      controller.repairGoogleTvPairing(device.id);
                    },
                  ),

                // Definir como padrão
                if (!device.isDefault)
                  ListTile(
                    leading: const Icon(Icons.star_outline_rounded, color: Colors.amber),
                    title: const Text('Definir como aparelho principal'),
                    onTap: () {
                      Navigator.of(modalContext).pop();
                      controller.setDefaultDevice(device.id);
                    },
                  ),

                // Renomear
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Editar apelido'),
                  onTap: () {
                    Navigator.of(modalContext).pop();
                    _showEditDeviceDialog(context, controller, device);
                  },
                ),

                // Excluir dispositivo salvo
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: AppColors.powerRed),
                  title: const Text('Remover do histórico',
                      style: TextStyle(color: AppColors.powerRed)),
                  onTap: () {
                    Navigator.of(modalContext).pop();
                    controller.removeSavedDevice(device.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditDeviceDialog(
    BuildContext context,
    RemoteController controller,
    SavedDevice device,
  ) {
    final nameCtrl = TextEditingController(text: device.name);
    final macCtrl = TextEditingController(text: device.mac);

    showDialog<void>(
      context: context,
      builder: (diagContext) => AlertDialog(
        backgroundColor: AppColors.remoteChassisOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Editar Aparelho'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Apelido (ex: Sala, Quarto)',
                prefixIcon: Icon(Icons.label_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: macCtrl,
              decoration: const InputDecoration(
                labelText: 'MAC Address (para Wake-on-LAN)',
                prefixIcon: Icon(Icons.perm_device_info_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(diagContext).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = nameCtrl.text.trim();
              if (newName.isNotEmpty) {
                final updated = device.copyWith(
                  name: newName,
                  mac: macCtrl.text.trim(),
                );
                controller.saveOrUpdateDevice(updated);
              }
              Navigator.of(diagContext).pop();
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
