import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_driver.dart';

/// Captures the target session: switching devices cannot submit its PIN elsewhere.
class GoogleTvPairingDialog extends StatefulWidget {
  const GoogleTvPairingDialog({
    super.key,
    required this.controller,
    required this.deviceId,
    required this.driver,
  });
  final RemoteController controller;
  final String deviceId;
  final TvDriver driver;
  @override
  State<GoogleTvPairingDialog> createState() => _GoogleTvPairingDialogState();
}

class _GoogleTvPairingDialogState extends State<GoogleTvPairingDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _sending = false;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final code = _code.text.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(code)) {
      setState(
        () => _error = 'Digite os 6 caracteres exibidos na TV (0–9 e A–F).',
      );
      return;
    }
    if (!identical(
      widget.controller.getSession(widget.deviceId)?.driver,
      widget.driver,
    )) {
      setState(
        () => _error = 'O aparelho foi removido. Feche e conecte novamente.',
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.driver.sendPairingPin(code);
      if (mounted && widget.driver.isConnected) {
        Navigator.of(context).pop();
      } else if (mounted) {
        setState(
          () => _error = 'A conexão foi encerrada. Feche e conecte novamente.',
        );
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Não foi possível concluir. Feche e conecte novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Parear Google TV'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Digite o código de 6 caracteres exibido na tela da TV.'),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
            ],
            decoration: InputDecoration(
              labelText: 'Código da TV',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          widget.controller.disconnectDevice(widget.deviceId);
          Navigator.of(context).pop();
        },
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _sending ? null : _submit,
        child: Text(_sending ? 'Pareando…' : 'Parear'),
      ),
    ],
  );
}
