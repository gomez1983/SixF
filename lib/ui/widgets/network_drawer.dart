import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_driver.dart';
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
                            controller.currentBrand.displayName,
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
                                key: const Key('drawer_theme_switch'),
                                value: isDarkMode,
                                activeThumbColor: AppColors.lgRed,
                                onChanged: (_) => controller.toggleTheme(),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Card de Seleção de Marca
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceCardOf(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderSubtleOf(context)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Marca / Plataforma da TV',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: TvBrand.values.map((brand) {
                                  final isSelected = controller.currentBrand == brand;
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 2),
                                      child: InkWell(
                                        onTap: () => controller.selectBrand(brand),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? AppColors.surfaceElevatedOf(context)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isSelected ? AppColors.iconHighlightOf(context) : AppColors.borderSubtleOf(context),
                                              width: isSelected ? 1.5 : 1,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              brand == TvBrand.lgWebOs
                                                  ? 'LG webOS'
                                                  : 'Samsung Tizen',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                color: isSelected
                                                    ? AppColors.textPrimaryOf(context)
                                                    : AppColors.textSecondaryOf(context),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
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
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.tv_rounded,
                                        color: AppColors.buttonYellow, size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        controller.supportsPairingPin
                                            ? 'A TV está exibindo um código PIN. Digite o código para parear:'
                                            : 'Aviso na tela da TV: por favor, clique em "Permitir" na sua TV para autorizar o controle.',
                                        style: TextStyle(
                                          color: AppColors.textPrimaryOf(context),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
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

                        // Seção de Múltiplos Dispositivos Salvos (Multi-Device)
                        _buildSavedDevicesSection(context, controller),

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

                        // Preferência de Feedback Háptico / Vibração
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevatedOf(context).withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderSubtleOf(context)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: controller.isHapticEnabled
                                      ? AppColors.iconHighlightOf(context).withValues(alpha: 0.15)
                                      : AppColors.surfaceInteractiveOf(context),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.vibration_rounded,
                                  size: 18,
                                  color: controller.isHapticEnabled
                                      ? AppColors.iconHighlightOf(context)
                                      : AppColors.textSecondaryOf(context),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Vibração nos Botões',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimaryOf(context),
                                      ),
                                    ),
                                    Text(
                                      'Feedback tátil ao pressionar (Android)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondaryOf(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                key: const Key('drawer_haptic_switch'),
                                value: controller.isHapticEnabled,
                                activeThumbColor: AppColors.iconHighlightOf(context),
                                onChanged: (val) => controller.setHapticFeedback(val),
                              ),
                            ],
                          ),
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

  Widget _buildSavedDevicesSection(BuildContext context, RemoteController controller) {
    final devices = controller.savedDevices;
    final activeId = controller.activeDeviceId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Dispositivos Salvos (${devices.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryOf(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (devices.length > 1)
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => controller.connectAllDevices(),
                child: const Text('Conectar Todos', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...devices.map((device) {
          final isActive = device.id == activeId;
          final isConnected = controller.isDeviceConnected(device.id);
          final isConnecting = controller.isDeviceConnecting(device.id);

          final isDark = controller.isDarkMode;
          final highlight = isDark ? AppColors.iconHighlight : AppColors.lightIconHighlight;
          final textColor = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
          final mutedColor = isDark ? AppColors.textMuted : AppColors.lightTextMuted;
          final secColor = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? highlight.withValues(alpha: isDark ? 0.12 : 0.08)
                  : (isDark ? AppColors.surfaceCard : AppColors.lightSurfaceCard),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? highlight
                    : (isDark ? AppColors.borderSubtle : AppColors.lightBorderSubtle),
                width: isActive ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                // LED de Status
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? AppColors.statusConnected
                        : (isConnecting
                            ? AppColors.statusConnecting
                            : AppColors.statusDisconnected),
                  ),
                ),
                const SizedBox(width: 8),

                // Ícone da Marca
                Icon(
                  device.brand == TvBrand.lgWebOs
                      ? Icons.smart_screen_rounded
                      : Icons.tv_rounded,
                  size: 18,
                  color: isActive ? highlight : secColor,
                ),
                const SizedBox(width: 8),

                // Dados do Aparelho (clicável para selecionar o ativo)
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (!isActive) {
                        controller.setActiveDevice(device.id);
                        _ipController.text = device.ip;
                        _macController.text = device.mac;
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                device.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                                  color: textColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (device.isDefault) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.star_rounded, size: 12, color: Colors.amber.shade400),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${device.brand.displayName} • ${device.ip}',
                          style: TextStyle(
                            fontSize: 10,
                            color: mutedColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // Botão Conectar / Desconectar individual
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: isConnecting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isConnected ? Icons.link_off_rounded : Icons.link_rounded,
                          size: 18,
                          color: isConnected ? AppColors.powerRed : AppColors.statusConnected,
                        ),
                  tooltip: isConnected ? 'Desconectar' : 'Conectar',
                  onPressed: isConnecting
                      ? null
                      : () {
                          if (isConnected) {
                            controller.disconnectDevice(device.id);
                          } else {
                            controller.connectDevice(device.id);
                          }
                        },
                ),

                // Menu Popup de opções do dispositivo
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  onSelected: (val) {
                    if (val == 'default') {
                      controller.setDefaultDevice(device.id);
                    } else if (val == 'edit') {
                      _showEditDeviceDialog(device, controller);
                    } else if (val == 'delete') {
                      controller.removeSavedDevice(device.id);
                    }
                  },
                  itemBuilder: (_) => [
                    if (!device.isDefault)
                      const PopupMenuItem(
                        value: 'default',
                        child: Text('Tornar principal'),
                      ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Editar apelido'),
                    ),
                    if (devices.length > 1)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Remover', style: TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  void _showEditDeviceDialog(SavedDevice device, RemoteController controller) {
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
