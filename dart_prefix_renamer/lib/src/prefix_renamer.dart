import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'add_junk_code.dart';
import 'asset_renamer.dart';
import 'capabilities/capability_pipeline.dart';
import 'config.dart';
import 'dart_string_cipher.dart';
import 'ios_asset_container.dart';
import 'ios_method_channel_diff.dart';
import 'ios_product_pod.dart';
import 'metadata_resetter.dart';
import 'project_copier.dart';
import 'project_layout.dart';
import 'report.dart';
import 'source_edit.dart';
import 'validator.dart';

final class PrefixRenamer {
  PrefixRenamer(this.config);

  final RenameConfig config;

  Future<RenameReport> run() async {
    stdout.writeln('Copying project to ${config.outputPath}');
    await copyProject(
      sourcePath: config.projectPath,
      destinationPath: config.outputPath,
    );

    if (config.runPubGet) {
      stdout.writeln('Resolving dependencies with FVM Flutter...');
      await runPubGet(config.outputPath);
    }

    final baseline = config.verify
        ? await captureAnalyzerErrors(config.outputPath)
        : AnalyzerSnapshot(const []);
    CapabilityPipelineReport? capabilityReport;
    if (config.capabilities.enabled) {
      stdout.writeln('Preparing manifest-driven capabilities...');
      capabilityReport = await CapabilityPipeline(
        CapabilityPipelineConfig(
          projectRoot: config.outputPath,
          targetPaths: config.targetPaths
              .map((target) => p.relative(target, from: config.projectPath))
              .toList(growable: false),
          productProfilePath: config.capabilities.productProfilePath,
          dartCapabilitiesPath: config.capabilities.dartCapabilitiesPath,
          nativeCapabilitiesPath: config.capabilities.nativeCapabilitiesPath,
          dependenciesPath: config.capabilities.dependenciesPath,
          libraryPoolPath: config.capabilities.libraryPoolPath,
          reportDirectory: config.capabilities.reportDirectory,
          seed: config.capabilities.seed,
        ),
      ).run();
      if (!capabilityReport.passed) {
        throw StateError(
          'Capability preparation failed; inspect generated reports.',
        );
      }
    }
    if (config.generateJunkCode) {
      stdout.writeln('Resetting generated Dart junk directory...');
      final junkDirectory = Directory(
        p.join(config.outputPath, 'lib', 'pack', 'junk_code'),
      );
      if (junkDirectory.existsSync()) {
        await junkDirectory.delete(recursive: true);
      }
    }

    final outputTargets = config.targetPaths
        .map(
          (target) => p.join(
            config.outputPath,
            p.relative(target, from: config.projectPath),
          ),
        )
        .toList(growable: false);
    final projectLayout = ProjectLayout.discover(config.outputPath);
    final directoryPlan = config.renameDirectories
        ? _DirectoryRenamePlan.discover(
            targets: outputTargets,
            layout: projectLayout,
            prefix: config.prefix,
          )
        : _DirectoryRenamePlan.empty();
    final fileRenames = _buildFileRenames(
      outputTargets,
      config.prefix,
      pathTransformer: directoryPlan.transformPath,
    );
    final fileRenameIndex = _FileRenameIndex(fileRenames);
    final assetPlan = config.renameAssets || config.renameDirectories
        ? AssetRenamePlan.discover(
            layout: projectLayout,
            prefix: config.prefix,
            pathTransformer: directoryPlan.transformPath,
            renameFiles: config.renameAssets,
          )
        : AssetRenamePlan.empty();
    _validateIntermediateFileRenames(fileRenames);
    _validateIntermediateFileRenames(assetPlan.fileRenames);

    stdout.writeln('Analyzing project and planning semantic edits...');
    final analysis = await _analyzeProject(
      projectPath: config.outputPath,
      targetPaths: outputTargets,
      prefix: config.prefix,
    );

    final editsByFile = <String, List<SourceEdit>>{};
    var rewrittenUris = 0;
    var updatedClassReferences = 0;
    var updatedAssetReferences = 0;
    for (final unit in analysis.units) {
      final uriVisitor = _UriEditVisitor(
        currentFilePath: unit.path,
        projectPath: config.outputPath,
        projectLayout: projectLayout,
        fileRenames: fileRenameIndex,
      );
      unit.unit.accept(uriVisitor);
      rewrittenUris += uriVisitor.edits.length;
      editsByFile.putIfAbsent(unit.path, () => []).addAll(uriVisitor.edits);

      final classVisitor = _ClassEditVisitor(analysis.classRenamesByElementKey);
      unit.unit.accept(classVisitor);
      updatedClassReferences += classVisitor.referenceEditCount;
      editsByFile.putIfAbsent(unit.path, () => []).addAll(classVisitor.edits);

      final assetVisitor = AssetStringEditVisitor(
        currentPackage: projectLayout.packageForPath(unit.path),
        plan: assetPlan,
      );
      unit.unit.accept(assetVisitor);
      updatedAssetReferences += assetVisitor.edits.length;
      editsByFile.putIfAbsent(unit.path, () => []).addAll(assetVisitor.edits);
    }

    stdout.writeln('Applying edits to ${editsByFile.length} files...');
    for (final entry in editsByFile.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final file = File(entry.key);
      final source = await file.readAsString();
      await file.writeAsString(applySourceEdits(source, entry.value));
    }

    for (final entry in assetPlan.pubspecEdits.entries) {
      final file = File(entry.key);
      final source = await file.readAsString();
      await file.writeAsString(applySourceEdits(source, entry.value));
      updatedAssetReferences += entry.value.length;
    }

    stdout.writeln('Renaming ${fileRenames.length} Dart files...');
    for (final entry in fileRenames.entries) {
      final intermediate = p.join(
        p.dirname(entry.key),
        p.basename(entry.value),
      );
      if (entry.key != intermediate) await File(entry.key).rename(intermediate);
    }
    await _writeRootEntrypointBridge(
      projectPath: config.outputPath,
      fileRenames: fileRenames,
    );
    stdout.writeln('Renaming ${assetPlan.fileRenames.length} asset files...');
    for (final entry in assetPlan.fileRenames.entries) {
      final intermediate = p.join(
        p.dirname(entry.key),
        p.basename(entry.value),
      );
      if (entry.key != intermediate) await File(entry.key).rename(intermediate);
    }
    if (directoryPlan.renames.isNotEmpty) {
      stdout.writeln(
        'Renaming ${directoryPlan.renames.length} lib directories...',
      );
      await directoryPlan.apply();
    }

    IosAssetBuildReport? encryptedAssetReport;
    if (config.containerizeIosAssets) {
      stdout.writeln('Encrypting and containerizing assets in output copy...');
      encryptedAssetReport = await IosAssetContainerBuilder(
        IosAssetBuildConfig(
          projectPath: config.outputPath,
          assetDirectories: config.assetDirectories,
          animationAssetDirectories: config.animationAssetDirectories,
          audioAssetDirectories: config.audioAssetDirectories,
          containerDirectory: config.containerDirectory,
          runtimeConfigPath: _renamedOutputPath(
            projectRelativePath: config.assetRuntimeConfig,
            fileRenames: fileRenames,
            directoryPlan: directoryPlan,
          ),
        ),
      ).applyPermanently();
    }

    DartStringBuildReport? encryptedStringReport;
    if (config.encryptDartStrings) {
      stdout.writeln('Encrypting marked Dart strings in output copy...');
      encryptedStringReport = await DartStringCipherBuilder(
        DartStringBuildConfig(
          projectPath: config.outputPath,
          runtimeConfigPath: _renamedOutputPath(
            projectRelativePath: config.stringRuntimeConfig,
            fileRenames: fileRenames,
            directoryPlan: directoryPlan,
          ),
          methodName: config.decryptMethod,
        ),
      ).applyPermanently();
    }

    AddJunkCodeReport? junkReport;
    if (config.generateJunkCode) {
      stdout.writeln('Running migrated AddJunkCode generator...');
      junkReport = await AddJunkCode(config.outputPath).addJunkCode();
    }

    IosMethodChannelDiffReport? iosMethodChannelReport;
    if (config.iosMethodChannelDiff) {
      stdout.writeln('Differentiating FlutterMethodChannels for iOS IPA...');
      // 文件/目录可能已在前面的流程中改名，因此入口必须先转换成输出副本中的实际路径。
      final entrypoints = config.iosMethodChannelEntrypoints
          .map((relative) {
            final transformed = _renamedOutputPath(
              projectRelativePath: relative,
              fileRenames: fileRenames,
              directoryPlan: directoryPlan,
            );
            return p.relative(transformed, from: config.outputPath);
          })
          .toList(growable: false);
      iosMethodChannelReport = await IosMethodChannelDifferentiator(
        IosMethodChannelDiffConfig(
          projectPath: config.outputPath,
          prefix: config.prefix,
          includes: config.iosMethodChannelIncludes,
          excludes: config.iosMethodChannelExcludes,
          dummyCount: config.iosDummyMethodChannelCount,
          entrypoints: entrypoints,
          seed: config.iosMethodChannelSeed,
        ),
      ).apply();
    }

    IosProductPodReport? iosProductPodReport;
    if (config.iosProductPod) {
      stdout.writeln('Generating deterministic local iOS product Pod...');
      // 必须在 Dart/Asset 改名之后生成，防止新客户端再次被前缀流程改写；
      // 同时必须早于最终 Analyzer 和 metadata reset，让新增文件参与校验与重置。
      // Generate after renaming, but before final analysis and metadata reset.
      iosProductPodReport = await IosProductPodGenerator(
        IosProductPodConfig(
          projectPath: config.outputPath,
          prefix: config.prefix,
          productId: config.iosProductId!,
          theme: config.iosProductTheme,
          seed: config.iosProductPodSeed,
        ),
      ).generate();
    }

    final metadataResetAt = config.resetMetadata ? DateTime.now() : null;
    final capabilityArtifacts = <String, String>{};
    for (final generated
        in capabilityReport?.generatedArtifactFiles ?? const <String>[]) {
      final actual =
          fileRenames[generated] ?? directoryPlan.transformPath(generated);
      final file = File(actual);
      if (file.existsSync()) {
        capabilityArtifacts[p.posix.joinAll(
          p.split(p.relative(actual, from: config.outputPath)),
        )] = sha256
            .convert(await file.readAsBytes())
            .toString();
      }
    }
    await _writeManifest(
      projectPath: config.outputPath,
      prefix: config.prefix,
      targetPaths: outputTargets,
      fileRenames: fileRenames,
      directoryRenames: directoryPlan.renames,
      classRenames: analysis.classRenamesByElementKey,
      assetRenames: assetPlan.fileRenames,
      junkEnabled: config.generateJunkCode,
      junkReport: junkReport,
      encryptedAssetReport: encryptedAssetReport,
      encryptedStringReport: encryptedStringReport,
      iosMethodChannelReport: iosMethodChannelReport,
      iosProductPodReport: iosProductPodReport,
      capabilityReport: capabilityReport,
      capabilityArtifacts: capabilityArtifacts,
      metadataResetAt: metadataResetAt,
    );

    final finalSnapshot = config.verify
        ? await captureAnalyzerErrors(config.outputPath)
        : AnalyzerSnapshot(const []);
    final newErrors = config.verify
        ? findNewErrors(baseline, finalSnapshot)
        : const <String>[];
    MetadataResetReport? metadataReport;
    if (config.resetMetadata) {
      stdout.writeln('Resetting output project metadata...');
      metadataReport = await resetProjectMetadata(
        projectPath: config.outputPath,
        resetAt: metadataResetAt,
      );
    }
    return RenameReport(
      renamedFiles: fileRenames.length,
      renamedDirectories: directoryPlan.renames.length,
      renamedClasses: analysis.classRenamesByElementKey.length,
      rewrittenUris: rewrittenUris,
      updatedClassReferences: updatedClassReferences,
      renamedAssets: assetPlan.fileRenames.length,
      updatedAssetReferences: updatedAssetReferences,
      generatedJunkFiles: junkReport?.files ?? 0,
      generatedJunkClasses: junkReport?.classes ?? 0,
      metadataEntitiesReset: metadataReport?.entities ?? 0,
      metadataResetAt: metadataReport?.resetAt,
      encryptedImages: encryptedAssetReport?.images ?? 0,
      encryptedAnimations: encryptedAssetReport?.animations ?? 0,
      encryptedAudio: encryptedAssetReport?.audio ?? 0,
      encryptedImagePlainBytes: encryptedAssetReport?.plainBytes ?? 0,
      encryptedDartFiles: encryptedStringReport?.files ?? 0,
      encryptedDartStrings: encryptedStringReport?.strings ?? 0,
      renamedIosMethodChannels: iosMethodChannelReport?.renames.length ?? 0,
      generatedIosMethodChannels:
          iosMethodChannelReport?.dummyNames.length ?? 0,
      iosMethodChannelDartEdits: iosMethodChannelReport?.dartEdits ?? 0,
      iosMethodChannelNativeEdits: iosMethodChannelReport?.iosEdits ?? 0,
      iosProductPodName: iosProductPodReport?.podName,
      iosProductPodTheme: iosProductPodReport?.theme,
      iosProductPodSeed: iosProductPodReport?.seed,
      iosProductPodSourceFiles: iosProductPodReport?.sourceFiles ?? 0,
      iosProductPodResourceFiles: iosProductPodReport?.resourceFiles ?? 0,
      iosProductPodGeneratedFiles: iosProductPodReport?.generatedFiles ?? 0,
      iosProductPodManifestHash: iosProductPodReport?.manifestHash,
      capabilitiesPlanned:
          capabilityReport?.dartReport.capabilitiesPlanned ?? 0,
      capabilitiesReachable:
          capabilityReport?.dartReport.capabilitiesReachable ?? 0,
      nativeCapabilitiesEnabled:
          capabilityReport?.nativeReport.enabledCount ?? 0,
      nativeCapabilitiesCalled: capabilityReport?.nativeReport.calledCount ?? 0,
      dependenciesJustified: capabilityReport?.dependencyReport.justified ?? 0,
      baselineErrors: baseline.errors.length,
      finalErrors: finalSnapshot.errors.length,
      newErrors: newErrors,
    );
  }

  String _renamedOutputPath({
    required String projectRelativePath,
    required Map<String, String> fileRenames,
    required _DirectoryRenamePlan directoryPlan,
  }) {
    final original = p.normalize(
      p.absolute(config.outputPath, projectRelativePath),
    );
    return fileRenames[original] ?? directoryPlan.transformPath(original);
  }
}

final class PrefixRestorer {
  PrefixRestorer(this.config);

  final RestoreConfig config;

  Future<RestoreReport> run() async {
    final manifestFile = File(config.manifestPath);
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Rename manifest root must be a JSON object.');
    }
    final version = decoded['version'] as int? ?? 1;
    if (version != 1 && version != 2) {
      throw FormatException('Unsupported rename manifest version: $version');
    }
    if (decoded['restoredAt'] != null) {
      throw StateError(
        'This manifest was already restored at ${decoded['restoredAt']}.',
      );
    }
    await restoreIosMethodChannelDiff(
      projectPath: config.projectPath,
      manifest: decoded,
    );
    // 先移除额外 Dart 客户端和原生注入，再分析并恢复原有 Dart 符号，
    // 避免生成文件干扰 restore 阶段的语义扫描。
    // Remove generated integration before semantic restoration of app sources.
    final restoredIosProductPodFiles = await restoreIosProductPod(
      projectPath: config.projectPath,
      manifest: decoded,
    );
    final files = _stringMap(decoded['files'], 'files');
    final directories = decoded['directories'] == null
        ? <String, String>{}
        : _stringMap(decoded['directories'], 'directories');
    final assets = _stringMap(decoded['assets'], 'assets');
    final classesValue = decoded['classes'];
    if (classesValue is! Map<String, dynamic>) {
      throw FormatException('Manifest classes must be a JSON object.');
    }

    final fileRenames = <String, String>{
      for (final entry in files.entries)
        p.join(config.projectPath, entry.value): p.join(
          config.projectPath,
          entry.key,
        ),
    };
    final assetRenames = <String, String>{
      for (final entry in assets.entries)
        p.join(config.projectPath, entry.value): p.join(
          config.projectPath,
          entry.key,
        ),
    };
    final directoryRenames = <String, String>{
      for (final entry in directories.entries)
        p.join(config.projectPath, entry.value): p.join(
          config.projectPath,
          entry.key,
        ),
    };
    _validateRestoreRenames(fileRenames, allowRootBridge: true);
    _validateRestoreRenames(assetRenames);
    _validateRestoreDirectories(directoryRenames);

    final baseline = config.verify
        ? await captureAnalyzerErrors(config.projectPath)
        : AnalyzerSnapshot(const []);
    stdout.writeln('Analyzing renamed project for semantic restore...');
    final analysis = await _analyzeProject(
      projectPath: config.projectPath,
      targetPaths: const [],
      prefix: 'restore',
    );
    final layout = ProjectLayout.discover(config.projectPath);
    final inverseClasses = <String, _ClassRename>{};
    for (final entry in classesValue.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic> ||
          value['original'] is! String ||
          value['replacement'] is! String) {
        throw FormatException('Invalid class mapping: ${entry.key}');
      }
      final separator = entry.key.lastIndexOf('#');
      if (separator <= 0) {
        throw FormatException('Invalid class element key: ${entry.key}');
      }
      final originalUri = entry.key.substring(0, separator);
      final originalPath = layout.resolvePackageUri(originalUri);
      if (originalPath == null) {
        throw StateError('Cannot resolve class library URI: $originalUri');
      }
      final originalRelative = _posixRelative(originalPath, config.projectPath);
      final renamedRelative = files[originalRelative] ?? originalRelative;
      final renamedPath = p.join(config.projectPath, renamedRelative);
      final renamedUri = layout.packageUriForPath(renamedPath);
      if (renamedUri == null) {
        throw StateError('Cannot build renamed class URI for $renamedPath');
      }
      final replacement = value['replacement'] as String;
      final currentUri = Platform.isMacOS || Platform.isWindows
          ? renamedUri.toLowerCase()
          : renamedUri;
      inverseClasses['$currentUri#$replacement'] = _ClassRename(
        originalName: replacement,
        replacementName: value['original'] as String,
      );
    }

    final uriIndex = _FileRenameIndex(fileRenames);
    final assetRestore = _AssetRestoreIndex(
      projectPath: config.projectPath,
      layout: layout,
      manifestAssets: assets,
      manifestDirectories: directories,
    );
    final editsByFile = <String, List<SourceEdit>>{};
    var restoredUris = 0;
    var restoredClassReferences = 0;
    var restoredAssetReferences = 0;
    for (final unit in analysis.units) {
      final classVisitor = _ClassEditVisitor(inverseClasses);
      unit.unit.accept(classVisitor);
      editsByFile.putIfAbsent(unit.path, () => []).addAll(classVisitor.edits);
      restoredClassReferences += classVisitor.referenceEditCount;

      final uriVisitor = _UriEditVisitor(
        currentFilePath: unit.path,
        projectPath: config.projectPath,
        projectLayout: layout,
        fileRenames: uriIndex,
      );
      unit.unit.accept(uriVisitor);
      editsByFile.putIfAbsent(unit.path, () => []).addAll(uriVisitor.edits);
      restoredUris += uriVisitor.edits.length;

      final assetVisitor = _AssetRestoreVisitor(
        currentPackage: layout.packageForPath(unit.path),
        index: assetRestore,
      );
      unit.unit.accept(assetVisitor);
      editsByFile.putIfAbsent(unit.path, () => []).addAll(assetVisitor.edits);
      restoredAssetReferences += assetVisitor.edits.length;
    }

    for (final entry in editsByFile.entries) {
      if (entry.value.isEmpty) continue;
      final file = File(entry.key);
      final source = await file.readAsString();
      await file.writeAsString(applySourceEdits(source, entry.value));
    }
    restoredAssetReferences += await assetRestore.restorePubspecs();

    final rootMain = File(p.join(config.projectPath, 'lib', 'main.dart'));
    if (files.containsKey('lib/main.dart') && rootMain.existsSync()) {
      final source = await rootMain.readAsString();
      if (!_isGeneratedRootBridge(source)) {
        throw StateError('Refusing to replace non-generated lib/main.dart.');
      }
      await rootMain.delete();
    }
    for (final entry in fileRenames.entries) {
      final intermediate = p.join(
        p.dirname(entry.key),
        p.basename(entry.value),
      );
      if (entry.key != intermediate) await File(entry.key).rename(intermediate);
    }
    for (final entry in assetRenames.entries) {
      final intermediate = p.join(
        p.dirname(entry.key),
        p.basename(entry.value),
      );
      if (entry.key != intermediate) await File(entry.key).rename(intermediate);
    }
    final restoreDirectories = directoryRenames.keys.toList()
      ..sort((a, b) => p.split(b).length.compareTo(p.split(a).length));
    for (final source in restoreDirectories) {
      await Directory(source).rename(
        p.join(p.dirname(source), p.basename(directoryRenames[source]!)),
      );
    }
    final restoredCapabilityFiles = await _restoreCapabilityArtifacts(
      projectPath: config.projectPath,
      manifest: decoded,
    );

    final finalSnapshot = config.verify
        ? await captureAnalyzerErrors(config.projectPath)
        : AnalyzerSnapshot(const []);
    final newErrors = config.verify
        ? findNewErrors(baseline, finalSnapshot)
        : const <String>[];
    decoded['restoredAt'] = DateTime.now().toIso8601String();
    decoded['restore'] = {
      'files': fileRenames.length,
      'directories': directoryRenames.length,
      'classes': inverseClasses.length,
      'classReferenceEdits': restoredClassReferences,
      'uriEdits': restoredUris,
      'assets': assetRenames.length,
      'assetReferenceEdits': restoredAssetReferences,
      'iosProductPodFiles': restoredIosProductPodFiles,
      'capabilityFiles': restoredCapabilityFiles,
    };
    await manifestFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
    );
    return RestoreReport(
      restoredFiles: fileRenames.length,
      restoredDirectories: directoryRenames.length,
      restoredClasses: inverseClasses.length,
      restoredClassReferences: restoredClassReferences,
      restoredUris: restoredUris,
      restoredAssets: assetRenames.length,
      restoredAssetReferences: restoredAssetReferences,
      restoredIosProductPodFiles: restoredIosProductPodFiles,
      baselineErrors: baseline.errors.length,
      finalErrors: finalSnapshot.errors.length,
      newErrors: newErrors,
    );
  }
}

void _validateRestoreDirectories(Map<String, String> renames) {
  for (final entry in renames.entries) {
    if (!Directory(entry.key).existsSync()) {
      throw StateError('Renamed directory is missing: ${entry.key}');
    }
    final physicalDestination = p.join(
      p.dirname(entry.key),
      p.basename(entry.value),
    );
    if (FileSystemEntity.typeSync(physicalDestination) !=
        FileSystemEntityType.notFound) {
      throw StateError(
        'Restore directory destination already exists: $physicalDestination',
      );
    }
  }
}

Map<String, String> _stringMap(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('Manifest $field must be a JSON object.');
  }
  return value.map((key, value) {
    if (value is! String) {
      throw FormatException('Manifest $field value for $key must be a string.');
    }
    return MapEntry(key, value);
  });
}

void _validateRestoreRenames(
  Map<String, String> renames, {
  bool allowRootBridge = false,
}) {
  for (final entry in renames.entries) {
    if (!File(entry.key).existsSync()) {
      throw StateError('Renamed file is missing: ${entry.key}');
    }
    if (!File(entry.value).existsSync()) continue;
    if (allowRootBridge &&
        p.basename(entry.value) == 'main.dart' &&
        p.basename(entry.key).endsWith('_main.dart')) {
      continue;
    }
    throw StateError('Restore destination already exists: ${entry.value}');
  }
}

bool _isGeneratedRootBridge(String source) => source.startsWith(
  '// Generated by dart_prefix_renamer. Keep Flutter\'s default entrypoint stable.',
);

String _posixRelative(String path, String root) =>
    p.posix.joinAll(p.split(p.relative(path, from: root)));

final class _AssetRestoreIndex {
  _AssetRestoreIndex({
    required this.projectPath,
    required this.layout,
    required Map<String, String> manifestAssets,
    required Map<String, String> manifestDirectories,
  }) {
    void addMapping(MapEntry<String, String> entry) {
      final originalPath = p.join(projectPath, entry.key);
      final renamedPath = p.join(projectPath, entry.value);
      final package = layout.packageForPath(originalPath);
      if (package == null) return;
      final original = _posixRelative(originalPath, package.rootPath);
      final renamed = _posixRelative(renamedPath, package.rootPath);
      byPackage.putIfAbsent(package.name, () => {})[renamed] = original;
      qualified['packages/${package.name}/$renamed'] =
          'packages/${package.name}/$original';
      final existing = unqualified[renamed];
      if (existing == null && !ambiguous.contains(renamed)) {
        unqualified[renamed] = original;
      } else if (existing != original) {
        unqualified.remove(renamed);
        ambiguous.add(renamed);
      }
    }

    for (final entry in manifestAssets.entries) {
      addMapping(entry);
    }
    for (final entry in manifestDirectories.entries) {
      addMapping(entry);
    }
  }

  final String projectPath;
  final ProjectLayout layout;
  final byPackage = <String, Map<String, String>>{};
  final qualified = <String, String>{};
  final unqualified = <String, String>{};
  final ambiguous = <String>{};

  String? replacement(ProjectPackage? package, String value) =>
      qualified[value] ??
      (package == null ? null : byPackage[package.name]?[value]) ??
      unqualified[value];

  Future<int> restorePubspecs() async {
    var edits = 0;
    for (final package in layout.packages.values) {
      final mappings = byPackage[package.name];
      if (mappings == null || mappings.isEmpty) continue;
      final file = File(package.pubspecPath);
      var source = await file.readAsString();
      for (final entry
          in mappings.entries.toList()
            ..sort((a, b) => b.key.length.compareTo(a.key.length))) {
        final count = entry.key.allMatches(source).length;
        if (count > 0) {
          source = source.replaceAll(entry.key, entry.value);
          edits += count;
        }
      }
      await file.writeAsString(source);
    }
    return edits;
  }
}

final class _AssetRestoreVisitor extends RecursiveAstVisitor<void> {
  _AssetRestoreVisitor({required this.currentPackage, required this.index});
  final ProjectPackage? currentPackage;
  final _AssetRestoreIndex index;
  final edits = <SourceEdit>[];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.stringValue;
    final replacement = value == null
        ? null
        : index.replacement(currentPackage, value);
    if (replacement != null && replacement != value) {
      edits.add(
        SourceEdit(
          offset: node.contentsOffset,
          length: node.contentsEnd - node.contentsOffset,
          replacement: replacement,
          reason: 'restore asset path',
        ),
      );
    }
    super.visitSimpleStringLiteral(node);
  }
}

Future<void> _writeRootEntrypointBridge({
  required String projectPath,
  required Map<String, String> fileRenames,
}) async {
  final originalPath = p.join(projectPath, 'lib', 'main.dart');
  final renamedPath = fileRenames[originalPath];
  if (renamedPath == null) {
    return;
  }
  final renamedBasename = p.basename(renamedPath);
  await File(originalPath).writeAsString('''
// Generated by dart_prefix_renamer. Keep Flutter's default entrypoint stable.
import '$renamedBasename' as renamed_entrypoint;

void main() {
  renamed_entrypoint.main();
}
''');
}

Map<String, String> _buildFileRenames(
  List<String> targetPaths,
  String prefix, {
  required String Function(String path) pathTransformer,
}) {
  final renames = <String, String>{};
  final destinations = <String>{};
  for (final targetPath in targetPaths) {
    for (final entity in Directory(
      targetPath,
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      // Legacy AddJunkCode files form a generated subgraph with hundreds of
      // relative imports. They are replaced by the themed-module phase and
      // must not be partially renamed while Analyzer intentionally skips them.
      if (_isLegacyJunkCodePath(entity.path)) {
        continue;
      }
      if (renames.containsKey(entity.path)) {
        continue;
      }
      final basename = p.basename(entity.path);
      final renamedBasename = basename.startsWith('${prefix}_')
          ? basename
          : '${prefix}_$basename';
      final destination = pathTransformer(
        p.join(p.dirname(entity.path), renamedBasename),
      );
      if (destination == entity.path) continue;
      if (!destinations.add(destination)) {
        throw StateError('Multiple files would be renamed to $destination');
      }
      if (FileSystemEntity.typeSync(destination) !=
              FileSystemEntityType.notFound &&
          !renames.containsKey(destination)) {
        throw StateError(
          'File rename destination already exists: $destination',
        );
      }
      renames[entity.path] = destination;
    }
  }
  return renames;
}

void _validateIntermediateFileRenames(Map<String, String> renames) {
  final destinations = <String>{};
  for (final entry in renames.entries) {
    final destination = p.join(p.dirname(entry.key), p.basename(entry.value));
    if (!destinations.add(destination)) {
      throw StateError('Multiple files would first be renamed to $destination');
    }
    if (FileSystemEntity.typeSync(destination) !=
            FileSystemEntityType.notFound &&
        !renames.containsKey(destination)) {
      throw StateError(
        'Intermediate file rename destination exists: $destination',
      );
    }
  }
}

final class _DirectoryRenamePlan {
  const _DirectoryRenamePlan(this.renames);

  factory _DirectoryRenamePlan.empty() => const _DirectoryRenamePlan({});

  factory _DirectoryRenamePlan.discover({
    required List<String> targets,
    required ProjectLayout layout,
    required String prefix,
  }) {
    final candidates = <String>{};
    for (final target in targets) {
      final package = layout.packageForPath(target);
      if (package == null ||
          (target != package.libPath && !p.isWithin(package.libPath, target))) {
        continue;
      }
      if (target != package.libPath &&
          !_isReservedLibDirectory(package, target)) {
        candidates.add(p.normalize(target));
      }
      for (final entity in Directory(
        target,
      ).listSync(recursive: true, followLinks: false).whereType<Directory>()) {
        if (!_isReservedLibDirectory(package, entity.path)) {
          candidates.add(p.normalize(entity.path));
        }
      }
    }
    candidates.removeWhere(
      (directory) => p.basename(directory).startsWith('${prefix}_'),
    );
    final renames = <String, String>{};
    final ordered = candidates.toList()
      ..sort((a, b) => p.split(a).length.compareTo(p.split(b).length));
    for (final directory in ordered) {
      var parent = p.dirname(directory);
      final renamedParent = renames[parent];
      if (renamedParent != null) parent = renamedParent;
      while (renames.containsKey(p.dirname(parent))) {
        parent = p.join(renames[p.dirname(parent)]!, p.basename(parent));
      }
      renames[directory] = p.join(parent, '${prefix}_${p.basename(directory)}');
    }
    final destinations = <String>{};
    for (final entry in renames.entries) {
      if (!destinations.add(entry.value)) {
        throw StateError(
          'Multiple directories would be renamed to ${entry.value}',
        );
      }
      if (FileSystemEntity.typeSync(entry.value) !=
              FileSystemEntityType.notFound &&
          !renames.containsKey(entry.value)) {
        throw StateError('Directory rename destination exists: ${entry.value}');
      }
      final physicalDestination = p.join(
        p.dirname(entry.key),
        p.basename(entry.value),
      );
      if (FileSystemEntity.typeSync(physicalDestination) !=
              FileSystemEntityType.notFound &&
          !renames.containsKey(physicalDestination)) {
        throw StateError(
          'Intermediate directory rename destination exists: $physicalDestination',
        );
      }
    }
    return _DirectoryRenamePlan(renames);
  }

  final Map<String, String> renames;

  String transformPath(String path) {
    var bestSource = '';
    String? bestDestination;
    for (final entry in renames.entries) {
      if ((path == entry.key || p.isWithin(entry.key, path)) &&
          entry.key.length > bestSource.length) {
        bestSource = entry.key;
        bestDestination = entry.value;
      }
    }
    if (bestDestination == null) return path;
    return p.join(bestDestination, p.relative(path, from: bestSource));
  }

  Future<void> apply() async {
    final ordered = renames.keys.toList()
      ..sort((a, b) => p.split(b).length.compareTo(p.split(a).length));
    for (final source in ordered) {
      final destination = renames[source]!;
      final physicalDestination = p.join(
        p.dirname(source),
        p.basename(destination),
      );
      await Directory(source).rename(physicalDestination);
    }
  }
}

bool _isReservedLibDirectory(ProjectPackage package, String directory) {
  final relative = p.posix.joinAll(
    p.split(p.relative(directory, from: package.libPath)),
  );
  return relative == 'pack' || relative.startsWith('pack/');
}

Future<void> _writeManifest({
  required String projectPath,
  required String prefix,
  required List<String> targetPaths,
  required Map<String, String> fileRenames,
  required Map<String, String> directoryRenames,
  required Map<String, _ClassRename> classRenames,
  required Map<String, String> assetRenames,
  required bool junkEnabled,
  required AddJunkCodeReport? junkReport,
  required IosAssetBuildReport? encryptedAssetReport,
  required DartStringBuildReport? encryptedStringReport,
  required IosMethodChannelDiffReport? iosMethodChannelReport,
  required IosProductPodReport? iosProductPodReport,
  required CapabilityPipelineReport? capabilityReport,
  required Map<String, String> capabilityArtifacts,
  required DateTime? metadataResetAt,
}) async {
  String relative(String path) =>
      p.posix.joinAll(p.split(p.relative(path, from: projectPath)));

  final manifest = <String, Object>{
    'version': capabilityReport == null ? 1 : 2,
    'prefix': prefix,
    'targets': targetPaths.map(relative).toList(growable: false)..sort(),
    'files': {
      for (final entry in fileRenames.entries)
        relative(entry.key): relative(entry.value),
    },
    'directories': {
      for (final entry in directoryRenames.entries)
        relative(entry.key): relative(entry.value),
    },
    'classes': {
      for (final entry in classRenames.entries)
        entry.key: {
          'original': entry.value.originalName,
          'replacement': entry.value.replacementName,
        },
    },
    'assets': {
      for (final entry in assetRenames.entries)
        relative(entry.key): relative(entry.value),
    },
    'junkCode': {
      'enabled': junkEnabled,
      'generatedFiles': junkReport?.files ?? 0,
      'generatedClasses': junkReport?.classes ?? 0,
      'directory': junkReport == null ? null : relative(junkReport.directory),
    },
    'iosAssetContainer': {
      'enabled': encryptedAssetReport != null,
      'images': encryptedAssetReport?.images ?? 0,
      'animations': encryptedAssetReport?.animations ?? 0,
      'audio': encryptedAssetReport?.audio ?? 0,
      'plainBytes': encryptedAssetReport?.plainBytes ?? 0,
      'containerBytes': encryptedAssetReport?.containerBytes ?? 0,
    },
    'dartStringEncryption': {
      'enabled': encryptedStringReport != null,
      'files': encryptedStringReport?.files ?? 0,
      'strings': encryptedStringReport?.strings ?? 0,
    },
    'iosMethodChannelDiff': {
      'enabled': iosMethodChannelReport != null,
      'renames': iosMethodChannelReport?.renames ?? const <String, String>{},
      'dummyNames': iosMethodChannelReport?.dummyNames ?? const <String>[],
      'dartEdits': iosMethodChannelReport?.dartEdits ?? 0,
      'iosEdits': iosMethodChannelReport?.iosEdits ?? 0,
      'generatedDartFile': iosMethodChannelReport?.generatedDartFile == null
          ? null
          : relative(iosMethodChannelReport!.generatedDartFile!),
      'entrypoints':
          iosMethodChannelReport?.entrypoints
              .map(relative)
              .toList(growable: false) ??
          const <String>[],
      'iosInjectionFile': iosMethodChannelReport?.iosInjectionFile == null
          ? null
          : relative(iosMethodChannelReport!.iosInjectionFile!),
    },
    'iosProductPod': {
      'enabled': iosProductPodReport != null,
      'productId': iosProductPodReport?.productId,
      'podName': iosProductPodReport?.podName,
      'classPrefix': iosProductPodReport?.classPrefix,
      'theme': iosProductPodReport?.theme,
      'seed': iosProductPodReport?.seed,
      'channelName': iosProductPodReport?.channelName,
      'sourceFiles': iosProductPodReport?.sourceFiles ?? 0,
      'resourceFiles': iosProductPodReport?.resourceFiles ?? 0,
      'generatedFiles': iosProductPodReport?.generatedFiles ?? 0,
      'contentHash': iosProductPodReport?.contentHash,
      'manifestHash': iosProductPodReport?.manifestHash,
      'podDirectory': iosProductPodReport == null
          ? null
          : relative(iosProductPodReport.podDirectory),
      'dartClientFile': iosProductPodReport == null
          ? null
          : relative(iosProductPodReport.dartClientFile),
      'podfile': iosProductPodReport == null
          ? null
          : relative(iosProductPodReport.podfile),
      'appDelegate': iosProductPodReport == null
          ? null
          : relative(iosProductPodReport.appDelegate),
    },
    'capabilities': {
      'enabled': capabilityReport != null,
      'planned': capabilityReport?.dartReport.capabilitiesPlanned ?? 0,
      'reachable': capabilityReport?.dartReport.capabilitiesReachable ?? 0,
      'nativeEnabled': capabilityReport?.nativeReport.enabledCount ?? 0,
      'nativeCalled': capabilityReport?.nativeReport.calledCount ?? 0,
      'dependenciesJustified':
          capabilityReport?.dependencyReport.justified ?? 0,
      'thirdPartyEnabled':
          capabilityReport?.dependencyGeneration.enabled ?? false,
      'thirdPartyPodDirectory':
          capabilityReport?.dependencyGeneration.enabled == true
          ? relative(capabilityReport!.dependencyGeneration.podDirectory)
          : null,
      'artifacts': capabilityArtifacts,
    },
    'metadataReset': {
      'enabled': metadataResetAt != null,
      'resetAt': metadataResetAt?.toIso8601String(),
      'clearsExtendedAttributes': metadataResetAt != null,
    },
  };
  final encoder = JsonEncoder.withIndent('  ');
  await File(
    p.join(projectPath, 'dart_prefix_renamer_manifest.json'),
  ).writeAsString('${encoder.convert(manifest)}\n');
}

Future<int> _restoreCapabilityArtifacts({
  required String projectPath,
  required Map<String, dynamic> manifest,
}) async {
  final capabilities = manifest['capabilities'];
  if (capabilities is! Map<String, dynamic>) return 0;
  final artifacts = capabilities['artifacts'];
  if (artifacts is! Map<String, dynamic>) return 0;
  var restored = 0;
  for (final entry in artifacts.entries) {
    final relative = p.normalize(entry.key);
    if (p.isAbsolute(relative) ||
        relative == '..' ||
        relative.startsWith('../')) {
      throw FormatException('Unsafe capability artifact path: ${entry.key}');
    }
    final file = File(p.join(projectPath, relative));
    if (!file.existsSync()) continue;
    final actualHash = sha256.convert(await file.readAsBytes()).toString();
    if (actualHash != entry.value) {
      throw StateError(
        'Refusing to delete modified capability artifact: ${entry.key}',
      );
    }
    await file.delete();
    restored++;
  }
  await _removeGeneratedMarker(
    File(p.join(projectPath, 'ios', 'Podfile')),
    '# dart-prefix-renamer:native-capabilities:begin',
    '# dart-prefix-renamer:native-capabilities:end',
  );
  await _removeGeneratedMarker(
    File(p.join(projectPath, 'ios', 'Runner', 'AppDelegate.swift')),
    '// dart-prefix-renamer:native-capabilities:begin',
    '// dart-prefix-renamer:native-capabilities:end',
  );
  await _removeGeneratedMarker(
    File(p.join(projectPath, 'ios', 'Runner', 'AppDelegate.swift')),
    '// dart-prefix-renamer:native-capabilities-import:begin',
    '// dart-prefix-renamer:native-capabilities-import:end',
  );
  final nativeGeneratedDirectory = Directory(
    p.join(projectPath, 'ios', 'NativeCapabilities', 'Generated'),
  );
  if (nativeGeneratedDirectory.existsSync() &&
      nativeGeneratedDirectory.listSync().isEmpty) {
    await nativeGeneratedDirectory.delete();
  }
  final thirdPartyEnabled = capabilities['thirdPartyEnabled'] == true;
  if (thirdPartyEnabled) {
    await _removeGeneratedMarker(
      File(p.join(projectPath, 'ios', 'Podfile')),
      '# dart_prefix_renamer:third-party-pod-begin',
      '# dart_prefix_renamer:third-party-pod-end',
    );
    await _removeGeneratedMarker(
      File(p.join(projectPath, 'ios', 'Runner', 'AppDelegate.swift')),
      '// dart_prefix_renamer:third-party-import-begin',
      '// dart_prefix_renamer:third-party-import-end',
    );
    await _removeGeneratedMarker(
      File(p.join(projectPath, 'ios', 'Runner', 'AppDelegate.swift')),
      '// dart_prefix_renamer:third-party-start-begin',
      '// dart_prefix_renamer:third-party-start-end',
    );
    final podRelative = capabilities['thirdPartyPodDirectory'];
    if (podRelative is String && podRelative.isNotEmpty) {
      final normalized = p.normalize(podRelative);
      if (p.isAbsolute(normalized) ||
          normalized == '..' ||
          normalized.startsWith('../')) {
        throw FormatException('Unsafe third-party Pod path: $podRelative');
      }
      final directory = Directory(p.join(projectPath, normalized));
      if (directory.existsSync() &&
          directory.listSync(recursive: true).isEmpty) {
        await directory.delete(recursive: true);
      }
    }
    final result = await Process.run('pod', const [
      'install',
      '--project-directory=ios',
    ], workingDirectory: projectPath);
    if (result.exitCode != 0) {
      throw ProcessException(
        'pod',
        const ['install', '--project-directory=ios'],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
  }
  return restored;
}

Future<bool> _removeGeneratedMarker(File file, String begin, String end) async {
  if (!file.existsSync()) return false;
  final source = await file.readAsString();
  if (!source.contains(begin)) return false;
  final pattern = RegExp(
    '\\n?[ \\t]*${RegExp.escape(begin)}[\\s\\S]*?${RegExp.escape(end)}\\n?',
  );
  await file.writeAsString(source.replaceFirst(pattern, '\n'));
  return true;
}

final class _ResolvedProject {
  const _ResolvedProject({
    required this.units,
    required this.classRenamesByElementKey,
  });

  final List<ResolvedUnitResult> units;
  final Map<String, _ClassRename> classRenamesByElementKey;
}

final class _ClassRename {
  const _ClassRename({
    required this.originalName,
    required this.replacementName,
  });

  final String originalName;
  final String replacementName;
}

Future<_ResolvedProject> _analyzeProject({
  required String projectPath,
  required List<String> targetPaths,
  required String prefix,
}) async {
  final collection = AnalysisContextCollection(includedPaths: [projectPath]);
  final units = <ResolvedUnitResult>[];
  for (final context in collection.contexts) {
    for (final path in context.contextRoot.analyzedFiles()) {
      if (!path.endsWith('.dart') || !_isProjectSource(projectPath, path)) {
        continue;
      }
      final result = await context.currentSession.getResolvedUnit(path);
      if (result is ResolvedUnitResult) {
        units.add(result);
      }
    }
  }

  final classRenames = <String, _ClassRename>{};
  final namesByLibrary = <String, Set<String>>{};
  for (final unit in units) {
    for (final declaration
        in unit.unit.declarations.whereType<ClassDeclaration>()) {
      final element = declaration.declaredFragment?.element;
      if (element == null) {
        continue;
      }
      final libraryKey = _libraryKey(element);
      namesByLibrary
          .putIfAbsent(libraryKey, () => <String>{})
          .add(declaration.name.lexeme);
    }
  }
  for (final unit in units.where(
    (unit) => _isInTargets(unit.path, targetPaths),
  )) {
    for (final declaration
        in unit.unit.declarations.whereType<ClassDeclaration>()) {
      final element = declaration.declaredFragment?.element;
      if (element == null) {
        continue;
      }
      final originalName = declaration.name.lexeme;
      final replacementName = _prefixClassName(originalName, prefix);
      if (replacementName == originalName) {
        continue;
      }
      final libraryKey = _libraryKey(element);
      if (namesByLibrary[libraryKey]?.contains(replacementName) ?? false) {
        throw StateError(
          'Class rename collision in $libraryKey: $originalName -> $replacementName',
        );
      }
      classRenames[_elementKey(element)] = _ClassRename(
        originalName: originalName,
        replacementName: replacementName,
      );
    }
  }
  return _ResolvedProject(units: units, classRenamesByElementKey: classRenames);
}

bool _isProjectSource(String projectPath, String path) {
  if (path != projectPath && !p.isWithin(projectPath, path)) {
    return false;
  }
  final relativeParts = p.split(p.relative(path, from: projectPath));
  if (_isLegacyJunkCodePath(p.joinAll(relativeParts))) {
    return false;
  }
  return !relativeParts.any(
    const {'.dart_tool', '.git', 'build', 'Pods'}.contains,
  );
}

bool _isLegacyJunkCodePath(String path) {
  final parts = p.split(p.normalize(path));
  for (var index = 0; index + 2 < parts.length; index++) {
    if (parts[index] == 'lib' &&
        parts[index + 1] == 'pack' &&
        parts[index + 2] == 'junk_code') {
      return true;
    }
  }
  return false;
}

bool _isInTargets(String path, List<String> targets) =>
    targets.any((target) => path == target || p.isWithin(target, path));

String _prefixClassName(String name, String prefix) {
  final classPrefix = '${prefix[0].toUpperCase()}${prefix.substring(1)}';
  if (name.startsWith('_')) {
    final publicPart = name.substring(1);
    return publicPart.startsWith(classPrefix)
        ? name
        : '_$classPrefix$publicPart';
  }
  return name.startsWith(classPrefix) ? name : '$classPrefix$name';
}

String _libraryKey(InterfaceElement element) {
  final uri = element.firstFragment.libraryFragment.source.uri.toString();
  return Platform.isMacOS || Platform.isWindows ? uri.toLowerCase() : uri;
}

String _elementKey(InterfaceElement element) =>
    '${_libraryKey(element)}#${element.displayName}';

InterfaceElement? _interfaceElement(Element? element) {
  if (element is InterfaceElement) {
    return element;
  }
  if (element is ConstructorElement) {
    return element.enclosingElement;
  }
  return null;
}

final class _ClassEditVisitor extends RecursiveAstVisitor<void> {
  _ClassEditVisitor(this.renames);

  final Map<String, _ClassRename> renames;
  final List<SourceEdit> edits = [];
  int referenceEditCount = 0;

  void _addTokenForElement(
    int offset,
    int length,
    String lexeme,
    Element? element,
    String reason,
  ) {
    final interfaceElement = _interfaceElement(element);
    if (interfaceElement == null) {
      return;
    }
    final rename = renames[_elementKey(interfaceElement)];
    if (rename == null || lexeme != rename.originalName) {
      return;
    }
    edits.add(
      SourceEdit(
        offset: offset,
        length: length,
        replacement: rename.replacementName,
        reason: reason,
      ),
    );
    referenceEditCount++;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    _addTokenForElement(
      node.name.offset,
      node.name.length,
      node.name.lexeme,
      element,
      'class declaration',
    );
    super.visitClassDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final element = node.declaredFragment?.element.enclosingElement;
    _addTokenForElement(
      node.returnType.offset,
      node.returnType.length,
      node.returnType.name,
      element,
      'constructor declaration',
    );
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _addTokenForElement(
      node.name.offset,
      node.name.length,
      node.name.lexeme,
      node.element,
      'type reference',
    );
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _addTokenForElement(
      node.offset,
      node.length,
      node.name,
      node.element,
      'class reference',
    );
    super.visitSimpleIdentifier(node);
  }
}

final class _UriEditVisitor extends RecursiveAstVisitor<void> {
  _UriEditVisitor({
    required this.currentFilePath,
    required this.projectPath,
    required this.projectLayout,
    required this.fileRenames,
  });

  final String currentFilePath;
  final String projectPath;
  final ProjectLayout projectLayout;
  final _FileRenameIndex fileRenames;
  final List<SourceEdit> edits = [];

  void _visitUri(StringLiteral literal, {String? resolvedPath}) {
    if (literal is! SimpleStringLiteral) {
      return;
    }
    final uri = literal.stringValue;
    if (uri == null || uri.startsWith('dart:')) {
      return;
    }
    late final String referencedPath;
    final packagePath = projectLayout.resolvePackageUri(uri);
    final isPackageUri = uri.startsWith('package:');
    if (resolvedPath != null) {
      referencedPath = p.normalize(resolvedPath);
    } else if (packagePath != null) {
      referencedPath = packagePath;
    } else if (!uri.contains(':')) {
      referencedPath = p.normalize(p.join(p.dirname(currentFilePath), uri));
    } else {
      return;
    }
    final renamedPath = fileRenames.lookup(referencedPath);
    if (renamedPath == null) {
      return;
    }
    final renamedCurrentPath =
        fileRenames.lookup(currentFilePath) ?? currentFilePath;
    final fileRelativePath = p.relative(
      renamedPath,
      from: p.dirname(renamedCurrentPath),
    );
    var replacement = isPackageUri
        ? projectLayout.packageUriForPath(renamedPath)!
        : p.posix.joinAll(p.split(fileRelativePath));
    if (!isPackageUri && uri.startsWith('./') && !replacement.startsWith('.')) {
      replacement = './$replacement';
    }
    edits.add(
      SourceEdit(
        offset: literal.contentsOffset,
        length: literal.contentsEnd - literal.contentsOffset,
        replacement: replacement,
        reason: 'URI rewrite',
      ),
    );
  }

  @override
  void visitExportDirective(ExportDirective node) {
    _visitUri(
      node.uri,
      resolvedPath:
          node.libraryExport?.exportedLibrary?.firstFragment.source.fullName,
    );
    super.visitExportDirective(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    _visitUri(
      node.uri,
      resolvedPath:
          node.libraryImport?.importedLibrary?.firstFragment.source.fullName,
    );
    super.visitImportDirective(node);
  }

  @override
  void visitPartDirective(PartDirective node) {
    _visitUri(
      node.uri,
      resolvedPath: node.partInclude?.includedFragment?.source.fullName,
    );
    super.visitPartDirective(node);
  }

  @override
  void visitPartOfDirective(PartOfDirective node) {
    final uri = node.uri;
    if (uri != null) {
      _visitUri(uri);
    }
    super.visitPartOfDirective(node);
  }

  @override
  void visitConfiguration(Configuration node) {
    _visitUri(node.uri);
    super.visitConfiguration(node);
  }
}

final class _FileRenameIndex {
  _FileRenameIndex(this.exact) {
    for (final entry in exact.entries) {
      final folded = _foldPath(entry.key);
      if (ambiguousFoldedPaths.contains(folded)) {
        continue;
      }
      final existing = foldedPaths[folded];
      if (existing != null && existing != entry.value) {
        foldedPaths.remove(folded);
        ambiguousFoldedPaths.add(folded);
      } else {
        foldedPaths[folded] = entry.value;
      }
    }
  }

  final Map<String, String> exact;
  final Map<String, String> foldedPaths = {};
  final Set<String> ambiguousFoldedPaths = {};

  String? lookup(String path) =>
      exact[p.normalize(path)] ?? foldedPaths[_foldPath(path)];
}

String _foldPath(String path) => p.normalize(path).toLowerCase();
