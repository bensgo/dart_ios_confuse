import 'dart:io';

import 'package:path/path.dart' as p;

import 'capabilities/dart/dart_capability_auto.dart';
import 'config.dart';
import 'prefix_renamer.dart';
import 'report.dart';

/// Runs the complete copy-mode pipeline in a disposable working copy.
final class TransactionalBuildConfig {
  TransactionalBuildConfig._({
    required this.renameConfig,
    required this.buildCommand,
    required this.artifactDirectories,
    required this.temporaryRoot,
    required this.enableDartCapabilities,
    required this.dartCapabilityArguments,
  });

  static Future<TransactionalBuildConfig> fromArguments(
    List<String> arguments,
  ) async {
    final separator = arguments.indexOf('--');
    if (separator < 0 || separator == arguments.length - 1) {
      throw UsageException(
        'The build command is required after `--`, for example:\n'
        '  --transactional-build --project=/app --target=lib --prefix=abc '
        '-- fvm flutter build ipa --release',
      );
    }
    final modeArguments = arguments.sublist(0, separator);
    if (modeArguments.any(
      (value) =>
          value == '--output' || value == '-o' || value.startsWith('--output='),
    )) {
      throw UsageException(
        '--transactional-build manages its own temporary --output.',
      );
    }

    final renameArguments = <String>[];
    final dartCapabilityArguments = <String>[];
    final artifacts = <String>[];
    for (var index = 0; index < modeArguments.length; index++) {
      final value = modeArguments[index];
      if (value == '--transactional-build') continue;
      if (value == '--auto-dart-capabilities') continue;
      if (_isDartCapabilityOption(value)) {
        dartCapabilityArguments.add(value);
        if (!value.contains('=') && index + 1 < modeArguments.length) {
          dartCapabilityArguments.add(modeArguments[++index]);
        }
        continue;
      }
      if (value.startsWith('--artifact-dir=')) {
        artifacts.add(value.substring('--artifact-dir='.length));
        continue;
      }
      if (value == '--artifact-dir') {
        if (index + 1 >= modeArguments.length) {
          throw UsageException('--artifact-dir requires a value.');
        }
        artifacts.add(modeArguments[++index]);
        continue;
      }
      renameArguments.add(value);
    }
    if (artifacts.isEmpty) artifacts.add('build/ios/ipa');
    for (var index = 0; index < artifacts.length; index++) {
      final artifact = artifacts[index];
      final normalized = p.normalize(artifact);
      if (artifact.trim().isEmpty ||
          normalized == '.' ||
          p.isAbsolute(normalized) ||
          normalized == '..' ||
          normalized.startsWith('../')) {
        throw UsageException(
          '--artifact-dir must be a project-relative path: $artifact',
        );
      }
      artifacts[index] = normalized;
    }

    final temporaryRoot = await Directory.systemTemp.createTemp(
      'dart_prefix_renamer_build_',
    );
    final outputPath = p.join(temporaryRoot.path, 'project');
    try {
      final renameConfig = RenameConfig.fromArguments([
        ...renameArguments,
        '--output=$outputPath',
      ]);
      return TransactionalBuildConfig._(
        renameConfig: renameConfig,
        buildCommand: arguments.sublist(separator + 1),
        artifactDirectories: artifacts,
        temporaryRoot: temporaryRoot,
        enableDartCapabilities: modeArguments.contains(
          '--auto-dart-capabilities',
        ),
        dartCapabilityArguments: dartCapabilityArguments,
      );
    } on Object {
      await temporaryRoot.delete(recursive: true);
      rethrow;
    }
  }

  final RenameConfig renameConfig;
  final List<String> buildCommand;
  final List<String> artifactDirectories;
  final Directory temporaryRoot;
  final bool enableDartCapabilities;
  final List<String> dartCapabilityArguments;

  static bool _isDartCapabilityOption(String value) => const <String>[
    '--dart-differentiation-percent',
    '--dart-capability-seed',
    '--dart-capability-suggestions-out',
    '--dart-capability-selection-out',
    '--dart-capability-selection',
  ].any((option) => value == option || value.startsWith('$option='));
}

final class TransactionalBuildReport {
  const TransactionalBuildReport({
    required this.renameReport,
    required this.buildExitCode,
    required this.copiedArtifactFiles,
    required this.workspaceRemoved,
    this.dartCapabilityReport,
  });

  final RenameReport renameReport;
  final int buildExitCode;
  final int copiedArtifactFiles;
  final bool workspaceRemoved;
  final DartCapabilityAutoReport? dartCapabilityReport;
}

final class TransactionalBuildRunner {
  TransactionalBuildRunner(this.config);

  final TransactionalBuildConfig config;

  Future<TransactionalBuildReport> run() async {
    RenameReport? renameReport;
    var buildExitCode = -1;
    var copiedArtifactFiles = 0;
    var workspaceRemoved = false;
    DartCapabilityAutoReport? dartCapabilityReport;
    try {
      renameReport = await PrefixRenamer(config.renameConfig).run();
      if (!renameReport.verificationPassed) {
        throw StateError(
          'Temporary project has ${renameReport.newErrors.length} new '
          'Analyzer errors; the build was not started.',
        );
      }
      if (config.enableDartCapabilities) {
        final target = config.renameConfig.targetPaths
            .map(
              (path) => p.relative(path, from: config.renameConfig.projectPath),
            )
            .join(',');
        final autoConfig = DartCapabilityAutoConfig.fromArguments([
          '--auto-dart-capabilities',
          '--project=${config.renameConfig.outputPath}',
          '--target=$target',
          ...config.dartCapabilityArguments,
        ]);
        dartCapabilityReport = await DartCapabilityAutoRunner(autoConfig).run();
      }
      final process = await Process.start(
        config.buildCommand.first,
        config.buildCommand.sublist(1),
        workingDirectory: config.renameConfig.outputPath,
        mode: ProcessStartMode.inheritStdio,
      );
      buildExitCode = await process.exitCode;
      if (buildExitCode != 0) {
        throw ProcessException(
          config.buildCommand.first,
          config.buildCommand.sublist(1),
          'Transactional build command failed',
          buildExitCode,
        );
      }
      for (final relative in config.artifactDirectories) {
        final source = Directory(
          p.join(config.renameConfig.outputPath, relative),
        );
        if (!source.existsSync()) {
          throw StateError(
            'Build artifact directory was not produced: ${source.path}',
          );
        }
        copiedArtifactFiles += await _copyDirectoryContents(
          source: source,
          destination: Directory(
            p.join(config.renameConfig.projectPath, relative),
          ),
        );
      }
    } finally {
      if (config.temporaryRoot.existsSync()) {
        await config.temporaryRoot.delete(recursive: true);
      }
      workspaceRemoved = true;
    }
    return TransactionalBuildReport(
      renameReport: renameReport,
      buildExitCode: buildExitCode,
      copiedArtifactFiles: copiedArtifactFiles,
      workspaceRemoved: workspaceRemoved,
      dartCapabilityReport: dartCapabilityReport,
    );
  }
}

Future<int> _copyDirectoryContents({
  required Directory source,
  required Directory destination,
}) async {
  var files = 0;
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    final target = p.join(destination.path, relative);
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
    } else if (entity is File) {
      await File(target).parent.create(recursive: true);
      await entity.copy(target);
      files++;
    }
  }
  return files;
}
