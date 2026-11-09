import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/data/navigation_guide.dart';
import 'package:jadwal/screens/guided_spotlight.dart';
import 'package:jadwal/screens/qibla_screen.dart';
import 'package:jadwal/screens/swipe_lesson.dart';
import 'navigation_guide_test.dart' as guide;

final bubble = find.byKey(const ValueKey('guide-bubble'));
Rect outline(WidgetTester t) =>
    (t
                    .widget<CustomPaint>(
                      find
                          .descendant(
                            of: find.byType(GuidedSpotlight),
                            matching: find.byType(CustomPaint),
                          )
                          .first,
                    )
                    .painter
                as dynamic)
            .hole
        as Rect;

void main() {
  setUpAll(guide.loadGuideFonts);
  for (final lang in ['ru', 'kz']) {
    testWidgets('$lang: own-reminder hint sits immediately above its button', (
      t,
    ) async {
      final app = await guide.start(t, lang: lang);
      await guide.toAdd(t, lang);
      final target = t.getRect(
        find.byKey(app.navigationGuide.target('page-add')),
      );
      final panel = t.getRect(bubble);
      expect(target.top - panel.bottom, inInclusiveRange(8, 22));
      expect(panel.overlaps(target), isFalse);
      expect(panel.height, lessThan(240));
      await t.pumpWidget(const SizedBox());
    });
    testWidgets('$lang: schedule and deeds have distinct accurate targets', (
      t,
    ) async {
      final app = await guide.start(t, lang: lang);
      await guide.openSwipe(t, lang);
      var hint = t.widget<GuidedSpotlight>(find.byType(GuidedSpotlight));
      expect(hint.target, same(app.navigationGuide.target('prayer-times')));
      final schedule = t.getRect(find.byKey(hint.target!));
      expect(
        schedule.contains(
          t.getCenter(find.text(lang == 'ru' ? 'Восход' : 'Күн шығуы')),
        ),
        isTrue,
      );
      expect(
        schedule.contains(
          t.getCenter(find.text(lang == 'ru' ? 'Иша' : 'Құптан')),
        ),
        isTrue,
      );
      await guide.next(t, lang);
      hint = t.widget<GuidedSpotlight>(find.byType(GuidedSpotlight));
      expect(hint.target, same(app.navigationGuide.target('today-deeds')));
      final deeds = outline(t);
      expect(deeds.top, greaterThan(schedule.bottom));
      expect(t.getRect(bubble).overlaps(deeds), isFalse);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      '$lang: calendar outline includes header; Skip is fully visible',
      (t) async {
        final app = await guide.start(t, lang: lang);
        await guide.toCalendar(t, lang);
        final card = t.getRect(
          find.byKey(app.navigationGuide.target('calendar')),
        );
        final header = t.getRect(
          find.text(lang == 'ru' ? 'Июль 2026' : 'Шілде 2026'),
        );
        expect(card.contains(header.topLeft), isTrue);
        expect(outline(t).contains(header.bottomRight), isTrue);
        expect(outline(t).top, lessThanOrEqualTo(card.top));
        expect(outline(t).bottom, greaterThanOrEqualTo(card.bottom));
        final skip = t.getRect(find.byKey(const ValueKey('guide-skip')));
        expect(t.getRect(bubble).contains(skip.topLeft), isTrue);
        expect(t.getRect(bubble).contains(skip.bottomRight), isTrue);
        expect(skip.bottom, lessThanOrEqualTo(852 - 34));
        expect(t.getRect(bubble).overlaps(card), isFalse);
        await t.tap(find.byKey(const ValueKey('guide-skip')));
        expect(app.navigationGuide.active, isFalse);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'gesture demonstration is transparent, animated and swipe-through',
    (t) async {
      final app = await guide.start(t);
      expect(find.byType(GuidedSpotlight), findsNothing);
      final hand = find.byKey(const ValueKey('guide-swipe-hand'));
      final caption = t.getRect(
        find.byKey(const ValueKey('guide-swipe-caption')),
      );
      expect(caption.height, lessThan(150));
      final before = t.getTopLeft(hand).dy;
      await t.pump(const Duration(milliseconds: 500));
      expect(t.getTopLeft(hand).dy, lessThan(before));
      expect(t.widget<Opacity>(hand).opacity, inInclusiveRange(0, .55));
      await t.dragFrom(const Offset(180, 430), const Offset(0, -230));
      await guide.tick(t);
      expect(app.navigationGuide.step, GuideStep.times);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('no old or unanchored panel flashes during page transitions', (
    t,
  ) async {
    final app = await guide.start(t);
    await t.tap(find.text('Открыть кнопкой'));
    await t.pump();
    var frames = 0;
    while (app.navigationGuide.moving && frames < 150) {
      expect(find.byType(GuidedSpotlight), findsNothing);
      expect(find.byType(SwipeLesson), findsNothing);
      await t.pump(const Duration(milliseconds: 16));
      frames++;
    }
    expect(frames, greaterThan(1));
    await guide.tick(t);
    expect(app.navigationGuide.step, GuideStep.times);
    expect(find.text('Время намазов'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'missing target never produces a floating panel; escape remains',
    (t) async {
      final app = await guide.start(t);
      await t.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            home: Scaffold(
              body: GuidedSpotlight(
                target: GlobalKey(),
                title: 'Wait',
                message: 'Wait',
              ),
            ),
          ),
        ),
      );
      await guide.tick(t);
      expect(bubble, findsNothing);
      await t.tap(find.text('Пропустить обучение'));
      expect(app.navigationGuide.active, isFalse);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'target measurement uses transformed size, not unscaled layout size',
    (t) async {
      final app = await guide.start(t);
      final key = GlobalKey();
      await t.pumpWidget(
        AppScope(
          state: app,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 90,
                    top: 200,
                    child: Transform.scale(
                      scale: .5,
                      alignment: Alignment.topLeft,
                      child: SizedBox(key: key, width: 200, height: 300),
                    ),
                  ),
                  Positioned.fill(
                    child: GuidedSpotlight(
                      target: key,
                      title: 'Scaled',
                      message: 'Card',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await guide.tick(t);
      expect(outline(t).width, closeTo(110, .1));
      expect(outline(t).height, closeTo(160, .1));
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final lang in ['ru', 'kz']) {
    testWidgets(
      '$lang: Qibla finale highlights only map icon, no forced map tour',
      (t) async {
        t.binding.defaultBinaryMessenger.setMockStreamHandler(
          const EventChannel('hemanthraj/flutter_compass'),
          MockStreamHandler.inline(
            onListen: (_, sink) => sink.success(<double>[180, 0, 5]),
          ),
        );
        final app = await guide.start(t, lang: lang);
        app.navigationGuide.go(GuideStep.finish);
        await t.pumpWidget(
          AppScope(
            state: app,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'Manrope',
                fontFamilyFallback: const ['Inter'],
              ),
              home: ColoredBox(
                color: const Color(0xFF1E3045),
                child: QiblaView(
                  embedded: true,
                  compassAvailabilityProbe: () async => true,
                ),
              ),
            ),
          ),
        );
        await guide.tick(t);
        final hint = t.widget<GuidedSpotlight>(find.byType(GuidedSpotlight));
        expect(hint.target, same(app.navigationGuide.target('qibla-mode')));
        final target = t.getRect(find.byKey(hint.target!));
        expect(target.width, lessThan(80));
        expect(t.getRect(bubble).overlaps(target), isFalse);
        final compass = t.getRect(
          find.byKey(app.navigationGuide.target('qibla-visual')),
        );
        expect(compass.width, greaterThan(200));
        expect(t.getRect(bubble).overlaps(compass), isFalse);
        if (lang == 'ru') {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/learning_qibla_map_icon_ru.png'),
          );
        }
        await guide.finishQibla(t, lang);
        expect(app.navigationGuide.active, isFalse);
        expect((t.state(find.byType(QiblaView)) as dynamic).selectedTab, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('map action opens the real map and keeps return lesson', (
    t,
  ) async {
    final app = await guide.start(t);
    app.navigationGuide.go(GuideStep.finish);
    await t.pumpWidget(
      AppScope(
        state: app,
        child: const MaterialApp(home: QiblaView(embedded: true)),
      ),
    );
    await guide.tick(t);
    await t.tap(find.text('Открыть карту'));
    await guide.tick(t);
    expect(app.navigationGuide.step, GuideStep.qiblaMap);
    expect((t.state(find.byType(QiblaView)) as dynamic).selectedTab, 1);
    await t.pumpWidget(const SizedBox());
  });
  test('closing a moving guide allows a fresh replay', () {
    final g = NavigationGuide()
      ..begin(usePages: true)
      ..navigationStarted();
    g.go(GuideStep.idle);
    g.offer();
    g.begin(usePages: true);
    expect(g.moving, isFalse);
    expect(g.step, GuideStep.day);
  });
}
