import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../../services/haptic_service.dart';
import 'payno.dart';

/// Botões de Navegação do Sistema: Home, Menu/Configurações, Entrada e Exit.
class SystemNavigationControls extends StatelessWidget {
  final double circleSize;

  const SystemNavigationControls({super.key, this.circleSize = 48});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<RemoteController>();

    final buttons = [
      _NavAction(
        icon: Icons.home_outlined,
        label: 'HOME',
        tooltip: 'Página Inicial (WebOS Dashboard)',
        onPressed: () => controller.pressHome(),
      ),
      _NavAction(
        icon: Icons.settings_outlined,
        label: 'MENU',
        tooltip: 'Menu de Ajustes Rápidos',
        onPressed: () => controller.pressMenu(),
      ),
      _NavAction(
        icon: Icons.login_rounded,
        label: 'INPUT',
        tooltip: 'Alternar Entrada / Fonte (HDMI, AV, TV)',
        onPressed: () => controller.navInput(),
      ),
      _NavAction(
        icon: Icons.logout_rounded,
        label: 'EXIT',
        tooltip: 'Fechar aplicativo / Sair da transmissão',
        onPressed: () => controller.pressExit(),
      ),
    ];

    // Padrão Payno ("Quick Actions"): círculos brancos com o rótulo abaixo.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: buttons.map((btn) {
        return Expanded(
          child: PaynoActionCircle(
            icon: btn.icon,
            label: btn.label,
            size: circleSize,
            tooltip: btn.tooltip,
            onPressed: () {
              HapticService.buttonPress();
              btn.onPressed();
            },
          ),
        );
      }).toList(),
    );
  }
}

class _NavAction {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  const _NavAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });
}
