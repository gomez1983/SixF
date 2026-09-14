import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../controllers/remote_controller.dart';

/// Serviço responsável por gerenciar o ícone da aplicação na Bandeja do Windows (System Tray).
///
/// Permite:
/// - Exibir o ícone do LG Remote perto do relógio do Windows.
/// - Restaurar / focar a janela ao clicar no ícone.
/// - Menu de contexto com botão direito (Abrir, Ligar TV, Desligar TV, Mudo, Sair).
class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  RemoteController? _controller;
  bool _initialized = false;

  Future<void> init(RemoteController controller) async {
    _controller = controller;

    if (kIsWeb || !Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    if (_initialized) return;

    try {
      trayManager.addListener(this);

      // Define o ícone da bandeja
      final iconPath = Platform.isWindows
          ? 'assets/icons/app_icon.ico'
          : 'assets/icons/SixF_Logo_01.png';

      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('SixF Smart Remote');

      await updateContextMenu();
      _initialized = true;
      debugPrint('[TrayService] Ícone na bandeja do Windows inicializado com sucesso.');
    } catch (e) {
      debugPrint('[TrayService] Falha ao inicializar ícone da bandeja: $e');
    }
  }

  /// Atualiza os itens do menu de contexto com base no estado da TV
  Future<void> updateContextMenu() async {
    if (kIsWeb || !Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final isConnected = _controller?.isConnected ?? false;
      final tvName = _controller?.connectedTvName ?? 'TV LG';

      final menu = Menu(
        items: [
          MenuItem(
            key: 'show_window',
            label: 'Abrir Controle Remoto ($tvName)',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'power_wol',
            label: 'Ligar TV (Wake-on-LAN)',
          ),
          MenuItem(
            key: 'power_off',
            label: 'Desligar TV',
            disabled: !isConnected,
          ),
          MenuItem(
            key: 'toggle_mute',
            label: 'Alternar Mudo',
            disabled: !isConnected,
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_app',
            label: 'Sair do Controle',
          ),
        ],
      );

      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('[TrayService] Erro ao configurar menu de contexto da bandeja: $e');
    }
  }

  @override
  void onTrayIconMouseDown() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('[TrayService] Erro ao restaurar janela: $e');
    }
  }


  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'power_wol':
        _controller?.powerToggle();
        break;
      case 'power_off':
        if (_controller?.isConnected ?? false) {
          _controller?.powerToggle();
        }
        break;
      case 'toggle_mute':
        _controller?.toggleMute();
        break;
      case 'exit_app':
        await windowManager.setPreventClose(false);
        await trayManager.destroy();
        await windowManager.destroy();
        exit(0);
    }
  }

  void dispose() {
    if (!kIsWeb && Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST')) {
      trayManager.removeListener(this);
      trayManager.destroy();
    }
  }
}
