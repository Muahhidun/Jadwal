import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/adhkar.dart';
import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/prayer/city.dart';
import 'package:jadwal/prayer/schedule_service.dart';
import 'package:jadwal/screens/reader.dart';
import 'package:jadwal/screens/zikr_reader_session.dart';
import 'package:jadwal/services/zikr_speech_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('состояние читалки хранит пропуск отдельно от общей практики', () {
    final session = ZikrReaderSession(itemCount: 3);
    session.skipCurrent();
    session.markCurrentSpeaking();
    session.confirmRepeat();

    expect(session.isCurrentSkipped, isTrue);
    expect(session.isCurrentSpeaking, isTrue);
    expect(session.repeatConfirmed, isTrue);
    expect(session.select(1), isTrue);
    expect(session.currentIndex, 1);
    expect(session.isCurrentSkipped, isFalse);
    expect(session.skippedIndices, {0});
    expect(session.isCurrentSpeaking, isFalse);
    expect(session.repeatConfirmed, isFalse);
    expect(session.canGoBack, isTrue);
    expect(session.select(0), isTrue);
    session.markCurrentRead();
    expect(session.skippedIndices, isEmpty);
    expect(session.select(3), isFalse);
    expect(session.currentIndex, 0);
  });

  test(
    'отключённая озвучка не запускает нативное чтение или возобновление',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('kz.dauam/speech');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'speakZikrs' ? true : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      const zikr = Zikr(
        order: 2,
        ar: 'النص الثاني',
        source: 'Тестовый источник',
        repeat: 1,
        status: 'draft',
      );
      await ZikrSpeechService.stop();
      final started = await ZikrSpeechService.speakZikr(
        zikr,
        title: 'Вечерние зикры',
      );

      final collection = ZikrCollection(
        id: 'morning',
        titleRu: 'Утренние зикры',
        titleKz: 'Таңғы зікірлер',
        items: const [zikr],
      );
      expect(await ZikrSpeechService.speakCollection(collection), isFalse);
      await ZikrSpeechService.pause();
      await ZikrSpeechService.resume();

      expect(ZikrSpeechService.enabled, isFalse);
      expect(started, isFalse);
      // Остановка остаётся доступной для очистки старого воспроизведения.
      expect(calls.map((call) => call.method), ['stop']);
    },
  );

  for (final collectionId in ['morning', 'evening']) {
    testWidgets('$collectionId: нет кнопки звука и старого автозапуска', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'lang': 'ru'});
      final state = await AppState.load();
      final prefs = await SharedPreferences.getInstance();
      final schedule = ScheduleService(
        prefs,
        now: () => DateTime(2026, 10, 1, 12),
      );
      schedule.preload(kDefaultCity, 2026, {
        '2026-10-01': [300, 390, 720, 960, 1100, 1200],
      });
      await tester.runAsync(AdhkarRepository.load);
      final calls = <MethodCall>[];
      const channel = MethodChannel('kz.dauam/speech');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: ScheduleScope(
            service: schedule,
            child: MaterialApp(
              home: ReaderScreen(
                collectionId: collectionId,
                autoStartSpeech: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-title')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reader-palette-button')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('reader-speech-toggle')), findsNothing);
      expect(calls.where((call) => call.method == 'speakZikrs'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
