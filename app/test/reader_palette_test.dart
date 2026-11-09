import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/prayer/schedule.dart';
import 'package:jadwal/screens/reader_palette.dart';

void main() {
  test('читалка предлагает две светлые и две тёмные палитры', () {
    expect(ReaderPalette.values, hasLength(4));
    expect(
      ReaderPalette.values.where((palette) => palette.isDark),
      hasLength(2),
    );
    expect(
      ReaderPalette.values.where((palette) => !palette.isDark),
      hasLength(2),
    );
  });

  test('выбранная палитра сохраняется локально', () async {
    SharedPreferences.setMockInitialValues({'readerPalette': 'softDark'});
    final state = await AppState.load();
    expect(state.readerPalette, 'softDark');

    state.readerPalette = 'monoLight';
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('readerPalette'), 'monoLight');
  });

  test('неизвестное старое значение безопасно возвращает бумажную палитру', () {
    expect(ReaderPalette.fromId('unknown'), ReaderPalette.paper);
  });

  test('транскрипция использует увеличенный размер шрифта', () {
    expect(readerTransliterationFontSize, greaterThanOrEqualTo(17));
  });

  group('автоматическая тема по времени суток', () {
    const times = {Prayer.sunrise: 6 * 60, Prayer.maghrib: 19 * 60};

    test(
      'в списке выбора пятый пункт «авто», настоящих палитр по-прежнему 4',
      () {
        expect(ReaderPalette.options, hasLength(5));
        expect(ReaderPalette.options.last.isAuto, isTrue);
        expect(ReaderPalette.values.any((p) => p.isAuto), isFalse);
      },
    );

    test('после Фаджра до восхода и после магриба — тёмная', () {
      expect(
        ReaderPalette.isNight(DateTime(2026, 11, 9, 5, 30), times),
        isTrue,
      );
      expect(
        ReaderPalette.isNight(DateTime(2026, 11, 9, 19, 0), times),
        isTrue,
      );
      expect(
        ReaderPalette.isNight(DateTime(2026, 11, 9, 23, 10), times),
        isTrue,
      );
    });

    test('от восхода до магриба (включая время после Аср) — светлая', () {
      expect(
        ReaderPalette.isNight(DateTime(2026, 11, 9, 6, 0), times),
        isFalse,
      );
      expect(
        ReaderPalette.isNight(DateTime(2026, 11, 9, 17, 30), times),
        isFalse,
      );
    });

    test('resolve даёт светлую бумагу днём и мягкую тёмную ночью', () {
      expect(ReaderPalette.resolve('auto', night: false), ReaderPalette.paper);
      expect(
        ReaderPalette.resolve('auto', night: true),
        ReaderPalette.softDark,
      );
      expect(
        ReaderPalette.resolve('monoDark', night: false),
        ReaderPalette.monoDark,
      );
    });

    test('без расписания «авто» остаётся светлой', () {
      expect(ReaderPalette.isNight(DateTime(2026, 11, 9, 3), null), isFalse);
    });
  });
}
