import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/remote_controller.dart';
import '../../services/drivers/tv_app_info.dart';
import '../../services/haptic_service.dart';
import '../theme/app_colors.dart';

/// Faixas de slots da aba Controle. Cada faixa guarda a própria configuração
/// por aparelho.
enum ControlSlotGroup {
  /// Faixa de cima (no lugar do antigo card "Ações rápidas").
  top('top', 4),

  /// Faixa de baixo (atalhos de apps, por padrão).
  bottom('bottom', 3);

  const ControlSlotGroup(this.id, this.count);
  final String id;
  final int count;
}

/// Ação fixa que um slot pode executar (tecla, entrada, energia, mídia).
class ControlSlotAction {
  const ControlSlotAction({
    required this.id,
    required this.label,
    required this.name,
    required this.icon,
    required this.tooltip,
    required this.run,
    this.isAvailable,
  });

  /// Identificador estável, gravado nas preferências.
  final String id;

  /// Rótulo curto exibido no slot (maiúsculas).
  final String label;

  /// Nome exibido no seletor.
  final String name;
  final IconData icon;
  final String tooltip;
  final void Function(RemoteController controller) run;

  /// `null` = disponível em qualquer aparelho.
  final bool Function(RemoteController controller)? isAvailable;

  bool availableFor(RemoteController c) => isAvailable?.call(c) ?? true;
}

/// Catálogo de ações disponíveis para os slots.
final List<ControlSlotAction> kControlSlotActions = [
  ControlSlotAction(
    id: 'power',
    label: 'LIGAR',
    name: 'Ligar/Desligar',
    icon: Icons.power_settings_new_rounded,
    tooltip: 'Ligar ou desligar o aparelho',
    run: (c) => c.powerToggle(),
  ),
  ControlSlotAction(
    id: 'home',
    label: 'HOME',
    name: 'Home',
    icon: Icons.home_outlined,
    tooltip: 'Página Inicial (WebOS Dashboard)',
    run: (c) => c.pressHome(),
  ),
  ControlSlotAction(
    id: 'menu',
    label: 'MENU',
    name: 'Menu',
    icon: Icons.settings_outlined,
    tooltip: 'Menu de Ajustes Rápidos',
    run: (c) => c.pressMenu(),
  ),
  ControlSlotAction(
    id: 'input',
    label: 'INPUT',
    name: 'Input',
    icon: Icons.login_rounded,
    tooltip: 'Alternar Entrada / Fonte (HDMI, AV, TV)',
    run: (c) => c.navInput(),
  ),
  ControlSlotAction(
    id: 'exit',
    label: 'EXIT',
    name: 'Exit',
    icon: Icons.logout_rounded,
    tooltip: 'Fechar aplicativo / Sair da transmissão',
    run: (c) => c.pressExit(),
  ),
  ControlSlotAction(
    id: 'back',
    label: 'VOLTAR',
    name: 'Voltar',
    icon: Icons.undo_rounded,
    tooltip: 'Voltar à tela anterior',
    run: (c) => c.pressBack(),
  ),
  ControlSlotAction(
    id: 'mute',
    label: 'MUDO',
    name: 'Mudo',
    icon: Icons.volume_off_outlined,
    tooltip: 'Alternar mudo',
    run: (c) => c.muteToggle(),
  ),
  ControlSlotAction(
    id: 'tv_digital',
    label: 'TV',
    name: 'TV Digital',
    icon: Icons.live_tv_rounded,
    tooltip: 'Sintonizar TV Digital / Antena',
    run: (c) => c.switchTvDigital(),
    isAvailable: (c) => c.supportsDirectInputs,
  ),
  ControlSlotAction(
    id: 'hdmi1',
    label: 'HDMI 1',
    name: 'HDMI 1',
    icon: Icons.settings_input_hdmi_rounded,
    tooltip: 'Alternar Entrada para HDMI 1',
    run: (c) => c.switchHdmi1(),
    isAvailable: (c) => c.supportsDirectInputs,
  ),
  // Teclas de mídia da TV (antes no card "Controles multimídia" da aba
  // Teclas): continuam acessíveis como funções de slot.
  ControlSlotAction(
    id: 'play',
    label: 'PLAY',
    name: 'Reproduzir',
    icon: Icons.play_arrow_rounded,
    tooltip: 'Reproduzir (Play)',
    run: (c) => c.mediaPlay(),
  ),
  ControlSlotAction(
    id: 'pause',
    label: 'PAUSA',
    name: 'Pausar',
    icon: Icons.pause_rounded,
    tooltip: 'Pausar (Pause)',
    run: (c) => c.mediaPause(),
  ),
  ControlSlotAction(
    id: 'stop',
    label: 'PARAR',
    name: 'Parar',
    icon: Icons.stop_rounded,
    tooltip: 'Parar (Stop)',
    run: (c) => c.mediaStop(),
  ),
  ControlSlotAction(
    id: 'rewind',
    label: 'RETR.',
    name: 'Retroceder',
    icon: Icons.fast_rewind_rounded,
    tooltip: 'Retroceder (<<)',
    run: (c) => c.mediaRewind(),
  ),
  ControlSlotAction(
    id: 'forward',
    label: 'AVANÇ.',
    name: 'Avançar',
    icon: Icons.fast_forward_rounded,
    tooltip: 'Avançar (>>)',
    run: (c) => c.mediaFastForward(),
  ),
];

ControlSlotAction? controlSlotActionById(String id) {
  for (final a in kControlSlotActions) {
    if (a.id == id) return a;
  }
  return null;
}

/// Conteúdo de um slot: vazio, uma ação fixa ou um app do aparelho.
///
/// Formato gravado: `''` (vazio), `key:<id>` ou `app:<id>\t<nome>`.
@immutable
class ControlSlot {
  const ControlSlot.empty() : actionId = null, appId = null, appName = null;
  const ControlSlot.action(String this.actionId) : appId = null, appName = null;
  const ControlSlot.app(String this.appId, String this.appName)
    : actionId = null;

  final String? actionId;
  final String? appId;
  final String? appName;

  bool get isEmpty => actionId == null && appId == null;
  bool get isApp => appId != null;

  String encode() {
    if (actionId != null) return 'key:$actionId';
    if (appId != null) return 'app:$appId\t$appName';
    return '';
  }

  static ControlSlot decode(String raw) {
    if (raw.startsWith('key:')) {
      final id = raw.substring(4);
      return controlSlotActionById(id) == null
          ? const ControlSlot.empty()
          : ControlSlot.action(id);
    }
    if (raw.startsWith('app:')) {
      final rest = raw.substring(4);
      final tab = rest.indexOf('\t');
      if (tab <= 0) return const ControlSlot.empty();
      return ControlSlot.app(rest.substring(0, tab), rest.substring(tab + 1));
    }
    return const ControlSlot.empty();
  }

  @override
  bool operator ==(Object other) =>
      other is ControlSlot &&
      other.actionId == actionId &&
      other.appId == appId &&
      other.appName == appName;

  @override
  int get hashCode => Object.hash(actionId, appId, appName);
}

/// Slots padrão de uma faixa enquanto o usuário não a personaliza.
///
/// Cima: HOME, MENU, INPUT, EXIT (as antigas "Ações rápidas"). Baixo: Netflix,
/// YouTube e Prime Video, quando instalados no aparelho; o que faltar fica
/// vazio ("+").
List<ControlSlot> defaultControlSlots(
  ControlSlotGroup group,
  RemoteController controller,
) {
  if (group == ControlSlotGroup.top) {
    return const [
      ControlSlot.action('home'),
      ControlSlot.action('menu'),
      ControlSlot.action('input'),
      ControlSlot.action('exit'),
    ];
  }
  const wanted = ['netflix', 'youtube', 'prime-video'];
  final apps = controller.installedApps;
  return [
    for (final logo in wanted)
      () {
        for (final app in apps) {
          if (app.iconAsset == 'assets/app_icons/$logo.png') {
            return ControlSlot.app(app.id, app.name);
          }
        }
        return const ControlSlot.empty();
      }(),
  ];
}

/// Slots efetivos de uma faixa: os salvos para o aparelho ativo ou o padrão.
List<ControlSlot> resolveControlSlots(
  ControlSlotGroup group,
  RemoteController controller,
) {
  final saved = controller.controlSlots(group.id);
  if (saved == null) return defaultControlSlots(group, controller);
  return [
    for (var i = 0; i < group.count; i++)
      i < saved.length ? ControlSlot.decode(saved[i]) : const ControlSlot.empty(),
  ];
}

/// Faixa de slots configuráveis. Toque executa a função; toque longo (ou
/// clique com o botão direito, no Windows) abre o seletor para trocá-la.
class ControlSlotStrip extends StatelessWidget {
  const ControlSlotStrip({
    super.key,
    required this.group,
    this.slotHeight = 44,
    this.gap = 8,
  });

  final ControlSlotGroup group;
  final double slotHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final slots = resolveControlSlots(group, controller);
    return Row(
      children: [
        for (var i = 0; i < slots.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: _SlotButton(
              key: ValueKey('control-slot-${group.id}-$i'),
              slot: slots[i],
              height: slotHeight,
              controller: controller,
              onEdit: () => _edit(context, controller, slots, i),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    RemoteController controller,
    List<ControlSlot> slots,
    int index,
  ) async {
    HapticService.selectionClick();
    final result = await showModalBottomSheet<_SlotPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: controller,
        child: _SlotPickerSheet(
          group: group,
          index: index,
          current: slots[index],
        ),
      ),
    );
    if (result == null) return;
    if (result.restoreDefaults) {
      await controller.saveControlSlots(group.id, null);
      return;
    }
    final next = [...slots]..[index] = result.slot!;
    await controller.saveControlSlots(group.id, [
      for (final s in next) s.encode(),
    ]);
  }
}

class _SlotButton extends StatelessWidget {
  const _SlotButton({
    super.key,
    required this.slot,
    required this.height,
    required this.controller,
    required this.onEdit,
  });

  final ControlSlot slot;
  final double height;
  final RemoteController controller;
  final VoidCallback onEdit;

  TvAppInfo? get _app {
    final id = slot.appId;
    if (id == null) return null;
    for (final a in controller.installedApps) {
      if (a.id == id) return a;
    }
    // App ainda não listado (aparelho desconectado): mantém nome e marca.
    return TvAppInfo(
      id: id,
      name: slot.appName ?? id,
      iconKey: TvAppInfo.resolveIconKey(id, slot.appName ?? id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = slot.actionId == null
        ? null
        : controlSlotActionById(slot.actionId!);
    final app = _app;
    final fg = AppColors.textPrimaryOf(context);
    final radius = BorderRadius.circular(14);

    late final Widget content;
    late final String tooltip;
    VoidCallback? onTap;

    if (action != null) {
      tooltip = action.tooltip;
      onTap = () {
        HapticService.buttonPress();
        action.run(controller);
      };
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(action.icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(
            action.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: fg,
            ),
          ),
        ],
      );
    } else if (app != null) {
      tooltip = 'Abrir ${app.name}';
      onTap = () => controller.openApp(app.id, appName: app.name);
      final asset = app.iconAsset;
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (asset != null)
            Image.asset(
              asset,
              width: 22,
              height: 22,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                app.fallbackIcon,
                size: 18,
                color: AppColors.iconHighlightOf(context),
              ),
            )
          else
            Icon(
              app.fallbackIcon,
              size: 18,
              color: AppColors.iconHighlightOf(context),
            ),
          const SizedBox(width: 6),
          Text(
            app.name,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      );
    } else {
      tooltip = 'Slot vazio — toque para escolher a função';
      onTap = onEdit;
      content = Icon(
        Icons.add_rounded,
        size: 20,
        color: AppColors.textMutedOf(context),
      );
    }

    final empty = slot.isEmpty;
    return Tooltip(
      message: empty ? tooltip : '$tooltip\nSegure para trocar a função',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: empty ? null : AppColors.softShadowOf(context),
        ),
        child: Material(
          color: empty ? Colors.transparent : AppColors.circleOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: AppColors.borderSubtleOf(context)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onEdit,
            onSecondaryTap: onEdit,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Center(
                  child: FittedBox(fit: BoxFit.scaleDown, child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotPickResult {
  const _SlotPickResult.slot(ControlSlot this.slot) : restoreDefaults = false;
  const _SlotPickResult.restore() : slot = null, restoreDefaults = true;
  final ControlSlot? slot;
  final bool restoreDefaults;
}

/// Seletor de função do slot: escolhe e aperta **Confirmar** (mesmo padrão
/// dos diálogos de legenda e áudio).
class _SlotPickerSheet extends StatefulWidget {
  const _SlotPickerSheet({
    required this.group,
    required this.index,
    required this.current,
  });

  final ControlSlotGroup group;
  final int index;
  final ControlSlot current;

  @override
  State<_SlotPickerSheet> createState() => _SlotPickerSheetState();
}

class _SlotPickerSheetState extends State<_SlotPickerSheet> {
  late ControlSlot _choice = widget.current;

  Widget _chip(String label, ControlSlot value, {IconData? icon}) {
    final selected = _choice == value;
    return ChoiceChip(
      label: Text(label),
      avatar: icon == null
          ? null
          : Icon(
              icon,
              size: 16,
              color: selected ? AppColors.onAccentOf(context) : AppColors.textMutedOf(context),
            ),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppColors.accentFillOf(context),
      backgroundColor: AppColors.circleOf(context),
      side: BorderSide(
        color: selected
            ? Colors.transparent
            : AppColors.borderSubtleOf(context),
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? AppColors.onAccentOf(context) : AppColors.textPrimaryOf(context),
      ),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => setState(() => _choice = value),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 1,
        fontWeight: FontWeight.w600,
        color: AppColors.textMutedOf(context),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RemoteController>();
    final actions = [
      for (final a in kControlSlotActions)
        if (a.availableFor(controller)) a,
    ];
    final apps = [...controller.installedApps]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final current = widget.current;
    // App salvo que não está na lista atual (aparelho desconectado): continua
    // selecionável para não ser perdido ao confirmar.
    final savedAppMissing =
        current.isApp && !apps.any((a) => a.id == current.appId);
    final where = widget.group == ControlSlotGroup.top
        ? 'faixa de cima'
        : 'faixa de baixo';

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceCardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.borderSubtleOf(context)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderSubtleOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Slot ${widget.index + 1} de ${widget.group.count} ($where)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Escolha a função e toque em Confirmar',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMutedOf(context),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('AÇÕES'),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        for (final a in actions)
                          _chip(
                            a.name,
                            ControlSlot.action(a.id),
                            icon: a.icon,
                          ),
                      ],
                    ),
                    _section('APPS INSTALADOS NO APARELHO'),
                    if (apps.isEmpty && !savedAppMissing)
                      Text(
                        controller.isLoadingApps
                            ? 'Carregando a lista de apps...'
                            : 'Conecte o aparelho para listar os apps.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMutedOf(context),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          if (savedAppMissing)
                            _chip(current.appName ?? current.appId!, current),
                          for (final app in apps)
                            _chip(app.name, ControlSlot.app(app.id, app.name)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            // Fora da rolagem: sempre visíveis, mesmo com muitos apps.
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _chip(
                  'Esvaziar slot',
                  const ControlSlot.empty(),
                  icon: Icons.crop_square_rounded,
                ),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, const _SlotPickResult.restore()),
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Restaurar padrão da faixa'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _SlotPickResult.slot(_choice),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Confirmar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
