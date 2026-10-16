import '../../services/drivers/tv_driver.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';

class ConnectionDiagnostic extends StatelessWidget {
  const ConnectionDiagnostic({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    return AlertDialog(
      title: Text(controller.connectedTvName ?? 'Conexão da TV'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(controller.connectionStatusLabel),
            const SizedBox(height: 12),
            Text(
              '${controller.currentBrand.displayName} · ${controller.ipAddress}',
            ),
            const SizedBox(height: 12),
            Text(controller.connectionGuidance),
          ],
        ),
      ),
      actions: [
        if (!controller.isConnected &&
            !controller.isConnecting &&
            !controller.isWaitingPairing)
          TextButton(
            onPressed: () => controller.connect(),
            child: const Text('Tentar novamente'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
