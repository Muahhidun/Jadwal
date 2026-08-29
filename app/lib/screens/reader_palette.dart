import 'package:flutter/material.dart';

const readerTransliterationFontSize = 17.0;

/// Локальные палитры читалки. Они не меняют общую тему приложения и нужны
/// только для комфортного чтения религиозных текстов в разных условиях.
class ReaderPalette {
  const ReaderPalette({
    required this.id,
    required this.titleRu,
    required this.titleKz,
    required this.isDark,
    required this.bg,
    required this.ink,
    required this.arabic,
    required this.translit,
    required this.accent,
    required this.fazPlate,
    required this.source,
    required this.divider,
    required this.button,
    required this.buttonInk,
    required this.disabled,
  });

  final String id, titleRu, titleKz;
  final bool isDark;
  final Color bg,
      ink,
      arabic,
      translit,
      accent,
      fazPlate,
      source,
      divider,
      button,
      buttonInk,
      disabled;

  String title(String lang) => lang == 'kz' ? titleKz : titleRu;

  static const paper = ReaderPalette(
    id: 'paper',
    titleRu: 'Тёплая бумага',
    titleKz: 'Жылы қағаз',
    isDark: false,
    bg: Color(0xFFF7F2E7),
    ink: Color(0xFF2C2A24),
    arabic: Color(0xFF23211B),
    translit: Color(0xFF615B4E),
    accent: Color(0xFF8C7A4E),
    fazPlate: Color(0xFFEFE8D6),
    source: Color(0xFF7F7868),
    divider: Color(0xFFE3DCC9),
    button: Color(0xFF2C2A24),
    buttonInk: Color(0xFFF7F2E7),
    disabled: Color(0xFFD9D1BC),
  );

  static const monoLight = ReaderPalette(
    id: 'monoLight',
    titleRu: 'Чёрное на белом',
    titleKz: 'Ақ фонда қара',
    isDark: false,
    bg: Color(0xFFFCFCFC),
    ink: Color(0xFF171717),
    arabic: Color(0xFF080808),
    translit: Color(0xFF3F3F3F),
    accent: Color(0xFF202020),
    fazPlate: Color(0xFFF0F0F0),
    source: Color(0xFF666666),
    divider: Color(0xFFDEDEDE),
    button: Color(0xFF111111),
    buttonInk: Color(0xFFFFFFFF),
    disabled: Color(0xFFC9C9C9),
  );

  static const monoDark = ReaderPalette(
    id: 'monoDark',
    titleRu: 'Белое на чёрном',
    titleKz: 'Қара фонда ақ',
    isDark: true,
    bg: Color(0xFF050505),
    ink: Color(0xFFF2F2F2),
    arabic: Color(0xFFFFFFFF),
    translit: Color(0xFFD8D8D8),
    accent: Color(0xFFFFFFFF),
    fazPlate: Color(0xFF151515),
    source: Color(0xFFA3A3A3),
    divider: Color(0xFF292929),
    button: Color(0xFFF4F4F4),
    buttonInk: Color(0xFF090909),
    disabled: Color(0xFF3A3A3A),
  );

  static const softDark = ReaderPalette(
    id: 'softDark',
    titleRu: 'Мягкая тёмная',
    titleKz: 'Жұмсақ қараңғы',
    isDark: true,
    bg: Color(0xFF19212B),
    ink: Color(0xFFE1DDD4),
    arabic: Color(0xFFF2EDE3),
    translit: Color(0xFFBDB6AA),
    accent: Color(0xFFC7A36A),
    fazPlate: Color(0xFF242F3C),
    source: Color(0xFF929BA5),
    divider: Color(0xFF35414E),
    button: Color(0xFFD9D2C5),
    buttonInk: Color(0xFF17202A),
    disabled: Color(0xFF414C58),
  );

  static const values = [paper, monoLight, monoDark, softDark];

  static ReaderPalette fromId(String id) =>
      values.firstWhere((palette) => palette.id == id, orElse: () => paper);
}
