import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';
import '../../services/haptic_service.dart';
import '../widgets/connection_diagnostic.dart';
import '../widgets/device_discovery_dialog.dart';
import '../widgets/device_selector_bar.dart';
import '../widgets/remote_button.dart' show HapticType, RemoteButton;
import 'liquid_glass.dart';

/// Moldura do controle no estilo iOS 26 / Liquid Glass: fundo ambiente,
/// cabeçalho, aparelhos, o conteúdo da aba ([body]) e a barra de abas.
///
/// Lê o [RemoteController] via `provider`, como o resto do app. A navegação
/// entre abas continua sendo do `RemoteView` (`selectedTab`/`onSelectTab`).
class GlassRemoteShell extends StatelessWidget {
  const GlassRemoteShell({
    super.key,
    required this.selectedTab,
    required this.onSelectTab,
    required this.onOpenDrawer,
    required this.body,
    this.onToggleCompact,
    this.showTrackpad,
  });

  /// Força a aba Trackpad ligada/desligada. Nulo = só se o aparelho ativo
  /// suporta (uso normal); a vitrine de design força ligada para mostrá-la.
  final bool? showTrackpad;

  /// Índice real da aba (0 Controle, 1 Teclas, 2 Trackpad, 3 Mídia, 4 Apps).
  final int selectedTab;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenDrawer;
  final VoidCallback? onToggleCompact;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final deviceTrackpad = context.select<RemoteController, bool>(
      (c) => c.supportsTrackpad,
    );
    final supportsTrackpad = showTrackpad ?? deviceTrackpad;
    final items = glassTabItems(supportsTrackpad: supportsTrackpad);
    return DefaultTextStyle.merge(
      style: TextStyle(color: t.label),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const GlassBackdrop(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: GlassHeader(
                    onOpenDrawer: onOpenDrawer,
                    onToggleCompact: onToggleCompact,
                  ),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 38, child: GlassDeviceBar()),
                Expanded(child: body),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    4,
                    14,
                    math.max(12, MediaQuery.paddingOf(context).bottom - 14),
                  ),
                  child: GlassTabBar(
                    items: items,
                    selected: selectedTab,
                    onSelect: onSelectTab,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Abas do controle (índice real do RemoteView). A aba Trackpad só existe nos
/// aparelhos que suportam.
List<GlassTabItem> glassTabItems({required bool supportsTrackpad}) => [
  const GlassTabItem(0, CupertinoIcons.tv, 'Controle'),
  const GlassTabItem(1, CupertinoIcons.circle_grid_3x3_fill, 'Teclas'),
  if (supportsTrackpad)
    const GlassTabItem(2, CupertinoIcons.hand_point_right, 'Trackpad'),
  const GlassTabItem(3, CupertinoIcons.play_rectangle, 'Mídia'),
  const GlassTabItem(4, CupertinoIcons.square_grid_2x2, 'Apps'),
];

class GlassTabItem {
  const GlassTabItem(this.index, this.icon, this.label);
  final int index;
  final IconData icon;
  final String label;
}

Color _accent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF38BDF8)
    : GlassTokens.of(context).accent;

// ---------------------------------------------------------------------------
// Cabeçalho

class GlassHeader extends StatelessWidget {
  const GlassHeader({super.key, required this.onOpenDrawer, this.onToggleCompact});

  final VoidCallback onOpenDrawer;
  final VoidCallback? onToggleCompact;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<RemoteController>();
    final t = GlassTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final statusColor = c.isConnecting
        ? const Color(0xFFFF9F0A)
        : c.isWaitingPairing
        ? const Color(0xFFFFD60A)
        : c.isConnected
        ? t.success
        : const Color(0xFF8E8E93);
    final statusText = c.isConnected
        ? (c.connectedTvName ?? 'Conectado')
        : c.connectionStatusLabel;
    const red = Color(0xFFFF453A);

    // Os botões do cabeçalho são RemoteButton (em vidro com a opção ligada),
    // com os mesmos tooltips da interface atual.
    Widget circle({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) => RemoteButton(
      width: 38,
      height: 38,
      isCircular: true,
      icon: icon,
      iconSize: 18,
      tooltip: tooltip,
      onPressed: onPressed,
    );

    return LiquidGlass(
      shape: const StadiumBorder(),
      height: 66,
      padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
      child: Row(
        children: [
          RemoteButton(
            width: 46,
            height: 46,
            isCircular: true,
            hapticType: HapticType.medium,
            backgroundColor: c.isPoweredOn ? red.withValues(alpha: 0.3) : null,
            foregroundColor: c.isPoweredOn ? red : t.secondaryLabel,
            icon: CupertinoIcons.power,
            iconSize: 22,
            tooltip: c.isPoweredOn ? 'Desligar TV' : 'Ligar TV (Wake-on-LAN)',
            onPressed: c.powerToggle,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => const ConnectionDiagnostic(),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SixF',
                          style: TextStyle(
                            color: _accent(context),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Remote',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: c.isConnected
                              ? [BoxShadow(color: statusColor, blurRadius: 8)]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: t.secondaryLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (onToggleCompact != null) ...[
            circle(
              icon: CupertinoIcons.rectangle_on_rectangle,
              tooltip: 'Modo compacto',
              onPressed: onToggleCompact,
            ),
            const SizedBox(width: 8),
          ],
          circle(
            icon: CupertinoIcons.dot_radiowaves_left_right,
            tooltip: c.isConnected
                ? 'TV Conectada: ${c.connectedTvName ?? c.ipAddress}'
                : (c.isConnecting
                      ? 'Conectando à TV...'
                      : 'Desconectado - Clique para Buscar e Conectar TVs LG'),
            onPressed: () => DeviceDiscoveryDialog.show(context),
          ),
          const SizedBox(width: 8),
          circle(
            icon: dark ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill,
            tooltip: dark ? 'Mudar para Modo Claro' : 'Mudar para Modo Escuro',
            onPressed: c.toggleTheme,
          ),
          const SizedBox(width: 8),
          circle(
            icon: Icons.tune_rounded,
            tooltip: 'Configurações de Rede (IP / MAC)',
            onPressed: onOpenDrawer,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aparelhos

class GlassDeviceBar extends StatelessWidget {
  const GlassDeviceBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<RemoteController>();
    final t = GlassTokens.of(context);
    final devices = c.savedDevices;
    final activeId = c.activeDeviceId;

    return ListView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final d in devices) ...[
          Builder(
            builder: (context) {
              final active = d.id == activeId;
              final connected = c.isDeviceConnected(d.id);
              final connecting = c.isDeviceConnecting(d.id);
              final dot = connected
                  ? t.success
                  : connecting
                  ? const Color(0xFFFF9F0A)
                  : const Color(0xFF8E8E93);
              return GlassButton(
                onPressed: () {
                  if (!active) c.setActiveDevice(d.id);
                  if (!connected && !connecting) c.connectDevice(d.id);
                },
                onLongPress: () {
                  HapticService.heavyPress();
                  const DeviceSelectorBar().showDeviceOptions(context, c, d);
                },
                semanticLabel: d.name,
                shape: const StadiumBorder(),
                tint: active ? t.tintBlue : null,
                height: 38,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dot,
                          boxShadow: connected
                              ? [BoxShadow(color: dot, blurRadius: 6)]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        d.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: active ? t.label : t.secondaryLabel,
                        ),
                      ),
                      if (d.isDefault) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          CupertinoIcons.star_fill,
                          size: 11,
                          color: Color(0xFFFFD60A),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
        GlassButton(
          onPressed: () {
            HapticService.selectionClick();
            DeviceDiscoveryDialog.show(context);
          },
          semanticLabel: 'Adicionar aparelho',
          shape: const StadiumBorder(),
          width: devices.isEmpty ? null : 38,
          height: 38,
          child: devices.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.plus, size: 16, color: t.label),
                      const SizedBox(width: 6),
                      Text(
                        'Adicionar aparelho',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.label,
                        ),
                      ),
                    ],
                  ),
                )
              : Icon(CupertinoIcons.plus, size: 17, color: t.label),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Barra de abas

/// Barra de abas flutuante. O indicador é um único vidro que desliza entre os
/// itens com mola e se estica durante o deslocamento, como no iOS 26.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<GlassTabItem> items;

  /// Índice real da aba selecionada ([GlassTabItem.index]).
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 230,
    damping: 17,
  );

  static int _posOf(GlassTabBar w) =>
      math.max(0, w.items.indexWhere((e) => e.index == w.selected));

  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
    value: _posOf(widget).toDouble(),
  );

  @override
  void didUpdateWidget(GlassTabBar old) {
    super.didUpdateWidget(old);
    final target = _posOf(widget);
    if (target != _posOf(old)) {
      _pos.animateWith(
        SpringSimulation(_spring, _pos.value, target.toDouble(), _pos.velocity),
      );
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = GlassTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = dark ? const Color(0xFF4DA3FF) : t.accent;
    final items = widget.items;
    return LiquidGlass(
      shape: const StadiumBorder(),
      tint: t.tabFill,
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          final tabW = box.maxWidth / items.length;
          return AnimatedBuilder(
            animation: _pos,
            builder: (context, _) {
              final v = _pos.value;
              // Quanto mais rápido o deslocamento, mais o vidro se estica.
              final stretch = (_pos.velocity.abs() * 0.09).clamp(0.0, 0.45);
              final w = tabW * (1 + stretch);
              return Stack(
                children: [
                  Positioned(
                    left: v * tabW - (w - tabW) / 2,
                    top: 7,
                    width: w,
                    height: 56,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: StadiumBorder(
                          side: BorderSide(
                            color: t.rimLight.withValues(alpha: 0.5),
                          ),
                        ),
                        color: t.fillStrong,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: GlassTap(
                            // A vibração de seleção já é feita pelo RemoteView.
                            haptic: false,
                            onPressed: () => widget.onSelect(items[i].index),
                            semanticLabel: items[i].label,
                            pressedScale: 0.92,
                            child: SizedBox(
                              height: 70,
                              child: _content(
                                items[i],
                                // A cor acompanha a posição do indicador.
                                Color.lerp(
                                  t.secondaryLabel,
                                  active,
                                  (1 - (v - i).abs()).clamp(0.0, 1.0),
                                )!,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _content(GlassTabItem item, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(item.icon, size: 23, color: color),
        const SizedBox(height: 3),
        Text(
          item.label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
