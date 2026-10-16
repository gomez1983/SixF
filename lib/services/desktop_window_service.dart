import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Preserva geometria, maximização e preferência de sobreposição ao compactar.
class DesktopWindowService {
  final WindowManager window;
  DesktopWindowService({WindowManager? window})
    : window = window ?? windowManager;
  Rect? _bounds;
  bool _maximized = false;
  bool _alwaysOnTop = false;
  bool _busy = false;

  Future<void> setCompact(bool compact) async {
    if (_busy) return;
    _busy = true;
    try {
      if (compact) {
        _bounds = await window.getBounds();
        _maximized = await window.isMaximized();
        _alwaysOnTop = await window.isAlwaysOnTop();
        if (_maximized) {
          await window.unmaximize();
          _bounds = await window.getBounds();
        }
        await window.setMinimumSize(const Size(320, 420));
        await window.setSize(const Size(360, 520));
        await window.setAlwaysOnTop(true);
      } else {
        await restore();
      }
    } catch (_) {
      try {
        await restore();
      } catch (_) {}
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> restore() async {
    final bounds = _bounds;
    if (bounds == null) return;
    await window.setAlwaysOnTop(_alwaysOnTop);
    await window.setMinimumSize(const Size(320, 420));
    await window.setBounds(bounds);
    if (_maximized) await window.maximize();
    _bounds = null;
  }
}
