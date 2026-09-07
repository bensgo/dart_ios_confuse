import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late String fixtureRoot;
  late ScanResult scan;
  late NormalizedConfig config;

  setUpAll(() async {
    fixtureRoot = p.absolute('test/fixtures/wp00_baseline');
    config = CapabilityConfigLoader(projectRoot: fixtureRoot).loadAll(
      productProfilePath: 'config/product_profile.yaml',
      dartCapabilitiesPath: 'config/dart_capabilities.yaml',
      nativeCapabilitiesPath: 'config/native_capabilities.yaml',
      dependenciesPath: 'config/dependencies.yaml',
    );
    final targets = Directory(p.join(fixtureRoot, 'packages'))
        .listSync()
        .whereType<Directory>()
        .map((directory) => p.join(directory.path, 'lib'))
        .where((path) => Directory(path).existsSync())
        .toList(growable: false);
    scan = await DartClassScanner(
      projectRoot: fixtureRoot,
      targetPaths: targets,
    ).scan();
  });

  test('scans workspace classes and their methods', () {
    expect(scan.classes.length, greaterThanOrEqualTo(15));
    final repository = scan.classes.firstWhere(
      (info) => info.name == 'UserRepository',
    );
    expect(
      repository.methods.map((method) => method.name),
      contains('loadUser'),
    );
    expect(repository.libraryUri, contains('repository_pkg'));
  });

  test('classifies supported responsibilities with evidence', () {
    const classifier = DartClassClassifier();
    for (final expectation in {
      'UserRepository': DartClassKind.repository,
      'ApiService': DartClassKind.service,
      'ConversationController': DartClassKind.controller,
      'User': DartClassKind.model,
      'UserProfileWidget': DartClassKind.widget,
    }.entries) {
      final info = scan.classes.firstWhere(
        (item) => item.name == expectation.key,
      );
      final result = classifier.classify(info);
      expect(result.kind, expectation.value);
      expect(result.canApply, isTrue);
      expect(result.evidence, isNotEmpty);
    }
  });

  test('classifies utility, manager, and logic with token boundaries', () {
    const classifier = DartClassClassifier();
    for (final expectation in {
      'DateUtil': DartClassKind.utility,
      'FormatHelper': DartClassKind.utility,
      'SessionManager': DartClassKind.manager,
      'ConversationLogic': DartClassKind.logic,
    }.entries) {
      final info = scan.classes.firstWhere(
        (item) => item.name == expectation.key,
      );
      final result = classifier.classify(info);
      expect(result.kind, expectation.value);
      expect(result.canApply, isTrue);
    }
    final result = classifier.classify(
      scan.classes.firstWhere((item) => item.name == 'Reutilization'),
    );
    expect(result.kind, DartClassKind.unclassified);
    expect(
      classifier
          .classify(
            scan.classes.firstWhere(
              (item) => item.name == 'UserRepositoryManager',
            ),
          )
          .kind,
      DartClassKind.repository,
    );
  });

  test('emits stable class suggestions and classification summary', () {
    final plan = DartCapabilityPlanner(
      projectRoot: fixtureRoot,
      profile: config.productProfile,
      manifest: config.dartCapabilities,
      seed: 42,
    ).createPlan(scan);
    final classes = plan.toJson()['classes'] as List<dynamic>;
    final manager = classes.cast<Map<String, dynamic>>().firstWhere(
      (entry) => entry['class'] == 'SessionManager',
    );
    expect(manager['type'], 'manager');
    expect(manager['suggestions'], isEmpty);
    expect(manager['candidate'], isTrue);
    final summary = plan.toJson()['classification_summary'] as List<dynamic>;
    expect(
      summary.cast<Map<String, dynamic>>().map((entry) => entry['type']),
      containsAll(['manager', 'logic', 'utility']),
    );
  });

  test('builds deterministic explicit plan and rejects negative fixtures', () {
    CapabilityPlan build() => DartCapabilityPlanner(
      projectRoot: fixtureRoot,
      profile: config.productProfile,
      manifest: config.dartCapabilities,
      seed: 42,
    ).createPlan(scan);

    final first = build();
    final second = build();
    expect(first.toJsonString(), second.toJsonString());
    expect(first.readyEntries, isNotEmpty);
    expect(
      first.readyEntries.map((entry) => entry.className),
      contains('UserRepository'),
    );
    final rejected = first.entries.where(
      (entry) => entry.status == PlanEntryStatus.rejected,
    );
    expect(
      rejected.map((entry) => entry.className),
      contains('DeadCodeRepository'),
    );
    expect(
      rejected
          .firstWhere((entry) => entry.className == 'WrongAnchorRepository')
          .reasons,
      contains('unsupported_call_anchor'),
    );
  });
}
