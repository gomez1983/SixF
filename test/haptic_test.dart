import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sixf_remote/controllers/remote_controller.dart';
import 'package:sixf_remote/services/haptic_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HapticService Tests', () {
    test('HapticService defaults and toggle state', () {
      HapticService.isEnabled = true;
      expect(HapticService.isEnabled, isTrue);

      HapticService.isEnabled = false;
      expect(HapticService.isEnabled, isFalse);

      HapticService.isEnabled = true;
      expect(HapticService.isEnabled, isTrue);
    });

    test('HapticService methods execute without throwing', () async {
      HapticService.isEnabled = true;
      expect(() => HapticService.buttonPress(), returnsNormally);
      expect(() => HapticService.heavyPress(), returnsNormally);
      expect(() => HapticService.selectionClick(), returnsNormally);
      expect(() => HapticService.voicePress(), returnsNormally);
      expect(() => HapticService.voiceRelease(), returnsNormally);
      expect(() => HapticService.voiceLock(), returnsNormally);

      HapticService.isEnabled = false;
      expect(() => HapticService.buttonPress(), returnsNormally);
      expect(() => HapticService.heavyPress(), returnsNormally);
      expect(() => HapticService.selectionClick(), returnsNormally);
      expect(() => HapticService.voicePress(), returnsNormally);
      expect(() => HapticService.voiceRelease(), returnsNormally);
      expect(() => HapticService.voiceLock(), returnsNormally);
    });

    test('RemoteController toggles and updates HapticService', () {
      final controller = RemoteController();
      expect(controller.isHapticEnabled, isTrue);

      controller.setHapticFeedback(false);
      expect(controller.isHapticEnabled, isFalse);
      expect(HapticService.isEnabled, isFalse);

      controller.toggleHapticFeedback();
      expect(controller.isHapticEnabled, isTrue);
      expect(HapticService.isEnabled, isTrue);
    });
  });
}
