import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/data/adhkar.dart';
import 'package:jadwal/screens/zikr_reader_session.dart';
import 'package:jadwal/services/zikr_speech_service.dart';

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
    'озвучка выбранного зикра отправляет нативному слою только его текст',
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

      expect(started, isTrue);
      expect(calls.map((call) => call.method), ['stop', 'speakZikrs']);
      final arguments = calls.last.arguments as Map<Object?, Object?>;
      expect(arguments['items'], ['النص الثاني']);
    },
  );
}
