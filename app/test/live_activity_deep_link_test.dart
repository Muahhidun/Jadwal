import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/services/live_activity_service.dart';

void main() {
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
}
