import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.contains('--prepare-ios-third-party-sdk-pods')) {
      final config = IosThirdPartySdkPodsConfig.fromArguments(arguments);
      final report = await IosThirdPartySdkPodsRunner(config).run();
      stdout
        ..writeln('iOS third-party SDK Pod preparation completed:')
        ..writeln('  Pod: ${report.generation.podName}')
        ..writeln('  Selected: ${report.dependencies.selected}')
        ..writeln('  Declared: ${report.dependencies.declared}')
        ..writeln('  Locked: ${report.dependencies.locked}')
        ..writeln('  Called: ${report.dependencies.called}')
        ..writeln('  Linked: ${report.dependencies.linked}')
        ..writeln('  Reports: ${report.integrationFile}')
        ..writeln('  Passed: ${report.passed}');
      if (!report.passed) exitCode = 2;
      return;
    }
    if (!arguments.contains('--transactional-build') &&
        (arguments.contains('--scan-dart-capabilities') ||
            arguments.contains('--auto-dart-capabilities'))) {
      final config = DartCapabilityAutoConfig.fromArguments(arguments);
      stdout
        ..writeln('Starting Dart capability scan...')
        ..writeln('  Project: ${config.projectRoot}')
        ..writeln('  Targets: ${config.targetPaths.length}');
      final report = await DartCapabilityAutoRunner(
        config,
        onProgress: stdout.writeln,
      ).run();
      stdout
        ..writeln('Dart capability automation completed:')
        ..writeln('  Classes scanned: ${report.classesScanned}')
        ..writeln('  Eligible candidates: ${report.candidates}')
        ..writeln('  Selected: ${report.selected}')
        ..writeln('  Inserted: ${report.inserted}')
        ..writeln('  Suggestions: ${report.suggestionsFile}')
        ..writeln('  Selection: ${report.selectionFile ?? '-'}');
      return;
    }
    if (arguments.contains('--prepare-dart-capabilities')) {
      final config = DartCapabilityPreparationConfig.fromArguments(arguments);
      final report = await DartCapabilityPreparation(config).run();
      stdout
        ..writeln('Dart capability preparation completed:')
        ..writeln('  Classes analyzed: ${report.plan.classesAnalyzed}')
        ..writeln('  Capabilities ready: ${report.plan.readyEntries.length}')
        ..writeln('  Definitions generated: ${report.generation.generated}')
        ..writeln(
          '  Dart reachable: ${report.dartReport.capabilitiesReachable}',
        )
        ..writeln('  Reports: ${report.reportFiles.length}')
        ..writeln('  Passed: ${report.passed}');
      if (!report.passed) exitCode = 2;
      return;
    }
    if (arguments.contains('--prepare-capabilities')) {
      final config = CapabilityPipelineConfig.fromArguments(arguments);
      final report = await CapabilityPipeline(config).run();
      stdout
        ..writeln('Capability preparation completed:')
        ..writeln('  Classes analyzed: ${report.plan.classesAnalyzed}')
        ..writeln('  Capabilities ready: ${report.plan.readyEntries.length}')
        ..writeln('  Definitions generated: ${report.generation.generated}')
        ..writeln(
          '  Dart reachable: ${report.dartReport.capabilitiesReachable}',
        )
        ..writeln('  Native enabled: ${report.nativeReport.enabledCount}')
        ..writeln('  Native called: ${report.nativeReport.calledCount}')
        ..writeln(
          '  Dependencies justified: ${report.dependencyReport.justified}',
        )
        ..writeln('  Reports: ${report.reportFiles.length}')
        ..writeln('  Passed: ${report.passed}');
      if (!report.passed) exitCode = 2;
      return;
    }
    if (arguments.contains('--transactional-build')) {
      final config = await TransactionalBuildConfig.fromArguments(arguments);
      final report = await TransactionalBuildRunner(config).run();
      stdout
        ..writeln('')
        ..writeln('Transactional full build completed:')
        ..writeln('  Files renamed: ${report.renameReport.renamedFiles}')
        ..writeln('  Classes renamed: ${report.renameReport.renamedClasses}')
        ..writeln('  Assets renamed: ${report.renameReport.renamedAssets}')
        ..writeln('  Images encrypted: ${report.renameReport.encryptedImages}')
        ..writeln(
          '  Animations encrypted: '
          '${report.renameReport.encryptedAnimations}',
        )
        ..writeln('  Audio encrypted: ${report.renameReport.encryptedAudio}')
        ..writeln(
          '  Dart strings encrypted: '
          '${report.renameReport.encryptedDartStrings}',
        )
        ..writeln(
          '  iOS MethodChannels renamed: '
          '${report.renameReport.renamedIosMethodChannels}',
        )
        ..writeln(
          '  iOS dummy MethodChannels: '
          '${report.renameReport.generatedIosMethodChannels}',
        )
        ..writeln(
          '  iOS product Pod: '
          '${report.renameReport.iosProductPodName ?? '-'}',
        )
        ..writeln(
          '  Dart capabilities inserted: '
          '${report.dartCapabilityReport?.inserted ?? 0}',
        )
        ..writeln('  Build exit code: ${report.buildExitCode}')
        ..writeln('  Artifact files copied: ${report.copiedArtifactFiles}')
        ..writeln('  Temporary workspace removed: ${report.workspaceRemoved}');
      return;
    }
    if (arguments.contains('--restore-dart-strings')) {
      final projectArgument = _projectArgument(arguments);
      if (projectArgument == null) {
        throw UsageException(
          '--restore-dart-strings requires --project=/absolute/project/path',
        );
      }
      final restored = await restoreDartStringTransaction(projectArgument);
      stdout.writeln(
        'Restored $restored Dart files from the string transaction.',
      );
      return;
    }
    if (arguments.contains('--dart-strings-build')) {
      stderr.writeln(
        'Warning: --dart-strings-build is a legacy single-feature entry. '
        'Prefer --transactional-build with --encrypt-dart-strings.',
      );
      final config = DartStringBuildConfig.fromArguments(arguments);
      final report = await DartStringCipherBuilder(config).run();
      stdout
        ..writeln('')
        ..writeln('Dart string protected build completed:')
        ..writeln('  Files: ${report.files}')
        ..writeln('  Strings: ${report.strings}')
        ..writeln('  Build exit code: ${report.buildExitCode}')
        ..writeln('  Sources restored: ${report.restored}');
      return;
    }
    if (arguments.contains('--restore-ios-assets')) {
      final projectArgument = _projectArgument(arguments);
      if (projectArgument == null) {
        throw UsageException(
          '--restore-ios-assets requires --project=/absolute/project/path',
        );
      }
      final restored = await restoreIosAssetTransaction(projectArgument);
      stdout.writeln('Restored $restored source images from the transaction.');
      return;
    }
    if (arguments.contains('--ios-assets-build')) {
      stderr.writeln(
        'Warning: --ios-assets-build is a legacy single-feature entry. '
        'Prefer --transactional-build with --containerize-ios-assets.',
      );
      final config = IosAssetBuildConfig.fromArguments(arguments);
      final report = await IosAssetContainerBuilder(config).run();
      stdout
        ..writeln('')
        ..writeln('iOS encrypted asset build completed:')
        ..writeln('  Images: ${report.images}')
        ..writeln('  Animations: ${report.animations}')
        ..writeln('  Audio: ${report.audio}')
        ..writeln('  Plain bytes: ${report.plainBytes}')
        ..writeln('  Container bytes: ${report.containerBytes}')
        ..writeln('  Build exit code: ${report.buildExitCode}')
        ..writeln('  Sources restored: ${report.restored}');
      return;
    }
    if (arguments.contains('--restore')) {
      final config = RestoreConfig.fromArguments(arguments);
      final report = await PrefixRestorer(config).run();
      stdout
        ..writeln('')
        ..writeln('Restore completed:')
        ..writeln('  Files restored: ${report.restoredFiles}')
        ..writeln('  Directories restored: ${report.restoredDirectories}')
        ..writeln('  Classes restored: ${report.restoredClasses}')
        ..writeln(
          '  Class declaration/reference edits: ${report.restoredClassReferences}',
        )
        ..writeln('  URI directives restored: ${report.restoredUris}')
        ..writeln('  Assets restored: ${report.restoredAssets}')
        ..writeln(
          '  iOS product Pod files restored: '
          '${report.restoredIosProductPodFiles}',
        )
        ..writeln('  Asset path edits: ${report.restoredAssetReferences}')
        ..writeln(
          '  Analyzer errors: ${report.baselineErrors} -> ${report.finalErrors}',
        );
      if (!report.verificationPassed) {
        stderr.writeln(
          'Restore verification failed with ${report.newErrors.length} new Analyzer errors.',
        );
        exitCode = 2;
      }
      return;
    }
    if (arguments.contains('--bind-ipa')) {
      final config = IpaBindingConfig.fromArguments(arguments);
      final report = await IpaBinder(config).run();
      stdout
        ..writeln('')
        ..writeln('IPA build identity bound:')
        ..writeln('  Manifest: ${report.manifestPath}')
        ..writeln('  IPA SHA-256: ${report.ipaSha256}')
        ..writeln('  IPA size: ${report.ipaSize}')
        ..writeln('  Main bundle SHA-256: ${report.mainBundleSha256}')
        ..writeln('  Components: ${report.components.length}')
        ..writeln('  Tool version: ${report.toolVersion}')
        ..writeln('  Prefix: ${report.prefix ?? '-'}')
        ..writeln('  Seed: ${report.seed?.toString() ?? '-'}')
        ..writeln('  Built at: ${report.builtAt.toIso8601String()}')
        ..writeln('  Lockfile SHA-256: ${report.lockfileSha256 ?? '-'}')
        ..writeln('  Already bound: ${report.alreadyBound}');
      return;
    }
    final config = RenameConfig.fromArguments(arguments);
    final report = await PrefixRenamer(config).run();
    stdout
      ..writeln('')
      ..writeln('Rename completed:')
      ..writeln('  Files renamed: ${report.renamedFiles}')
      ..writeln('  Directories renamed: ${report.renamedDirectories}')
      ..writeln('  Classes renamed: ${report.renamedClasses}')
      ..writeln('  URI directives rewritten: ${report.rewrittenUris}')
      ..writeln(
        '  Class declaration/reference edits: ${report.updatedClassReferences}',
      )
      ..writeln('  Assets renamed: ${report.renamedAssets}')
      ..writeln('  Asset path edits: ${report.updatedAssetReferences}')
      ..writeln('  Junk files generated: ${report.generatedJunkFiles}')
      ..writeln('  Junk classes generated: ${report.generatedJunkClasses}')
      ..writeln('  Images encrypted: ${report.encryptedImages}')
      ..writeln('  Animations encrypted: ${report.encryptedAnimations}')
      ..writeln('  Audio encrypted: ${report.encryptedAudio}')
      ..writeln(
        '  Asset plaintext bytes removed: ${report.encryptedImagePlainBytes}',
      )
      ..writeln('  Dart files encrypted: ${report.encryptedDartFiles}')
      ..writeln('  Dart strings encrypted: ${report.encryptedDartStrings}')
      ..writeln(
        '  iOS MethodChannels renamed: ${report.renamedIosMethodChannels}',
      )
      ..writeln(
        '  iOS dummy MethodChannels: ${report.generatedIosMethodChannels}',
      )
      ..writeln(
        '  MethodChannel edits (Dart/iOS): '
        '${report.iosMethodChannelDartEdits}/'
        '${report.iosMethodChannelNativeEdits}',
      )
      ..writeln('  iOS product Pod: ${report.iosProductPodName ?? '-'}')
      ..writeln('  iOS product Pod theme: ${report.iosProductPodTheme ?? '-'}')
      ..writeln(
        '  iOS product Pod seed: ${report.iosProductPodSeed?.toString() ?? '-'}',
      )
      ..writeln(
        '  iOS product Pod files (source/resource/total): '
        '${report.iosProductPodSourceFiles}/'
        '${report.iosProductPodResourceFiles}/'
        '${report.iosProductPodGeneratedFiles}',
      )
      ..writeln(
        '  iOS product Pod manifest SHA-256: '
        '${report.iosProductPodManifestHash ?? '-'}',
      )
      ..writeln(
        '  Dart capabilities (planned/reachable): '
        '${report.capabilitiesPlanned}/${report.capabilitiesReachable}',
      )
      ..writeln(
        '  Native capabilities (enabled/called): '
        '${report.nativeCapabilitiesEnabled}/${report.nativeCapabilitiesCalled}',
      )
      ..writeln('  Dependencies justified: ${report.dependenciesJustified}')
      ..writeln('  Metadata entities reset: ${report.metadataEntitiesReset}')
      ..writeln(
        '  Metadata reset at: ${report.metadataResetAt?.toIso8601String() ?? '-'}',
      )
      ..writeln(
        '  Analyzer errors: ${report.baselineErrors} -> ${report.finalErrors}',
      );

    if (!report.verificationPassed) {
      stderr
        ..writeln('')
        ..writeln(
          'Verification failed with ${report.newErrors.length} new Analyzer errors:',
        );
      for (final error in report.newErrors.take(20)) {
        stderr.writeln('  $error');
      }
      if (report.newErrors.length > 20) {
        stderr.writeln('  ... ${report.newErrors.length - 20} more');
      }
      exitCode = 2;
    }
  } on UsageException catch (error) {
    final sink = error.exitCode == 0 ? stdout : stderr;
    sink.writeln(error.message);
    exitCode = error.exitCode;
  } on Object catch (error, stackTrace) {
    stderr
      ..writeln('Rename failed: $error')
      ..writeln(stackTrace);
    exitCode = 1;
  }
}

String? _projectArgument(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final value = arguments[index];
    if (value.startsWith('--project=')) {
      return value.substring('--project='.length);
    }
    if ((value == '--project' || value == '-p') &&
        index + 1 < arguments.length) {
      return arguments[index + 1];
    }
  }
  return null;
}
