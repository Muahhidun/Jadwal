import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
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
}
