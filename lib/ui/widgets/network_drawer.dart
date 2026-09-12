import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'device_discovery_dialog.dart';

/// Gaveta Lateral (Drawer) para configuração dos parâmetros de rede e preferências da Smart TV LG.
///
/// Permite definir e validar o IP e MAC Address, acionar conexão/desconexão,
/// buscar TVs automaticamente via SSDP (com nome amigável, ex: "André TV") e alternar o tema do app.
class NetworkDrawer extends StatefulWidget {
  const NetworkDrawer({super.key});

  @override
  State<NetworkDrawer> createState() => _NetworkDrawerState();
}

class _NetworkDrawerState extends State<NetworkDrawer> {
  late final TextEditingController _ipController;
  late final TextEditingController _macController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final controller = context.read<RemoteController>();
    _ipController = TextEditingController(text: controller.ipAddress);
    _macController = TextEditingController(text: controller.macAddress);
  }

  @override
  void dispose() {
    _ipController.dispose();
    _macController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final isConnected = controller.isConnected;
    final isConnecting = controller.isConnecting;
    final isWaitingPairing = controller.isWaitingPairing;
    final isDarkMode = controller.isDarkMode;
    final tvs = controller.discoveredTvs;

    return Drawer(
      backgroundColor: AppColors.remoteChassisOf(context),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabeçalho da Gaveta
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevatedOf(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.settings_ethernet_rounded,
                          color: AppColors.iconHighlightOf(context), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configurações',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          Text(
                            'LG webOS Smart TV',
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
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),

                const Divider(height: 24),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card de Alternância de Tema (Aparência)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceCardOf(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderSubtleOf(context)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                size: 20,
                                color: isDarkMode
                                    ? AppColors.buttonYellow
                                    : AppColors.iconHighlightOf(context),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  isDarkMode ? 'Modo Escuro (Dark)' : 'Modo Claro (Light)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                              ),
                              Switch(
                                value: isDarkMode,
                                activeThumbColor: AppColors.lgRed,
                                onChanged: (_) => controller.toggleTheme(),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Aviso de Pareamento na TV quando aplicável
                        if (isWaitingPairing) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.buttonYellow.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.buttonYellow.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.tv_rounded,
                                    color: AppColors.buttonYellow, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Aviso na tela da TV: por favor, clique em "Permitir" na sua TV LG para autorizar o controle.',
                                    style: TextStyle(
                                      color: AppColors.textPrimaryOf(context),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Card de status atual de rede
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceCardOf(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isConnected
                                  ? AppColors.statusConnected.withValues(alpha: 0.3)
                                  : AppColors.borderSubtleOf(context),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isConnecting
                                      ? AppColors.statusConnecting
                                      : (isConnected
                                          ? AppColors.statusConnected
                                          : AppColors.statusDisconnected),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isConnecting
                                          ? 'Tentando conexão...'
                                          : (isConnected
                                              ? 'Conectada: ${controller.connectedTvName ?? 'LG Smart TV'}'
                                              : 'Desconectada'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimaryOf(context),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'IP: ${controller.ipAddress} • Porta: 3000/3001',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMutedOf(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Card / Botão de Abertura de Busca de Dispositivos na Rede
                        InkWell(
                          onTap: () => DeviceDiscoveryDialog.show(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevatedOf(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.iconHighlightOf(context).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.radar_rounded, color: AppColors.lgRed, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Buscar TVs na Rede',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimaryOf(context),
                                        ),
                                      ),
                                      Text(
                                        'Ver lista de dispositivos compatíveis',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondaryOf(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Seção de TVs Encontradas se houver
                        if (tvs.isNotEmpty) ...[
                          Text(
                            'Dispositivos Encontrados:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...tvs.map((tv) {
                            final isThisConnected = isConnected && controller.ipAddress == tv.ip;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceCardOf(context),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isThisConnected
                                      ? AppColors.statusConnected
                                      : AppColors.borderSubtleOf(context),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.tv_rounded,
                                    size: 20,
                                    color: isThisConnected
                                        ? AppColors.statusConnected
                                        : AppColors.iconHighlightOf(context),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tv.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimaryOf(context),
                                          ),
                                        ),
                                        Text(
                                          tv.ip,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textMutedOf(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isThisConnected)
                                    const Text(
                                      'Conectada',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.statusConnected,
                                      ),
                                    )
                                  else
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () {
                                        _ipController.text = tv.ip;
                                        controller.connectToTv(tv);
                                      },
                                      child: const Text('Conectar', style: TextStyle(fontSize: 11)),
                                    ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                        ],

                        // Campos de IP e MAC para ajuste manual
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Endereço IP da TV',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: controller.isScanningTvs
                                    ? null
                                    : () async {
                                        final list = await controller.scanForTvs();
                                        if (list.isNotEmpty) {
                                          setState(() {
                                            _ipController.text = list.first.ip;
                                          });
                                        }
                                      },
                                icon: controller.isScanningTvs
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Icon(Icons.radar_rounded,
                                        size: 15, color: AppColors.iconHighlightOf(context)),
                                label: Text(
                                  controller.isScanningTvs ? 'Buscando...' : 'Auto-Detectar',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.iconHighlightOf(context),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _ipController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(fontSize: 14, color: AppColors.textPrimaryOf(context)),
                          decoration: const InputDecoration(
                            hintText: 'Ex: 192.168.1.150',
                            prefixIcon: Icon(Icons.wifi_rounded, size: 20),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe o endereço IP';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Campo MAC Address
                        Text(
                          'MAC Address',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _macController,
                          style: TextStyle(fontSize: 14, color: AppColors.textPrimaryOf(context)),
                          decoration: const InputDecoration(
                            hintText: 'Ex: A4:77:33:B2:9C:10',
                            prefixIcon: Icon(Icons.perm_device_info_rounded, size: 20),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe o MAC Address para Wake-on-LAN';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        // Botões de Conectar e Desconectar
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.statusConnected.withValues(alpha: 0.15),
                                  foregroundColor: AppColors.statusConnected,
                                  side: BorderSide(
                                    color: AppColors.statusConnected.withValues(alpha: 0.4),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                ),
                                onPressed: isConnecting
                                    ? null
                                    : () {
                                        if (_formKey.currentState?.validate() ?? false) {
                                          controller.connect(
                                            ip: _ipController.text,
                                            mac: _macController.text,
                                          );
                                        }
                                      },
                                icon: isConnecting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.statusConnected,
                                        ),
                                      )
                                    : const Icon(Icons.link_rounded, size: 18),
                                label: Text(isConnecting ? 'Conectando' : 'Conectar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.powerRed.withValues(alpha: 0.12),
                                  foregroundColor: AppColors.powerRed,
                                  side: BorderSide(
                                    color: AppColors.powerRed.withValues(alpha: 0.3),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                ),
                                onPressed: (!isConnected && !isConnecting)
                                    ? null
                                    : () {
                                        controller.disconnect();
                                      },
                                icon: const Icon(Icons.link_off_rounded, size: 18),
                                label: const Text('Desconectar'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Dica / Rodapé da Gaveta
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevatedOf(context).withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderSubtleOf(context)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 18, color: AppColors.textSecondaryOf(context)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'A Smart TV LG e o computador devem estar na mesma rede local Wi-Fi ou cabo.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondaryOf(context),
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
