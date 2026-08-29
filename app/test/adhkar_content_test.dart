import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/adhkar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('утренние и вечерние зикры следуют порядку Крепости мусульманина', () async {
    final collections = await AdhkarRepository.load();
    final morning = collections['morning']!;
    final evening = collections['evening']!;

    final expectedMorning = <int>[
      for (var number = 75; number <= 96; number++) number,
      98,
    ];
    final expectedEvening = <int>[
      for (var number = 75; number <= 92; number++) number,
      96,
      97,
      98,
    ];

    expect(morning.items, hasLength(expectedMorning.length));
    expect(evening.items, hasLength(expectedEvening.length));
    expect(morning.items.map((item) => item.order), orderedEquals([
      for (var order = 1; order <= expectedMorning.length; order++) order,
    ]));
    expect(evening.items.map((item) => item.order), orderedEquals([
      for (var order = 1; order <= expectedEvening.length; order++) order,
    ]));

    for (var index = 0; index < expectedMorning.length; index++) {
      expect(
        morning.items[index].source,
        contains('№ ${expectedMorning[index]}'),
      );
      expect(morning.items[index].status, contains('религиозная проверка'));
    }
    for (var index = 0; index < expectedEvening.length; index++) {
      expect(
        evening.items[index].source,
        contains('№ ${expectedEvening[index]}'),
      );
      expect(evening.items[index].status, contains('религиозная проверка'));
    }
  });
}
