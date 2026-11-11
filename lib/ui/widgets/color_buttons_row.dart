import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

/// Quatro botões coloridos tradicionais de Smart TV LG (Vermelho, Verde, Amarelo e Azul).
class ColorButtonsRow extends StatelessWidget {
  /// Botões por linha (4 = uma linha; 2 = grade 2x2).
  final int columns;

  const ColorButtonsRow({super.key, this.columns = 4});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<RemoteController>();

    final colorButtons = [
      _ColorData(
        label: 'VERMELHO',
        color: AppColors.buttonRed,
        tooltip: 'Função Vermelho / Opção A',
        onPressed: () => controller.pressColorRed(),
      ),
      _ColorData(
        label: 'VERDE',
        color: AppColors.buttonGreen,
        tooltip: 'Função Verde / Opção B',
        onPressed: () => controller.pressColorGreen(),
      ),
      _ColorData(
        label: 'AMARELO',
        color: AppColors.buttonYellow,
        tooltip: 'Função Amarelo / Opção C',
        onPressed: () => controller.pressColorYellow(),
      ),
      _ColorData(
        label: 'AZUL',
        color: AppColors.buttonBlue,
        tooltip: 'Função Azul / Opção D',
        onPressed: () => controller.pressColorBlue(),
      ),
    ];

    // Padrão Payno: pílulas neutras com um ponto colorido e o rótulo escuro.
    Widget button(_ColorData btn) => RemoteButton(
      height: 38,
      borderRadius: 14,
      backgroundColor: AppColors.surfaceInteractiveOf(context),
      tooltip: btn.tooltip,
      onPressed: btn.onPressed,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: btn.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              btn.label,
              style: TextStyle(
                color: AppColors.textPrimaryOf(context),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
    final rows = <List<_ColorData>>[
      for (var i = 0; i < colorButtons.length; i += columns)
        colorButtons.sublist(i, (i + columns).clamp(0, colorButtons.length)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var c = 0; c < rows[r].length; c++) ...[
                if (c > 0) const SizedBox(width: 8),
                Expanded(child: button(rows[r][c])),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _ColorData {
  final String label;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  const _ColorData({
    required this.label,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });
}
