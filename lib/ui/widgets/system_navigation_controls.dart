import 'package:flutter/material.dart';

import 'control_slots.dart';

/// Faixa de slots de cima da aba Controle. Por padrão traz HOME, MENU, INPUT
/// e EXIT (as antigas "Ações rápidas"); cada slot pode receber outra função
/// ou um app — segure o botão para trocar.
class SystemNavigationControls extends StatelessWidget {
  final double slotHeight;

  const SystemNavigationControls({super.key, this.slotHeight = 44});

  @override
  Widget build(BuildContext context) =>
      ControlSlotStrip(group: ControlSlotGroup.top, slotHeight: slotHeight);
}
