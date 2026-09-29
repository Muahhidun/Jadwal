import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jadwal/data/app_state.dart';
import 'package:jadwal/prayer/city.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('город за границей помнит, что времена — местный расчёт', () async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    final app = await AppState.load();
    app.setCity(
      const City(
        'Стамбул',
        '41.01',
        '28.98',
        region: 'Турция',
        source: City.sourceLocal,
      ),
    );
    final restored = (await AppState.load()).city;
    expect(restored.isLocalCalc, isTrue);
    expect(restored.displayName('ru'), 'Стамбул');
    expect(restored.displayRegion('ru'), 'Турция');
  });

  test('город ДУМК остаётся источником ДУМК, координаты не меняются', () async {
    SharedPreferences.setMockInitialValues({'onboardingDone': true});
    final app = await AppState.load();
    app.setCity(kDefaultCity);
    final restored = (await AppState.load()).city;
    expect(restored.isLocalCalc, isFalse);
    expect(restored.latStr, '43.238293');
    expect(restored.lngStr, '76.945465');
  });

  test('далеко от справочника ДУМК — расстояние большое', () async {
    final (_, km) = await CityRepository.nearestWithDistance(41.01, 28.98);
    expect(km, greaterThan(120));
    final (almaty, near) = await CityRepository.nearestWithDistance(
      43.2383,
      76.9455,
    );
    expect(near, lessThan(5));
    expect(almaty.isLocalCalc, isFalse);
  });
}
