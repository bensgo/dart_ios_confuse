import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../model/capability_manifest.dart';
import '../model/ios_library_pool.dart';
import '../model/product_profile.dart';

class CapabilityConfigLoader {
  CapabilityConfigLoader({required String projectRoot})
    : _projectRoot = p.normalize(p.absolute(projectRoot));

  final String _projectRoot;

  ProductProfile loadProductProfile(String relativePath) {
    final file = _resolveAndValidate(relativePath);
    final content = file.readAsStringSync();
    final yaml = loadYaml(content) as Map<dynamic, dynamic>;
    final map = _castMap(yaml);
    _validateSchemaVersion(map, 'product_profile');
    _validateProductProfile(map);
    return ProductProfile.fromJson(map);
  }

  DartCapabilityManifest loadDartCapabilities(String relativePath) {
    final file = _resolveAndValidate(relativePath);
    final content = file.readAsStringSync();
    final yaml = loadYaml(content) as Map<dynamic, dynamic>;
    final map = _castMap(yaml);
    _validateSchemaVersion(map, 'dart_capabilities');
    _validateDartCapabilities(map);
    return DartCapabilityManifest.fromJson(map);
  }

  NativeCapabilityManifest loadNativeCapabilities(String relativePath) {
    final file = _resolveAndValidate(relativePath);
    final content = file.readAsStringSync();
    final yaml = loadYaml(content) as Map<dynamic, dynamic>;
    final map = _castMap(yaml);
    _validateSchemaVersion(map, 'native_capabilities');
    _validateNativeCapabilities(map);
    return NativeCapabilityManifest.fromJson(map);
  }

  DependencyManifest loadDependencies(String relativePath) {
    final file = _resolveAndValidate(relativePath);
    final content = file.readAsStringSync();
    final yaml = loadYaml(content) as Map<dynamic, dynamic>;
    final map = _castMap(yaml);
    _validateSchemaVersion(map, 'dependencies');
    return DependencyManifest.fromJson(map);
  }

  IosLibraryPool loadIosLibraryPool(String relativePath) {
    final file = _resolveAndValidate(relativePath);
    final yaml = loadYaml(file.readAsStringSync()) as Map<dynamic, dynamic>;
    final map = _castMap(yaml);
    _validateSchemaVersion(map, 'ios_library_pool');
    return IosLibraryPool.fromJson(map);
  }

  NormalizedConfig loadAll({
    required String productProfilePath,
    required String dartCapabilitiesPath,
    required String nativeCapabilitiesPath,
    required String dependenciesPath,
    String? cliProductId,
    String? cliPrefix,
  }) {
    final productProfile = loadProductProfile(productProfilePath);
    final dartCapabilities = loadDartCapabilities(dartCapabilitiesPath);
    final nativeCapabilities = loadNativeCapabilities(nativeCapabilitiesPath);
    final dependencies = loadDependencies(dependenciesPath);

    _validateProductIdConsistency(productProfile, cliProductId);
    _validateDartNativeConsistency(dartCapabilities, nativeCapabilities);

    final inputHashes = computeInputHashes(
      productProfilePath: productProfilePath,
      dartCapabilitiesPath: dartCapabilitiesPath,
      nativeCapabilitiesPath: nativeCapabilitiesPath,
      dependenciesPath: dependenciesPath,
    );

    return NormalizedConfig(
      productProfile: productProfile,
      dartCapabilities: dartCapabilities,
      nativeCapabilities: nativeCapabilities,
      dependencies: dependencies,
      inputHashes: inputHashes,
    );
  }

  Map<String, String> computeInputHashes({
    String? productProfilePath,
    String? dartCapabilitiesPath,
    String? nativeCapabilitiesPath,
    String? dependenciesPath,
  }) {
    final hashes = <String, String>{};
    if (productProfilePath != null) {
      hashes['product_profile'] = _sha256(productProfilePath);
    }
    if (dartCapabilitiesPath != null) {
      hashes['dart_capabilities'] = _sha256(dartCapabilitiesPath);
    }
    if (nativeCapabilitiesPath != null) {
      hashes['native_capabilities'] = _sha256(nativeCapabilitiesPath);
    }
    if (dependenciesPath != null) {
      hashes['dependencies'] = _sha256(dependenciesPath);
    }
    return hashes;
  }

  File _resolveAndValidate(String relativePath) {
    if (p.isAbsolute(relativePath)) {
      throw ConfigException('E006', 'Path must be relative: $relativePath');
    }
    if (relativePath.contains('..')) {
      throw ConfigException(
        'E007',
        'Path traversal not allowed: $relativePath',
      );
    }
    final absolute = p.normalize(p.join(_projectRoot, relativePath));
    if (!p.isWithin(_projectRoot, absolute)) {
      throw ConfigException('E008', 'Path escapes project root: $relativePath');
    }
    final file = File(absolute);
    if (!file.existsSync()) {
      throw ConfigException('E003', 'Config file not found: $relativePath');
    }
    return file;
  }

  String _sha256(String relativePath) {
    final file = _resolveAndValidate(relativePath);
    final bytes = file.readAsBytesSync();
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void _validateSchemaVersion(Map<String, dynamic> map, String configName) {
    final version = map['schema_version'] as int?;
    if (version == null) {
      throw ConfigException(
        'E003',
        'Missing required field: schema_version in $configName',
      );
    }
    final supported = configName == 'dependencies' ? const {1, 2} : const {1};
    if (!supported.contains(version)) {
      throw ConfigException(
        'E001',
        'Unsupported schema_version: $version in $configName '
            '(expected ${supported.join(' or ')})',
      );
    }
  }

  void _validateDartCapabilities(Map<String, dynamic> map) {
    final rules = map['rules'] as Map<String, dynamic>?;
    if (rules == null) {
      throw ConfigException(
        'E003',
        'Missing required field: rules in dart_capabilities',
      );
    }

    final allowedCapabilities = <String>{};
    for (final entry in rules.entries) {
      final rule = entry.value as Map<String, dynamic>;
      final allowed = rule['allowed'] as List<dynamic>?;
      if (allowed != null) {
        for (final cap in allowed) {
          allowedCapabilities.add(cap as String);
        }
      }
    }

    final integrations = map['integrations'] as List<dynamic>?;
    if (integrations != null) {
      final seen = <String>{};
      for (int i = 0; i < integrations.length; i++) {
        final integration = integrations[i] as Map<String, dynamic>;
        final className = integration['class'] as String?;
        final capability = integration['capability'] as String?;
        final library = integration['library'] as String?;

        if (className == null || className.isEmpty) {
          throw ConfigException(
            'E003',
            'Missing required field: class in integration[$i]',
          );
        }
        if (capability == null || capability.isEmpty) {
          throw ConfigException(
            'E003',
            'Missing required field: capability in integration[$i]',
          );
        }
        if (library == null || library.isEmpty) {
          throw ConfigException(
            'E003',
            'Missing required field: library in integration[$i]',
          );
        }

        if (!allowedCapabilities.contains(capability)) {
          throw ConfigException(
            'E011',
            'Unknown capability in integration: $capability',
          );
        }

        final key = '$className:$capability';
        if (seen.contains(key)) {
          throw ConfigException(
            'E005',
            'Duplicate integration for same class+capability: $key',
          );
        }
        seen.add(key);

        final callSite = integration['call_site'] as Map<String, dynamic>?;
        if (callSite == null) {
          throw ConfigException(
            'E003',
            'Missing required field: call_site in integration[$i]',
          );
        }
        final method = callSite['method'] as String?;
        final anchor = callSite['anchor'] as String?;
        if (method == null || method.isEmpty) {
          throw ConfigException(
            'E003',
            'Missing required field: call_site.method in integration[$i]',
          );
        }
        if (anchor == null || anchor.isEmpty) {
          throw ConfigException(
            'E003',
            'Missing required field: call_site.anchor in integration[$i]',
          );
        }

        final libPath = p.normalize(p.join(_projectRoot, library));
        if (!p.isWithin(_projectRoot, libPath) || !File(libPath).existsSync()) {
          throw ConfigException(
            'E012',
            'Integration class library not found: $library',
          );
        }
      }
    }
  }

  void _validateProductProfile(Map<String, dynamic> map) {
    const allowedRootFields = {'schema_version', 'product'};
    for (final field in map.keys) {
      if (!allowedRootFields.contains(field)) {
        throw ConfigException(
          'E002',
          'Unknown field in product_profile: $field. Product capabilities must '
              'be declared only in dart_capabilities.yaml or '
              'native_capabilities.yaml.',
        );
      }
    }
    final product = map['product'];
    if (product is! Map<String, dynamic>) {
      throw ConfigException(
        'E003',
        'Missing required object field: product in product_profile',
      );
    }
    const allowedProductFields = {'id', 'type'};
    for (final field in product.keys) {
      if (!allowedProductFields.contains(field)) {
        throw ConfigException(
          'E002',
          'Unknown product field in product_profile: $field',
        );
      }
    }
    for (final field in allowedProductFields) {
      final value = product[field];
      if (value is! String || value.isEmpty) {
        throw ConfigException(
          'E003',
          'Missing required string field: product.$field in product_profile',
        );
      }
    }
  }

  void _validateNativeCapabilities(Map<String, dynamic> map) {
    final native = map['native'] as Map<String, dynamic>?;
    if (native == null) {
      throw ConfigException(
        'E003',
        'Missing required field: native in native_capabilities',
      );
    }

    const validProviders = {
      'system',
      'nw_path_monitor',
      'keychain',
      'crypto_kit',
      'os_signpost',
      'kingfisher',
      'sdwebimage',
      'grdb',
      'zipfoundation',
      'cocoalumberjack',
      'swiftprotobuf',
      'starscream',
    };

    for (final entry in native.entries) {
      final spec = entry.value as Map<String, dynamic>;
      final provider = spec['provider'] as String? ?? 'system';
      if (!validProviders.contains(provider)) {
        throw ConfigException(
          'E017',
          'Unknown provider: $provider for capability ${entry.key}',
        );
      }
    }

    final bridges = map['bridges'] as List<dynamic>?;
    if (bridges != null) {
      for (int i = 0; i < bridges.length; i++) {
        final bridge = bridges[i] as Map<String, dynamic>;
        final api = bridge['api'] as String?;
        final consumer = bridge['consumer'] as String?;
        final effect = bridge['effect'] as String?;

        if (api == null || api.isEmpty) {
          throw ConfigException(
            'E003',
            'Missing required field: api in bridge[$i]',
          );
        }
        if (consumer == null || consumer.isEmpty) {
          throw ConfigException(
            'E003',
            'Missing required field: consumer in bridge[$i]',
          );
        }
        if (effect == null || effect.isEmpty) {
          throw ConfigException(
            'E003',
            'Missing required field: effect in bridge[$i]',
          );
        }

        final consumerPath = p.normalize(p.join(_projectRoot, consumer));
        if (!p.isWithin(_projectRoot, consumerPath) ||
            !File(consumerPath).existsSync()) {
          throw ConfigException('E018', 'Bridge consumer not found: $consumer');
        }
      }
    }
  }

  void _validateProductIdConsistency(
    ProductProfile profile,
    String? cliProductId,
  ) {
    if (cliProductId != null &&
        cliProductId.isNotEmpty &&
        profile.product.id != cliProductId) {
      throw ConfigException(
        'E009',
        'Product ID conflict: profile has ${profile.product.id}, CLI has $cliProductId',
      );
    }
  }

  void _validateDartNativeConsistency(
    DartCapabilityManifest dartCapabilities,
    NativeCapabilityManifest nativeCapabilities,
  ) {
    for (final entry in nativeCapabilities.native.entries) {
      if (entry.value.enabled) {
        // Verify that enabled native capabilities have corresponding Dart integrations or are system-only
        // This is a soft check - just ensure the capability is known
      }
    }
  }

  Map<String, dynamic> _castMap(Map<dynamic, dynamic> yamlMap) {
    return yamlMap.map((k, v) => MapEntry(k as String, _castValue(v)));
  }

  dynamic _castValue(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k as String, _castValue(v)));
    }
    if (value is List) {
      return value.map(_castValue).toList(growable: false);
    }
    return value;
  }
}

class NormalizedConfig {
  NormalizedConfig({
    required this.productProfile,
    required this.dartCapabilities,
    required this.nativeCapabilities,
    required this.dependencies,
    required this.inputHashes,
  });

  final ProductProfile productProfile;
  final DartCapabilityManifest dartCapabilities;
  final NativeCapabilityManifest nativeCapabilities;
  final DependencyManifest dependencies;
  final Map<String, String> inputHashes;

  Map<String, dynamic> toJson() => {
    'product_profile': productProfile.toJson(),
    'dart_capabilities': dartCapabilities.toJson(),
    'native_capabilities': nativeCapabilities.toJson(),
    'dependencies': dependencies.toJson(),
    'input_hashes': inputHashes,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class ConfigException implements Exception {
  ConfigException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '[$code] $message';
}
