import 'package:flutter_test/flutter_test.dart';
import 'package:sixf_remote/services/google_tv_apps_adb.dart';

void main() {
  test(
    'ADB inventory deduplicates real activities and ignores shell noise',
    () {
      final apps = GoogleTvAppsAdb.parseApps(
        'com.netflix.ninja/.MainActivity\r\ncom.netflix.ninja/.OtherActivity\ncom.google.android.youtube.tv/com.google.android.apps.youtube.tv.activity.MainActivity\n2 activities found\nerror; rm stuff\n',
      );
      expect(apps, hasLength(2));
      expect(apps.first.id, 'adb:com.netflix.ninja/.MainActivity');
    },
  );
  test('ADB refuses injected component before connecting', () async {
    await expectLater(
      GoogleTvAppsAdb.launch('127.0.0.1', 'x/y; reboot'),
      throwsStateError,
    );
  });
}
