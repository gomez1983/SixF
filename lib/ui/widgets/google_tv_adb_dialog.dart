import 'package:flutter/material.dart';

import '../../services/google_tv_apps_adb.dart';
import '../theme/app_colors.dart';

/// Painel embutido na gaveta de Apps do Chromecast para (re)conectar o ADB.
///
/// Aparece somente quando a lista de aplicativos instalados não está
/// disponível. O controle remoto continua funcionando sem ele: só a lista de
/// apps depende da Depuração por Wi-Fi.
class GoogleTvAdbPanel extends StatefulWidget {
  const GoogleTvAdbPanel({
    super.key,
    required this.host,
    required this.wasConfigured,
    required this.onConnected,
    this.compact = false,
  });

  final String host;

  /// Já houve pareamento nesta instalação (conexão caiu) ou é a 1ª vez.
  final bool wasConfigured;
  final Future<void> Function() onConnected;
  final bool compact;

  @override
  State<GoogleTvAdbPanel> createState() => _GoogleTvAdbPanelState();
}

class _GoogleTvAdbPanelState extends State<GoogleTvAdbPanel> {
  final _pairPort = TextEditingController();
  final _code = TextEditingController();
  final _connPort = TextEditingController();
  bool _busy = false;
  bool _askConnectionPort = false;
  String? _error;

  @override
  void dispose() {
    _pairPort.dispose();
    _code.dispose();
    _connPort.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await widget.onConnected();
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().replaceFirst('Bad state: ', '');
      setState(() {
        _error = text;
        if (text.contains('porta de conexão')) _askConnectionPort = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
    final pairPort = GoogleTvAppsAdb.parsePort(_pairPort.text);
    final code = _code.text.trim();
    final connPort = GoogleTvAppsAdb.parsePort(_connPort.text);
    if (pairPort == null && connPort == null) {
      throw StateError('Informe a porta exibida na TV.');
    }
    if (pairPort != null && code.length != 6) {
      throw StateError('Informe os 6 dígitos do código exibido na TV.');
    }
    await GoogleTvAppsAdb.configure(
      widget.host,
      connPort,
      pairingPort: pairPort,
      code: pairPort != null ? code : null,
    );
  });

  /// Sem novo pareamento: só procura a porta atual (TV já autorizada).
  Future<void> _retry() => _run(() async {
    final connPort = GoogleTvAppsAdb.parsePort(_connPort.text);
    await GoogleTvAppsAdb.configure(widget.host, connPort);
  });

  @override
  Widget build(BuildContext context) {
    final highlight = AppColors.iconHighlightOf(context);
    final primary = AppColors.textPrimaryOf(context);
    final secondary = AppColors.textSecondaryOf(context);

    Widget step(int n, InlineSpan text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highlight.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: TextStyle(
                color: highlight,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              text,
              style: TextStyle(color: primary, fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );

    TextSpan b(String s) => TextSpan(
      text: s,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );

    InputDecoration field(String label, String hint) => InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      border: const OutlineInputBorder(),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.link_off_rounded, color: highlight, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.wasConfigured
                      ? 'Reconectar a lista de aplicativos'
                      : 'Mostrar os aplicativos do Chromecast',
                  style: TextStyle(
                    color: primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.wasConfigured
                ? 'A conexão ADB caiu (o controle continua funcionando). '
                      'Faça isto no Chromecast:'
                : 'Faça isto uma vez no Chromecast:',
            style: TextStyle(color: secondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          step(
            1,
            TextSpan(
              children: [
                const TextSpan(text: 'Abra '),
                b('Configurações › Sistema › Opções do desenvolvedor'),
                const TextSpan(text: ' e ative '),
                b('Depuração por Wi-Fi'),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          step(
            2,
            TextSpan(
              children: [
                const TextSpan(text: 'Entre em '),
                b('Depuração por Wi-Fi'),
                const TextSpan(text: ' e toque em '),
                b('Parear o dispositivo com um código de pareamento'),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          step(
            3,
            TextSpan(
              children: [
                const TextSpan(text: 'Digite aqui a '),
                b('porta'),
                const TextSpan(text: ' (o número depois dos “:” em '),
                b('Endereço IP e porta'),
                const TextSpan(text: ') e o '),
                b('código de 6 dígitos'),
                const TextSpan(text: ' que aparecem na TV.'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  key: const ValueKey('adb-pair-port'),
                  controller: _pairPort,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: field('Porta', 'ex.: 37123'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: TextField(
                  key: const ValueKey('adb-pair-code'),
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: field(
                    'Código',
                    '6 dígitos',
                  ).copyWith(counterText: ''),
                  onSubmitted: (_) => _busy ? null : _connect(),
                ),
              ),
            ],
          ),
          if (_askConnectionPort) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('adb-conn-port'),
              controller: _connPort,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: field(
                'Porta de conexão',
                'número depois dos “:” na tela Depuração por Wi-Fi',
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.powerRed, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Conectar'),
                ),
              ),
              if (widget.wasConfigured) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _retry,
                  child: const Text('Tentar de novo'),
                ),
              ],
            ],
          ),
          if (widget.wasConfigured) ...[
            const SizedBox(height: 6),
            Text(
              'Se a TV já foi pareada antes, basta ativar a Depuração por Wi-Fi '
              '(passo 1) e tocar em Tentar de novo.',
              style: TextStyle(color: secondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
