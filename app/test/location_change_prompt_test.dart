import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/screens/location_change_prompt.dart';
import 'package:jadwal/screens/scene_background.dart';
import 'package:jadwal/theme/tokens.dart';

void main() {
  setUpAll(() async {
    final manrope = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    final cupertinoIcons = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await Future.wait([manrope.load(), cupertinoIcons.load()]);
  });

  const palette = DaySurfacePalette(
    colors: JColors.night,
    isLight: false,
    top: Color(0xFF172235),
    middle: Color(0xFF101B24),
    bottom: Color(0xFF061112),
    glow: Color(0xFF9BC2CF),
    surface: Color(0xA6172228),
    border: Color(0x1FFFFFFF),
    dock: Color(0xB518232A),
    dockBorder: Color(0x2BFFFFFF),
    shadow: Color(0x66000000),
  );

  Widget prompt({String lang = 'ru'}) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: LocationChangePrompt(
          currentCity: const City('Астана қаласы', '51.1', '71.4'),
          detectedCity: const City('Екібастұз қаласы', '51.7', '75.3'),
          lang: lang,
          palette: palette,
          accent: const Color(0xFF9BC2CF),
          onKeepCurrent: () {},
          onUpdate: () {},
        ),
      ),
    ),
  );

  testWidgets(
    'русская версия не показывает казахский суффикс и не теснит кнопки',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(prompt());

      expect(find.text('Астана'), findsOneWidget);
      expect(find.text('Экибастуз'), findsOneWidget);
      expect(find.textContaining('қаласы'), findsNothing);
      expect(find.text('Обновить город'), findsOneWidget);
      expect(find.text('Оставить текущий'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final primary = tester.getSize(find.byType(FilledButton));
      final secondary = tester.getSize(find.byType(OutlinedButton));
      expect(primary, secondary);
      expect(primary.height, 54);
      await expectLater(
        find.byType(LocationChangePrompt),
        matchesGoldenFile('goldens/location_change_prompt_320x640.png'),
      );
    },
  );

  testWidgets('казахская версия локализована целиком', (tester) async {
    await tester.pumpWidget(prompt(lang: 'kz'));

    expect(find.text('Басқа қалаға келдіңіз бе?'), findsOneWidget);
    expect(find.text('Қазіргі қала'), findsOneWidget);
    expect(find.text('Геолокация бойынша'), findsOneWidget);
    expect(find.text('Қаланы жаңарту'), findsOneWidget);
    expect(find.text('Қазіргі қаланы сақтау'), findsOneWidget);
    expect(find.text('Астана қаласы'), findsOneWidget);
    expect(find.text('Екібастұз қаласы'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
