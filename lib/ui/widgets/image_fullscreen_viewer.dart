import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/library_sources.dart';

/// Visualizador de fotos em tela cheia do SixF (padrão de galeria):
/// deslizar troca de foto, pinça/toque duplo dá zoom, um toque mostra/oculta
/// os controles. Teclado: ← → navegam, Esc ou F volta à tela normal.
///
/// No Windows a janela entra em tela cheia real; no Android as barras do
/// sistema ficam ocultas (modo imersivo). Ao sair, tudo volta ao estado
/// anterior. Retorna o índice da última foto exibida.
class ImageFullscreenViewer extends StatefulWidget {
  const ImageFullscreenViewer({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.resolve,
    this.onIndexChanged,
  });

  final List<LibraryEntry> items;
  final int initialIndex;
  final Future<File> Function(LibraryEntry entry) resolve;

  /// Chamado a cada troca de foto (para a TV acompanhar a tela cheia).
  final ValueChanged<int>? onIndexChanged;

  static Future<int?> show(
    BuildContext context, {
    required List<LibraryEntry> items,
    required int initialIndex,
    required Future<File> Function(LibraryEntry entry) resolve,
    ValueChanged<int>? onIndexChanged,
  }) {
    return Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        opaque: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, _, _) => ImageFullscreenViewer(
          items: items,
          initialIndex: initialIndex,
          resolve: resolve,
          onIndexChanged: onIndexChanged,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<ImageFullscreenViewer> createState() => _ImageFullscreenViewerState();
}

class _ImageFullscreenViewerState extends State<ImageFullscreenViewer> {
  late final PageController _pages;
  late int _index;
  bool _chrome = true;
  bool _zoomed = false;
  bool _windowFullscreen = false;
  final Map<int, Future<File>> _files = {};
  final FocusNode _focus = FocusNode();

  static bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pages = PageController(initialPage: _index);
    unawaited(_enterFullscreen());
  }

  Future<void> _enterFullscreen() async {
    if (_isTest) return;
    try {
      if (Platform.isWindows) {
        _windowFullscreen = !await windowManager.isFullScreen();
        if (_windowFullscreen) await windowManager.setFullScreen(true);
      } else if (Platform.isAndroid) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } catch (_) {}
  }

  Future<void> _leaveFullscreen() async {
    if (_isTest) return;
    try {
      if (Platform.isWindows && _windowFullscreen) {
        _windowFullscreen = false;
        await windowManager.setFullScreen(false);
      } else if (Platform.isAndroid) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(_leaveFullscreen());
    _pages.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<File> _fileAt(int i) =>
      _files.putIfAbsent(i, () => widget.resolve(widget.items[i]));

  void _close() => Navigator.of(context).pop(_index);

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= widget.items.length) return;
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyF) {
      _close();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _go(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _go(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.items[_index];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              PageView.builder(
                controller: _pages,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: widget.items.length,
                onPageChanged: (i) {
                  setState(() {
                    _index = i;
                    _zoomed = false;
                  });
                  widget.onIndexChanged?.call(i);
                },
                itemBuilder: (_, i) => _ZoomablePhoto(
                  key: ValueKey('fullscreen-photo-$i'),
                  file: _fileAt(i),
                  onTap: () => setState(() => _chrome = !_chrome),
                  onZoomChanged: (z) {
                    if (i == _index && z != _zoomed) {
                      setState(() => _zoomed = z);
                    }
                  },
                ),
              ),
              AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  ignoring: !_chrome,
                  child: SafeArea(
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 18),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.black87, Colors.transparent],
                              ),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Sair da tela cheia (Esc)',
                                  color: Colors.white,
                                  icon: const Icon(
                                    Icons.fullscreen_exit_rounded,
                                  ),
                                  onPressed: _close,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    entry.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_index + 1} de ${widget.items.length}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),
                        ),
                        if (_index > 0)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: IconButton.filledTonal(
                                tooltip: 'Foto anterior',
                                onPressed: () => _go(-1),
                                icon: const Icon(Icons.chevron_left_rounded),
                              ),
                            ),
                          ),
                        if (_index + 1 < widget.items.length)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: IconButton.filledTonal(
                                tooltip: 'Próxima foto',
                                onPressed: () => _go(1),
                                icon: const Icon(Icons.chevron_right_rounded),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    super.key,
    required this.file,
    required this.onTap,
    required this.onZoomChanged,
  });

  final Future<File> file;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  Animation<Matrix4>? _tween;
  Offset _lastTap = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01);
    });
    _anim.addListener(() {
      final t = _tween;
      if (t != null) _transform.value = t.value;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 end;
    if (zoomed) {
      end = Matrix4.identity();
    } else {
      const scale = 2.5;
      end = Matrix4.identity()
        ..translateByDouble(
          -_lastTap.dx * (scale - 1),
          -_lastTap.dy * (scale - 1),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1);
    }
    _tween = Matrix4Tween(
      begin: _transform.value,
      end: end,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: widget.file,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Não foi possível carregar esta foto.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return GestureDetector(
          onTap: widget.onTap,
          onDoubleTapDown: (d) => _lastTap = d.localPosition,
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: 6,
            child: SizedBox.expand(
              child: Image.file(
                file,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        );
      },
    );
  }
}
