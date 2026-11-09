import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Apple release gate rejects lost App Groups in signed packages',
    () async {
      final result = await Process.run('python3', [
        '-B',
        '-m',
        'unittest',
        'discover',
        '-s',
        'tool',
        '-p',
        'verify_apple_release_test.py',
        '-v',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
}
