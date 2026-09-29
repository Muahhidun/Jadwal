import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/services/compass_capability_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kz.dauam/compass_capability');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reads the physical compass capability from the native platform',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'isCompassAvailable');
            return false;
          });

      expect(await CompassCapabilityService.isAvailable(), isFalse);
    },
  );

  test(
    'treats an unavailable native channel as an unknown capability',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'unavailable');
          });

      expect(await CompassCapabilityService.isAvailable(), isNull);
    },
  );
}
