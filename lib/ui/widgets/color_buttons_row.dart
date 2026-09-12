import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

/// Quatro botões coloridos tradicionais de Smart TV LG (Vermelho, Verde, Amarelo e Azul).
class ColorButtonsRow extends StatelessWidget {
  const ColorButtonsRow({super.key});

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

    return Row(
      children: colorButtons.map((btn) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: RemoteButton(
              height: 34,
              borderRadius: 17,
              backgroundColor: btn.color.withValues(alpha: 0.18),
              borderColor: btn.color.withValues(alpha: 0.7),
              foregroundColor: btn.color,
              tooltip: btn.tooltip,
              onPressed: btn.onPressed,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: btn.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: btn.color.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      btn.label,
                      style: TextStyle(
                        color: btn.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
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
