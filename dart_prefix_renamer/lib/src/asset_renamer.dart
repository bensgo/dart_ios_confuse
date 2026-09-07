import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'project_layout.dart';
import 'source_edit.dart';

final class AssetRenamePlan {
  AssetRenamePlan._({
    required this.fileRenames,
    required this.pubspecEdits,
    required this.pathRenamesByPackage,
    required this.qualifiedPathRenames,
    required this.unqualifiedPathRenames,
  });

  factory AssetRenamePlan.discover({
    required ProjectLayout layout,
    required String prefix,
    String Function(String path)? pathTransformer,
    bool renameFiles = true,
  }) {
    final fileRenames = <String, String>{};
    final destinations = <String>{};
    final pubspecEdits = <String, List<SourceEdit>>{};
    final pathRenamesByPackage = <String, Map<String, String>>{};
    final qualifiedPathRenames = <String, String>{};
    final unqualifiedPathRenames = <String, String>{};
    final ambiguousUnqualifiedPaths = <String>{};

    for (final package in layout.packages.values) {
      final pubspecFile = File(package.pubspecPath);
      final source = pubspecFile.readAsStringSync();
      final document = loadYaml(source);
      if (document is! YamlMap) {
        continue;
      }
      final flutter = document['flutter'];
      final assets = flutter is YamlMap ? flutter['assets'] : null;
      if (assets is! YamlList) {
        continue;
      }
      final packagePaths = pathRenamesByPackage.putIfAbsent(
        package.name,
        () => <String, String>{},
      );
      for (final node in assets.nodes) {
        final declaredPath = node.value;
        if (declaredPath is! String || declaredPath.isEmpty) {
          continue;
        }
        final absolute = p.normalize(p.join(package.rootPath, declaredPath));
        if (absolute != package.rootPath &&
            !p.isWithin(package.rootPath, absolute)) {
          throw StateError(
            'Asset path escapes package ${package.name}: $declaredPath',
          );
        }
        final type = FileSystemEntity.typeSync(absolute);
        final assetFiles = <File>[];
        if (type == FileSystemEntityType.directory) {
          assetFiles.addAll(
            Directory(
              absolute,
            ).listSync(recursive: true, followLinks: false).whereType<File>(),
          );
        } else if (type == FileSystemEntityType.file) {
          assetFiles.add(File(absolute));
        }
        for (final assetFile in assetFiles) {
          if (fileRenames.containsKey(assetFile.path)) {
            continue;
          }
          final basename = p.basename(assetFile.path);
          if (basename.startsWith('.')) {
            continue;
          }
          final renamedBasename =
              !renameFiles || basename.startsWith('${prefix}_')
              ? basename
              : '${prefix}_$basename';
          final prefixedDestination = p.join(
            p.dirname(assetFile.path),
            renamedBasename,
          );
          final destination =
              pathTransformer?.call(prefixedDestination) ?? prefixedDestination;
          if (destination == assetFile.path) continue;
          if (!destinations.add(destination) ||
              (FileSystemEntity.typeSync(destination) !=
                      FileSystemEntityType.notFound &&
                  !fileRenames.containsKey(destination))) {
            throw StateError('Asset rename destination exists: $destination');
          }
          fileRenames[assetFile.path] = destination;
          final oldPath = _packageRelative(package, assetFile.path);
          final newPath = _packageRelative(package, destination);
          packagePaths[oldPath] = newPath;
          final existingUnqualified = unqualifiedPathRenames[oldPath];
          if (existingUnqualified == null &&
              !ambiguousUnqualifiedPaths.contains(oldPath)) {
            unqualifiedPathRenames[oldPath] = newPath;
          } else if (existingUnqualified != newPath) {
            unqualifiedPathRenames.remove(oldPath);
            ambiguousUnqualifiedPaths.add(oldPath);
          }
          qualifiedPathRenames['packages/${package.name}/$oldPath'] =
              'packages/${package.name}/$newPath';
        }

        if (type == FileSystemEntityType.file) {
          final renamed = fileRenames[absolute];
          if (renamed != null) {
            final replacement = _packageRelative(package, renamed);
            pubspecEdits
                .putIfAbsent(package.pubspecPath, () => <SourceEdit>[])
                .add(
                  SourceEdit(
                    offset: node.span.start.offset,
                    length: node.span.length,
                    replacement: _yamlScalar(replacement, node.span.text),
                    reason: 'asset pubspec path',
                  ),
                );
          }
        } else if (type == FileSystemEntityType.directory &&
            pathTransformer != null) {
          final transformed = pathTransformer(absolute);
          if (transformed != absolute) {
            var replacement = _packageRelative(package, transformed);
            if (declaredPath.endsWith('/')) replacement = '$replacement/';
            pubspecEdits
                .putIfAbsent(package.pubspecPath, () => <SourceEdit>[])
                .add(
                  SourceEdit(
                    offset: node.span.start.offset,
                    length: node.span.length,
                    replacement: _yamlScalar(replacement, node.span.text),
                    reason: 'asset directory path',
                  ),
                );
          }
        }
      }
    }
    return AssetRenamePlan._(
      fileRenames: fileRenames,
      pubspecEdits: pubspecEdits,
      pathRenamesByPackage: pathRenamesByPackage,
      qualifiedPathRenames: qualifiedPathRenames,
      unqualifiedPathRenames: unqualifiedPathRenames,
    );
  }

  factory AssetRenamePlan.empty() => AssetRenamePlan._(
    fileRenames: const {},
    pubspecEdits: const {},
    pathRenamesByPackage: const {},
    qualifiedPathRenames: const {},
    unqualifiedPathRenames: const {},
  );

  final Map<String, String> fileRenames;
  final Map<String, List<SourceEdit>> pubspecEdits;
  final Map<String, Map<String, String>> pathRenamesByPackage;
  final Map<String, String> qualifiedPathRenames;
  final Map<String, String> unqualifiedPathRenames;

  String? replacementFor({
    required ProjectPackage? currentPackage,
    required String value,
  }) {
    final qualified = qualifiedPathRenames[value];
    if (qualified != null) {
      return qualified;
    }
    if (currentPackage == null) {
      return null;
    }
    return pathRenamesByPackage[currentPackage.name]?[value] ??
        unqualifiedPathRenames[value];
  }
}

final class AssetStringEditVisitor extends RecursiveAstVisitor<void> {
  AssetStringEditVisitor({required this.currentPackage, required this.plan});

  final ProjectPackage? currentPackage;
  final AssetRenamePlan plan;
  final List<SourceEdit> edits = [];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.stringValue;
    if (value != null) {
      final replacement = plan.replacementFor(
        currentPackage: currentPackage,
        value: value,
      );
      if (replacement != null && replacement != value) {
        edits.add(
          SourceEdit(
            offset: node.contentsOffset,
            length: node.contentsEnd - node.contentsOffset,
            replacement: replacement,
            reason: 'asset string path',
          ),
        );
      }
    }
    super.visitSimpleStringLiteral(node);
  }
}

String _packageRelative(ProjectPackage package, String path) =>
    p.posix.joinAll(p.split(p.relative(path, from: package.rootPath)));

String _yamlScalar(String value, String original) {
  if (original.startsWith("'") && original.endsWith("'")) {
    return "'${value.replaceAll("'", "''")}'";
  }
  if (original.startsWith('"') && original.endsWith('"')) {
    return '"${value.replaceAll('"', r'\"')}"';
  }
  return value;
}
