import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

/// Teclado Numérico clássico com teclas de 0 a 9, traço (-) e Backspace.
class NumericKeypad extends StatelessWidget {
  /// Altura de cada tecla.
  final double keyHeight;

  const NumericKeypad({super.key, this.keyHeight = 48});

  @override
  Widget build(BuildContext context) {
    final controller = context.read<RemoteController>();

    final keys = [
      _KeypadItem.digit(1),
      _KeypadItem.digit(2),
      _KeypadItem.digit(3),
      _KeypadItem.digit(4),
      _KeypadItem.digit(5),
      _KeypadItem.digit(6),
      _KeypadItem.digit(7),
      _KeypadItem.digit(8),
      _KeypadItem.digit(9),
      _KeypadItem.dash(),
      _KeypadItem.digit(0),
      _KeypadItem.backspace(),
    ];

    // Padrão Payno: teclas cinza-claras lisas, números em peso leve.
    final rows = <List<_KeypadItem>>[
      for (var i = 0; i < keys.length; i += 3) keys.sublist(i, i + 3),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 9),
          Row(
            children: [
              for (var c = 0; c < 3; c++) ...[
                if (c > 0) const SizedBox(width: 9),
                Expanded(child: _key(context, controller, rows[r][c])),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _key(BuildContext context, RemoteController controller, _KeypadItem item) {
    return RemoteButton(
      height: keyHeight,
      borderRadius: 16,
      backgroundColor: AppColors.surfaceInteractiveOf(context),
      foregroundColor: item.isAction
          ? AppColors.textMutedOf(context)
          : AppColors.textPrimaryOf(context),
      icon: item.icon,
      iconSize: 20,
      tooltip: item.tooltip,
      onPressed: () {
        if (item.digit != null) {
          controller.sendDigit(item.digit!);
        } else if (item.isDash) {
          controller.sendDash();
        } else if (item.isBackspace) {
          controller.sendBackspace();
        }
      },
      child: item.label == null
          ? null
          : Text(
              item.label!,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w300,
                color: item.isAction
                    ? AppColors.textMutedOf(context)
                    : AppColors.textPrimaryOf(context),
              ),
            ),
    );
  }
}

class _KeypadItem {
  final int? digit;
  final String? label;
  final IconData? icon;
  final String tooltip;
  final bool isDash;
  final bool isBackspace;
  final bool isAction;

  _KeypadItem.digit(int d)
      : digit = d,
        label = '$d',
        icon = null,
        tooltip = 'Número $d',
        isDash = false,
        isBackspace = false,
        isAction = false;

  _KeypadItem.dash()
      : digit = null,
        label = '—',
        icon = null,
        tooltip = 'Subcanal / Traço (-)',
        isDash = true,
        isBackspace = false,
        isAction = true;

  _KeypadItem.backspace()
      : digit = null,
        label = null,
        icon = Icons.backspace_outlined,
        tooltip = 'Apagar / Limpar',
        isDash = false,
        isBackspace = true,
        isAction = true;
}
