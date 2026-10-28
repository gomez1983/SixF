import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/drivers/tv_driver.dart';
import 'session_regression_test.dart' show RecordingDriver;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Chromecast routes volume to single saved TV; explicit device choice persists',() async {
    SharedPreferences.setMockInitialValues({});
    final controller=RemoteController(driverFactory:RecordingDriver.new);
    await controller.ready; addTearDown(controller.dispose);
    final tv=controller.activeDevice!;
    await controller.connectDevice(tv.id,allowDiscoveryFallback:false);
    await controller.saveOrUpdateDevice(const SavedDevice(id:'cast',name:'Chromecast',ip:'192.168.1.3',brand:TvBrand.googleTv),makeActive:true);
    await controller.connectDevice('cast',allowDiscoveryFallback:false);
    controller.volumeUp();
    final tvDriver=controller.getSession(tv.id)!.driver as RecordingDriver;
    final castDriver=controller.driver as RecordingDriver;
    expect(tvDriver.sentKeys,[RemoteKey.volumeUp]); expect(castDriver.sentKeys,isEmpty);
    expect(controller.activeDeviceId,'cast');
    await controller.setVolumeTarget('cast');
    controller.volumeDown();
    expect(castDriver.sentKeys,[RemoteKey.volumeDown]);
    expect(controller.storageService.getVolumeTarget('cast'),'cast');
  });
}
