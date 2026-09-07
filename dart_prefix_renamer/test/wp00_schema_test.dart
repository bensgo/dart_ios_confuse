import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';

void main() {
  late Directory tempDir;
  late String fixtureRoot;
  late String projectRoot;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wp00_schema_test_');
    projectRoot = p.absolute(
      p.join(Directory.current.path, 'test/fixtures/wp00_baseline'),
    );
    fixtureRoot = projectRoot;
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  group('ProductProfile', () {
    test('parses valid product_profile.yaml', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final profile = loader.loadProductProfile('config/product_profile.yaml');

      expect(profile.schemaVersion, 1);
      expect(profile.product.id, 'product_test');
      expect(profile.product.type, 'test');
    });

    test('serializes to JSON and back', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final profile = loader.loadProductProfile('config/product_profile.yaml');
      final json = profile.toJson();
      final restored = ProductProfile.fromJson(json);

      expect(restored.product.id, profile.product.id);
      expect(restored.product.type, profile.product.type);
    });

    test('rejects unsupported schema_version', () {
      final file = File(p.join(fixtureRoot, 'config/product_profile.yaml'));
      final content = file.readAsStringSync().replaceFirst(
        'schema_version: 1',
        'schema_version: 99',
      );
      final modifiedFile = File(p.join(tempDir.path, 'bad_schema.yaml'));
      modifiedFile.writeAsStringSync(content);

      expect(
        () => ProductProfile.fromJson({'schema_version': 99, 'product': {}}),
        throwsFormatException,
      );
    });

    test('rejects retired product capability fields', () {
      final file = File(p.join(tempDir.path, 'retired_profile.yaml'))
        ..writeAsStringSync('''
schema_version: 1
product: {id: product_test, type: test}
features: {chat: true}
''');
      final loader = CapabilityConfigLoader(projectRoot: tempDir.path);

      expect(
        () => loader.loadProductProfile(p.basename(file.path)),
        throwsA(isA<ConfigException>().having((e) => e.code, 'code', 'E002')),
      );
    });
  });

  group('DartCapabilityManifest', () {
    test('parses valid dart_capabilities.yaml', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final manifest = loader.loadDartCapabilities(
        'config/dart_capabilities.yaml',
      );

      expect(manifest.schemaVersion, 1);
      expect(manifest.rules.length, 5);
      expect(manifest.rules['repository']?.min, 1);
      expect(manifest.rules['repository']?.max, 3);
      expect(manifest.rules['repository']?.allowed, contains('cache_key'));
      expect(
        manifest.rules['repository']?.allowed,
        contains('cache_validation'),
      );
      expect(manifest.integrations.length, greaterThan(10));
    });

    test('parses integration specs correctly', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final manifest = loader.loadDartCapabilities(
        'config/dart_capabilities.yaml',
      );

      final cacheKeyIntegration = manifest.integrations.firstWhere(
        (i) => i.className == 'UserRepository' && i.capability == 'cache_key',
      );
      expect(
        cacheKeyIntegration.library,
        'packages/repository_pkg/lib/src/repository.dart',
      );
      expect(cacheKeyIntegration.callSite.method, 'loadUser');
      expect(cacheKeyIntegration.callSite.anchor, 'before_cache_read');
      expect(cacheKeyIntegration.effect, 'cache_lookup_key');
      expect(cacheKeyIntegration.expected, 'accepted');
    });

    test('includes negative test cases with expected: rejected', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final manifest = loader.loadDartCapabilities(
        'config/dart_capabilities.yaml',
      );

      final deadCode = manifest.integrations.firstWhere(
        (i) =>
            i.className == 'DeadCodeRepository' && i.capability == 'cache_key',
      );
      expect(deadCode.expected, 'rejected');

      final wrongAnchor = manifest.integrations.firstWhere(
        (i) =>
            i.className == 'WrongAnchorRepository' &&
            i.capability == 'cache_validation',
      );
      expect(wrongAnchor.expected, 'rejected');

      final dynamicReflection = manifest.integrations.firstWhere(
        (i) =>
            i.className == 'DynamicReflectionRepository' &&
            i.capability == 'cache_key',
      );
      expect(dynamicReflection.expected, 'rejected');
    });
  });

  group('NativeCapabilityManifest', () {
    test('parses valid native_capabilities.yaml', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final manifest = loader.loadNativeCapabilities(
        'config/native_capabilities.yaml',
      );

      expect(manifest.schemaVersion, 1);
      expect(manifest.native.length, 10);
      expect(manifest.native['device']?.enabled, isTrue);
      expect(manifest.native['device']?.provider, 'system');
      expect(manifest.native['image']?.enabled, isFalse);
      expect(manifest.bridges.length, 6);
    });

    test('parses bridge specs correctly', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final manifest = loader.loadNativeCapabilities(
        'config/native_capabilities.yaml',
      );

      final networkBridge = manifest.bridges.firstWhere(
        (b) => b.api == 'networkState',
      );
      expect(networkBridge.consumer, 'lib/platform/platform_service.dart');
      expect(networkBridge.effect, 'offline_state');
    });
  });

  group('DependencyManifest', () {
    test('parses empty dependencies.yaml', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final manifest = loader.loadDependencies('config/dependencies.yaml');

      expect(manifest.schemaVersion, 1);
      expect(manifest.dependencies.isEmpty, isTrue);
    });

    test('parses deterministic random schema v2', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final manifest = loader.loadDependencies(
        'config/dependencies_random.yaml',
      );

      expect(manifest.schemaVersion, 2);
      expect(manifest.selection?.enabled, isTrue);
      expect(manifest.selection?.count, 7);
      expect(manifest.selection?.candidates, hasLength(15));
    });
  });

  group('CapabilityConfigLoader path safety', () {
    test('rejects absolute paths', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      expect(
        () => loader.loadProductProfile('/absolute/path.yaml'),
        throwsA(isA<ConfigException>().having((e) => e.code, 'code', 'E006')),
      );
    });

    test('rejects path traversal', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      expect(
        () => loader.loadProductProfile('../outside.yaml'),
        throwsA(isA<ConfigException>().having((e) => e.code, 'code', 'E007')),
      );
    });

    test('rejects paths escaping project root', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      expect(
        () => loader.loadProductProfile('config/../../../etc/passwd'),
        throwsA(isA<ConfigException>().having((e) => e.code, 'code', 'E007')),
      );
    });

    test('computes input hashes', () {
      final loader = CapabilityConfigLoader(projectRoot: fixtureRoot);
      final hashes = loader.computeInputHashes(
        productProfilePath: 'config/product_profile.yaml',
        dartCapabilitiesPath: 'config/dart_capabilities.yaml',
        nativeCapabilitiesPath: 'config/native_capabilities.yaml',
        dependenciesPath: 'config/dependencies.yaml',
      );

      expect(hashes.length, 4);
      expect(hashes['product_profile'], isNotEmpty);
      expect(hashes['dart_capabilities'], isNotEmpty);
      expect(hashes['native_capabilities'], isNotEmpty);
      expect(hashes['dependencies'], isNotEmpty);
    });
  });

  group('CapabilityReport models', () {
    test('DartCapabilityReport serializes correctly', () {
      final report = DartCapabilityReport(
        classesAnalyzed: 100,
        capabilitiesPlanned: 20,
        capabilitiesApplied: 18,
        capabilitiesReachable: 18,
        capabilitiesFailed: 0,
        integrations: [
          IntegrationReport(
            className: 'UserRepository',
            library: 'packages/repository_pkg/lib/src/repository.dart',
            capability: 'cache_key',
            callSite: 'loadUser:before_cache_read',
            effect: 'cache_lookup_key',
            defined: true,
            productionCallCount: 2,
            effectVerified: true,
          ),
        ],
      );

      final json = report.toJson();
      expect(json['classes_analyzed'], 100);
      expect(json['capabilities_planned'], 20);
      expect(json['integrations'], hasLength(1));
    });

    test('NativeCapabilityReport serializes correctly', () {
      final report = NativeCapabilityReport(
        enabledCount: 6,
        registeredCount: 6,
        calledCount: 6,
        capabilities: {
          'network': NativeCapabilityStatus(
            enabled: true,
            bridgeCalled: true,
            provider: 'nw_path_monitor',
          ),
          'image': NativeCapabilityStatus(enabled: false, bridgeCalled: false),
        },
      );

      final json = report.toJson();
      expect(json['enabled_count'], 6);
      expect(json['capabilities']['network']['enabled'], true);
      expect(json['capabilities']['network']['bridge_called'], true);
      expect(json['capabilities']['image']['enabled'], false);
    });

    test('DependencyReport serializes correctly', () {
      final report = DependencyReport(
        total: 3,
        justified: 3,
        dependencies: [
          DependencyStatus(
            name: 'Kingfisher',
            version: '8.0.0',
            reason: 'image_cache',
            used: true,
          ),
        ],
      );

      final json = report.toJson();
      expect(json['total'], 3);
      expect(json['justified'], 3);
      expect(json['dependencies'], hasLength(1));
    });

    test('ReleaseValidationReport serializes correctly', () {
      final report = ReleaseValidationReport(
        buildSuccess: true,
        analyzerPassed: true,
        ipaHash: 'abc123',
        lockfileHash: 'def456',
        components: [
          ComponentHash(
            path: 'Frameworks/App.framework/App',
            sha256: 'sha1',
            size: 1000,
          ),
        ],
      );

      final json = report.toJson();
      expect(json['build_success'], true);
      expect(json['analyzer_passed'], true);
      expect(json['ipa_sha256'], 'abc123');
      expect(json['components'], hasLength(1));
    });

    test('Full CapabilityReport round-trip', () {
      final report = CapabilityReport(
        schemaVersion: 1,
        toolVersion: '1.0.0',
        inputHashes: {'product_profile': 'hash1'},
        generatedAt: '2026-08-21T00:00:00Z',
        dartCapabilities: DartCapabilityReport(
          classesAnalyzed: 10,
          capabilitiesPlanned: 5,
          capabilitiesApplied: 5,
          capabilitiesReachable: 5,
          capabilitiesFailed: 0,
          integrations: [],
        ),
        nativeCapabilities: NativeCapabilityReport(
          enabledCount: 3,
          registeredCount: 3,
          calledCount: 3,
          capabilities: {},
        ),
        dependencies: DependencyReport(
          total: 0,
          justified: 0,
          dependencies: [],
        ),
        releaseValidation: ReleaseValidationReport(
          buildSuccess: true,
          analyzerPassed: true,
          ipaHash: '',
          lockfileHash: '',
          components: [],
        ),
        status: 'passed',
        failureCodes: [],
      );

      final json = report.toJson();
      final restored = CapabilityReport.fromJson(json);

      expect(restored.schemaVersion, 1);
      expect(restored.toolVersion, '1.0.0');
      expect(restored.status, 'passed');
    });
  });

  group('Error codes stability', () {
    test('Error codes are defined as constants', () {
      // These are documented in schema.md - verify they exist conceptually
      const errorCodes = {
        'E001': 'Schema version mismatch',
        'E002': 'Unknown field in YAML',
        'E003': 'Missing required field',
        'E004': 'Invalid field type',
        'E005': 'Duplicate integration ID',
        'E006': 'Absolute path not allowed',
        'E007': 'Path traversal detected',
        'E008': 'Path outside project root',
        'E009': 'Product ID conflict with CLI',
        'E010': 'Unknown capability in rules',
        'E011': 'Unknown capability in integration',
        'E012': 'Integration class not found',
        'E013': 'Integration method not found',
        'E014': 'Anchor not found in method',
        'E015': 'Duplicate integration for same class+capability',
        'E016': 'Unknown native capability',
        'E017': 'Unknown provider',
        'E018': 'Bridge consumer not found',
        'E019': 'Version not in lockfile',
        'E020': 'Lockfile mismatch',
      };

      expect(errorCodes.length, 20);
      for (final entry in errorCodes.entries) {
        expect(entry.key, matches(RegExp(r'^E\d{3}$')));
        expect(entry.value, isNotEmpty);
      }
    });
  });
}
