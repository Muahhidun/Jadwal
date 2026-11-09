import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/screens/contextual_hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> showHintTarget(
  WidgetTester tester, {
  String lang = 'ru',
  bool onboarding = true,
  double textScale = 1,
  bool seen = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'lang': lang,
    'onboardingDone': onboarding,
    'contextHint:v1:demo': seen,
  });
  final app = await AppState.load();
  await tester.pumpWidget(
    AppScope(
      state: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFD4E1E5),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ContextualHint(
                  id: 'demo',
                  title: lang == 'kz'
                      ? 'Оқуға ыңғайлы көрініс'
                      : 'Удобный вид для чтения',
                  message: lang == 'kz'
                      ? 'Осы батырмадан қағаз, ақ немесе қара фонды таңдаңыз.'
                      : 'Здесь можно выбрать бумажный, белый или тёмный фон. Транскрипцию и перевод можно свернуть нажатием на их заголовки.',
                  child: IconButton(
                    key: const ValueKey('target-button'),
                    onPressed: () {},
                    icon: const Icon(Icons.palette_outlined),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 360));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Manrope',
    )..addFont(rootBundle.load('assets/fonts/Manrope.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('одна подсказка, закрытие сохраняется после перезапуска', (
    tester,
  ) async {
    final app = await showHintTarget(tester);
    expect(
      find.byKey(const ValueKey('contextual-hint-bubble')),
      findsOneWidget,
    );
    expect(app.contextHintSeen('demo'), isFalse);
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('contextual-hint-bubble')), findsNothing);
    expect((await AppState.load()).contextHintSeen('demo'), isTrue);
    await tester.tap(find.byKey(const ValueKey('target-button')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Понятно'), findsNothing);
  });

  testWidgets('закрывается нажатием вне пузыря', (tester) async {
    final app = await showHintTarget(tester);
    await tester.tapAt(const Offset(20, 500));
    await tester.pumpAndSettle();
    expect(app.contextHintSeen('demo'), isTrue);
    expect(find.text('Понятно'), findsNothing);
  });

  testWidgets(
    'не перекрывает онбординг и не повторяет просмотренную подсказку',
    (tester) async {
      await showHintTarget(tester, onboarding: false);
      expect(find.text('Понятно'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await showHintTarget(tester, seen: true);
      expect(find.text('Понятно'), findsNothing);
    },
  );

  testWidgets('казахская подсказка помещается с крупным системным шрифтом', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showHintTarget(tester, lang: 'kz', textScale: 1.8);
    expect(find.text('Түсінікті'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Түсінікті'));
    await tester.pumpAndSettle();
  });

  testWidgets('подсказка привязана к кнопке на телефоне', (tester) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await showHintTarget(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/contextual_hint_393x852.png'),
    );
    debugDisableShadows = true;
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
  });
}
