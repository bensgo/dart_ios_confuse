import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('catalog contains the sixteen supported templates', () {
    expect(
      DartCapabilityCatalog.templates.keys,
      containsAll({
        'cache_key',
        'cache_validation',
        'response_normalizer',
        'request_context',
        'input_validation',
        'analytics_context',
        'state_validation',
        'debug_summary',
        'request_metadata',
        'retry_context',
        'operation_context',
        'lifecycle_snapshot',
        'decision_context',
        'rule_validation',
        'presentation_metadata',
        'accessibility_context',
      }),
    );
    expect(DartCapabilityCatalog.templates, hasLength(16));
  });

  test(
    'generates a missing definition only when a production call exists',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'capability_generator_',
      );
      addTearDown(() => root.delete(recursive: true));
      final file = File(p.join(root.path, 'lib', 'repository.dart'));
      await file.parent.create(recursive: true);
      await file.writeAsString('''
class UserRepository {
  String loadUser(String id) {
    return buildCapabilityCacheKey(id);
  }
}
''');
      final plan = CapabilityPlan(
        schemaVersion: 1,
        productId: 'product_test',
        seed: 1,
        classesAnalyzed: 1,
        entries: [
          const CapabilityPlanEntry(
            className: 'UserRepository',
            library: 'lib/repository.dart',
            capability: 'cache_key',
            classKind: 'repository',
            classificationEvidence: ['name:UserRepository'],
            callMethod: 'loadUser',
            callAnchor: 'return',
            effect: 'cache_lookup_key',
            status: PlanEntryStatus.ready,
            reasons: [],
          ),
        ],
        suggestions: const [],
      );
      final generator = DartCapabilityGenerator(projectRoot: root.path);
      final report = await generator.apply(plan);
      expect(report.generated, 1);
      final source = await file.readAsString();
      expect(source, contains('String buildCapabilityCacheKey(String value)'));

      final validation = await DartCapabilityValidator(
        projectRoot: root.path,
      ).validate(plan);
      expect(validation.capabilitiesReachable, 1);
      expect(validation.integrations.single.effectVerified, isTrue);

      final second = await generator.apply(plan);
      expect(second.existing, 1);
    },
  );

  test('refuses to insert a definition without a production call', () async {
    final root = await Directory.systemTemp.createTemp('capability_no_call_');
    addTearDown(() => root.delete(recursive: true));
    final file = File(p.join(root.path, 'lib', 'repository.dart'));
    await file.parent.create(recursive: true);
    await file.writeAsString('''
class UserRepository {
  String loadUser(String id) => id;
}
''');
    final plan = CapabilityPlan(
      schemaVersion: 1,
      productId: 'product_test',
      seed: 1,
      classesAnalyzed: 1,
      entries: [
        const CapabilityPlanEntry(
          className: 'UserRepository',
          library: 'lib/repository.dart',
          capability: 'cache_key',
          classKind: 'repository',
          classificationEvidence: [],
          callMethod: 'loadUser',
          callAnchor: 'return',
          effect: 'cache_lookup_key',
          status: PlanEntryStatus.ready,
          reasons: [],
        ),
      ],
      suggestions: const [],
    );
    expect(
      () => DartCapabilityGenerator(projectRoot: root.path).apply(plan),
      throwsA(isA<StateError>()),
    );
  });
}
