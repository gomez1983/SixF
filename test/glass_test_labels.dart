import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/ui/glass/glass_flags.dart';
import 'package:sixf_remote/ui/widgets/volume_channel_controls.dart';

/// Rótulos das abas e achados que mudam entre a interface atual e o modo
/// Liquid Glass (`--dart-define=SIXF_GLASS_UI=true`). Os testes de layout usam
/// estes ajudantes para valerem nos dois modos.
String get tabKeysLabel => kGlassUi ? 'Teclas' : 'Teclas & Mídia';
String get tabTrackpadLabel => kGlassUi ? 'Trackpad' : 'Magic Trackpad';
String get tabLibraryLabel => kGlassUi ? 'Mídia' : 'Biblioteca de mídia';

/// Bloco de VOL/MUTE/VOZ/CH: o widget atual ou o equivalente em vidro.
Finder volumeBlock() => kGlassUi
    ? find.byKey(const Key('glass-volume'))
    : find.byType(VolumeChannelControls);
