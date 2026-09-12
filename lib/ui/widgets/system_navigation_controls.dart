import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

/// Botões de Navegação do Sistema: Home, Menu/Configurações, Voltar e Exit.
class SystemNavigationControls extends StatelessWidget {
  const SystemNavigationControls({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<RemoteController>();

    final buttons = [
      _NavAction(
        icon: Icons.home_rounded,
        label: 'HOME',
        tooltip: 'Página Inicial (WebOS Dashboard)',
        onPressed: () => controller.pressHome(),
      ),
      _NavAction(
        icon: Icons.settings_rounded,
        label: 'MENU',
        tooltip: 'Menu de Ajustes Rápidos',
        onPressed: () => controller.pressMenu(),
      ),
      _NavAction(
        icon: Icons.undo_rounded,
        label: 'VOLTAR',
        tooltip: 'Voltar à tela anterior (Esc ou Backspace)',
        onPressed: () => controller.pressBack(),
      ),
      _NavAction(
        icon: Icons.exit_to_app_rounded,
        label: 'EXIT',
        tooltip: 'Fechar aplicativo / Sair da transmissão',
        onPressed: () => controller.pressExit(),
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: buttons.map((btn) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: RemoteButton(
              height: 52,
              borderRadius: 12,
              backgroundColor: AppColors.surfaceInteractiveOf(context),
              foregroundColor: AppColors.textPrimaryOf(context),
              icon: btn.icon,
              label: btn.label,
              iconSize: 18,
              tooltip: btn.tooltip,
              onPressed: btn.onPressed,
            ),
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
