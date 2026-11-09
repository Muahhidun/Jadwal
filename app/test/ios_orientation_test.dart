import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();

  List<String> orientations(String key) {
    final array = RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);
    expect(array, isNotNull, reason: '$key must be explicitly configured');
    return RegExp(
      '<string>(.*?)</string>',
    ).allMatches(array!.group(1)!).map((match) => match.group(1)!).toList();
  }

  test('iPhone разрешает горизонталь только для читалок', () {
    // Нативный список открывает горизонталь; остальные экраны остаются
    // вертикальными за счёт AppOrientation.lockPortrait() (main.dart).
    expect(orientations('UISupportedInterfaceOrientations'), [
      'UIInterfaceOrientationPortrait',
      'UIInterfaceOrientationLandscapeLeft',
      'UIInterfaceOrientationLandscapeRight',
    ]);
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('AppOrientation.lockPortrait()'));
    for (final file in ['reader.dart', 'kahf_reader.dart']) {
      final src = File('lib/screens/$file').readAsStringSync();
      expect(src, contains('AppOrientation.allowReading()'), reason: file);
      expect(src, contains('AppOrientation.lockPortrait()'), reason: file);
    }
  });

  test('iPad retains all orientations and multitasking support', () {
    expect(orientations('UISupportedInterfaceOrientations~ipad'), [
      'UIInterfaceOrientationPortrait',
      'UIInterfaceOrientationPortraitUpsideDown',
      'UIInterfaceOrientationLandscapeLeft',
      'UIInterfaceOrientationLandscapeRight',
    ]);
    expect(plist, isNot(contains('<key>UIRequiresFullScreen</key>')));
  });
}
