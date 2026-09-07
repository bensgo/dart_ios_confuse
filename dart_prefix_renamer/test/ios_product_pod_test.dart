import 'dart:convert';
import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('iOS product Pod configuration', () {
    test('requires a product id when enabled', () async {
      final fixture = await _fixture('product_pod_missing_id_');
      addTearDown(() => fixture.delete(recursive: true));

      expect(
        () => RenameConfig.fromArguments([
          '--project=${fixture.path}',
          '--output=${fixture.path}_output',
          '--target=lib',
          '--prefix=abc',
          '--ios-custom-pod',
        ]),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('--ios-custom-pod-id is required'),
          ),
        ),
      );
    });

    test('rejects invalid ids, themes, and feature arguments', () async {
      final fixture = await _fixture('product_pod_invalid_config_');
      addTearDown(() => fixture.delete(recursive: true));

      List<String> arguments(String productId, String theme) => [
        '--project=${fixture.path}',
        '--output=${fixture.path}_${productId}_output',
        '--target=lib',
        '--prefix=abc',
        '--ios-custom-pod',
        '--ios-custom-pod-id=$productId',
        '--ios-custom-pod-theme=$theme',
      ];

      expect(
        () => RenameConfig.fromArguments(
          arguments('Product-A', 'resource_catalog'),
        ),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => RenameConfig.fromArguments(
          arguments('product_a', 'remote_profile'),
        ),
        throwsA(isA<UsageException>()),
      );
      expect(
        () => RenameConfig.fromArguments([
          '--project=${fixture.path}',
          '--output=${fixture.path}_disabled_output',
          '--target=lib',
          '--prefix=abc',
          '--ios-product-id=product_a',
        ]),
        throwsA(isA<UsageException>()),
      );
    });

    test('rejects projects without an iOS Podfile', () async {
      final fixture = await Directory.systemTemp.createTemp(
        'product_pod_non_ios_',
      );
      addTearDown(() => fixture.delete(recursive: true));
      _write(fixture.path, 'pubspec.yaml', 'name: fixture\n');
      Directory(p.join(fixture.path, 'lib')).createSync();

      expect(
        () => RenameConfig.fromArguments([
          '--project=${fixture.path}',
          '--output=${fixture.path}_output',
          '--target=lib',
          '--prefix=abc',
          '--ios-product-pod',
          '--ios-product-id=product_a',
        ]),
        throwsA(isA<UsageException>()),
      );
    });
  });

  test('generation is deterministic for the same product inputs', () async {
    final first = await _fixture('product_pod_deterministic_a_');
    final second = await _fixture('product_pod_deterministic_b_');
    addTearDown(() => first.delete(recursive: true));
    addTearDown(() => second.delete(recursive: true));

    final firstReport = await _generate(first.path);
    final secondReport = await _generate(second.path);

    expect(firstReport.podName, secondReport.podName);
    expect(firstReport.classPrefix, secondReport.classPrefix);
    expect(firstReport.theme, secondReport.theme);
    expect(firstReport.seed, secondReport.seed);
    expect(firstReport.channelName, secondReport.channelName);
    expect(firstReport.contentHash, secondReport.contentHash);
    expect(firstReport.manifestHash, secondReport.manifestHash);
  });

  test('different products generate different modules and payloads', () async {
    final first = await _fixture('product_pod_variant_a_');
    final second = await _fixture('product_pod_variant_b_');
    addTearDown(() => first.delete(recursive: true));
    addTearDown(() => second.delete(recursive: true));

    final firstReport = await _generate(first.path);
    final secondReport = await IosProductPodGenerator(
      IosProductPodConfig(
        projectPath: second.path,
        prefix: 'xyz',
        productId: 'product_beta',
      ),
    ).generate();

    expect(firstReport.podName, isNot(secondReport.podName));
    expect(firstReport.channelName, isNot(secondReport.channelName));
    expect(firstReport.contentHash, isNot(secondReport.contentHash));
  });

  test(
    'integrates once and restore removes only generated artifacts',
    () async {
      final fixture = await _fixture('product_pod_restore_');
      addTearDown(() => fixture.delete(recursive: true));
      final originalPodfile = File(
        p.join(fixture.path, 'ios', 'Podfile'),
      ).readAsStringSync();
      final originalAppDelegate = File(
        p.join(fixture.path, 'ios', 'Runner', 'AppDelegate.swift'),
      ).readAsStringSync();

      final report = await _generate(fixture.path);
      final podfile = File(report.podfile).readAsStringSync();
      final appDelegate = File(report.appDelegate).readAsStringSync();
      expect(
        '# dart_prefix_renamer:ios-product-pod-begin'
            .allMatches(podfile)
            .length,
        1,
      );
      expect(
        '// dart_prefix_renamer:ios-product-pod-import-begin'
            .allMatches(appDelegate)
            .length,
        1,
      );
      expect(Directory(report.podDirectory).existsSync(), isTrue);
      expect(File(report.dartClientFile).existsSync(), isTrue);

      final manifest = <String, dynamic>{
        'iosProductPod': <String, dynamic>{
          'enabled': true,
          'podDirectory': p.relative(report.podDirectory, from: fixture.path),
          'dartClientFile': p.relative(
            report.dartClientFile,
            from: fixture.path,
          ),
          'podfile': p.relative(report.podfile, from: fixture.path),
          'appDelegate': p.relative(report.appDelegate, from: fixture.path),
        },
      };
      final removed = await restoreIosProductPod(
        projectPath: fixture.path,
        manifest: manifest,
      );

      expect(removed, greaterThan(1));
      expect(Directory(report.podDirectory).existsSync(), isFalse);
      expect(File(report.dartClientFile).existsSync(), isFalse);
      expect(File(report.podfile).readAsStringSync(), originalPodfile);
      expect(File(report.appDelegate).readAsStringSync(), originalAppDelegate);
    },
  );

  test('manifest records offline constraints and generated files', () async {
    final fixture = await _fixture('product_pod_manifest_');
    addTearDown(() => fixture.delete(recursive: true));
    final report = await _generate(fixture.path);
    final manifest =
        jsonDecode(
              File(
                p.join(report.podDirectory, 'product_pod_manifest.json'),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(manifest['productId'], 'product_alpha');
    expect(manifest['contentHash'], report.contentHash);
    expect(manifest['sourceFiles'], hasLength(8));
    expect(manifest['resourceFiles'], hasLength(2));
    expect(manifest['constraints'], {
      'network': false,
      'permissions': false,
      'deviceIdentifiers': false,
      'backgroundTasks': false,
      'dataCollection': false,
      'thirdPartyDependencies': false,
    });

    final podspec = File(
      p.join(report.podDirectory, '${report.podName}.podspec'),
    ).readAsStringSync();
    expect(podspec, contains("s.dependency 'Flutter'"));
    expect(RegExp(r"s\.dependency '[^']+'").allMatches(podspec).length, 1);
  });
}

Future<IosProductPodReport> _generate(String projectPath) =>
    IosProductPodGenerator(
      IosProductPodConfig(
        projectPath: projectPath,
        prefix: 'abc',
        productId: 'product_alpha',
        theme: 'resource_catalog',
      ),
    ).generate();

Future<Directory> _fixture(String prefix) async {
  final project = await Directory.systemTemp.createTemp(prefix);
  _write(project.path, 'pubspec.yaml', '''
name: fixture
environment:
  sdk: ^3.9.2
''');
  _write(project.path, 'lib/main.dart', 'void main() {}\n');
  _write(project.path, 'ios/Podfile', '''
target 'Runner' do
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
''');
  _write(project.path, 'ios/Runner/AppDelegate.swift', '''
import UIKit
import Flutter

@main
class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
''');
  return project;
}

void _write(String root, String relative, String contents) {
  final file = File(p.join(root, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
