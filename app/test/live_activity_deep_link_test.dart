import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/services/live_activity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ссылка Live Activity возвращает в текущий сборник', () {
    final target = zikrTargetFromDeepLink(
      'dauam://zikr?collection=evening&index=7',
    );

    expect(target?.collectionId, 'evening');
    expect(target?.index, 7);
  });

  test('неверные и негативные параметры обрабатываются безопасно', () {
    expect(zikrTargetFromDeepLink('dauam://home'), isNull);
    expect(
      zikrTargetFromDeepLink('dauam://zikr?collection=other&index=4'),
      isNull,
    );
    expect(
      zikrTargetFromDeepLink('dauam://zikr?collection=morning&index=-3')?.index,
      0,
    );
  });

  test('Android не обращается к iOS-каналу Live Activity', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final result = await LiveActivityService.startZikrSession(
      collectionId: 'morning',
      currentIndex: 0,
      title: 'Утренние зикры',
      counterCurrent: 1,
      counterTotal: 21,
      zikrArabic: 'ذكر',
      zikrTranslation: 'Зикр',
    );

    expect(result, 'UNSUPPORTED');
  });
}
