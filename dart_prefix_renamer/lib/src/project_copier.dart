import 'dart:io';

import 'package:path/path.dart' as p;

const _excludedDirectoryNames = <String>{
  '.dart_tool',
  '.git',
  '.idea',
  '.symlinks',
  'build',
  'Pods',
};

Future<void> copyProject({
  required String sourcePath,
  required String destinationPath,
}) async {
  final source = Directory(sourcePath);
  final destination = Directory(destinationPath);
  await destination.create(recursive: true);
  await _copyDirectory(source, destination);
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entity in source.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (entity is Directory && _excludedDirectoryNames.contains(name)) {
      continue;
    }

    final destinationEntityPath = p.join(destination.path, name);
    if (entity is Directory) {
      final childDestination = Directory(destinationEntityPath);
      await childDestination.create();
      await _copyDirectory(entity, childDestination);
    } else if (entity is File) {
      await entity.copy(destinationEntityPath);
    } else if (entity is Link) {
      await Link(destinationEntityPath).create(await entity.target());
    }
  }
}

Future<void> runPubGet(String projectPath) async {
  final result = await Process.run(
    'fvm',
    const ['flutter', 'pub', 'get'],
    workingDirectory: projectPath,
    runInShell: true,
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    throw ProcessException(
      'fvm',
      const ['flutter', 'pub', 'get'],
      'Dependency resolution failed.',
      result.exitCode,
    );
  }
}
