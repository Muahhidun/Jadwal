import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BoxDecoration, Icons, MaterialApp;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/adhkar.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/i18n/strings.dart';
import 'package:jadwal/main.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/home.dart';
import 'package:jadwal/screens/qibla_screen.dart';
import 'package:jadwal/screens/reader.dart';
import 'package:jadwal/screens/reminders.dart';
import 'package:jadwal/services/widget_data_service.dart';

/// Фиксированный день из дизайн-прототипа: пятница 03.07.2026, 20:11, Алматы.
/// Времена — [fajr, sunrise, dhuhr, asr, maghrib, isha] в минутах.
Future<ScheduleService> demoSchedule() async {
  final prefs = await SharedPreferences.getInstance();
  final service = ScheduleService(
    prefs,
    now: () => DateTime(2026, 7, 3, 20, 11),
  );
  service.preload(kDefaultCity, 2026, {
    '2026-07-03': [185, 298, 779, 1074, 1253, 1358],
    '2026-07-04': [186, 299, 779, 1074, 1253, 1357],
  });
  return service;
}

void main() {
  test('русские названия месяцев хиджры не склоняются', () {
    expect(S.ru.hijriMonths[0], 'мухаррам');
    expect(S.ru.hijriMonths[1], 'сафар');
    expect(S.ru.hijriMonths[8], 'рамадан');
  });

  test('дата в шапке не содержит день недели', () {
    expect(dateLine(S.ru, DateTime(2026, 8, 24), true), '24 августа');
    expect(dateLine(S.ru, DateTime(2026, 8, 24), false), isNot(contains('·')));
  });

  test('кольцо дня учитывает пользовательские дела', () async {
    final daily = ReminderConfig(
      id: 'personal',
      title: 'Личное дело',
      prayer: 4,
      offsetMin: 0,
    );
    final anotherDay = ReminderConfig(
      id: 'weekly',
      title: 'Пятничное дело',
      prayer: 2,
      offsetMin: 0,
      repeat: 'weekly',
      weekday: DateTime.friday,
    );
    SharedPreferences.setMockInitialValues({
      'customReminders': jsonEncode([daily.toJson(), anotherDay.toJson()]),
      'done:2026-7-23': ['morning', 'custom:personal'],
    });
    final state = await AppState.load();

    expect(state.taskProgressOn(DateTime(2026, 7, 23)), (2, 3));
  });

  testWidgets('первый запуск открывает онбординг с выбором языка', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = await AppState.load();
    await tester.pumpWidget(
      JadwalApp(state: state, schedule: await demoSchedule()),
    );
    await tester.pump();

    expect(find.text('Дауам'), findsOneWidget);
    expect(find.text('Қазақша'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
  });

  testWidgets('вечером в открытое окно главный зовёт к вечерним зикрам', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    await tester.pumpWidget(
      JadwalApp(state: state, schedule: await demoSchedule()),
    );
    await tester.pump();

    // В заголовке — неразрывный пробел ( ), как в дизайн-прототипе.
    expect(find.text('Вечерние зикры'), findsWidgets);
    expect(find.text('Читать зикры'), findsOneWidget);
    expect(find.textContaining('42'), findsWidgets); // адаптивно: «42 мин»
  });

  testWidgets('верхний и нижний экраны свайпом возвращаются к таймеру', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    await tester.pumpWidget(
      JadwalApp(state: state, schedule: await demoSchedule()),
    );
    await tester.pump();

    final home = find.byType(HomeScreen);
    dynamic homeState() => tester.state(home);
    Future<void> swipe(double dy, {double startY = 420}) async {
      final gesture = await tester.startGesture(Offset(196, startY));
      await gesture.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    // Центральный таймер → верхняя Кибла → центральный таймер.
    await swipe(240);
    expect(homeState().swipeProgress, closeTo(-1.0, 0.01));
    expect(find.text('ДО МАГРИБА'), findsNothing);
    expect(find.text('свайп вниз — назад'), findsOneWidget);

    final qibla = find.byType(QiblaView);
    expect(tester.widget<QiblaView>(qibla).hapticsEnabled, isTrue);
    homeState().swipeProgress = -0.75;
    await tester.pump();
    expect(tester.widget<QiblaView>(qibla).hapticsEnabled, isFalse);
    homeState().swipeProgress = -1.0;
    await tester.pump();
    expect(
      find.descendant(
        of: qibla,
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsNothing,
    );
    // Шапка и вкладки не являются зонами перелистывания.
    await tester.drag(
      find.descendant(of: qibla, matching: find.text('Карта')),
      const Offset(0, -240),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(homeState().swipeProgress, closeTo(-1.0, 0.01));

    // Переключение карты не должно возвращать приложение на главный экран.
    await tester.tap(find.descendant(of: qibla, matching: find.text('Карта')));
    await tester.pump(const Duration(milliseconds: 250));
    expect((tester.state(qibla) as dynamic).selectedTab, 1);
    expect(homeState().swipeProgress, closeTo(-1.0, 0.01));
    expect(find.text('свайп вниз — назад'), findsNothing);

    // Центр карты получает естественное однопальцевое перемещение и не листает
    // приложение. Возврат доступен только по левой/правой рамке.
    final map = find.byKey(const ValueKey('qibla-map'));
    expect(map, findsOneWidget);
    await tester.drag(map, const Offset(0, -240));
    await tester.pump(const Duration(milliseconds: 250));
    expect(homeState().swipeProgress, closeTo(-1.0, 0.01));

    await tester.tap(find.byKey(const ValueKey('qibla-map-center-button')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(homeState().swipeProgress, closeTo(-1.0, 0.01));
    expect((tester.state(qibla) as dynamic).selectedTab, 1);

    final edge = find.byKey(const ValueKey('qibla-map-left-return-zone'));
    expect(edge, findsOneWidget);
    await tester.drag(edge, const Offset(0, -240));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(homeState().swipeProgress, closeTo(0.0, 0.01));

    // Центральный таймер → нижний экран дня → центральный таймер.
    await swipe(-240);
    expect(homeState().swipeProgress, closeTo(1.0, 0.01));

    await swipe(240);
    expect(homeState().swipeProgress, closeTo(0.0, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'без магнитометра Кибла сразу открывает карту и не показывает стрелку',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboardingDone': true,
        'lang': 'ru',
      });
      final state = await AppState.load();

      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            home: QiblaView(
              selectedCity: kDefaultCity,
              compassAvailabilityProbe: () async => false,
            ),
          ),
        ),
      );
      await tester.pump();

      final qibla = find.byType(QiblaView);
      expect((tester.state(qibla) as dynamic).selectedTab, 1);
      expect(find.byKey(const ValueKey('qibla-map')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('qibla-compass-notice')),
        findsOneWidget,
      );
      expect(find.textContaining('нет датчика компаса'), findsOneWidget);
      expect(find.byIcon(Icons.mosque), findsNothing);

      await tester.tap(find.text('Локатор'));
      await tester.pump();
      expect((tester.state(qibla) as dynamic).selectedTab, 1);
      expect(find.byKey(const ValueKey('qibla-map')), findsOneWidget);
    },
  );

  testWidgets('Fold увеличивает элементы экрана Киблы', (tester) async {
    tester.view.physicalSize = const Size(673, 841);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: QiblaView(
            selectedCity: kDefaultCity,
            compassAvailabilityProbe: () async => false,
          ),
        ),
      ),
    );
    await tester.pump();

    final title = find.text('Направление Киблы');
    expect(tester.widget<Text>(title).style?.fontSize, 23);
    expect(tester.takeException(), isNull);
  });

  testWidgets('компас без данных через пять секунд переходит на карту', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: QiblaView(
            selectedCity: kDefaultCity,
            compassAvailabilityProbe: () async => true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));

    final qibla = find.byType(QiblaView);
    expect((tester.state(qibla) as dynamic).selectedTab, 1);
    expect(find.byKey(const ValueKey('qibla-map')), findsOneWidget);
    expect(find.textContaining('Не удалось получить'), findsOneWidget);
  });

  testWidgets('календарная дата не запускает родительский свайп после Киблы', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    await tester.pumpWidget(
      JadwalApp(state: state, schedule: await demoSchedule()),
    );
    await tester.pump();

    final home = find.byType(HomeScreen);
    dynamic homeState() => tester.state(home);
    Future<void> swipeAt(Offset start, double dy) async {
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(Offset(0, dy / 2));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    // Сначала воспроизводим пользовательский путь Кибла → главный.
    await swipeAt(const Offset(196, 420), 240);
    expect(homeState().swipeProgress, closeTo(-1.0, 0.01));
    await swipeAt(
      tester.getCenter(find.byKey(const ValueKey('qibla-locator-return-zone'))),
      -240,
    );
    expect(homeState().swipeProgress, closeTo(0.0, 0.01));

    final before = state.dateGregorian;
    await tester.tap(find.byKey(const ValueKey('home-date-toggle')));
    await tester.pump();

    expect(state.dateGregorian, isNot(before));
    expect(homeState().swipeProgress, closeTo(0.0, 0.01));

    // Небольшое вертикальное движение по верхней полосе поглощается ею.
    await tester.drag(
      find.byKey(const ValueKey('home-header-gesture-shield')),
      const Offset(0, -80),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(homeState().swipeProgress, closeTo(0.0, 0.01));

    // Осознанный свайп из центральной допустимой зоны по-прежнему работает.
    await swipeAt(const Offset(196, 420), 240);
    expect(homeState().swipeProgress, closeTo(-1.0, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'календарная дата не возвращает нижний экран после возвратного свайпа',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboardingDone': true,
        'lang': 'ru',
      });
      final state = await AppState.load();
      await tester.pumpWidget(
        JadwalApp(state: state, schedule: await demoSchedule()),
      );
      await tester.pump();

      final home = find.byType(HomeScreen);
      dynamic homeState() => tester.state(home);

      Future<void> swipeAt(Offset start, double dy) async {
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(Offset(0, dy / 2));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(Offset(0, dy / 2));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Главный → нижний экран → главный, затем сразу нажатие по дате.
      await swipeAt(const Offset(196, 420), -240);
      expect(homeState().swipeProgress, closeTo(1.0, 0.01));
      await swipeAt(const Offset(196, 420), 240);
      expect(homeState().swipeProgress, closeTo(0.0, 0.01));

      final before = state.dateGregorian;
      await tester.tap(find.byKey(const ValueKey('home-date-toggle')));
      await tester.pump();

      expect(state.dateGregorian, isNot(before));
      expect(homeState().swipeProgress, closeTo(0.0, 0.01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('снимок для iPhone и Watch содержит 14 дней расписания', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    final prefs = await SharedPreferences.getInstance();
    final start = DateTime(2026, 7, 3, 20, 11);
    final service = ScheduleService(prefs, now: () => start);
    final year = <String, List<int>>{};
    for (
      var offset = 0;
      offset < WidgetDataService.scheduleLookaheadDays;
      offset++
    ) {
      final date = DateTime(start.year, start.month, start.day + offset);
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      year[key] = [185, 298, 779, 1074, 1253, 1358];
    }
    service.preload(kDefaultCity, 2026, year);

    String? payload;
    const channel = MethodChannel('kz.dauam/widgets');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'saveSnapshot') payload = call.arguments as String;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final today = service.timesFor(kDefaultCity, start)!;
    final saved = await WidgetDataService.sync(
      app: state,
      schedule: service,
      strings: S.ru,
      today: today,
      now: start,
      dateLabel: 'Пятница · 10 сафар',
    );

    expect(saved, isTrue);
    final json = jsonDecode(payload!) as Map<String, dynamic>;
    expect(json['schemaVersion'], 2);
    expect(json['scheduleDays'], WidgetDataService.scheduleLookaheadDays);
    expect(
      json['prayers'],
      hasLength(WidgetDataService.scheduleLookaheadDays * 6),
    );
  });

  testWidgets('после отметки вечерних появляется час дуа (пятница)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    await tester.pumpWidget(
      JadwalApp(state: state, schedule: await demoSchedule()),
    );
    await tester.pump();

    await tester.tap(
      find.text('Отметить без чтения ✓').first,
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Час дуа'), findsWidgets);
  });

  testWidgets('действие часа дуа не перекрывает выполненные дела', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
      'done:${AppState.dayKey(DateTime.now())}': ['morning', 'kahf', 'evening'],
    });
    final state = await AppState.load();
    await tester.pumpWidget(
      JadwalApp(state: state, schedule: await demoSchedule()),
    );
    await tester.pump();

    final chips = tester.getRect(find.byKey(const ValueKey('home-done-chips')));
    final action = tester.getRect(
      find.byKey(const ValueKey('home-window-action')),
    );

    expect(find.text('Час дуа'), findsWidgets);
    expect(action.top, greaterThanOrEqualTo(chips.bottom + 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('заголовок читалки центрирован, а пропуск выровнен по Далее', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    final schedule = await demoSchedule();
    await tester.runAsync(AdhkarRepository.load);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: ScheduleScope(
          service: schedule,
          child: const MaterialApp(home: ReaderScreen(collectionId: 'morning')),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    final title = find.byKey(const ValueKey('reader-title'));
    final pageCount = find.byWidgetPredicate(
      (widget) =>
          widget is Text && RegExp(r'^1 из \d+$').hasMatch(widget.data ?? ''),
    );
    final skip = find.byKey(const ValueKey('reader-skip-action'));
    final next = find.byKey(const ValueKey('reader-next-action'));

    expect(title, findsOneWidget);
    expect(pageCount, findsOneWidget);
    expect(tester.getCenter(title).dx, closeTo(196.5, 0.5));
    expect(tester.getCenter(pageCount).dx, closeTo(196.5, 0.5));
    expect(tester.getCenter(skip).dx, closeTo(tester.getCenter(next).dx, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fold использует двухколоночный экран дня', (tester) async {
    // Approximate logical viewport of an unfolded Galaxy Fold in portrait.
    tester.view.physicalSize = const Size(673, 841);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    await tester.pumpWidget(
      JadwalApp(state: state, schedule: await demoSchedule()),
    );
    await tester.pump();

    final home = find.byType(HomeScreen);
    (tester.state(home) as dynamic).swipeProgress = 1.0;
    await tester.pump();

    expect(find.byKey(const ValueKey('expanded-day-layout')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fold показывает крупный арабский текст в читалке', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(673, 841);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    final schedule = await demoSchedule();
    await tester.runAsync(AdhkarRepository.load);
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: ScheduleScope(
          service: schedule,
          child: const MaterialApp(home: ReaderScreen(collectionId: 'morning')),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    final arabic = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.textDirection == TextDirection.rtl &&
          (widget.data?.isNotEmpty ?? false),
    );
    expect(arabic, findsOneWidget);
    expect(tester.widget<Text>(arabic).style?.fontSize, 34);
    expect(find.textContaining('LiveActivity status'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('центр напоминаний знакомит один раз и оставляет справку', (
    tester,
  ) async {
    final fonts = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await fonts.load();
    final cupertinoIcons = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await cupertinoIcons.load();
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
    });
    final state = await AppState.load();
    await tester.pumpWidget(
      JadwalApp(state: state, schedule: await demoSchedule()),
    );
    await tester.pump();
    (tester.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 1.0;
    await tester.pump();
    await tester
        .pump(); // применить автопозиционирование ленты на актуальном деле

    await tester.tap(find.text('Напоминания'));
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('В нужный момент'), findsOneWidget);
    expect(find.text('Пропустить'), findsOneWidget);
    await expectLater(
      find.byType(JadwalApp),
      matchesGoldenFile('goldens/reminders_guide_393x852.png'),
    );

    await tester.tap(find.text('Далее'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('Готовые напоминания'), findsOneWidget);
    await tester.tap(find.text('Далее'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('Свои — только если нужны'), findsOneWidget);
    await tester.tap(find.text('Открыть напоминания'));
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('Времена молитв'), findsOneWidget);
    expect(find.text('ЕЖЕДНЕВНЫЕ'), findsOneWidget);
    expect(find.text('ЕЖЕНЕДЕЛЬНЫЕ'), findsOneWidget);
    expect(find.text('Утренние зикры'), findsOneWidget);
    expect(find.text('Вечерние зикры'), findsOneWidget);
    expect(find.text('Сура аль-Кахф'), findsOneWidget);
    expect(find.bySemanticsLabel('Читать суру'), findsOneWidget);
    expect(find.text('Час дуа в пятницу'), findsOneWidget);
    expect(find.text('Добавить напоминание'), findsOneWidget);
    expect(find.text('Название'), findsNothing);
    expect(state.remindersGuideSeen, isTrue);
    await expectLater(
      find.byType(JadwalApp),
      matchesGoldenFile('goldens/reminders_hub_393x852.png'),
    );

    await tester.tap(find.byIcon(CupertinoIcons.question).first);
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('В нужный момент'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);

    await tester.tap(find.text('Готово'));
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.tap(find.text('Времена молитв'));
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.tap(find.byIcon(CupertinoIcons.question).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('Напоминания о молитвах'), findsOneWidget);
    expect(find.text('Понятно'), findsOneWidget);
    final helpSurface = tester.widget<Container>(
      find.byKey(const ValueKey('reminder-help-surface')),
    );
    final helpDecoration = helpSurface.decoration! as BoxDecoration;
    expect(helpDecoration.color!.a, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Понятно'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.tap(find.text('Восход').last);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('СИСТЕМНЫЙ БУДИЛЬНИК'), findsOneWidget);
    expect(find.textContaining('Восход доступен'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'первый вход в будильник показывает крепкий сон и оставляет справку',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fonts = FontLoader('Manrope')
        ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
      await fonts.load();
      final cupertinoIcons =
          FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          );
      await cupertinoIcons.load();
      SharedPreferences.setMockInitialValues({
        'lang': 'ru',
        'prayer_alarm:fajr:enabled': true,
      });
      final state = await AppState.load();
      final schedule = await demoSchedule();
      const alarmChannel = MethodChannel('kz.dauam/alarm');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        alarmChannel,
        (call) async => <String, dynamic>{
          'success': true,
          'mode': 'alarmKit',
          'scheduled': 4,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          alarmChannel,
          null,
        ),
      );

      await tester.pumpWidget(
        AppScope(
          state: state,
          child: ScheduleScope(
            service: schedule,
            child: const MaterialApp(
              home: ReminderDetailScreen(configId: 'fajr', root: true),
            ),
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.text('Режим «Крепкий сон»'), findsWidgets);
      expect(state.heavySleeperGuideSeen, isFalse);
      expect(find.byKey(const ValueKey('heavy-sleeper-guide')), findsOneWidget);
      expect(find.textContaining('ещё три раза'), findsOneWidget);
      expect(find.text('«Я проснулся»'), findsOneWidget);
      expect(state.heavySleeperEnabled, isFalse);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/heavy_sleeper_guide_393x852.png'),
      );

      await tester.tap(find.text('Понятно'));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(state.heavySleeperGuideSeen, isTrue);
      expect(find.byKey(const ValueKey('heavy-sleeper-guide')), findsNothing);

      await tester.tap(find.byType(CupertinoSwitch).last);
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(state.heavySleeperEnabled, isTrue);
      expect(find.byKey(const ValueKey('heavy-sleeper-guide')), findsNothing);

      await tester.tap(find.byIcon(CupertinoIcons.question_circle));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(find.byKey(const ValueKey('heavy-sleeper-guide')), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('нижний экран 393x852 помещается целиком и не прокручивается', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'lang': 'ru',
      'remindersGuideSeenV2': true,
    });
    final state = await AppState.load();
    await tester.pumpWidget(
      JadwalApp(state: state, schedule: await demoSchedule()),
    );
    await tester.pump();
    final date = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          widget.data!.contains('мухаррам'),
    );
    expect(date.first, findsOneWidget);
    expect(tester.getTopRight(date.first).dx, closeTo(365, 0.5));
    // В демо-состоянии пятницы старый action-блок главного экрана шире
    // тестового viewport; очищаем эту отдельную известную ошибку до свайпа.
    tester.takeException();

    (tester.state(find.byType(HomeScreen)) as dynamic).swipeProgress = 1.0;
    await tester.pump();

    expect(find.text('Сегодня'), findsNothing);
    expect(find.text('Фаджр'), findsWidgets);
    expect(find.text('Восход'), findsWidgets);
    expect(find.text('Иша'), findsWidgets);
    expect(find.textContaining('Вечерние'), findsWidgets);
    expect(find.text('Час дуа'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('today-task-evening'))).dx,
      closeTo(
        tester.getTopLeft(find.byKey(const ValueKey('today-task-rail'))).dx,
        0.5,
      ),
    );
    expect(
      find.byKey(const ValueKey('today-task-forward-hint')),
      findsOneWidget,
    );
    // Аль-Кахф остаётся делом всю пятницу, даже если окно
    // напоминания уже закрыто. Тап по делу ведёт во встроенную читалку.
    await tester.drag(
      find.byKey(const ValueKey('today-task-rail')),
      const Offset(500, 0),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byKey(const ValueKey('today-task-kahf')), findsOneWidget);
    expect(find.text('Сура аль-Кахф'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('today-task-rail')),
      const Offset(-500, 0),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('today-task-dua'))).dx,
      closeTo(
        tester.getTopLeft(find.byKey(const ValueKey('today-task-rail'))).dx,
        0.5,
      ),
    );
    expect(find.byKey(const ValueKey('today-task-forward-hint')), findsNothing);
    expect(find.textContaining(RegExp(r'^42:\d{2}$')), findsWidgets);
    expect(find.text('Тетрадь постоянства'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);

    final fajrBefore = tester.getTopLeft(find.text('Фаджр'));
    await tester.dragFrom(const Offset(196, 430), const Offset(0, -120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    final fajrAfter = tester.getTopLeft(find.text('Фаджр'));

    expect(fajrAfter.dy, closeTo(fajrBefore.dy, 0.5));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Магриб'));
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('Когда напомнить'), findsOneWidget);
    expect(find.text('Событие'), findsNothing);
    expect(find.text('Повторение'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(CupertinoIcons.xmark).last);
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    await tester.tap(find.text('Напоминания'));
    for (var i = 0; i < 18; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('Времена молитв'), findsOneWidget);
    expect(find.text('Сура аль-Кахф'), findsOneWidget);
    expect(find.bySemanticsLabel('Читать суру'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
