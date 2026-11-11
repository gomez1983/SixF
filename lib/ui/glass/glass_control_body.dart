import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';
import '../widgets/volume_channel_controls.dart' show VoicePttButton;
import 'liquid_glass.dart';

/// Conteúdo da aba "Controle" em Liquid Glass: HOME/MENU/INPUT/EXIT,
/// VOL/MUTE/VOZ/CH e a roda direcional. Cada botão chama o mesmo método do
/// [RemoteController] que a interface atual usa.
class GlassControlBody extends StatelessWidget {
  const GlassControlBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: _SystemRow(),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final h = box.maxHeight;
              final volumeHeight = (h * 0.42).clamp(130.0, 190.0);
              // Nunca negativo: no Android o primeiro quadro chega com a tela
              // 0x0 e um tamanho negativo derruba a árvore de widgets.
              final wheel = math.max(
                0.0,
                math.min(
                  (h - volumeHeight - 28).clamp(120.0, 236.0),
                  box.maxWidth - 32 - 2 * 72,
                ),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _VolumeBlock(height: volumeHeight),
                    _DPadBlock(size: wheel),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.size = 10.5});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
      color: GlassTokens.of(context).secondaryLabel,
    ),
  );
}

class _SystemRow extends StatelessWidget {
  const _SystemRow();

  @override
  Widget build(BuildContext context) {
    final c = context.read<RemoteController>();
    final t = GlassTokens.of(context);
    final items = <(IconData, String, VoidCallback)>[
      (CupertinoIcons.house, 'HOME', c.pressHome),
      (CupertinoIcons.gear, 'MENU', c.pressMenu),
      (CupertinoIcons.arrow_right_to_line, 'INPUT', c.navInput),
      (CupertinoIcons.square_arrow_right, 'EXIT', c.pressExit),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: GlassButton(
              onPressed: items[i].$3,
              semanticLabel: items[i].$2,
              height: 62,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(items[i].$1, size: 21, color: t.label),
                  const SizedBox(height: 5),
                  _Label(items[i].$2),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _VolumeBlock extends StatelessWidget {
  const _VolumeBlock({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<RemoteController>();
    final t = GlassTokens.of(context);
    // Dois botões redondos + rótulos + respiro precisam caber na altura do
    // bloco; em área baixa (tela pequena) os botões encolhem em vez de estourar.
    final round = ((height * 0.96 - 38) / 2).clamp(36.0, 62.0);
    final muted = c.isMuted;
    return SizedBox(
      key: const Key('glass-volume'),
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Rocker(
            title: 'VOL',
            value: muted ? 'mudo' : '${c.volumeLevel}',
            height: height,
            enabledRepeat: c.isConnected,
            token: c.driver,
            onPlus: c.volumeUp,
            onMinus: c.volumeDown,
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlassButton(
                onPressed: c.muteToggle,
                semanticLabel: muted ? 'Desmutar' : 'Mutar',
                shape: const CircleBorder(),
                tint: muted ? t.tintRed : null,
                width: round,
                height: round,
                child: Icon(
                  muted
                      ? CupertinoIcons.speaker_slash_fill
                      : CupertinoIcons.speaker_2_fill,
                  size: 24,
                  color: muted ? const Color(0xFFFF453A) : t.label,
                ),
              ),
              const SizedBox(height: 4),
              const _Label('MUTE'),
              SizedBox(height: height * 0.04),
              // Mesma lógica de Push-to-Talk (segurar, deslizar para travar).
              VoicePttButton(
                controller: c,
                size: round,
                builder: (context, pressed, locked) => LiquidGlass(
                  shape: const CircleBorder(),
                  tint: pressed || locked ? t.tintBlue : null,
                  strong: pressed,
                  width: round,
                  height: round,
                  child: Center(
                    child: Icon(
                      locked
                          ? CupertinoIcons.lock_open_fill
                          : CupertinoIcons.mic_fill,
                      size: 24,
                      color: pressed || locked ? t.accent : t.label,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const _Label('VOZ'),
            ],
          ),
          _Rocker(
            title: 'CH',
            value: '${c.currentChannel}',
            height: height,
            enabledRepeat: c.isConnected,
            token: c.driver,
            onPlus: c.channelUp,
            onMinus: c.channelDown,
          ),
        ],
      ),
    );
  }
}

class _Rocker extends StatelessWidget {
  const _Rocker({
    required this.title,
    required this.value,
    required this.height,
    required this.enabledRepeat,
    required this.token,
    required this.onPlus,
    required this.onMinus,
  });

  final String title;
  final String value;
  final double height;
  final bool enabledRepeat;
  final Object token;
  final VoidCallback onPlus;
  final VoidCallback onMinus;

  Widget _half(GlassTokens t, IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GlassRepeat(
        enabled: enabledRepeat,
        token: token,
        onRepeat: onTap,
        child: GlassTap(
          onPressed: onTap,
          semanticLabel: label,
          child: Center(child: Icon(icon, size: 25, color: t.label)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LiquidGlass(
      shape: const StadiumBorder(),
      width: 70,
      height: height,
      child: Column(
        children: [
          _half(t, CupertinoIcons.plus, '$title mais', onPlus),
          _Label(title, size: 12),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: dark ? const Color(0xFF38BDF8) : t.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          _half(t, CupertinoIcons.minus, '$title menos', onMinus),
        ],
      ),
    );
  }
}

class _DPadBlock extends StatelessWidget {
  const _DPadBlock({required this.size});
  final double size;

  static const _sideWidth = 64.0;

  Widget _side(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final t = GlassTokens.of(context);
    return GlassButton(
      onPressed: onTap,
      semanticLabel: label,
      width: _sideWidth,
      height: 60,
      shape: glassRounded(21),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21, color: t.label),
          const SizedBox(height: 4),
          _Label(label, size: 9.5),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<RemoteController>();
    final t = GlassTokens.of(context);
    final arrow = size * 0.25;

    final back = KeyedSubtree(
      key: const Key('chromecast-back'),
      child: _side(context, CupertinoIcons.arrow_uturn_left, 'VOLTAR', c.pressBack),
    );
    // TV Digital e HDMI só existem na LG; nos demais, o espaço fica vazio
    // para a roda continuar centralizada (mesma regra do D-pad atual).
    final inputs = c.supportsDirectInputs
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _side(context, CupertinoIcons.tv, 'TV Digital', c.switchTvDigital),
              const SizedBox(height: 10),
              _side(context, CupertinoIcons.rectangle_dock, 'HDMI 1', c.switchHdmi1),
            ],
          )
        : const SizedBox(width: _sideWidth, height: 60);
    final backOnRight = c.backButtonOnRight;

    Widget arrowButton(Alignment a, IconData icon, String name, VoidCallback act) {
      return Align(
        alignment: a,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: GlassRepeat(
            enabled: c.isConnected,
            token: c.driver,
            onRepeat: act,
            child: GlassTap(
              onPressed: act,
              semanticLabel: name,
              pressedScale: 0.86,
              child: SizedBox(
                width: arrow,
                height: arrow,
                child: Icon(icon, size: 28, color: t.label),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        backOnRight ? inputs : back,
        SizedBox(
          key: const Key('chromecast-dpad'),
          width: size,
          height: size,
          child: LiquidGlass(
            shape: const CircleBorder(),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: size * 0.86,
                  height: size * 0.86,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: t.tertiaryLabel.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                arrowButton(Alignment.topCenter, CupertinoIcons.chevron_up, 'Cima', c.dpadUp),
                arrowButton(Alignment.bottomCenter, CupertinoIcons.chevron_down, 'Baixo', c.dpadDown),
                arrowButton(Alignment.centerLeft, CupertinoIcons.chevron_left, 'Esquerda', c.dpadLeft),
                arrowButton(Alignment.centerRight, CupertinoIcons.chevron_right, 'Direita', c.dpadRight),
                GlassButton(
                  onPressed: c.dpadOk,
                  semanticLabel: 'OK',
                  shape: const CircleBorder(),
                  tint: const Color(0xD90A84FF),
                  strong: true,
                  width: size * 0.40,
                  height: size * 0.40,
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        backOnRight ? back : inputs,
      ],
    );
  }
}
