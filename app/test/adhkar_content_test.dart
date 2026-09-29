import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/adhkar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'утренние и вечерние зикры следуют порядку Крепости мусульманина',
    () async {
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
      expect(
        morning.items.map((item) => item.order),
        orderedEquals([
          for (var order = 1; order <= expectedMorning.length; order++) order,
        ]),
      );
      expect(
        evening.items.map((item) => item.order),
        orderedEquals([
          for (var order = 1; order <= expectedEvening.length; order++) order,
        ]),
      );

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
    },
  );

  test(
    'все транскрипции заполнены полностью и не заканчиваются многоточием',
    () async {
      final collections = await AdhkarRepository.load();
      final items = collections.values.expand((collection) => collection.items);

      for (final item in items) {
        final transcription = item.translit?.trim();
        expect(
          transcription,
          isNotNull,
          reason: 'Нет транскрипции у зикра №${item.order}',
        );
        expect(
          transcription,
          isNotEmpty,
          reason: 'Пустая транскрипция у зикра №${item.order}',
        );
        expect(
          transcription,
          isNot(anyOf(endsWith('…'), endsWith('...'))),
          reason: 'Оборванная транскрипция у зикра №${item.order}',
        );
      }
    },
  );

  test('утренний и вечерний варианты дуа №80 содержат полный финал', () async {
    final collections = await AdhkarRepository.load();
    final morning = collections['morning']!.items[5].translit!;
    final evening = collections['evening']!.items[5].translit!;

    expect(morning, startsWith('Аллахумма инни асбахту'));
    expect(evening, startsWith('Аллахумма инни амсайту'));
    expect(morning, endsWith('ва анна Мухаммадан ‘абду-ка ва расулю-ка.'));
    expect(evening, endsWith('ва анна Мухаммадан ‘абду-ка ва расулю-ка.'));
  });

  test('варианты зикра на 10 и 100 раз не смешивают достоинства', () async {
    final collections = await AdhkarRepository.load();
    final morning = collections['morning']!;
    final evening = collections['evening']!;

    final morningTen = morning.items.firstWhere(
      (item) => item.source.contains('№ 92'),
    );
    final eveningTen = evening.items.firstWhere(
      (item) => item.source.contains('№ 92'),
    );
    final dailyHundred = morning.items.firstWhere(
      (item) => item.source.contains('№ 93'),
    );

    for (final ten in [morningTen, eveningTen]) {
      expect(ten.repeat, 10);
      expect(ten.fazRu, contains('десять раз'));
      expect(ten.fazRu, isNot(contains('100 раз')));
      expect(ten.source, contains('ан-Насаи'));
      expect(ten.source, isNot(contains('аль-Бухари')));
    }

    expect(dailyHundred.repeat, 100);
    expect(dailyHundred.fazRu, contains('100 раз'));
    expect(dailyHundred.source, contains('аль-Бухари, 3293'));
    expect(dailyHundred.source, contains('Муслим, 2691'));
  });
}
