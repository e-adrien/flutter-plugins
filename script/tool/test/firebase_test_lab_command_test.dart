// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_plugin_tools/src/common/core.dart';
import 'package:flutter_plugin_tools/src/firebase_test_lab_command.dart';
import 'package:test/test.dart';

import 'mocks.dart';
import 'util.dart';

void main() {
  group('$FirebaseTestLabCommand', () {
    FileSystem fileSystem;
    late Directory packagesDir;
    late CommandRunner<void> runner;
    late RecordingProcessRunner processRunner;

    setUp(() {
      fileSystem = MemoryFileSystem();
      packagesDir = createPackagesDirectory(fileSystem: fileSystem);
      processRunner = RecordingProcessRunner();
      final FirebaseTestLabCommand command =
          FirebaseTestLabCommand(packagesDir, processRunner: processRunner);

      runner = CommandRunner<void>(
          'firebase_test_lab_command', 'Test for $FirebaseTestLabCommand');
      runner.addCommand(command);
    });

    test('retries gcloud set', () async {
      final MockProcess mockProcess = MockProcess();
      mockProcess.exitCodeCompleter.complete(1);
      processRunner.processToReturn = mockProcess;
      createFakePlugin('plugin', packagesDir, extraFiles: <String>[
        'example/integration_test/foo_test.dart',
        'example/android/gradlew',
        'example/android/app/src/androidTest/MainActivityTest.java',
      ]);

      Error? commandError;
      final List<String> output = await runCapturingPrint(
          runner, <String>['firebase-test-lab'], errorHandler: (Error e) {
        commandError = e;
      });

      expect(commandError, isA<ToolExit>());
      expect(
          output,
          containsAllInOrder(<Matcher>[
            contains(
                'Warning: gcloud config set returned a non-zero exit code. Continuing anyway.'),
          ]));
    });

    test('runs integration tests', () async {
      createFakePlugin('plugin', packagesDir, extraFiles: <String>[
        'test/plugin_test.dart',
        'example/integration_test/bar_test.dart',
        'example/integration_test/foo_test.dart',
        'example/integration_test/should_not_run.dart',
        'example/android/gradlew',
        'example/android/app/src/androidTest/MainActivityTest.java',
      ]);

      final List<String> output = await runCapturingPrint(runner, <String>[
        'firebase-test-lab',
        '--device',
        'model=flame,version=29',
        '--device',
        'model=seoul,version=26',
        '--test-run-id',
        'testRunId',
        '--build-id',
        'buildId',
      ]);

      expect(
        output,
        containsAllInOrder(<Matcher>[
          contains('Running for plugin'),
          contains('Firebase project configured.'),
          contains('Testing example/integration_test/bar_test.dart...'),
          contains('Testing example/integration_test/foo_test.dart...'),
        ]),
      );
      expect(output, isNot(contains('test/plugin_test.dart')));
      expect(output,
          isNot(contains('example/integration_test/should_not_run.dart')));

      expect(
        processRunner.recordedCalls,
        orderedEquals(<ProcessCall>[
          ProcessCall(
              'gcloud',
              'auth activate-service-account --key-file=${Platform.environment['HOME']}/gcloud-service-key.json'
                  .split(' '),
              null),
          ProcessCall(
              'gcloud', 'config set project flutter-infra'.split(' '), null),
          ProcessCall(
              '/packages/plugin/example/android/gradlew',
              'app:assembleAndroidTest -Pverbose=true'.split(' '),
              '/packages/plugin/example/android'),
          ProcessCall(
              '/packages/plugin/example/android/gradlew',
              'app:assembleDebug -Pverbose=true -Ptarget=/packages/plugin/example/integration_test/bar_test.dart'
                  .split(' '),
              '/packages/plugin/example/android'),
          ProcessCall(
              'gcloud',
              'firebase test android run --type instrumentation --app build/app/outputs/apk/debug/app-debug.apk --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk --timeout 5m --results-bucket=gs://flutter_firebase_testlab --results-dir=plugins_android_test/plugin/buildId/testRunId/0/ --device model=flame,version=29 --device model=seoul,version=26'
                  .split(' '),
              '/packages/plugin/example'),
          ProcessCall(
              '/packages/plugin/example/android/gradlew',
              'app:assembleDebug -Pverbose=true -Ptarget=/packages/plugin/example/integration_test/foo_test.dart'
                  .split(' '),
              '/packages/plugin/example/android'),
          ProcessCall(
              'gcloud',
              'firebase test android run --type instrumentation --app build/app/outputs/apk/debug/app-debug.apk --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk --timeout 5m --results-bucket=gs://flutter_firebase_testlab --results-dir=plugins_android_test/plugin/buildId/testRunId/1/ --device model=flame,version=29 --device model=seoul,version=26'
                  .split(' '),
              '/packages/plugin/example'),
        ]),
      );
    });

    test('skips packages with no androidTest directory', () async {
      createFakePlugin('plugin', packagesDir, extraFiles: <String>[
        'example/integration_test/foo_test.dart',
        'example/android/gradlew',
      ]);

      final List<String> output = await runCapturingPrint(runner, <String>[
        'firebase-test-lab',
        '--device',
        'model=flame,version=29',
        '--device',
        'model=seoul,version=26',
        '--test-run-id',
        'testRunId',
        '--build-id',
        'buildId',
      ]);

      expect(
        output,
        containsAllInOrder(<Matcher>[
          contains('Running for plugin'),
          contains('No example with androidTest directory'),
        ]),
      );
      expect(output,
          isNot(contains('Testing example/integration_test/foo_test.dart...')));

      expect(
        processRunner.recordedCalls,
        orderedEquals(<ProcessCall>[]),
      );
    });

    test('builds if gradlew is missing', () async {
      createFakePlugin('plugin', packagesDir, extraFiles: <String>[
        'example/integration_test/foo_test.dart',
        'example/android/app/src/androidTest/MainActivityTest.java',
      ]);

      final List<String> output = await runCapturingPrint(runner, <String>[
        'firebase-test-lab',
        '--device',
        'model=flame,version=29',
        '--device',
        'model=seoul,version=26',
        '--test-run-id',
        'testRunId',
        '--build-id',
        'buildId',
      ]);

      expect(
        output,
        containsAllInOrder(<Matcher>[
          contains('Running for plugin'),
          contains('Running flutter build apk...'),
          contains('Firebase project configured.'),
          contains('Testing example/integration_test/foo_test.dart...'),
        ]),
      );

      expect(
        processRunner.recordedCalls,
        orderedEquals(<ProcessCall>[
          ProcessCall(
            'flutter',
            'build apk'.split(' '),
            '/packages/plugin/example/android',
          ),
          ProcessCall(
              'gcloud',
              'auth activate-service-account --key-file=${Platform.environment['HOME']}/gcloud-service-key.json'
                  .split(' '),
              null),
          ProcessCall(
              'gcloud', 'config set project flutter-infra'.split(' '), null),
          ProcessCall(
              '/packages/plugin/example/android/gradlew',
              'app:assembleAndroidTest -Pverbose=true'.split(' '),
              '/packages/plugin/example/android'),
          ProcessCall(
              '/packages/plugin/example/android/gradlew',
              'app:assembleDebug -Pverbose=true -Ptarget=/packages/plugin/example/integration_test/foo_test.dart'
                  .split(' '),
              '/packages/plugin/example/android'),
          ProcessCall(
              'gcloud',
              'firebase test android run --type instrumentation --app build/app/outputs/apk/debug/app-debug.apk --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk --timeout 5m --results-bucket=gs://flutter_firebase_testlab --results-dir=plugins_android_test/plugin/buildId/testRunId/0/ --device model=flame,version=29 --device model=seoul,version=26'
                  .split(' '),
              '/packages/plugin/example'),
        ]),
      );
    });

    test('experimental flag', () async {
      createFakePlugin('plugin', packagesDir, extraFiles: <String>[
        'example/integration_test/foo_test.dart',
        'example/android/gradlew',
        'example/android/app/src/androidTest/MainActivityTest.java',
      ]);

      await runCapturingPrint(runner, <String>[
        'firebase-test-lab',
        '--device',
        'model=flame,version=29',
        '--test-run-id',
        'testRunId',
        '--build-id',
        'buildId',
        '--enable-experiment=exp1',
      ]);

      expect(
        processRunner.recordedCalls,
        orderedEquals(<ProcessCall>[
          ProcessCall(
              'gcloud',
              'auth activate-service-account --key-file=${Platform.environment['HOME']}/gcloud-service-key.json'
                  .split(' '),
              null),
          ProcessCall(
              'gcloud', 'config set project flutter-infra'.split(' '), null),
          ProcessCall(
              '/packages/plugin/example/android/gradlew',
              'app:assembleAndroidTest -Pverbose=true -Pextra-front-end-options=--enable-experiment%3Dexp1 -Pextra-gen-snapshot-options=--enable-experiment%3Dexp1'
                  .split(' '),
              '/packages/plugin/example/android'),
          ProcessCall(
              '/packages/plugin/example/android/gradlew',
              'app:assembleDebug -Pverbose=true -Ptarget=/packages/plugin/example/integration_test/foo_test.dart -Pextra-front-end-options=--enable-experiment%3Dexp1 -Pextra-gen-snapshot-options=--enable-experiment%3Dexp1'
                  .split(' '),
              '/packages/plugin/example/android'),
          ProcessCall(
              'gcloud',
              'firebase test android run --type instrumentation --app build/app/outputs/apk/debug/app-debug.apk --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk --timeout 5m --results-bucket=gs://flutter_firebase_testlab --results-dir=plugins_android_test/plugin/buildId/testRunId/0/ --device model=flame,version=29'
                  .split(' '),
              '/packages/plugin/example'),
        ]),
      );
    });
  });
}
