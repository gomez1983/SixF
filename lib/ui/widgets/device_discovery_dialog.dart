import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';

/// Modal para busca e seleção de TVs LG na rede local.
///
/// Exibe a lista de dispositivos compatíveis encontrados com seu nome amigável
/// (ex: "André TV"), modelo e IP, com botão direto de conexão.
class DeviceDiscoveryDialog extends StatefulWidget {
  const DeviceDiscoveryDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const DeviceDiscoveryDialog(),
    );
  }

  @override
  State<DeviceDiscoveryDialog> createState() => _DeviceDiscoveryDialogState();
}

class _DeviceDiscoveryDialogState extends State<DeviceDiscoveryDialog> {
  late final TextEditingController _manualIpController;
  bool _showManualIp = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<RemoteController>();
    _manualIpController = TextEditingController(text: controller.ipAddress);

    // Inicia a varredura automaticamente ao abrir o diálogo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<RemoteController>().scanForTvs();
      }
    });
  }

  @override
  void dispose() {
    _manualIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final isScanning = controller.isScanningTvs;
    final tvs = controller.discoveredTvs;
    final isConnected = controller.isConnected;
    final currentIp = controller.ipAddress;
    final isConnecting = controller.isConnecting;

    return Dialog(
      backgroundColor: AppColors.remoteChassisOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppColors.borderSubtleOf(context)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevatedOf(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.tv_rounded,
                      color: AppColors.lgRed,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dispositivos na Rede',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        Text(
                          'Smart TVs LG compatíveis',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondaryOf(context)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Botão de Varredura / Status
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCardOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderSubtleOf(context)),
                ),
                child: Row(
                  children: [
                    if (isScanning)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppColors.lgRed,
                        ),
                      )
                    else
                      Icon(
                        Icons.wifi_find_rounded,
                        size: 20,
                        color: AppColors.iconHighlightOf(context),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isScanning
                            ? 'Procurando dispositivos na rede local...'
                            : '${tvs.length} dispositivo(s) encontrado(s)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceInteractiveOf(context),
                        foregroundColor: AppColors.textPrimaryOf(context),
                        elevation: 0,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: isScanning ? null : () => controller.scanForTvs(),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Buscar', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Lista de Dispositivos Encontrados
              Expanded(
                child: tvs.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isScanning
                                    ? Icons.radar_rounded
                                    : Icons.tv_off_rounded,
                                size: 48,
                                color: AppColors.textMutedOf(context),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                isScanning
                                    ? 'Buscando sua Smart TV LG...'
                                    : 'Nenhuma TV LG localizada automaticamente.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Certifique-se de que a TV esteja ligada e conectada na mesma rede Wi-Fi.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMutedOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: tvs.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final tv = tvs[index];
                          final isThisTvConnected =
                              isConnected && currentIp == tv.ip;
                          final isThisTvConnecting =
                              isConnecting && currentIp == tv.ip;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isThisTvConnected
                                  ? AppColors.statusConnected.withValues(alpha: 0.12)
                                  : AppColors.surfaceCardOf(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isThisTvConnected
                                    ? AppColors.statusConnected
                                    : AppColors.borderSubtleOf(context),
                                width: isThisTvConnected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isThisTvConnected
                                        ? AppColors.statusConnected
                                            .withValues(alpha: 0.2)
                                        : AppColors.surfaceInteractiveOf(context),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.tv_rounded,
                                    color: isThisTvConnected
                                        ? AppColors.statusConnected
                                        : AppColors.iconHighlightOf(context),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tv.name,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimaryOf(context),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'IP: ${tv.ip}${tv.modelName != null ? ' • ${tv.modelName}' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondaryOf(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                if (isThisTvConnected)
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.powerRed
                                          .withValues(alpha: 0.15),
                                      foregroundColor: AppColors.powerRed,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                    ),
                                    onPressed: () => controller.disconnect(),
                                    child: const Text('Desconectar',
                                        style: TextStyle(fontSize: 12)),
                                  )
                                else if (isThisTvConnecting)
                                  const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.lgRed,
                                    ),
                                  )
                                else
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.lgRed,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                    ),
                                    onPressed: () async {
                                      await controller.connectToTv(tv);
                                      if (context.mounted &&
                                          controller.isConnected) {
                                        Navigator.of(context).pop();
                                      }
                                    },
                                    child: const Text('Conectar',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 12),

              // Alternador para Conexão Manual por IP
              InkWell(
                onTap: () {
                  setState(() {
                    _showManualIp = !_showManualIp;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        _showManualIp
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppColors.textSecondaryOf(context),
                      ),
                      Expanded(
                        child: Text(
                          'Conectar digitando o IP manualmente',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context),
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_showManualIp) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualIpController,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimaryOf(context),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Ex: 192.168.1.150',
                          prefixIcon: Icon(Icons.lan_rounded, size: 18),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceInteractiveOf(context),
                        foregroundColor: AppColors.textPrimaryOf(context),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onPressed: () async {
                        final ip = _manualIpController.text.trim();
                        if (ip.isNotEmpty) {
                          await controller.connect(ip: ip, tvName: 'LG Smart TV ($ip)');
                          if (context.mounted && controller.isConnected) {
                            Navigator.of(context).pop();
                          }
                        }
                      },
                      child: const Text('Conectar', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
