import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final class ProjectPackage {
  const ProjectPackage({required this.name, required this.rootPath});

  final String name;
  final String rootPath;

  String get libPath => p.join(rootPath, 'lib');

  String get pubspecPath => p.join(rootPath, 'pubspec.yaml');
}

final class ProjectLayout {
  ProjectLayout._({required this.rootPath, required this.packages});

  factory ProjectLayout.discover(String rootPath) {
    final normalizedRoot = p.normalize(p.absolute(rootPath));
    final rootPubspec = _readPubspec(normalizedRoot);
    final packageRoots = <String>{normalizedRoot};
    final workspace = rootPubspec['workspace'];
    if (workspace is YamlList) {
      for (final member in workspace.nodes) {
        if (member.value is! String) {
          throw FormatException(
            'Workspace members must be paths: ${member.value}',
          );
        }
        packageRoots.add(
          p.normalize(p.join(normalizedRoot, member.value as String)),
        );
      }
    }

    final packages = <String, ProjectPackage>{};
    for (final packageRoot in packageRoots) {
      final pubspecFile = File(p.join(packageRoot, 'pubspec.yaml'));
      if (!pubspecFile.existsSync()) {
        throw StateError('Workspace member has no pubspec.yaml: $packageRoot');
      }
      final pubspec = _readPubspec(packageRoot);
      final name = pubspec['name'];
      if (name is! String || name.isEmpty) {
        // A workspace-only root is allowed to omit its package name.
        if (packageRoot == normalizedRoot && workspace is YamlList) {
          continue;
        }
        throw StateError('Unable to read package name from $pubspecFile');
      }
      if (packages.containsKey(name)) {
        throw StateError('Duplicate package name in workspace: $name');
      }
      packages[name] = ProjectPackage(name: name, rootPath: packageRoot);
    }
    return ProjectLayout._(rootPath: normalizedRoot, packages: packages);
  }

  final String rootPath;
  final Map<String, ProjectPackage> packages;

  String? resolvePackageUri(String uri) {
    final match = RegExp(r'^package:([^/]+)/(.+)$').firstMatch(uri);
    if (match == null) {
      return null;
    }
    final package = packages[match.group(1)];
    if (package == null) {
      return null;
    }
    return p.normalize(p.join(package.libPath, match.group(2)!));
  }

  String? packageUriForPath(String path) {
    final normalized = p.normalize(path);
    for (final package in packages.values) {
      if (normalized == package.libPath ||
          p.isWithin(package.libPath, normalized)) {
        final relative = p.relative(normalized, from: package.libPath);
        return 'package:${package.name}/${p.posix.joinAll(p.split(relative))}';
      }
    }
    return null;
  }

  ProjectPackage? packageForPath(String path) {
    final normalized = p.normalize(path);
    ProjectPackage? bestMatch;
    for (final package in packages.values) {
      if (normalized != package.rootPath &&
          !p.isWithin(package.rootPath, normalized)) {
        continue;
      }
      if (bestMatch == null ||
          package.rootPath.length > bestMatch.rootPath.length) {
        bestMatch = package;
      }
    }
    return bestMatch;
  }
}

YamlMap _readPubspec(String directory) {
  final file = File(p.join(directory, 'pubspec.yaml'));
  final document = loadYaml(file.readAsStringSync());
  if (document is! YamlMap) {
    throw FormatException('pubspec.yaml must contain a YAML map: ${file.path}');
  }
  return document;
}
