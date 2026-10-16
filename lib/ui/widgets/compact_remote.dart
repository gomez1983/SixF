import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';
import 'device_selector_bar.dart';
import 'dpad_widget.dart';
import 'remote_button.dart';
import 'app_drawer_widget.dart';

class CompactRemote extends StatelessWidget {
  final VoidCallback onExpand;
  const CompactRemote({super.key, required this.onExpand});
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.connectedTvName ?? 'SixF Remote',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: onExpand,
                icon: const Icon(Icons.open_in_full),
                tooltip: 'Sair do modo compacto',
              ),
            ],
          ),
          Text(controller.connectionStatusLabel),
          const DeviceSelectorBar(),
          const SizedBox(height: 12),
          const DPadWidget(size: 148),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              RemoteButton(
                onPressed: controller.volumeDown,
                icon: Icons.volume_down,
                tooltip: 'Diminuir volume',
                width: 54,
                height: 48,
                repeatOnHold: controller.isConnected,
                repeatToken: controller.driver,
              ),
              RemoteButton(
                onPressed: controller.toggleMute,
                icon: Icons.volume_off,
                tooltip: 'Alternar mudo',
                width: 54,
                height: 48,
              ),
              RemoteButton(
                onPressed: controller.volumeUp,
                icon: Icons.volume_up,
                tooltip: 'Aumentar volume',
                width: 54,
                height: 48,
                repeatOnHold: controller.isConnected,
                repeatToken: controller.driver,
              ),
              RemoteButton(
                onPressed: () => AppDrawerWidget.showAsBottomSheet(context),
                icon: Icons.apps,
                tooltip: 'Apps e favoritos',
                width: 54,
                height: 48,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
