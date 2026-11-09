import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  late String executable;
  setUpAll(() async {
    if (!Platform.isMacOS) return;
    scratch = Directory.systemTemp.createTempSync('dauam-snapshot-tests-');
    executable = '${scratch.path}/checks';
    final compiled = await Process.run('xcrun', [
      'swiftc',
      '-parse-as-library',
      'ios/DauamWatchShared/DauamWatchSnapshot.swift',
      'test/native/apple_snapshot_checks.swift',
      '-o',
      executable,
    ]);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}\n${compiled.stderr}',
    );
  });
  tearDownAll(() {
    if (Platform.isMacOS && scratch.existsSync()) {
      scratch.deleteSync(recursive: true);
    }
  });
  for (final name in [
    'empty',
    'broken',
    'unsupported',
    'stale',
    'date',
    'same-day',
    'midnight',
    'empty-timeline',
    'legacy',
    'expired',
    'grace-boundary',
    'save-validation',
    'heading-missing',
    'heading-unavailable',
    'heading-invalid',
    'heading-ready',
  ]) {
    test(
      'Apple native snapshot: $name',
      () async {
        final result = await Process.run(
          executable,
          [name],
          environment: {'TZ': 'UTC'},
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      },
      skip: !Platform.isMacOS,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  for (final target in [
    (
      sdk: 'iphoneos',
      platform: 'ios17.0',
      files: ['ios/JadwalWidgetExtension/DauamWidgets.swift'],
    ),
    (
      sdk: 'watchos',
      platform: 'watchos10.0',
      files: [
        'ios/DauamWatchApp/DauamWatchViews.swift',
        'ios/DauamWatchApp/DauamWatchApp.swift',
        'ios/DauamWatchApp/WatchConnectivityReceiver.swift',
      ],
    ),
    (
      sdk: 'watchos',
      platform: 'watchos10.0',
      files: [
        'ios/DauamWatchWidgets/DauamWatchWidgets.swift',
        'ios/DauamWatchWidgets/DauamWatchWidgetsBundle.swift',
      ],
    ),
  ]) {
    test(
      'Apple SDK typecheck: ${target.files.first}',
      () async {
        final sdk = await Process.run('xcrun', [
          '--sdk',
          target.sdk,
          '--show-sdk-path',
        ]);
        expect(sdk.exitCode, 0, reason: '${sdk.stderr}');
        final result = await Process.run('xcrun', [
          '--sdk',
          target.sdk,
          'swiftc',
          '-typecheck',
          '-target',
          'arm64-apple-${target.platform}',
          '-sdk',
          sdk.stdout.toString().trim(),
          'ios/DauamWatchShared/DauamWatchSnapshot.swift',
          ...target.files,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      },
      skip: !Platform.isMacOS,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test('iPhone widget target compiles the shared snapshot model', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final sources = project.substring(
      project.indexOf('/* Begin PBXSourcesBuildPhase section */'),
    );
    expect(
      sources,
      contains(
        'C20000000000000000000013 /* DauamWatchSnapshot.swift in Sources */',
      ),
    );
    final widget = File(
      'ios/JadwalWidgetExtension/DauamWidgets.swift',
    ).readAsStringSync();
    expect(
      widget,
      contains('private typealias DauamSnapshot = DauamWatchSnapshot'),
    );
    expect(widget, contains('snapshot.projected(at: \$0)'));
  });
}
