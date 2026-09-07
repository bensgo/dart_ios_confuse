import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'resets file and directory dates and clears extended attributes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'metadata_resetter_test_',
      );
      addTearDown(() => root.delete(recursive: true));
      final nested = Directory(p.join(root.path, 'nested'))..createSync();
      final file = File(p.join(nested.path, 'sample.txt'))
        ..writeAsStringSync('sample');
      Link(
        p.join(root.path, 'broken_link'),
      ).createSync(p.join(root.path, 'missing_target'));
      final oldTime = DateTime(2020, 1, 2, 3, 4, 5);
      file.setLastModifiedSync(oldTime);
      final xattrWrite = await Process.run('/usr/bin/xattr', [
        '-w',
        'com.dart_prefix_renamer.test',
        'value',
        file.path,
      ]);
      expect(xattrWrite.exitCode, 0, reason: '${xattrWrite.stderr}');

      final resetAt = DateTime(2024, 6, 7, 8, 9, 10);
      final report = await resetProjectMetadata(
        projectPath: root.path,
        resetAt: resetAt,
      );

      expect(report.entities, 4);
      expect(file.lastModifiedSync(), resetAt);
      expect(nested.statSync().modified, resetAt);
      final birthTime = await Process.run('/usr/bin/stat', [
        '-f',
        '%B',
        file.path,
      ]);
      expect(birthTime.exitCode, 0);
      expect(
        int.parse('${birthTime.stdout}'.trim()),
        resetAt.millisecondsSinceEpoch ~/ 1000,
      );
      final attributes = await Process.run('/usr/bin/xattr', [file.path]);
      expect(attributes.exitCode, 0);
      expect(
        '${attributes.stdout}',
        isNot(contains('com.dart_prefix_renamer.test')),
      );
    },
    skip: !Platform.isMacOS,
  );
}
