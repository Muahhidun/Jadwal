import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadwal/prayer/city.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Читаем реальный файл cities.json из папки активов проекта
    final file = File('assets/data/cities.json');
    final jsonString = await file.readAsString();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final encoded = utf8.encode(jsonString);
          return ByteData.sublistView(Uint8List.fromList(encoded));
        });
  });

  group('Поиск городов по-русски', () {
    test('название и область отображаются на языке интерфейса', () {
      const city = City('Екібастұз', '51.7', '75.3', region: 'Павлодар облысы');
      expect(city.displayName('ru'), 'Экибастуз');
      expect(city.displayRegion('ru'), 'Павлодарская область');
      expect(city.displayName('kz'), 'Екібастұз');
      expect(city.displayRegion('kz'), 'Павлодар облысы');
    });

    test('суффикс «қаласы» не ломает русское название', () {
      const ekibastuz = City('Екібастұз қаласы', '51.7', '75.3');
      const oskemen = City('Өскемен қаласы', '49.9', '82.6');

      expect(ekibastuz.displayName('ru'), 'Экибастуз');
      expect(oskemen.displayName('ru'), 'Усть-Каменогорск');
    });

    test('Поиск по точному совпамому (Казахский)', () async {
      final results = await CityRepository.search('Алматы');
      expect(results.any((c) => c.name.contains('Алматы')), isTrue);
    });

    test('Поиск с нормализацией букв (Караганда -> Қарағанды)', () async {
      final results = await CityRepository.search('Караганда');
      expect(results.any((c) => c.name.contains('Қарағанды')), isTrue);
    });

    test('Поиск с нормализацией букв и э/е (Экибастуз -> Екібастұз)', () async {
      final results = await CityRepository.search('Экибастуз');
      expect(results.any((c) => c.name.contains('Екібастұз')), isTrue);
    });

    test('Поиск с синонимами (Уральск -> Орал)', () async {
      final results = await CityRepository.search('Уральск');
      expect(results.any((c) => c.name.contains('Орал')), isTrue);
    });

    test('Поиск с синонимами (Усть-Каменогорск -> Өскемен)', () async {
      final results = await CityRepository.search('Усть-Каменогорск');
      expect(results.any((c) => c.name.contains('Өскемен')), isTrue);

      final results2 = await CityRepository.search('Устькаменогорск');
      expect(results2.any((c) => c.name.contains('Өскемен')), isTrue);
    });

    test('Поиск с синонимами (Петропавловск -> Петропавл)', () async {
      final results = await CityRepository.search('Петропавловск');
      expect(results.any((c) => c.name.contains('Петропавл')), isTrue);
    });

    test('Поиск с нормализацией (Кустанай -> Қостанай)', () async {
      final results = await CityRepository.search('Кустанай');
      expect(results.any((c) => c.name.contains('Қостанай')), isTrue);
    });

    test('Поиск с нормализацией (Чимкент -> Шымкент)', () async {
      final results = await CityRepository.search('Чимкент');
      expect(results.any((c) => c.name.contains('Шымкент')), isTrue);
    });
  });
}
