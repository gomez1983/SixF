import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/remote_controller.dart';
import '../theme/app_colors.dart';
import 'remote_button.dart';

/// Teclado Numérico clássico com teclas de 0 a 9, traço (-) e Backspace.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({super.key});

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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtleOf(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grade 3x4
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: keys.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
            ),
            itemBuilder: (context, index) {
              final item = keys[index];
              return RemoteButton(
                borderRadius: 10,
                backgroundColor: item.isAction
                    ? AppColors.surfaceElevatedOf(context)
                    : AppColors.surfaceInteractiveOf(context),
                foregroundColor: item.isAction
                    ? AppColors.iconHighlightOf(context)
                    : AppColors.textPrimaryOf(context),
                label: item.label,
                icon: item.icon,
                iconSize: 18,
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
              );
            },
          ),
        ],
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
