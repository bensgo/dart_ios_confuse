import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('accepts every copy-mode feature flag', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'transactional_build_config_test_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = Directory(p.join(temporary.path, 'app'))..createSync();
    _write(project.path, 'pubspec.yaml', '''
name: fixture
environment:
  sdk: ^3.9.2
''');
    Directory(p.join(project.path, 'lib')).createSync();
    _writeIosFixture(project.path);

    final config = await TransactionalBuildConfig.fromArguments([
      '--transactional-build',
      '--project=${project.path}',
      '--target=lib',
      '--prefix=pre',
      '--junk-code',
      '--reset-metadata',
      '--rename-directories',
      '--containerize-ios-assets',
      '--encrypt-dart-strings',
      '--ios-custom-pod',
      '--ios-custom-pod-id=product_alpha',
      '--ios-custom-pod-theme=resource_catalog',
      '--',
      Platform.resolvedExecutable,
      '--version',
    ]);
    addTearDown(() async {
      if (config.temporaryRoot.existsSync()) {
        await config.temporaryRoot.delete(recursive: true);
      }
    });

    expect(config.renameConfig.generateJunkCode, isTrue);
    expect(config.renameConfig.resetMetadata, isTrue);
    expect(config.renameConfig.renameDirectories, isTrue);
    expect(config.renameConfig.containerizeIosAssets, isTrue);
    expect(config.renameConfig.encryptDartStrings, isTrue);
    expect(config.renameConfig.iosProductPod, isTrue);
    expect(config.renameConfig.iosProductId, 'product_alpha');
    expect(config.enableDartCapabilities, isFalse);
  });

  test(
    'rejects an artifact directory that resolves to the project root',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'transactional_build_artifact_test_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final project = Directory(p.join(temporary.path, 'app'))..createSync();
      _write(project.path, 'pubspec.yaml', '''
name: fixture
environment:
  sdk: ^3.9.2
''');
      Directory(p.join(project.path, 'lib')).createSync();

      await expectLater(
        TransactionalBuildConfig.fromArguments([
          '--transactional-build',
          '--project=${project.path}',
          '--target=lib',
          '--prefix=pre',
          '--artifact-dir=.',
          '--',
          Platform.resolvedExecutable,
          '--version',
        ]),
        throwsA(isA<UsageException>()),
      );
    },
  );

  test(
    'builds the fully transformed temporary copy and keeps only artifacts',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'transactional_full_build_test_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final project = Directory(p.join(temporary.path, 'app'))..createSync();
      _write(project.path, 'pubspec.yaml', '''
name: fixture
environment:
  sdk: ^3.9.2
flutter:
  assets:
    - assets/images/
    - assets/data/
''');
      _write(project.path, 'lib/service/api.dart', '''
class ApiService {
  String load() {
    return 'ok';
  }
}
String api() => TbrEncrypt.decryptedPS('https://api.example.com', '');
''');
      _write(project.path, 'lib/asset_config.g.dart', '''
abstract final class AssetContainerConfig {
  static const bool enabled = false;
}
''');
      _write(project.path, 'lib/string_config.g.dart', '''
abstract final class StringCipherConfig {
  static const bool enabled = false;
}
''');
      _writeIosFixture(project.path);
      final image = File(p.join(project.path, 'assets/images/logo.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List<int>.generate(129, (index) => index % 127));
      _write(project.path, 'assets/data/info.json', '{"ok":true}\n');
      final checker = File(p.join(temporary.path, 'checker.dart'))
        ..writeAsStringSync(r'''
import 'dart:io';

void main() {
  final root = Directory.current.path;
  final api = File('$root/lib/pre_service/pre_api.dart');
  if (!api.existsSync()) exit(10);
  final source = api.readAsStringSync();
  if (source.contains('https://api.example.com')) exit(11);
  if (!source.contains('PreApiService')) exit(12);
  if (File('$root/assets/images/pre_logo.png').existsSync()) exit(13);
  final images = Directory('$root/assets/images').listSync();
  if (!images.any((value) => value.path.endsWith('.dat'))) exit(14);
  if (!images.any((value) => value.path.endsWith('.cfg'))) exit(15);
  if (!File('$root/assets/data/pre_info.json').existsSync()) exit(16);
  final manifest = File('$root/dart_prefix_renamer_manifest.json').readAsStringSync();
  if (!manifest.contains('ProductAlphaPreLocalKit')) exit(17);
  if (!Directory('$root/ios/LocalPods/ProductAlphaPreLocalKit').existsSync()) exit(18);
  if (!File('$root/lib/pack/product_runtime/pre_product_runtime.dart').existsSync()) exit(19);
  if (!source.contains('// dart-capability:')) exit(20);
  final ipa = File('$root/build/ios/ipa/fixture.ipa');
  ipa.createSync(recursive: true);
  ipa.writeAsStringSync('ipa');
}
''');

      final config = await TransactionalBuildConfig.fromArguments([
        '--transactional-build',
        '--project=${project.path}',
        '--target=lib',
        '--prefix=pre',
        '--no-pub-get',
        '--no-verify',
        '--assets',
        '--rename-directories',
        '--containerize-ios-assets',
        '--runtime-config=lib/asset_config.g.dart',
        '--encrypt-dart-strings',
        '--string-runtime-config=lib/string_config.g.dart',
        '--ios-custom-pod',
        '--ios-custom-pod-id=product_alpha',
        '--ios-custom-pod-theme=resource_catalog',
        '--auto-dart-capabilities',
        '--dart-differentiation-percent=100',
        '--dart-capability-seed=0',
        '--',
        Platform.resolvedExecutable,
        checker.path,
      ]);

      final report = await TransactionalBuildRunner(config).run();

      expect(report.buildExitCode, 0);
      expect(report.workspaceRemoved, isTrue);
      expect(report.renameReport.renamedClasses, 3);
      expect(report.renameReport.encryptedImages, 1);
      expect(report.renameReport.encryptedDartStrings, 1);
      expect(report.dartCapabilityReport?.inserted, 1);
      expect(report.copiedArtifactFiles, 1);
      expect(config.temporaryRoot.existsSync(), isFalse);
      expect(image.existsSync(), isTrue);
      expect(
        File(p.join(project.path, 'lib/service/api.dart')).readAsStringSync(),
        contains('https://api.example.com'),
      );
      expect(
        File(p.join(project.path, 'assets/data/info.json')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(project.path, 'build/ios/ipa/fixture.ipa'),
        ).readAsStringSync(),
        'ipa',
      );
    },
  );
}

void _write(String root, String relative, String contents) {
  final file = File(p.join(root, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _writeIosFixture(String root) {
  _write(root, 'ios/Podfile', '''
target 'Runner' do
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
''');
  _write(root, 'ios/Runner/AppDelegate.swift', '''
import UIKit
import Flutter

class AppDelegate: FlutterAppDelegate {
  func configure() {
    let controller = window?.rootViewController as! FlutterViewController
  }
}
''');
}
