import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'controllers/remote_controller.dart';
import 'services/tray_service.dart';
import 'services/volume_key_service.dart';
import 'ui/theme/app_theme.dart';
import 'ui/views/remote_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SixFRemoteApp());
}

/// Aplicação de controle remoto universal inteligente SixF.
class SixFRemoteApp extends StatefulWidget {
  const SixFRemoteApp({super.key});

  @override
  State<SixFRemoteApp> createState() => _SixFRemoteAppState();
}

class _SixFRemoteAppState extends State<SixFRemoteApp> with WindowListener, WidgetsBindingObserver {
  late final RemoteController _remoteController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remoteController = RemoteController();
    _remoteController.addListener(_onControllerChanged);
    VolumeKeyService().init(_remoteController);
    _initDesktopFeatures();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _remoteController.autoReconnectIfNeeded();
    }
  }

  void _initDesktopFeatures() async {
    if (!kIsWeb && Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        windowManager.addListener(this);
        await windowManager.setPreventClose(true);
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        debugPrint('[Desktop] Erro windowManager: $e');
      }
    }
    try {
      await TrayService().init(_remoteController);
    } catch (e) {
      debugPrint('[Desktop] Erro TrayService: $e');
    }
  }

  @override
  void onWindowClose() async {
    if (!kIsWeb && Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST')) {
      final isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose) {
        await windowManager.hide();
      }
    }
  }

  void _onControllerChanged() {
    TrayService().updateContextMenu();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb && Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST')) {
      windowManager.removeListener(this);
    }
    VolumeKeyService().dispose();
    _remoteController.removeListener(_onControllerChanged);
    _remoteController.dispose();
    TrayService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _remoteController,
      child: Consumer<RemoteController>(
        builder: (context, controller, _) {
          return MaterialApp(
            title: 'SixF Remote',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: controller.themeMode,
            home: const RemoteView(),
          );
        },
      ),
    );
  }
}
