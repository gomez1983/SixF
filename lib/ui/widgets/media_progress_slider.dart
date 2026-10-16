import 'package:flutter/material.dart';

import '../../controllers/media_cast_controller.dart';

/// Mantém a prévia do gesto local e envia somente uma busca ao soltar.
class MediaProgressSlider extends StatefulWidget {
  final MediaCastController controller;
  const MediaProgressSlider({super.key, required this.controller});

  @override
  State<MediaProgressSlider> createState() => _MediaProgressSliderState();
}

class _MediaProgressSliderState extends State<MediaProgressSlider> {
  double? _preview;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final max = controller.totalDuration.inMilliseconds.toDouble();
    if (max <= 0) return const SizedBox.shrink();
    if (!controller.canSeek) _preview = null;
    return Slider(
      value: (_preview ?? controller.currentPosition.inMilliseconds.toDouble())
          .clamp(0, max),
      max: max,
      onChanged: controller.canSeek
          ? (value) => setState(() => _preview = value)
          : null,
      onChangeEnd: controller.canSeek
          ? (value) {
              setState(() => _preview = null);
              controller.seekTo(Duration(milliseconds: value.round()));
            }
          : null,
    );
  }
}
