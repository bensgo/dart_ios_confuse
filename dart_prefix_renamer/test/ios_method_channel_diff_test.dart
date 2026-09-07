import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'renames paired Swift channel and generates retained dummy channels',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'ios_method_channel_diff_test_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      _write(temporary.path, 'pubspec.yaml', 'name: channel_fixture\n');
      _write(temporary.path, 'lib/main.dart', '''
import 'package:flutter/services.dart';

const native = MethodChannel('com.example/native');
void boot() {}
void main() => boot();
''');
      _write(temporary.path, 'ios/Runner/AppDelegate.swift', '''
import Flutter

@main
class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.example/native",
      binaryMessenger: controller.binaryMessenger
    )
    _ = channel
    return super.application(application, didFinishLaunchingWithOptions: options)
  }
}
''');

      final report = await IosMethodChannelDifferentiator(
        IosMethodChannelDiffConfig(
          projectPath: temporary.path,
          prefix: 'pre',
          includes: const ['com.example/native'],
          excludes: const [],
          dummyCount: 3,
          entrypoints: const ['lib/main.dart'],
          seed: 42,
        ),
      ).apply();

      expect(report.renames, hasLength(1));
      expect(report.dummyNames, hasLength(3));
      expect(report.dartEdits, 1);
      expect(report.iosEdits, 1);
      final replacement = report.renames['com.example/native']!;
      expect(replacement, startsWith('pre.mc.'));
      expect(
        File(p.join(temporary.path, 'lib/main.dart')).readAsStringSync(),
        allOf(
          contains(replacement),
          contains('initializeIosDifferentiatedMethodChannels();'),
          isNot(contains("MethodChannel('com.example/native')")),
        ),
      );
      final generated = File(report.generatedDartFile!).readAsStringSync();
      for (final name in report.dummyNames) {
        expect(generated, contains("MethodChannel('$name')"));
      }
      final swift = File(report.iosInjectionFile!).readAsStringSync();
      expect(swift, contains(replacement));
      expect(swift, contains('private var differentiatedMethodChannels'));
      for (final name in report.dummyNames) {
        expect(swift, contains('FlutterMethodChannel(name: "$name"'));
      }
      if (Platform.isMacOS) {
        final parse = await Process.run('xcrun', [
          'swiftc',
          '-frontend',
          '-parse',
          report.iosInjectionFile!,
        ]);
        expect(parse.exitCode, 0, reason: '${parse.stdout}\n${parse.stderr}');
      }

      await restoreIosMethodChannelDiff(
        projectPath: temporary.path,
        manifest: {
          'iosMethodChannelDiff': {
            'enabled': true,
            'renames': report.renames,
            'generatedDartFile': p.relative(
              report.generatedDartFile!,
              from: temporary.path,
            ),
            'entrypoints': report.entrypoints
                .map((path) => p.relative(path, from: temporary.path))
                .toList(),
            'iosInjectionFile': p.relative(
              report.iosInjectionFile!,
              from: temporary.path,
            ),
          },
        },
      );
      final restoredDart = File(
        p.join(temporary.path, 'lib/main.dart'),
      ).readAsStringSync();
      final restoredSwift = File(
        p.join(temporary.path, 'ios/Runner/AppDelegate.swift'),
      ).readAsStringSync();
      expect(restoredDart, contains("MethodChannel('com.example/native')"));
      expect(restoredDart, isNot(contains('ios-method-channel-import')));
      expect(restoredDart, isNot(contains('initializeIosDifferentiated')));
      expect(restoredSwift, contains('name: "com.example/native"'));
      expect(restoredSwift, isNot(contains('differentiatedMethodChannels')));
      expect(File(report.generatedDartFile!).existsSync(), isFalse);
    },
  );

  test('rejects third-party plugin channels outside app-owned ios', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ios_method_channel_third_party_test_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    _write(temporary.path, 'lib/main.dart', 'void main() {}\n');
    _write(
      temporary.path,
      'ios/Runner/AppDelegate.swift',
      'final class AppDelegate {}\n',
    );
    _write(
      temporary.path,
      'plugins/vendor_plugin/lib/vendor_plugin.dart',
      "const channel = MethodChannel('vendor.channel');\n",
    );
    _write(
      temporary.path,
      'plugins/vendor_plugin/ios/Classes/VendorPlugin.m',
      'FlutterMethodChannel *channel = '
          '[FlutterMethodChannel methodChannelWithName:@"vendor.channel" '
          'binaryMessenger:registrar.messenger];\n',
    );

    final operation = IosMethodChannelDifferentiator(
      IosMethodChannelDiffConfig(
        projectPath: temporary.path,
        prefix: 'pre',
        includes: const ['vendor.channel'],
        excludes: const [],
        dummyCount: 0,
        entrypoints: const [],
        seed: 17,
      ),
    ).apply();

    await expectLater(
      operation,
      throwsA(
        isA<StateError>()
            .having(
              (error) => error.message,
              'message',
              contains('vendor.channel (Dart: 1, iOS: 0)'),
            )
            .having(
              (error) => error.message,
              'guidance',
              contains('do not include third-party plugin channels'),
            ),
      ),
    );
    expect(
      File(
        p.join(
          temporary.path,
          'plugins/vendor_plugin/ios/Classes/VendorPlugin.m',
        ),
      ).readAsStringSync(),
      contains('vendor.channel'),
    );
  });

  test(
    'supports Objective-C AppDelegate and exclude takes precedence',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'ios_method_channel_objc_test_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      _write(temporary.path, 'lib/main.dart', '''
import 'package:flutter/services.dart';
const channel = MethodChannel('keep.me');
void main() {}
''');
      _write(temporary.path, 'ios/Runner/AppDelegate.m', '''
#import "AppDelegate.h"
#import <Flutter/Flutter.h>

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
  FlutterViewController *controller = (FlutterViewController *)self.window.rootViewController;
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"keep.me" binaryMessenger:controller.binaryMessenger];
  return YES;
}
''');

      final report = await IosMethodChannelDifferentiator(
        IosMethodChannelDiffConfig(
          projectPath: temporary.path,
          prefix: 'pre',
          includes: const ['keep.me'],
          excludes: const ['keep.me'],
          dummyCount: 1,
          entrypoints: const ['lib/main.dart'],
          seed: 7,
        ),
      ).apply();

      expect(report.renames, isEmpty);
      expect(report.dummyNames, hasLength(1));
      final objc = File(report.iosInjectionFile!).readAsStringSync();
      expect(objc, contains('static NSArray<FlutterMethodChannel *>'));
      expect(objc, contains(report.dummyNames.single));
      expect(objc, contains('@"keep.me"'));
    },
  );

  test('integrates with PrefixRenamer manifest and restore pipeline', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ios_method_channel_pipeline_test_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = p.join(temporary.path, 'project');
    final output = p.join(temporary.path, 'output');
    _write(project, 'pubspec.yaml', '''
name: channel_pipeline_fixture
environment:
  sdk: ^3.9.2
dependencies:
  flutter:
    sdk: flutter
''');
    _write(project, 'lib/model/value.dart', 'const value = 1;\n');
    _write(project, 'lib/main.dart', '''
import 'package:flutter/services.dart';
const channel = MethodChannel('pipeline.channel');
void main() {}
''');
    _write(project, 'ios/Runner/AppDelegate.swift', '''
import Flutter
@main
class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    _ = FlutterMethodChannel(name: "pipeline.channel", binaryMessenger: controller.binaryMessenger)
    return true
  }
}
''');

    final report = await PrefixRenamer(
      RenameConfig(
        projectPath: project,
        outputPath: output,
        targetPaths: const ['lib/model'],
        prefix: 'pre',
        runPubGet: false,
        verify: false,
        renameAssets: false,
        iosMethodChannelDiff: true,
        iosMethodChannelIncludes: const ['pipeline.channel'],
        iosDummyMethodChannelCount: 2,
        iosMethodChannelSeed: 99,
      ),
    ).run();

    expect(report.renamedIosMethodChannels, 1);
    expect(report.generatedIosMethodChannels, 2);
    final manifest = File(
      p.join(output, 'dart_prefix_renamer_manifest.json'),
    ).readAsStringSync();
    expect(manifest, contains('"iosMethodChannelDiff"'));
    expect(manifest, contains('"pipeline.channel"'));
    expect(manifest, contains('"dummyNames"'));

    final restore = await PrefixRestorer(
      RestoreConfig(projectPath: output, verify: false),
    ).run();
    expect(restore.verificationPassed, isTrue);
    expect(
      File(p.join(output, 'lib/main.dart')).readAsStringSync(),
      allOf(
        contains("MethodChannel('pipeline.channel')"),
        isNot(contains('initializeIosDifferentiatedMethodChannels')),
      ),
    );
    expect(
      File(p.join(output, 'ios/Runner/AppDelegate.swift')).readAsStringSync(),
      allOf(
        contains('name: "pipeline.channel"'),
        isNot(contains('differentiatedMethodChannels')),
      ),
    );
  });
}

void _write(String root, String relative, String contents) {
  final file = File(p.join(root, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
