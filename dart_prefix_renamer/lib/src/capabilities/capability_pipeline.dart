import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../config.dart';
import 'config/capability_config_loader.dart';
import 'dart/dart_capability_generator.dart';
import 'dart/dart_capability_planner.dart';
import 'dart/dart_capability_validator.dart';
import 'dart/dart_class_scanner.dart';
import 'ios/dependency_generator.dart';
import 'ios/dependency_inspector.dart';
import 'ios/dependency_planner.dart';
import 'ios/native_capability_generator.dart';
import 'ios/pigeon_bridge_generator.dart';
import 'model/capability_report.dart';
import 'release/release_inspector.dart';

class CapabilityPipelineConfig {
  CapabilityPipelineConfig({
    required String projectRoot,
    required List<String> targetPaths,
    this.productProfilePath = 'config/product_profile.yaml',
    this.dartCapabilitiesPath = 'config/dart_capabilities.yaml',
    this.nativeCapabilitiesPath = 'config/native_capabilities.yaml',
    this.dependenciesPath = 'config/dependencies.yaml',
    this.libraryPoolPath = 'config/ios_library_pool.yaml',
    this.reportDirectory = 'reports',
    this.seed = 0,
    this.verifyRelease = false,
    this.releaseArtifact,
    this.analyzerPassed = true,
    this.buildSuccess = true,
  }) : projectRoot = p.normalize(p.absolute(projectRoot)),
       targetPaths = targetPaths
           .map((path) => p.normalize(p.absolute(projectRoot, path)))
           .toList(growable: false) {
    if (!Directory(this.projectRoot).existsSync()) {
      throw UsageException(
        'Project directory does not exist: ${this.projectRoot}',
      );
    }
    if (this.targetPaths.isEmpty ||
        this.targetPaths.any(
          (path) =>
              !Directory(path).existsSync() ||
              (path != this.projectRoot && !p.isWithin(this.projectRoot, path)),
        )) {
      throw UsageException(
        'Capability targets must be existing project directories.',
      );
    }
    final report = p.normalize(reportDirectory);
    if (p.isAbsolute(report) || report == '..' || report.startsWith('../')) {
      throw UsageException('--capability-report-dir must be project-relative.');
    }
    if (verifyRelease && releaseArtifact == null) {
      throw UsageException(
        '--release-artifact is required with --verify-release-capabilities.',
      );
    }
  }

  factory CapabilityPipelineConfig.fromArguments(List<String> arguments) {
    final parser = ArgParser()
      ..addFlag('prepare-capabilities', negatable: false)
      ..addOption('project', abbr: 'p', mandatory: true)
      ..addOption('target', abbr: 't', mandatory: true)
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
      ..addFlag('verify-release-capabilities', negatable: false)
      ..addOption('release-artifact')
      ..addFlag('analyzer-passed', defaultsTo: true)
      ..addFlag('build-success', defaultsTo: true)
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
    final seed = int.tryParse(results.option('capability-seed')!);
    if (seed == null) {
      throw UsageException('--capability-seed must be an integer.');
    }
    return CapabilityPipelineConfig(
      projectRoot: results.option('project')!,
      targetPaths: results
          .option('target')!
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      productProfilePath: results.option('product-profile')!,
      dartCapabilitiesPath: results.option('dart-capabilities')!,
      nativeCapabilitiesPath: results.option('native-capabilities')!,
      dependenciesPath: results.option('dependency-manifest')!,
      libraryPoolPath: results.option('library-pool')!,
      reportDirectory: results.option('capability-report-dir')!,
      seed: seed,
      verifyRelease: results.flag('verify-release-capabilities'),
      releaseArtifact: results.option('release-artifact'),
      analyzerPassed: results.flag('analyzer-passed'),
      buildSuccess: results.flag('build-success'),
    );
  }

  final String projectRoot;
  final List<String> targetPaths;
  final String productProfilePath;
  final String dartCapabilitiesPath;
  final String nativeCapabilitiesPath;
  final String dependenciesPath;
  final String libraryPoolPath;
  final String reportDirectory;
  final int seed;
  final bool verifyRelease;
  final String? releaseArtifact;
  final bool analyzerPassed;
  final bool buildSuccess;
}

/// Configuration for the Dart-only capability preparation flow.
///
/// This deliberately excludes Native/Pigeon and third-party dependency
/// manifests. It still uses the product profile as the deterministic plan
/// identity.
class DartCapabilityPreparationConfig {
  DartCapabilityPreparationConfig({
    required String projectRoot,
    required List<String> targetPaths,
    this.productProfilePath = 'config/product_profile.yaml',
    this.dartCapabilitiesPath = 'config/dart_capabilities.yaml',
    this.reportDirectory = 'reports',
    this.seed = 0,
  }) : projectRoot = p.normalize(p.absolute(projectRoot)),
       targetPaths = targetPaths
           .map((path) => p.normalize(p.absolute(projectRoot, path)))
           .toList(growable: false) {
    if (!Directory(this.projectRoot).existsSync()) {
      throw UsageException(
        'Project directory does not exist: ${this.projectRoot}',
      );
    }
    if (this.targetPaths.isEmpty ||
        this.targetPaths.any(
          (path) =>
              !Directory(path).existsSync() ||
              (path != this.projectRoot && !p.isWithin(this.projectRoot, path)),
        )) {
      throw UsageException(
        'Dart capability targets must be existing project directories.',
      );
    }
    final report = p.normalize(reportDirectory);
    if (p.isAbsolute(report) || report == '..' || report.startsWith('../')) {
      throw UsageException(
        '--dart-capability-report-dir must be project-relative.',
      );
    }
  }

  factory DartCapabilityPreparationConfig.fromArguments(
    List<String> arguments,
  ) {
    final parser = ArgParser()
      ..addFlag('prepare-dart-capabilities', negatable: false)
      ..addOption('project', abbr: 'p', mandatory: true)
      ..addOption('target', abbr: 't', mandatory: true)
      ..addOption('product-profile', defaultsTo: 'config/product_profile.yaml')
      ..addOption(
        'dart-capabilities',
        defaultsTo: 'config/dart_capabilities.yaml',
      )
      ..addOption('dart-capability-report-dir', defaultsTo: 'reports')
      ..addOption('dart-capability-seed', defaultsTo: '0')
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
    final seed = int.tryParse(results.option('dart-capability-seed')!);
    if (seed == null) {
      throw UsageException('--dart-capability-seed must be an integer.');
    }
    return DartCapabilityPreparationConfig(
      projectRoot: results.option('project')!,
      targetPaths: results
          .option('target')!
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      productProfilePath: results.option('product-profile')!,
      dartCapabilitiesPath: results.option('dart-capabilities')!,
      reportDirectory: results.option('dart-capability-report-dir')!,
      seed: seed,
    );
  }

  final String projectRoot;
  final List<String> targetPaths;
  final String productProfilePath;
  final String dartCapabilitiesPath;
  final String reportDirectory;
  final int seed;
}

class DartCapabilityPreparation {
  DartCapabilityPreparation(this.config);

  final DartCapabilityPreparationConfig config;

  Future<DartCapabilityPreparationReport> run() async {
    final loader = CapabilityConfigLoader(projectRoot: config.projectRoot);
    final profile = loader.loadProductProfile(config.productProfilePath);
    final manifest = loader.loadDartCapabilities(config.dartCapabilitiesPath);
    final scan = await DartClassScanner(
      projectRoot: config.projectRoot,
      targetPaths: config.targetPaths,
    ).scan();
    final plan = DartCapabilityPlanner(
      projectRoot: config.projectRoot,
      profile: profile,
      manifest: manifest,
      seed: config.seed,
    ).createPlan(scan);
    final reportRoot = Directory(
      p.join(config.projectRoot, config.reportDirectory),
    );
    await reportRoot.create(recursive: true);
    final planFile = await _writeCapabilityJson(
      reportRoot,
      'dart-capability-plan.json',
      plan.toJson(),
    );
    final generation = await DartCapabilityGenerator(
      projectRoot: config.projectRoot,
    ).apply(plan);
    final dartReport = await DartCapabilityValidator(
      projectRoot: config.projectRoot,
    ).validate(plan);
    final dartFile = await _writeCapabilityJson(
      reportRoot,
      'dart-capability-report.json',
      dartReport.toJson(),
    );
    return DartCapabilityPreparationReport(
      plan: plan,
      generation: generation,
      dartReport: dartReport,
      reportFiles: [planFile.path, dartFile.path],
    );
  }
}

class DartCapabilityPreparationReport {
  const DartCapabilityPreparationReport({
    required this.plan,
    required this.generation,
    required this.dartReport,
    required this.reportFiles,
  });

  final CapabilityPlan plan;
  final DartCapabilityGenerationReport generation;
  final DartCapabilityReport dartReport;
  final List<String> reportFiles;

  bool get passed => dartReport.capabilitiesFailed == 0;
}

class CapabilityPipeline {
  CapabilityPipeline(this.config);

  final CapabilityPipelineConfig config;

  Future<CapabilityPipelineReport> run() async {
    final loader = CapabilityConfigLoader(projectRoot: config.projectRoot);
    final normalized = loader.loadAll(
      productProfilePath: config.productProfilePath,
      dartCapabilitiesPath: config.dartCapabilitiesPath,
      nativeCapabilitiesPath: config.nativeCapabilitiesPath,
      dependenciesPath: config.dependenciesPath,
    );
    final pool = loader.loadIosLibraryPool(config.libraryPoolPath);
    final dependencyPlan = DependencyPlanner(
      productId: normalized.productProfile.product.id,
      seed: config.seed,
      manifest: normalized.dependencies,
      libraryPool: pool,
    ).createPlan();
    final scan = await DartClassScanner(
      projectRoot: config.projectRoot,
      targetPaths: config.targetPaths,
    ).scan();
    final plan = DartCapabilityPlanner(
      projectRoot: config.projectRoot,
      profile: normalized.productProfile,
      manifest: normalized.dartCapabilities,
      seed: config.seed,
    ).createPlan(scan);
    final reportRoot = Directory(
      p.join(config.projectRoot, config.reportDirectory),
    );
    await reportRoot.create(recursive: true);
    final planFile = await _writeJson(
      reportRoot,
      'capability-plan.json',
      plan.toJson(),
    );
    final dependencySelectionFile = await _writeJson(
      reportRoot,
      'dependency-selection.json',
      dependencyPlan.toJson(),
    );
    final generation = await DartCapabilityGenerator(
      projectRoot: config.projectRoot,
    ).apply(plan);
    final dartReport = await DartCapabilityValidator(
      projectRoot: config.projectRoot,
    ).validate(plan);
    final nativeGeneration = await NativeCapabilityGenerator(
      projectRoot: config.projectRoot,
    ).generate(normalized.nativeCapabilities);
    final bridge = await PigeonBridgeGenerator(
      projectRoot: config.projectRoot,
    ).generate(normalized.nativeCapabilities);
    final dependencyGeneration = await DependencyGenerator(
      projectRoot: config.projectRoot,
    ).generate(dependencyPlan);
    final dependencies = await DependencyInspector(
      projectRoot: config.projectRoot,
    ).inspect(manifest: dependencyPlan.resolvedManifest, libraryPool: pool);
    final dartFile = await _writeJson(
      reportRoot,
      'dart-capability-report.json',
      dartReport.toJson(),
    );
    final nativeFile = await _writeJson(
      reportRoot,
      'native-capability-report.json',
      bridge.report.toJson(),
    );
    final dependencyFile = await _writeJson(
      reportRoot,
      'dependency-report.json',
      dependencies.toJson(),
    );
    CapabilityReport? releaseReport;
    File? releaseFile;
    if (config.verifyRelease) {
      releaseReport = await ReleaseInspector(projectRoot: config.projectRoot)
          .inspect(
            inputHashes: normalized.inputHashes,
            dartReport: dartReport,
            nativeReport: bridge.report,
            dependencyReport: dependencies,
            analyzerPassed: config.analyzerPassed,
            buildSuccess: config.buildSuccess,
            ipaPath: config.releaseArtifact,
          );
      releaseFile = await ReleaseInspector(projectRoot: config.projectRoot)
          .writeReport(
            releaseReport,
            relativePath: p.join(config.reportDirectory, 'release-report.json'),
          );
      await dependencyFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(releaseReport.dependencies.toJson())}\n',
      );
    }
    return CapabilityPipelineReport(
      plan: plan,
      dependencyPlan: dependencyPlan,
      dependencyGeneration: dependencyGeneration,
      generation: generation,
      dartReport: dartReport,
      nativeGeneration: nativeGeneration,
      bridgeGeneration: bridge,
      nativeReport: bridge.report,
      dependencyReport: dependencies,
      releaseReport: releaseReport,
      reportFiles: [
        planFile.path,
        dependencySelectionFile.path,
        dartFile.path,
        nativeFile.path,
        dependencyFile.path,
        if (releaseFile != null) releaseFile.path,
      ],
    );
  }

  Future<File> _writeJson(
    Directory root,
    String name,
    Map<String, dynamic> value,
  ) => _writeCapabilityJson(root, name, value);
}

Future<File> _writeCapabilityJson(
  Directory root,
  String name,
  Map<String, dynamic> value,
) async {
  final file = File(p.join(root.path, name));
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
  return file;
}

class CapabilityPipelineReport {
  const CapabilityPipelineReport({
    required this.plan,
    required this.dependencyPlan,
    required this.dependencyGeneration,
    required this.generation,
    required this.dartReport,
    required this.nativeGeneration,
    required this.bridgeGeneration,
    required this.nativeReport,
    required this.dependencyReport,
    required this.releaseReport,
    required this.reportFiles,
  });

  final CapabilityPlan plan;
  final DependencySelectionPlan dependencyPlan;
  final DependencyGenerationReport dependencyGeneration;
  final DartCapabilityGenerationReport generation;
  final DartCapabilityReport dartReport;
  final NativeGenerationReport nativeGeneration;
  final PigeonBridgeReport bridgeGeneration;
  final NativeCapabilityReport nativeReport;
  final DependencyReport dependencyReport;
  final CapabilityReport? releaseReport;
  final List<String> reportFiles;

  List<String> get generatedArtifactFiles => [
    ...dependencyGeneration.generatedFiles,
    ...nativeGeneration.generatedFiles,
    bridgeGeneration.pigeonFile,
    bridgeGeneration.optionsFile,
    ...bridgeGeneration.generatedFiles,
    ...reportFiles,
  ];

  bool get passed =>
      dartReport.capabilitiesFailed == 0 &&
      nativeReport.capabilities.values
          .where((item) => item.enabled)
          .every((item) => item.bridgeCalled) &&
      dependencyReport.justified == dependencyReport.total &&
      (releaseReport == null || releaseReport!.status == 'passed');
}
