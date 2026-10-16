import 'dart:async';

import 'package:flutter/material.dart';

/// Repetição limitada ao gesto atual e ao aparelho que o iniciou.
class RepeatPress extends StatefulWidget {
  final Widget child;
  final VoidCallback onRepeat;
  final Object? sessionToken;
  const RepeatPress({
    super.key,
    required this.child,
    required this.onRepeat,
    this.sessionToken,
  });
  @override
  State<RepeatPress> createState() => _RepeatPressState();
}

class _RepeatPressState extends State<RepeatPress> with WidgetsBindingObserver {
  Timer? _timer;
  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(RepeatPress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionToken != widget.sessionToken) _stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  @override
  void dispose() {
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onExit: (_) => _stop(),
    child: GestureDetector(
      onLongPressStart: (_) {
        _stop();
        widget.onRepeat();
        _timer = Timer.periodic(
          const Duration(milliseconds: 120),
          (_) => widget.onRepeat(),
        );
      },
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      onLongPressMoveUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null &&
            !(Offset.zero & box.size).contains(details.localPosition)) {
          _stop();
        }
      },
      child: widget.child,
    ),
  );
}
