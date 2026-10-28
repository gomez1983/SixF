import 'package:sixf_remote/ui/widgets/remote_button.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/controllers/media_cast_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'package:sixf_remote/ui/widgets/media_cast_dialog.dart';
import 'package:sixf_remote/ui/widgets/multimedia_controls.dart';
import 'package:sixf_remote/ui/widgets/media_progress_slider.dart';
import 'media_gallery_cast_test.dart' show SimulatedCast;
import 'session_regression_test.dart' show RecordingDriver;
import 'security_lifecycle_test.dart' show LocalMediaServer,RealHttp;
class ScopedRemote extends RemoteController {
  ScopedRemote():super(initialDriver:RecordingDriver(TvBrand.googleTv));
  String ip='127.0.0.1';
  @override String get ipAddress=>ip;
  @override bool get isConnected=>true;
}
void main() {
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  testWidgets('gallery fits 320px, swipes next and previous without reopening picker',(tester) async {
    tester.view.physicalSize=const Size(320,640); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final dir=Directory.systemTemp.createTempSync('sixf-gallery-widget');
    final files=[File('${dir.path}/a.jpg')..writeAsBytesSync([1]),File('${dir.path}/b.jpg')..writeAsBytesSync([2])];
    final remote=ScopedRemote(); await remote.ready;
    final media=MediaCastController(serverService:LocalMediaServer(),castFactory:SimulatedCast.new);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox()); media.dispose(); remote.dispose();
      await tester.runAsync(() async {
        for(var i=0;i<10;i++) {
          try { await dir.delete(recursive:true); return; } on FileSystemException { await Future<void>.delayed(const Duration(milliseconds:40)); }
        }
        await dir.delete(recursive:true);
      });
    });
    await tester.runAsync(()=>HttpOverrides.runWithHttpOverrides(()=>media.castPlaylist(files,targetTvIp:'127.0.0.1',brand:TvBrand.googleTv),RealHttp()));
    await tester.pumpWidget(MultiProvider(providers:[ChangeNotifierProvider<RemoteController>.value(value:remote),ChangeNotifierProvider.value(value:media)],
      child:const MaterialApp(home:Scaffold(body:MediaCastDialog()))));
    await tester.pump();
    expect(find.byKey(const Key('photo-gallery')),findsOneWidget);
    final gesture=await tester.startGesture(tester.getCenter(find.byKey(const Key('photo-gallery'))));
    await gesture.moveBy(const Offset(-40,0),timeStamp:const Duration(milliseconds:20));
    await tester.pump(const Duration(milliseconds:20));
    await gesture.moveBy(const Offset(-60,0),timeStamp:const Duration(milliseconds:40));
    await tester.pump(const Duration(milliseconds:20));
    await gesture.moveBy(const Offset(-60,0),timeStamp:const Duration(milliseconds:60));
    await tester.runAsync(()=>gesture.up());
    for(var i=0;i<20 && media.playlistPosition!=2;i++) {
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));
      await tester.pump();
    }
    expect(media.playlistPosition,2);
    expect(find.text('2 de 2 arquivos'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('media tab offers timeline repeat shuffle scoped to selected device',(tester) async {
    final dir=Directory.systemTemp.createTempSync('sixf-video-widget');
    final files=[File('${dir.path}/a.mp4')..writeAsBytesSync([1]),File('${dir.path}/b.mp4')..writeAsBytesSync([2])];
    final remote=ScopedRemote(); await remote.ready;
    final media=MediaCastController(serverService:LocalMediaServer(),castFactory:SimulatedCast.new);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox()); media.dispose(); remote.dispose();
      await tester.runAsync(() async {
        for(var i=0;i<10;i++) {
          try { await dir.delete(recursive:true); return; } on FileSystemException { await Future<void>.delayed(const Duration(milliseconds:40)); }
        }
        await dir.delete(recursive:true);
      });
    });
    await tester.runAsync(()=>HttpOverrides.runWithHttpOverrides(()=>media.castPlaylist(files,targetTvIp:'127.0.0.1',brand:TvBrand.googleTv),RealHttp()));
    await tester.pumpWidget(MultiProvider(providers:[ChangeNotifierProvider<RemoteController>.value(value:remote),ChangeNotifierProvider.value(value:media)],
      child:const MaterialApp(home:Scaffold(body:MultimediaControls()))));
    await tester.pump();
    expect(find.byType(MediaProgressSlider),findsOneWidget);
    expect(find.byTooltip('Repetir arquivo'),findsOneWidget);
    expect(find.byTooltip('Ordem aleatória dos arquivos selecionados'),findsOneWidget);
    await tester.tap(find.byTooltip('Repetir arquivo')); await tester.pump(); expect(media.isLooping,isTrue);
    for(final action in ['pause','play','stop']) {
      final tooltip={'pause':'Pausar (Pause)','play':'Reproduzir (Play)','stop':'Parar (Stop)'}[action]!;
      await tester.tap(find.byTooltip(tooltip)); await tester.pump();
      expect(remote.selectedMediaAction,action);
      final selected=tester.widgetList<RemoteButton>(find.byType(RemoteButton)).where((b)=>b.isSelected && b.tooltip==tooltip);
      expect(selected,hasLength(1));
    }
    remote.ip='127.0.0.2'; remote.notifyListeners(); await tester.pump();
    expect(find.byType(MediaProgressSlider),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
