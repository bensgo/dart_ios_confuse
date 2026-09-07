import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('scans all classes and emits catalog suggestions', () async {
    final project = await _copyFixture();
    addTearDown(() => project.delete(recursive: true));
    final report = await DartCapabilityAutoRunner(
      _config(project.path, scanOnly: true),
    ).run();
    final decoded =
        jsonDecode(await File(report.suggestionsFile).readAsString())
            as List<dynamic>;
    final repository = decoded.cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['class'] == 'UserRepository',
    );
    expect(repository['type'], 'repository');
    expect(
      repository['suggestions'],
      containsAll(['cache_key', 'cache_validation']),
    );
    final manager = decoded.cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['class'] == 'SessionManager',
    );
    expect(
      manager['suggestions'],
      containsAll(['operation_context', 'lifecycle_snapshot']),
    );
    expect(manager['candidate'], isTrue);
    final logic = decoded.cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['class'] == 'ConversationLogic',
    );
    expect(
      logic['suggestions'],
      containsAll(['decision_context', 'rule_validation']),
    );
    final widget = decoded.cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['class'] == 'UserProfileWidget',
    );
    expect(
      widget['suggestions'],
      containsAll(['presentation_metadata', 'accessibility_context']),
    );
    expect(
      decoded.cast<Map<String, dynamic>>().map((entry) => entry['class']),
      isNot(contains('GeneratedJunkManager')),
    );
  });

  test('selects by percentage, inserts calls, and reuses selection', () async {
    final first = await _copyFixture();
    final second = await _copyFixture();
    addTearDown(() => first.delete(recursive: true));
    addTearDown(() => second.delete(recursive: true));

    final firstReport = await DartCapabilityAutoRunner(
      _config(first.path, percentage: 100),
    ).run();
    expect(firstReport.selected, greaterThan(0));
    expect(firstReport.inserted, firstReport.selected);
    final selection = File(firstReport.selectionFile!);
    final selectedJson =
        jsonDecode(await selection.readAsString()) as Map<String, dynamic>;
    expect(selectedJson['selected_count'], firstReport.selected);
    final selectedTypes = (selectedJson['entries'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((entry) => entry['type']);
    expect(selectedTypes, containsAll(['manager', 'logic', 'widget']));
    final markerCount = Directory(first.path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .fold<int>(
          0,
          (total, source) =>
              total + RegExp(r'// dart-capability:').allMatches(source).length,
        );
    expect(markerCount, firstReport.selected);

    final reusable = File(p.join(second.path, 'selection.json'));
    final selectionForSecond = jsonEncode(
      _rehashSelection(selectedJson, first.path, second.path),
    );
    await reusable.writeAsString(selectionForSecond);
    final secondReport = await DartCapabilityAutoRunner(
      _config(second.path, percentage: 1, selectionInput: 'selection.json'),
    ).run();
    expect(secondReport.selected, firstReport.selected);
    expect(secondReport.inserted, firstReport.selected);
  });

  test('rejects reusable selection after source drift', () async {
    final project = await _copyFixture();
    addTearDown(() => project.delete(recursive: true));
    final report = await DartCapabilityAutoRunner(
      _config(project.path, percentage: 50),
    ).run();
    final selection =
        jsonDecode(await File(report.selectionFile!).readAsString())
            as Map<String, dynamic>;
    final entry =
        (selection['entries'] as List<dynamic>).first as Map<String, dynamic>;
    final source = File(p.join(project.path, entry['library'] as String));
    await source.writeAsString('${await source.readAsString()}\n// drift\n');
    await expectLater(
      DartCapabilityAutoRunner(
        _config(
          project.path,
          selectionInput: p.relative(report.selectionFile!, from: project.path),
        ),
      ).run(),
      throwsA(isA<StateError>()),
    );
  });
}

DartCapabilityAutoConfig _config(
  String root, {
  bool scanOnly = false,
  double percentage = 0,
  String? selectionInput,
}) => DartCapabilityAutoConfig(
  projectRoot: root,
  targetPaths: [
    'packages/repository_pkg/lib',
    'packages/service_pkg/lib',
    'packages/controller_pkg/lib',
    'packages/model_pkg/lib',
    'packages/classification_pkg/lib',
    'packages/widget_pkg/lib',
  ],
  scanOnly: scanOnly,
  percentage: percentage,
  seed: 42,
  suggestionsOutput: 'reports/suggestions.json',
  selectionOutput: 'reports/selection.json',
  selectionInput: selectionInput,
);

Future<Directory> _copyFixture() async {
  final output = await Directory.systemTemp.createTemp('dart_auto_test_');
  await _copyDirectory(
    Directory(p.absolute('test/fixtures/wp00_baseline')),
    output,
  );
  final junk = File(
    p.join(
      output.path,
      'packages',
      'classification_pkg',
      'lib',
      'pack',
      'junk_code',
      'junk.dart',
    ),
  );
  await junk.parent.create(recursive: true);
  await junk.writeAsString('''
class GeneratedJunkManager {
  void run() {}
}
''');
  return output;
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entity in source.list(recursive: false)) {
    final target = p.join(destination.path, p.basename(entity.path));
    if (entity is Directory) {
      final directory = await Directory(target).create();
      await _copyDirectory(entity, directory);
    } else if (entity is File && !entity.path.endsWith('.DS_Store')) {
      await entity.copy(target);
    }
  }
}

Map<String, dynamic> _rehashSelection(
  Map<String, dynamic> selection,
  String firstRoot,
  String secondRoot,
) {
  final copied = jsonDecode(jsonEncode(selection)) as Map<String, dynamic>;
  for (final raw in copied['entries'] as List<dynamic>) {
    final entry = raw as Map<String, dynamic>;
    final relative = entry['library'] as String;
    final original = File(p.join(firstRoot, relative));
    final pristine = File(p.join(secondRoot, relative));
    expect(original.existsSync(), isTrue);
    entry['source_sha256'] = _sha(pristine.readAsBytesSync());
  }
  return copied;
}

String _sha(List<int> bytes) {
  // The selection uses standard lowercase SHA-256. Keep the test independent
  // from private runner helpers while producing the same value.
  return sha256.convert(bytes).toString();
}
