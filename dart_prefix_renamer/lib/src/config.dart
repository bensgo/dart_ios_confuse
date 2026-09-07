import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

final class RenameConfig {
  RenameConfig({
    required String projectPath,
    required String outputPath,
    required List<String> targetPaths,
    required this.prefix,
    this.runPubGet = true,
    this.verify = true,
    this.renameAssets = true,
    this.generateJunkCode = false,
    this.resetMetadata = false,
    this.renameDirectories = false,
    this.containerizeIosAssets = false,
    this.assetDirectories = const ['assets/images'],
    this.animationAssetDirectories = const [],
    this.audioAssetDirectories = const [],
    this.containerDirectory = 'assets/images',
    this.assetRuntimeConfig =
        'lib/app_tools/asset_container/asset_container_config.g.dart',
    this.encryptDartStrings = false,
    this.stringRuntimeConfig =
        'packages/aixi_app_config/lib/src/string_cipher_config.g.dart',
    this.decryptMethod = 'decryptedPS',
    this.iosMethodChannelDiff = false,
    this.iosMethodChannelIncludes = const [],
    this.iosMethodChannelExcludes = const [],
    this.iosDummyMethodChannelCount = 12,
    this.iosMethodChannelSeed,
    this.iosMethodChannelEntrypoints = const ['lib/main.dart'],
    this.iosProductPod = false,
    this.iosProductId,
    this.iosProductTheme,
    this.iosProductPodSeed,
    this.capabilities = const CapabilityOptions(),
  }) : projectPath = p.normalize(p.absolute(projectPath)),
       outputPath = p.normalize(p.absolute(outputPath)),
       targetPaths = targetPaths
           .map((path) => p.normalize(p.absolute(projectPath, path)))
           .toList(growable: false) {
    _validate();
  }

  factory RenameConfig.fromArguments(List<String> arguments) {
    final parser = ArgParser()
      ..addOption(
        'project',
        abbr: 'p',
        mandatory: true,
        help: 'Flutter/Dart project root.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        mandatory: true,
        help: 'New output project directory.',
      )
      ..addOption(
        'target',
        abbr: 't',
        mandatory: true,
        help:
            'Comma-separated project-relative directories whose Dart files and classes are renamed.',
      )
      ..addOption(
        'prefix',
        mandatory: true,
        help: 'Lowercase ASCII prefix, for example "abc".',
      )
      ..addFlag(
        'pub-get',
        defaultsTo: true,
        help: 'Run `fvm flutter pub get` in the copied project.',
      )
      ..addFlag(
        'verify',
        defaultsTo: true,
        help: 'Compare Analyzer errors before and after renaming.',
      )
      ..addFlag(
        'assets',
        defaultsTo: true,
        help: 'Rename declared Flutter assets and rewrite static paths.',
      )
      ..addFlag(
        'junk-code',
        defaultsTo: false,
        help: 'Generate standalone Dart junk files under lib/pack/junk_code.',
      )
      ..addFlag(
        'reset-metadata',
        defaultsTo: false,
        help:
            'Reset output file/directory dates and clear macOS extended attributes.',
      )
      ..addFlag(
        'rename-directories',
        defaultsTo: false,
        help: 'Prefix directories inside targeted package lib directories.',
      )
      ..addFlag(
        'containerize-ios-assets',
        defaultsTo: false,
        help: 'Keep encrypted iOS image containers in the output copy.',
      )
      ..addMultiOption(
        'asset-dir',
        help:
            'Project-relative image directory. May be repeated; defaults to '
            'assets/images only when no asset directory option is provided.',
      )
      ..addMultiOption(
        'animation-asset-dir',
        help: 'Project-relative SVGA/Lottie directory. May be repeated.',
      )
      ..addMultiOption(
        'audio-asset-dir',
        help: 'Project-relative audio directory. May be repeated.',
      )
      ..addOption('container-dir', defaultsTo: 'assets/images')
      ..addOption(
        'runtime-config',
        defaultsTo:
            'lib/app_tools/asset_container/asset_container_config.g.dart',
      )
      ..addFlag(
        'encrypt-dart-strings',
        defaultsTo: false,
        help: 'Keep encrypted marked Dart strings in the output copy.',
      )
      ..addOption(
        'string-runtime-config',
        defaultsTo:
            'packages/aixi_app_config/lib/src/string_cipher_config.g.dart',
      )
      ..addOption('decrypt-method', defaultsTo: 'decryptedPS')
      ..addFlag(
        'ios-method-channel-diff',
        defaultsTo: false,
        help:
            'Differentiate selected Flutter MethodChannels for iOS IPA builds.',
      )
      ..addMultiOption(
        'ios-method-channel-include',
        help: 'Static channel name to rename on both Dart and iOS. May repeat.',
      )
      ..addMultiOption(
        'ios-method-channel-exclude',
        help: 'Channel name that must never be renamed. May repeat.',
      )
      ..addOption(
        'ios-dummy-method-channel-count',
        defaultsTo: '12',
        help: 'Number of paired, inert Dart/iOS channels to generate.',
      )
      ..addOption(
        'ios-method-channel-seed',
        help: 'Optional integer seed for reproducible channel names.',
      )
      ..addMultiOption(
        'ios-method-channel-entrypoint',
        defaultsTo: const ['lib/main.dart'],
        help:
            'Dart entrypoint that initializes generated channels. May repeat.',
      )
      ..addFlag(
        'ios-custom-pod',
        defaultsTo: false,
        help:
            'Generate and integrate one deterministic, source-based custom iOS Pod.',
      )
      ..addOption(
        'ios-custom-pod-id',
        help: 'Product identity for the generated custom Pod.',
      )
      ..addOption(
        'ios-custom-pod-theme',
        help:
            'Offline module theme: resource_catalog, display_rules, or configuration_profile.',
      )
      ..addOption(
        'ios-custom-pod-seed',
        help: 'Optional integer seed for reproducible custom Pod generation.',
      )
      ..addFlag(
        'ios-product-pod',
        defaultsTo: false,
        hide: true,
        help: 'Deprecated alias for --ios-custom-pod.',
      )
      ..addOption(
        'ios-product-id',
        hide: true,
        help: 'Deprecated alias for --ios-custom-pod-id.',
      )
      ..addOption(
        'ios-product-theme',
        hide: true,
        help:
            'Offline module theme: resource_catalog, display_rules, or configuration_profile.',
      )
      ..addOption(
        'ios-product-pod-seed',
        hide: true,
        help:
            'Optional integer seed. Defaults to a stable SHA-256 derivation from product id and prefix.',
      )
      ..addFlag(
        'capabilities',
        defaultsTo: false,
        help:
            'Prepare manifest-driven Dart and iOS capabilities in the output copy.',
      )
      ..addOption('product-profile', defaultsTo: 'config/product_profile.yaml')
      ..addOption(
        'dart-capabilities',
        defaultsTo: 'config/dart_capabilities.yaml',
      )
      ..addOption(
        'native-capabilities',
        defaultsTo: 'config/native_capabilities.yaml',
      )
      ..addOption('dependency-manifest', defaultsTo: 'config/dependencies.yaml')
      ..addOption('library-pool', defaultsTo: 'config/ios_library_pool.yaml')
      ..addOption('capability-report-dir', defaultsTo: 'reports')
      ..addOption('capability-seed', defaultsTo: '0')
      ..addFlag('help', abbr: 'h', negatable: false);

    late final ArgResults results;
    try {
      results = parser.parse(arguments);
    } on FormatException catch (error) {
      throw UsageException('${error.message}\n\n${parser.usage}');
    }

    if (results.flag('help')) {
      throw UsageException(parser.usage, exitCode: 0);
    }

    final targets = (results.option('target') ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    int parseIntegerOption(String name) {
      final value = results.option(name)!;
      final parsed = int.tryParse(value);
      if (parsed == null) {
        throw UsageException('--$name must be an integer: $value');
      }
      return parsed;
    }

    int? parseOptionalIntegerOption(String name) {
      final value = results.option(name);
      if (value == null) return null;
      final parsed = int.tryParse(value);
      if (parsed == null) {
        throw UsageException('--$name must be an integer: $value');
      }
      return parsed;
    }

    String? canonicalOption(String canonical, String legacy) {
      final canonicalValue = results.option(canonical);
      final legacyValue = results.option(legacy);
      if (canonicalValue != null &&
          legacyValue != null &&
          canonicalValue != legacyValue) {
        throw UsageException(
          '--$canonical and deprecated --$legacy cannot have different values.',
        );
      }
      return canonicalValue ?? legacyValue;
    }

    final customPodEnabled =
        results.flag('ios-custom-pod') || results.flag('ios-product-pod');

    final imageAssetDirectories = results.multiOption('asset-dir');
    final animationAssetDirectories = results.multiOption(
      'animation-asset-dir',
    );
    final audioAssetDirectories = results.multiOption('audio-asset-dir');
    final hasExplicitAssetDirectories =
        imageAssetDirectories.isNotEmpty ||
        animationAssetDirectories.isNotEmpty ||
        audioAssetDirectories.isNotEmpty;

    return RenameConfig(
      projectPath: results.option('project')!,
      outputPath: results.option('output')!,
      targetPaths: targets,
      prefix: results.option('prefix')!,
      runPubGet: results.flag('pub-get'),
      verify: results.flag('verify'),
      renameAssets: results.flag('assets'),
      generateJunkCode: results.flag('junk-code'),
      resetMetadata: results.flag('reset-metadata'),
      renameDirectories: results.flag('rename-directories'),
      containerizeIosAssets: results.flag('containerize-ios-assets'),
      assetDirectories: hasExplicitAssetDirectories
          ? imageAssetDirectories
          : const ['assets/images'],
      animationAssetDirectories: animationAssetDirectories,
      audioAssetDirectories: audioAssetDirectories,
      containerDirectory: results.option('container-dir')!,
      assetRuntimeConfig: results.option('runtime-config')!,
      encryptDartStrings: results.flag('encrypt-dart-strings'),
      stringRuntimeConfig: results.option('string-runtime-config')!,
      decryptMethod: results.option('decrypt-method')!,
      iosMethodChannelDiff: results.flag('ios-method-channel-diff'),
      iosMethodChannelIncludes: results.multiOption(
        'ios-method-channel-include',
      ),
      iosMethodChannelExcludes: results.multiOption(
        'ios-method-channel-exclude',
      ),
      iosDummyMethodChannelCount: parseIntegerOption(
        'ios-dummy-method-channel-count',
      ),
      iosMethodChannelSeed: parseOptionalIntegerOption(
        'ios-method-channel-seed',
      ),
      iosMethodChannelEntrypoints: results.multiOption(
        'ios-method-channel-entrypoint',
      ),
      iosProductPod: customPodEnabled,
      iosProductId: canonicalOption('ios-custom-pod-id', 'ios-product-id'),
      iosProductTheme: canonicalOption(
        'ios-custom-pod-theme',
        'ios-product-theme',
      ),
      iosProductPodSeed: () {
        final value = canonicalOption(
          'ios-custom-pod-seed',
          'ios-product-pod-seed',
        );
        if (value == null) return null;
        final parsed = int.tryParse(value);
        if (parsed == null) {
          throw UsageException(
            '--ios-custom-pod-seed must be an integer: $value',
          );
        }
        return parsed;
      }(),
      capabilities: CapabilityOptions(
        enabled: results.flag('capabilities'),
        productProfilePath: results.option('product-profile')!,
        dartCapabilitiesPath: results.option('dart-capabilities')!,
        nativeCapabilitiesPath: results.option('native-capabilities')!,
        dependenciesPath: results.option('dependency-manifest')!,
        libraryPoolPath: results.option('library-pool')!,
        reportDirectory: results.option('capability-report-dir')!,
        seed: parseIntegerOption('capability-seed'),
      ),
    );
  }

  final String projectPath;
  final String outputPath;
  final List<String> targetPaths;
  final String prefix;
  final bool runPubGet;
  final bool verify;
  final bool renameAssets;
  final bool generateJunkCode;
  final bool resetMetadata;
  final bool renameDirectories;
  final bool containerizeIosAssets;
  final List<String> assetDirectories;
  final List<String> animationAssetDirectories;
  final List<String> audioAssetDirectories;
  final String containerDirectory;
  final String assetRuntimeConfig;
  final bool encryptDartStrings;
  final String stringRuntimeConfig;
  final String decryptMethod;

  /// 是否执行仅面向 iOS IPA 的 MethodChannel 差异化。
  final bool iosMethodChannelDiff;

  /// 显式授权改名的真实 Channel；不会自动改写所有第三方 Channel。
  final List<String> iosMethodChannelIncludes;

  /// 明确保护的 Channel，优先级高于 include。
  final List<String> iosMethodChannelExcludes;

  /// Dart 和 iOS 两端成对生成的无用 Channel 数量，默认 12。
  final int iosDummyMethodChannelCount;

  /// 可选随机种子。设置后，相同 prefix 和配置会生成相同名称。
  final int? iosMethodChannelSeed;

  /// 注入无用 Channel 初始化调用的 Dart main 文件。
  final List<String> iosMethodChannelEntrypoints;

  /// 是否在输出副本生成确定性的本地 iOS 源码 Pod。
  /// Whether to generate a deterministic local iOS source Pod in the output copy.
  final bool iosProductPod;

  /// 稳定的产品身份，会进入 Pod 名、资源与 manifest；它不等同于重命名前缀。
  /// Stable product identity used by Pod names, resources, and manifests.
  final String? iosProductId;

  /// 可选离线主题；省略时由 [iosProductId] 确定性选择，而不是运行时随机选择。
  /// Optional offline theme, selected deterministically from [iosProductId]
  /// when omitted.
  final String? iosProductTheme;

  /// 可选确定性 seed；省略时由 productId + prefix 的 SHA-256 派生。
  /// Optional deterministic seed derived from productId + prefix when omitted.
  final int? iosProductPodSeed;
  final CapabilityOptions capabilities;

  void _validate() {
    if (!Directory(projectPath).existsSync()) {
      throw UsageException('Project directory does not exist: $projectPath');
    }
    if (!File(p.join(projectPath, 'pubspec.yaml')).existsSync()) {
      throw UsageException('Project has no pubspec.yaml: $projectPath');
    }
    if (!RegExp(r'^[a-z]+$').hasMatch(prefix)) {
      throw UsageException(
        'Prefix must contain lowercase ASCII letters only: $prefix',
      );
    }
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(decryptMethod)) {
      throw UsageException('Invalid decrypt method name: $decryptMethod');
    }
    if (iosDummyMethodChannelCount < 0) {
      throw UsageException('--ios-dummy-method-channel-count must be >= 0.');
    }
    if (iosMethodChannelDiff && iosMethodChannelEntrypoints.isEmpty) {
      throw UsageException(
        'At least one --ios-method-channel-entrypoint is required.',
      );
    }
    const supportedProductThemes = {
      'resource_catalog',
      'display_rules',
      'configuration_profile',
    };
    // 产品 Pod 会改写输出副本中的 Podfile，因此在复制工程前就拒绝不完整配置，
    // 避免失败后留下一个只能部分构建的输出目录。
    // Fail before copying so invalid Pod settings cannot leave a partial output.
    if (iosProductPod) {
      final productId = iosProductId;
      if (productId == null || productId.isEmpty) {
        throw UsageException(
          '--ios-custom-pod-id is required with --ios-custom-pod.',
        );
      }
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(productId)) {
        throw UsageException(
          '--ios-custom-pod-id must start with a lowercase ASCII letter and '
          'contain lowercase letters, digits, or underscores only: $productId',
        );
      }
      final theme = iosProductTheme;
      if (theme != null && !supportedProductThemes.contains(theme)) {
        throw UsageException(
          'Unsupported --ios-custom-pod-theme: $theme. Expected one of: '
          '${supportedProductThemes.join(', ')}',
        );
      }
      if (!Directory(p.join(projectPath, 'ios')).existsSync()) {
        throw UsageException(
          '--ios-custom-pod requires an iOS project directory: '
          '${p.join(projectPath, 'ios')}',
        );
      }
      if (!File(p.join(projectPath, 'ios', 'Podfile')).existsSync()) {
        throw UsageException(
          '--ios-custom-pod requires ios/Podfile in the source project.',
        );
      }
    } else if (iosProductId != null ||
        iosProductTheme != null ||
        iosProductPodSeed != null) {
      throw UsageException(
        '--ios-custom-pod-id, --ios-custom-pod-theme, and '
        '--ios-custom-pod-seed require --ios-custom-pod.',
      );
    }
    for (final value in [
      ...iosMethodChannelIncludes,
      ...iosMethodChannelExcludes,
    ]) {
      if (value.trim().isEmpty) {
        throw UsageException('MethodChannel names must not be empty.');
      }
    }
    for (final entrypoint in iosMethodChannelEntrypoints) {
      final normalized = p.normalize(entrypoint);
      if (p.isAbsolute(normalized) ||
          normalized == '..' ||
          normalized.startsWith('../') ||
          p.extension(normalized) != '.dart') {
        throw UsageException(
          'iOS MethodChannel entrypoint must be a project-relative Dart file: '
          '$entrypoint',
        );
      }
    }
    if (targetPaths.isEmpty) {
      throw UsageException('At least one --target directory is required.');
    }
    for (final targetPath in targetPaths) {
      if (!_isWithin(projectPath, targetPath) ||
          !Directory(targetPath).existsSync()) {
        throw UsageException(
          'Target must be an existing directory inside the project: $targetPath',
        );
      }
    }
    if (_isWithin(projectPath, outputPath) ||
        _isWithin(outputPath, projectPath)) {
      throw UsageException(
        'Project and output directories must not contain one another.',
      );
    }
    if (FileSystemEntity.typeSync(outputPath) !=
        FileSystemEntityType.notFound) {
      throw UsageException(
        'Output path already exists; refusing to overwrite: $outputPath',
      );
    }
  }
}

final class CapabilityOptions {
  const CapabilityOptions({
    this.enabled = false,
    this.productProfilePath = 'config/product_profile.yaml',
    this.dartCapabilitiesPath = 'config/dart_capabilities.yaml',
    this.nativeCapabilitiesPath = 'config/native_capabilities.yaml',
    this.dependenciesPath = 'config/dependencies.yaml',
    this.libraryPoolPath = 'config/ios_library_pool.yaml',
    this.reportDirectory = 'reports',
    this.seed = 0,
  });

  final bool enabled;
  final String productProfilePath;
  final String dartCapabilitiesPath;
  final String nativeCapabilitiesPath;
  final String dependenciesPath;
  final String libraryPoolPath;
  final String reportDirectory;
  final int seed;
}

final class UsageException implements Exception {
  UsageException(this.message, {this.exitCode = 64});

  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

final class RestoreConfig {
  RestoreConfig({
    required String projectPath,
    String? manifestPath,
    this.verify = true,
  }) : projectPath = p.normalize(p.absolute(projectPath)),
       manifestPath = p.normalize(
         p.absolute(
           manifestPath ??
               p.join(projectPath, 'dart_prefix_renamer_manifest.json'),
         ),
       ) {
    if (!Directory(this.projectPath).existsSync()) {
      throw UsageException(
        'Restore project directory does not exist: ${this.projectPath}',
      );
    }
    if (!File(this.manifestPath).existsSync()) {
      throw UsageException(
        'Restore manifest does not exist: ${this.manifestPath}',
      );
    }
    if (this.manifestPath != this.projectPath &&
        !p.isWithin(this.projectPath, this.manifestPath)) {
      throw UsageException('Restore manifest must be inside the project.');
    }
  }

  factory RestoreConfig.fromArguments(List<String> arguments) {
    final parser = ArgParser()
      ..addFlag(
        'restore',
        negatable: false,
        help: 'Restore names from manifest.',
      )
      ..addOption('project', abbr: 'p', mandatory: true)
      ..addOption(
        'manifest',
        help: 'Manifest path; defaults to the project root manifest.',
      )
      ..addFlag(
        'verify',
        defaultsTo: true,
        help: 'Compare Analyzer errors before and after restore.',
      )
      ..addFlag('help', abbr: 'h', negatable: false);
    late final ArgResults results;
    try {
      results = parser.parse(arguments);
    } on FormatException catch (error) {
      throw UsageException('${error.message}\n\n${parser.usage}');
    }
    if (results.flag('help')) {
      throw UsageException(parser.usage, exitCode: 0);
    }
    return RestoreConfig(
      projectPath: results.option('project')!,
      manifestPath: results.option('manifest'),
      verify: results.flag('verify'),
    );
  }

  final String projectPath;
  final String manifestPath;
  final bool verify;
}

bool _isWithin(String parent, String child) =>
    parent == child || p.isWithin(parent, child);
