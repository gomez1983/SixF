import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/google_tv_apps_adb.dart';

class GoogleTvAdbDialog extends StatefulWidget {
  final String host;
  const GoogleTvAdbDialog({super.key, required this.host});
  @override
  State<GoogleTvAdbDialog> createState() => _GoogleTvAdbDialogState();
}

class _GoogleTvAdbDialogState extends State<GoogleTvAdbDialog> {
  final port = TextEditingController(),
      pairingPort = TextEditingController(),
      code = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _loadPort();
  }

  Future<void> _loadPort() async {
    final stored = (await SharedPreferences.getInstance()).getInt(
      'sixf_adb_port_${widget.host}',
    );
    final value = stored ?? await GoogleTvAppsAdb.discoverPort(widget.host);
    if (mounted && port.text.isEmpty && value != null) port.text = '$value';
  }

  @override
  void dispose() {
    port.dispose();
    pairingPort.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final connectionPort = int.tryParse(port.text.trim());
      final pairPort = int.tryParse(pairingPort.text.trim());
      if (connectionPort == null ||
          (pairingPort.text.isNotEmpty && pairPort == null)) {
        throw StateError('Confira as portas informadas.');
      }
      await GoogleTvAppsAdb.configure(
        widget.host,
        connectionPort,
        pairingPort: pairPort,
        code: code.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Aplicativos via ADB'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Chromecast: ${widget.host}\nAtive a depuração nas opções do desenvolvedor e autorize o SixF na TV. A porta de conexão é diferente da porta de pareamento.',
            ),
            TextField(
              controller: port,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Porta de conexão ADB',
              ),
            ),
            TextField(
              controller: pairingPort,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Porta de pareamento (se exigida)',
              ),
            ),
            TextField(
              controller: code,
              enabled: !busy,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Código ADB de seis dígitos',
              ),
            ),
            if (error != null) Text(error!),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: const Text('Conectar'),
        ),
      ],
    ),
  );
}
