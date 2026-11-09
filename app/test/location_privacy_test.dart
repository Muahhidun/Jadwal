import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jadwal/prayer/aladhan.dart';

void main() {
  for (final point in [(41.008237, 28.978359), (-33.8688197, -151.2092955)]) {
    test('reverse geocoding rounds GPS before sending $point', () async {
      Uri? sent;
      await http.runWithClient(
        () async {
          final place = await PlaceNameApi.lookup(point.$1, point.$2, 'ru');
          expect(place?.city, 'Город');
        },
        () => MockClient((request) async {
          sent = request.url;
          return http.Response(
            jsonEncode({
              'address': {'city': 'Город'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(sent?.queryParameters['lat'], point.$1.toStringAsFixed(2));
      expect(sent?.queryParameters['lon'], point.$2.toStringAsFixed(2));
    });
  }
}
