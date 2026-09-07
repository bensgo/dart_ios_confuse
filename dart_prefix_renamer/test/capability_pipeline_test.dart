import 'dart:convert';
import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'prepares Dart, Native, Pigeon and dependency reports together',
    () async {
      final fixture = Directory(p.absolute('test/fixtures/wp00_baseline'));
      final root = await Directory.systemTemp.createTemp(
        'capability_pipeline_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _copyDirectory(fixture, root);
      await File(
        p.join(root.path, 'config/dart_capabilities.yaml'),
      ).writeAsString('''
schema_version: 1
rules:
  repository:
    min: 1
    max: 3
    allowed: [cache_key, response_normalizer]
integrations:
  - class: UserRepository
    library: packages/repository_pkg/lib/src/repository.dart
    capability: cache_key
    call_site: {method: loadUser, anchor: before_cache_read}
    effect: cache_lookup_key
  - class: ProductRepository
    library: packages/repository_pkg/lib/src/repository.dart
    capability: response_normalizer
    call_site: {method: loadProducts, anchor: after_fetch}
    effect: normalized_response
''');
      final report = await CapabilityPipeline(
        CapabilityPipelineConfig(
          projectRoot: root.path,
          targetPaths: ['packages/repository_pkg/lib'],
          seed: 42,
        ),
      ).run();
      expect(report.passed, isTrue);
      expect(report.dartReport.capabilitiesReachable, 2);
      expect(report.nativeReport.enabledCount, 6);
      expect(report.nativeReport.calledCount, 6);
      expect(report.reportFiles, hasLength(5));
      expect(
        report.reportFiles,
        contains(endsWith('dependency-selection.json')),
      );
      for (final path in report.reportFiles) {
        expect(File(path).existsSync(), isTrue);
      }
      expect(
        File(
          p.join(root.path, 'ios/NativeCapabilities/NetworkCapability.swift'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(root.path, 'pigeons/native_capability_api.dart'),
        ).readAsStringSync(),
        contains('@HostApi()'),
      );
    },
  );

  test('parses the standalone prepare CLI contract', () {
    final fixture = p.absolute('test/fixtures/wp00_baseline');
    final config = CapabilityPipelineConfig.fromArguments([
      '--prepare-capabilities',
      '--project=$fixture',
      '--target=packages/repository_pkg/lib',
      '--capability-seed=7',
    ]);
    expect(config.seed, 7);
    expect(config.targetPaths.single, endsWith('packages/repository_pkg/lib'));
  });

  test(
    'prepares Dart capabilities without Native or dependency manifests',
    () async {
      final fixture = Directory(p.absolute('test/fixtures/wp00_baseline'));
      final root = await Directory.systemTemp.createTemp(
        'dart_capability_only_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _copyDirectory(fixture, root);
      for (final path in [
        'config/native_capabilities.yaml',
        'config/dependencies.yaml',
        'config/ios_library_pool.yaml',
      ]) {
        await File(p.join(root.path, path)).delete();
      }
      await File(
        p.join(root.path, 'config/dart_capabilities.yaml'),
      ).writeAsString('''
schema_version: 1
rules:
  repository: {min: 1, max: 1, allowed: [cache_key]}
integrations:
  - class: UserRepository
    library: packages/repository_pkg/lib/src/repository.dart
    capability: cache_key
    call_site: {method: loadUser, anchor: before_cache_read}
    effect: cache_lookup_key
''');
      final report = await DartCapabilityPreparation(
        DartCapabilityPreparationConfig(
          projectRoot: root.path,
          targetPaths: ['packages/repository_pkg/lib'],
        ),
      ).run();
      expect(report.passed, isTrue);
      expect(report.dartReport.capabilitiesReachable, 1);
      expect(report.reportFiles, hasLength(2));
      expect(
        File(
          p.join(root.path, 'reports/dart-capability-plan.json'),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('parses the Dart-only prepare CLI contract', () {
    final fixture = p.absolute('test/fixtures/wp00_baseline');
    final config = DartCapabilityPreparationConfig.fromArguments([
      '--prepare-dart-capabilities',
      '--project=$fixture',
      '--target=packages/repository_pkg/lib',
      '--dart-capability-seed=7',
    ]);
    expect(config.seed, 7);
    expect(config.targetPaths.single, endsWith('packages/repository_pkg/lib'));
  });

  test('parses capabilities in the shared copy-mode contract', () {
    final fixture = p.absolute('test/fixtures/wp00_baseline');
    final config = RenameConfig.fromArguments([
      '--project=$fixture',
      '--output=${p.join(Directory.systemTemp.path, 'capability_copy_output')}',
      '--target=packages/repository_pkg/lib',
      '--prefix=cap',
      '--capabilities',
      '--capability-seed=9',
    ]);
    expect(config.capabilities.enabled, isTrue);
    expect(config.capabilities.seed, 9);
  });

  test(
    'writes manifest v2 and safely restores capability artifacts',
    () async {
      final fixture = Directory(p.absolute('test/fixtures/wp00_baseline'));
      final source = await Directory.systemTemp.createTemp(
        'capability_restore_source_',
      );
      final output = p.join(
        Directory.systemTemp.path,
        'capability_restore_${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() async {
        if (source.existsSync()) await source.delete(recursive: true);
        final directory = Directory(output);
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      await _copyDirectory(fixture, source);
      await File(
        p.join(source.path, 'config/dart_capabilities.yaml'),
      ).writeAsString('''
schema_version: 1
rules:
  repository: {min: 1, max: 1, allowed: [cache_key]}
integrations:
  - class: UserRepository
    library: packages/repository_pkg/lib/src/repository.dart
    capability: cache_key
    call_site: {method: loadUser, anchor: before_cache_read}
    effect: cache_lookup_key
''');
      final report = await PrefixRenamer(
        RenameConfig(
          projectPath: source.path,
          outputPath: output,
          targetPaths: ['packages/repository_pkg/lib'],
          prefix: 'cap',
          runPubGet: true,
          verify: false,
          renameAssets: false,
          capabilities: const CapabilityOptions(enabled: true, seed: 3),
        ),
      ).run();
      expect(report.capabilitiesReachable, 1);
      final manifest =
          jsonDecode(
                File(
                  p.join(output, 'dart_prefix_renamer_manifest.json'),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(manifest['version'], 2);
      expect(
        (manifest['capabilities'] as Map<String, dynamic>)['artifacts'],
        isNotEmpty,
      );
      final restore = await PrefixRestorer(
        RestoreConfig(projectPath: output, verify: false),
      ).run();
      expect(restore.verificationPassed, isTrue);
      expect(
        Directory(p.join(output, 'ios/NativeCapabilities')).listSync(),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'two product profiles produce different native compositions',
    () async {
      final fixture = Directory(p.absolute('test/fixtures/wp00_baseline'));
      final alpha = await Directory.systemTemp.createTemp('profile_alpha_');
      final beta = await Directory.systemTemp.createTemp('profile_beta_');
      addTearDown(() async {
        await alpha.delete(recursive: true);
        await beta.delete(recursive: true);
      });
      await _copyDirectory(fixture, alpha);
      await _copyDirectory(fixture, beta);
      for (final root in [alpha, beta]) {
        await File(
          p.join(root.path, 'config/dart_capabilities.yaml'),
        ).writeAsString('schema_version: 1\nrules: {}\nintegrations: []\n');
      }
      final alphaReport = await CapabilityPipeline(
        CapabilityPipelineConfig(
          projectRoot: alpha.path,
          targetPaths: ['packages/repository_pkg/lib'],
          productProfilePath: 'config/product_alpha_profile.yaml',
          nativeCapabilitiesPath: 'config/native_capabilities_alpha.yaml',
        ),
      ).run();
      final betaReport = await CapabilityPipeline(
        CapabilityPipelineConfig(
          projectRoot: beta.path,
          targetPaths: ['packages/repository_pkg/lib'],
          productProfilePath: 'config/product_beta_profile.yaml',
          nativeCapabilitiesPath: 'config/native_capabilities_beta.yaml',
        ),
      ).run();
      expect(alphaReport.passed, isTrue);
      expect(betaReport.passed, isTrue);
      expect(alphaReport.nativeGeneration.enabled, hasLength(4));
      expect(betaReport.nativeGeneration.enabled, hasLength(5));
      expect(
        alphaReport.nativeGeneration.contentHash,
        isNot(betaReport.nativeGeneration.contentHash),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    if (entity is Directory) {
      await Directory(
        p.join(destination.path, relative),
      ).create(recursive: true);
    } else if (entity is File) {
      final target = File(p.join(destination.path, relative));
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
    }
  }
}
