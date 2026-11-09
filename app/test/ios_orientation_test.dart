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

  test('iPhone keeps every app screen in portrait when the phone rotates', () {
    expect(orientations('UISupportedInterfaceOrientations'), [
      'UIInterfaceOrientationPortrait',
    ]);
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
