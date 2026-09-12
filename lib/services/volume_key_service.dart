import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../controllers/remote_controller.dart';

/// Serviço que gerencia a comunicação nativa para interceptação de teclas de hardware de volume.
/// No Windows, a integração C++ via WH_KEYBOARD_LL intercepta VK_VOLUME_UP, VK_VOLUME_DOWN e
/// VK_VOLUME_MUTE quando o app está em primeiro plano, suprimindo a alteração no Windows
/// e enviando os comandos para a Smart TV LG.
class VolumeKeyService {
  static const MethodChannel _channel = MethodChannel('controle_lg/volume_keys');
  static final VolumeKeyService _instance = VolumeKeyService._internal();

  factory VolumeKeyService() => _instance;

  VolumeKeyService._internal();

  RemoteController? _controller;

  void init(RemoteController controller) {
    _controller = controller;
    if (!kIsWeb && Platform.isWindows) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    final controller = _controller;
    if (controller == null) return null;

    switch (call.method) {
      case 'volumeUp':
        controller.volumeUp();
        break;
      case 'volumeDown':
        controller.volumeDown();
        break;
      case 'volumeMute':
        controller.muteToggle();
        break;
      default:
        break;
    }
    return null;
  }

  void dispose() {
    if (!kIsWeb && Platform.isWindows) {
      _channel.setMethodCallHandler(null);
    }
    _controller = null;
  }
}
