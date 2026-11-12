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
    this.configure = GoogleTvAppsAdb.configure,
  });

  final String host;

  /// Já houve pareamento nesta instalação (conexão caiu) ou é a 1ª vez.
  final bool wasConfigured;
  final Future<void> Function() onConnected;
  final bool compact;

  /// Pareamento/conexão ADB. Substituível nos testes de widget.
  final Future<void> Function(
    String host,
    int? port, {
    int? pairingPort,
    String? code,
  })
  configure;

  @override
  State<GoogleTvAdbPanel> createState() => _GoogleTvAdbPanelState();
}

class _GoogleTvAdbPanelState extends State<GoogleTvAdbPanel> {
  final _pairPort = TextEditingController();
  final _code = TextEditingController();
  final _connPort = TextEditingController();
  final _connPortFocus = FocusNode();
  bool _busy = false;

  /// Etapa 2: o pareamento está resolvido e só falta a porta de conexão.
  /// Enquanto for `false`, a tela mostra apenas os campos do pareamento.
  bool _needsConnectionPort = false;

  /// O pareamento por código foi concluído nesta tela (aviso de sucesso).
  bool _pairedNow = false;
  String? _error;

  @override
  void dispose() {
    _pairPort.dispose();
    _code.dispose();
    _connPort.dispose();
    _connPortFocus.dispose();
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
    } on AdbConnectionPortException catch (e) {
      if (!mounted) return;
      setState(() {
        // Na primeira vez a troca de etapa já explica o que falta; a mensagem
        // só vira erro se a porta digitada na etapa 2 também falhar.
        _error = _needsConnectionPort ? e.message : null;
        _pairedNow = _pairedNow || e.paired;
        _needsConnectionPort = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connPortFocus.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Etapa 1: pareia com a porta e o código da janela de pareamento.
  Future<void> _pair() => _run(() async {
    final pairPort = GoogleTvAppsAdb.parsePort(_pairPort.text);
    final code = _code.text.trim();
    if (pairPort == null) {
      throw StateError(
        'Informe a porta do código. Ela aparece na TV na mesma janela do '
        'código de 6 dígitos.',
      );
    }
    if (code.length != 6) {
      throw StateError('Informe os 6 dígitos do código exibido na TV.');
    }
    await widget.configure(
      widget.host,
      null,
      pairingPort: pairPort,
      code: code,
    );
  });

  /// Etapa 2: TV já pareada, conecta na porta informada.
  Future<void> _connectPort() => _run(() async {
    final connPort = GoogleTvAppsAdb.parsePort(_connPort.text);
    if (connPort == null) {
      throw StateError('Informe a porta de conexão exibida na TV.');
    }
    await widget.configure(widget.host, connPort);
  });

  /// Sem novo pareamento: só procura a porta atual (TV já autorizada).
  Future<void> _retry() => _run(() => widget.configure(widget.host, null));

  void _backToPairing() => setState(() {
    _needsConnectionPort = false;
    _pairedNow = false;
    _error = null;
    _connPort.clear();
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

    final errorText = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.powerRed, fontSize: 12),
            ),
          );

    Widget spinnerOr(IconData icon) => _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 18);

    // Etapa 2: só a porta de conexão. Os campos do pareamento somem.
    final connectionStep = <Widget>[
      Row(
        children: [
          Icon(
            _pairedNow ? Icons.check_circle_rounded : Icons.link_off_rounded,
            color: _pairedNow ? AppColors.buttonGreen : highlight,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _pairedNow ? 'Pareado com a TV' : 'Falta a porta de conexão',
              key: const ValueKey('adb-step-connection'),
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
        'Falta só um número: o SixF não achou a porta de conexão sozinho.',
        style: TextStyle(color: secondary, fontSize: 12),
      ),
      const SizedBox(height: 10),
      step(
        1,
        TextSpan(
          children: [
            const TextSpan(text: 'Na TV, volte para a tela '),
            b('Depuração por Wi-Fi'),
            const TextSpan(text: ' (feche a janela do código).'),
          ],
        ),
      ),
      step(
        2,
        TextSpan(
          children: [
            const TextSpan(text: 'Em '),
            b('Endereço IP e porta'),
            const TextSpan(text: ', digite aqui o número depois dos “:”.'),
          ],
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey('adb-conn-port'),
        controller: _connPort,
        focusNode: _connPortFocus,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        decoration: field('Porta de conexão', 'ex.: 46761'),
        onSubmitted: (_) => _busy ? null : _connectPort(),
      ),
      ?errorText,
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _connectPort,
              icon: spinnerOr(Icons.link_rounded),
              label: const Text('Conectar'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _busy ? null : _backToPairing,
            child: const Text('Parear de novo'),
          ),
        ],
      ),
    ];

    // Etapa 1: só a porta do código e o código.
    final pairingStep = <Widget>[
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
            const TextSpan(text: 'A TV abre uma janela com o '),
            b('código de 6 dígitos'),
            const TextSpan(text: ' e um '),
            b('Endereço IP e porta'),
            const TextSpan(text: '. Digite aqui os dois: a '),
            b('porta dessa janela'),
            const TextSpan(text: ' (o número depois dos “:”) e o código.'),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('adb-pair-port'),
              controller: _pairPort,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: field('Porta do código', 'ex.: 37123'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
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
              onSubmitted: (_) => _busy ? null : _pair(),
            ),
          ),
        ],
      ),
      ?errorText,
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _pair,
              icon: spinnerOr(Icons.link_rounded),
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
    ];

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
        children: _needsConnectionPort ? connectionStep : pairingStep,
      ),
    );
  }
}
