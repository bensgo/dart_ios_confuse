import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'capabilities/config/capability_config_loader.dart';
import 'capabilities/ios/dependency_generator.dart';
import 'capabilities/ios/dependency_inspector.dart';
import 'capabilities/ios/dependency_planner.dart';
import 'capabilities/model/capability_report.dart';
import 'capabilities/release/release_inspector.dart';
import 'config.dart';

/// Standalone configuration for deterministic iOS third-party SDK Pods.
///
/// This entry intentionally does not load Dart or Native capability manifests.
final class IosThirdPartySdkPodsConfig {
  IosThirdPartySdkPodsConfig({
    required String projectRoot,
    required this.productId,
    this.dependenciesPath = 'config/dependencies.yaml',
    this.libraryPoolPath = 'config/ios_library_pool.yaml',
    this.reportDirectory = 'reports/ios-third-party-sdk-pods',
    this.seed = 0,
    this.verifyRelease = false,
    this.releaseArtifact,
    this.runPodInstall = true,
  }) : projectRoot = p.normalize(p.absolute(projectRoot)) {
    if (!Directory(this.projectRoot).existsSync()) {
      throw UsageException(
        'Project directory does not exist: ${this.projectRoot}',
      );
    }
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(productId)) {
      throw UsageException(
        '--ios-third-party-sdk-product-id must start with a lowercase ASCII '
        'letter and contain only lowercase letters, digits, or underscores.',
      );
    }
    final normalizedReport = p.normalize(reportDirectory);
    if (p.isAbsolute(normalizedReport) ||
        normalizedReport == '..' ||
        normalizedReport.startsWith('../')) {
      throw UsageException(
        '--ios-third-party-sdk-report-dir must be project-relative.',
      );
    }
    if (verifyRelease && releaseArtifact == null) {
      throw UsageException(
        '--ios-third-party-sdk-release-artifact is required with '
        '--verify-ios-third-party-sdk-pods.',
      );
    }
  }

  factory IosThirdPartySdkPodsConfig.fromArguments(List<String> arguments) {
    final parser = ArgParser()
      ..addFlag('prepare-ios-third-party-sdk-pods', negatable: false)
      ..addFlag('verify-ios-third-party-sdk-pods', negatable: false)
      ..addOption('project', abbr: 'p', mandatory: true)
      ..addOption('ios-third-party-sdk-product-id', mandatory: true)
      ..addOption(
        'ios-third-party-sdk-dependencies',
        defaultsTo: 'config/dependencies.yaml',
      )
      ..addOption(
        'ios-third-party-sdk-library-pool',
        defaultsTo: 'config/ios_library_pool.yaml',
      )
      ..addOption(
        'ios-third-party-sdk-report-dir',
        defaultsTo: 'reports/ios-third-party-sdk-pods',
      )
      ..addOption('ios-third-party-sdk-seed', defaultsTo: '0')
      ..addOption('ios-third-party-sdk-release-artifact')
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
    final seed = int.tryParse(results.option('ios-third-party-sdk-seed')!);
    if (seed == null) {
      throw UsageException('--ios-third-party-sdk-seed must be an integer.');
    }
    return IosThirdPartySdkPodsConfig(
      projectRoot: results.option('project')!,
      productId: results.option('ios-third-party-sdk-product-id')!,
      dependenciesPath: results.option('ios-third-party-sdk-dependencies')!,
      libraryPoolPath: results.option('ios-third-party-sdk-library-pool')!,
      reportDirectory: results.option('ios-third-party-sdk-report-dir')!,
      seed: seed,
      verifyRelease: results.flag('verify-ios-third-party-sdk-pods'),
      releaseArtifact: results.option('ios-third-party-sdk-release-artifact'),
    );
  }

  final String projectRoot;
  final String productId;
  final String dependenciesPath;
  final String libraryPoolPath;
  final String reportDirectory;
  final int seed;
  final bool verifyRelease;
  final String? releaseArtifact;
  final bool runPodInstall;
}

final class IosThirdPartySdkPodsRunner {
  const IosThirdPartySdkPodsRunner(this.config);

  final IosThirdPartySdkPodsConfig config;

  Future<IosThirdPartySdkPodsReport> run() async {
    final loader = CapabilityConfigLoader(projectRoot: config.projectRoot);
    final manifest = loader.loadDependencies(config.dependenciesPath);
    final pool = loader.loadIosLibraryPool(config.libraryPoolPath);
    final plan = DependencyPlanner(
      productId: config.productId,
      seed: config.seed,
      manifest: manifest,
      libraryPool: pool,
    ).createPlan();
    final reportRoot = Directory(
      p.join(config.projectRoot, config.reportDirectory),
    );
    await reportRoot.create(recursive: true);
    final selectionFile = await _writeJson(
      reportRoot,
      'selection.json',
      plan.toJson(),
    );
    final generation = await DependencyGenerator(
      projectRoot: config.projectRoot,
      runPodInstall: config.runPodInstall,
    ).generate(plan);
    var dependencyReport = await DependencyInspector(
      projectRoot: config.projectRoot,
    ).inspect(manifest: plan.resolvedManifest, libraryPool: pool);
    final dependencyFile = await _writeJson(
      reportRoot,
      'integration-report.json',
      dependencyReport.toJson(),
    );
    File? releaseFile;
    CapabilityReport? releaseReport;
    if (config.verifyRelease) {
      releaseReport = await ReleaseInspector(projectRoot: config.projectRoot)
          .inspect(
            inputHashes: loader.computeInputHashes(
              dependenciesPath: config.dependenciesPath,
            ),
            dartReport: DartCapabilityReport(
              classesAnalyzed: 0,
              capabilitiesPlanned: 0,
              capabilitiesApplied: 0,
              capabilitiesReachable: 0,
              capabilitiesFailed: 0,
              integrations: const [],
            ),
            nativeReport: NativeCapabilityReport(
              enabledCount: 0,
              registeredCount: 0,
              calledCount: 0,
              capabilities: const {},
            ),
            dependencyReport: dependencyReport,
            analyzerPassed: true,
            buildSuccess: true,
            ipaPath: config.releaseArtifact,
          );
      dependencyReport = releaseReport.dependencies;
      await dependencyFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(dependencyReport.toJson())}\n',
      );
      releaseFile = await ReleaseInspector(projectRoot: config.projectRoot)
          .writeReport(
            releaseReport,
            relativePath: p.join(config.reportDirectory, 'release-report.json'),
          );
    }
    return IosThirdPartySdkPodsReport(
      selectionFile: selectionFile.path,
      integrationFile: dependencyFile.path,
      releaseFile: releaseFile?.path,
      generation: generation,
      dependencies: dependencyReport,
      releaseReport: releaseReport,
    );
  }
}

final class IosThirdPartySdkPodsReport {
  const IosThirdPartySdkPodsReport({
    required this.selectionFile,
    required this.integrationFile,
    required this.releaseFile,
    required this.generation,
    required this.dependencies,
    required this.releaseReport,
  });

  final String selectionFile;
  final String integrationFile;
  final String? releaseFile;
  final DependencyGenerationReport generation;
  final DependencyReport dependencies;
  final CapabilityReport? releaseReport;

  bool get passed =>
      dependencies.justified == dependencies.total &&
      (releaseReport == null || releaseReport!.status == 'passed');
}

Future<File> _writeJson(
  Directory directory,
  String name,
  Map<String, dynamic> value,
) async {
  final file = File(p.join(directory.path, name));
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
  return file;
}
