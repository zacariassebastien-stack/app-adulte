import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:couple_cards/domain/game/game_models.dart';
import 'package:couple_cards/features/game/game_media_capabilities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const reader = PlatformGameMediaCapabilities();
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformGameMediaCapabilities.channel, null),
  );
  test(
    'native capture probe forwards only supported capture capabilities',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformGameMediaCapabilities.channel, (
            call,
          ) async {
            expect(call.method, 'captureCapabilities');
            return ['PHOTO_CAPTURE', 'MEDIA_SEND', 'UNKNOWN'];
          });
      expect(await reader.read(), {MediaCapability.PHOTO_CAPTURE});
    },
  );
  test(
    'absent device support does not fabricate photo or video capabilities',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            PlatformGameMediaCapabilities.channel,
            (_) async => [],
          );
      expect(await reader.read(), isEmpty);
    },
  );
  test('missing platform bridge is conservatively unavailable', () async {
    expect(await reader.read(), isEmpty);
  });
  test('native errors are conservatively unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PlatformGameMediaCapabilities.channel,
          (_) async => throw PlatformException(code: 'unavailable'),
        );
    expect(await reader.read(), isEmpty);
  });
}
