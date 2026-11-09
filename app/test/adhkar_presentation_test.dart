import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/adhkar.dart';
import 'package:jadwal/data/adhkar_presentation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('карточки сохраняют сборники и номера, без имён и оценок', () async {
    final collections = await AdhkarRepository.load();
    for (final collection in collections.values) {
      for (final zikr in collection.items) {
        final source = readerSource(zikr.source);
        expect(source, isNotEmpty);
        expect(source, matches(RegExp(r'\d')));
        expect(
          source,
          isNot(
            matches(
              RegExp(
                'Альбани|Албани|Ибн Баз|Кулиев|мауд|маукуф|слабый|хасан',
                caseSensitive: false,
              ),
            ),
          ),
        );
        expect(readerTranslation(zikr.ru ?? ''), isNot(contains('Кулиев')));
      }
      final questioned = collection.items[8];
      expect(readerSource(questioned.source), 'Абу Дауд, 5081');
      expect(questioned.fazRu, isNull);
      expect(questioned.note, contains('проверка религиозным специалистом'));
    }
  });

  test(
    'перевод остаётся полным, происхождение исходных строк не теряется',
    () async {
      final collections = await AdhkarRepository.load();
      for (final collection in collections.values) {
        final kursi = collection.items[0];
        expect(kursi.ru, contains('Кулиева'));
        expect(readerTranslation(kursi.ru!), contains('Возвышенный, Великий'));
        expect(readerTranslation(kursi.ru!), endsWith('(аль-Бакара, 2:255).'));
        final surahs = readerTranslation(collection.items[1].ru!);
        expect(surahs, contains('Аллах Самодостаточный'));
        expect(surahs, contains('джиннов и людей'));
        expect(surahs, contains('Каждую суру читать по три раза.'));
      }
    },
  );

  test('утренний пример владельца и полный финал дуа сохранены', () async {
    final collections = await AdhkarRepository.load();
    final original = collections['morning']!.items[2].translit!;
    final displayed = readerTranscription(original);
    expect(displayed, startsWith('Асбахна уа асбахаль-мульку лильлях'));
    expect(displayed, contains('ля иляха илля Аллах, уахдаху ля шарика лях'));
    expect(displayed, contains("уа хуа 'аля кулли шайн кодир."));
    expect(displayed, contains('Робби'));
    expect(displayed, endsWith("уа 'азабин филь-кабр"));
    expect(original, contains('ва асбахаль'));
    final evening = readerTranscription(
      collections['evening']!.items[2].translit!,
    );
    expect(evening, startsWith('Амсайна уа амсаль-мульку лильлях'));
    expect(evening, contains('хазихиль-ляйляти'));
  });

  test('уа единообразно, но нет слепой замены всех ра или са', () async {
    final collections = await AdhkarRepository.load();
    for (final zikr in collections.values.expand((c) => c.items)) {
      final displayed = readerTranscription(zikr.translit!);
      expect(displayed, isNot(matches(RegExp('[вВ]'))));
      expect(displayed, isNotEmpty);
    }
    expect(readerTranscription('Хува куфуван'), 'Хуа куфуан');
    expect(
      readerTranscription('Робби би-рахматика Самад'),
      'Робби би-рохматика Сомад',
    );
    expect(
      readerTranscription('фитратиль-ислям судурин-нас'),
      'фитратиль-ислям судурин-нас',
    );
  });
}
