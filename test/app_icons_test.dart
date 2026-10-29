import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/drivers/tv_app_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('known ADB apps use their own logos without matching unknown packages', () {
    expect(TvAppInfo.fromRaw(
      id: 'adb:com.google.android.youtube.tvmusic/.Main', name: 'YouTube Music',
    ).iconAsset, 'assets/app_icons/youtube-music.png');
    expect(TvAppInfo.fromRaw(
      id: 'adb:com.example.netflixclone/.Main', name: 'Netflix clone',
    ).iconAsset, isNull);
    expect(TvAppInfo.fromRaw(id: 'netflix', name: 'Netflix').iconAsset,
      'assets/app_icons/netflix.png');
  });
  test('every bundled logo is packaged and decodes as an image', () async {
    final icons = Directory('assets/app_icons').listSync()
        .whereType<File>().where((file) => file.path.endsWith('.png'));
    expect(icons.length, 13);
    for (final file in icons) {
      final asset = file.path.replaceAll('\\', '/');
      final bytes = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0), reason: asset);
      frame.image.dispose();
      codec.dispose();
    }
  });
}
