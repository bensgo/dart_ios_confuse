import 'dart:io';

import 'package:path/path.dart' as p;

final class MetadataResetReport {
  const MetadataResetReport({required this.resetAt, required this.entities});

  final DateTime resetAt;
  final int entities;
}

/// 清除输出工程的 macOS 扩展属性，并统一普通文件和目录的创建、修改时间。
Future<MetadataResetReport> resetProjectMetadata({
  required String projectPath,
  DateTime? resetAt,
}) async {
  final root = Directory(p.normalize(p.absolute(projectPath)));
  if (!root.existsSync()) {
    throw StateError('Metadata reset target does not exist: ${root.path}');
  }
  if (!Platform.isMacOS) {
    throw UnsupportedError(
      'Metadata reset currently requires macOS xattr and SetFile.',
    );
  }

  final timestamp = (resetAt ?? DateTime.now()).toLocal();
  final entities = <String>[root.path];
  final links = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is File || entity is Directory) {
      entities.add(entity.path);
    } else if (entity is Link) {
      links.add(entity.path);
    }
  }

  // Do not use `xattr -r`: a broken framework symlink makes the entire command
  // fail. Enumerate without following links, then clear each kind explicitly.
  for (final batch in _batches(entities, 200)) {
    await _run('/usr/bin/xattr', ['-c', ...batch]);
  }
  for (final batch in _batches(links, 200)) {
    await _run('/usr/bin/xattr', ['-c', '-s', ...batch]);
  }

  final setFileDate =
      '${_two(timestamp.month)}/${_two(timestamp.day)}/${timestamp.year} '
      '${_two(timestamp.hour)}:${_two(timestamp.minute)}:'
      '${_two(timestamp.second)}';
  for (final batch in _batches(entities, 200)) {
    await _run('/usr/bin/SetFile', [
      '-d',
      setFileDate,
      '-m',
      setFileDate,
      ...batch,
    ]);
  }

  return MetadataResetReport(
    resetAt: timestamp,
    entities: entities.length + links.length,
  );
}

Iterable<List<String>> _batches(List<String> values, int size) sync* {
  for (var start = 0; start < values.length; start += size) {
    final end = start + size < values.length ? start + size : values.length;
    yield values.sublist(start, end);
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stderr}'.trim(),
      result.exitCode,
    );
  }
}
