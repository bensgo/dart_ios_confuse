import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'renames files, URI directives, classes, constructors, and external references',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'prefix_renamer_test_',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));

      final project = Directory(p.join(temporaryDirectory.path, 'fixture'))
        ..createSync();
      final output = p.join(temporaryDirectory.path, 'fixture_output');
      _write(project.path, 'pubspec.yaml', '''
name: rename_fixture
environment:
  sdk: ^3.9.2
flutter:
  assets:
    - assets/
    - config/app.json
''');
      _write(project.path, 'assets/logo.png', 'fake-png');
      _write(project.path, 'assets/2.0x/logo.png', 'fake-2x-png');
      _write(project.path, 'config/app.json', '{"enabled":true}');
      _write(project.path, 'lib/models/internal/readme.txt', 'nested');
      _write(project.path, 'lib/models/person.dart', '''
part 'person_part.dart';

class Person {
  Person();
  Person.named();
}

class _PrivatePerson {
  _PrivatePerson();
}
''');
      _write(project.path, 'lib/models/person_part.dart', '''
part of 'person.dart';

class Helper {
  Person create() => Person.named();
  _PrivatePerson createPrivate() => _PrivatePerson();
}
''');
      _write(
        project.path,
        'lib/api.dart',
        "export 'models/person.dart' show Person;\n",
      );
      _write(project.path, 'lib/consumer.dart', '''
import 'package:rename_fixture/models/person.dart';

Person createPerson() => Person();
const logoAsset = 'assets/logo.png';
const configAsset = 'config/app.json';
''');
      _write(
        project.path,
        'lib/models/condition_stub.dart',
        'class Condition {}\n',
      );
      _write(project.path, 'lib/models/condition_io.dart', '''
import 'condition_stub.dart';

class IoCondition extends Condition {}
''');
      _write(project.path, 'lib/conditional.dart', '''
import 'models/condition_stub.dart'
    if (dart.library.io) 'models/condition_io.dart';

Condition createCondition() => Condition();
''');
      _write(project.path, 'bin/main.dart', '''
import '../lib/models/person.dart';

void main() => Person.named();
''');
      _write(project.path, 'lib/deep/one/resolved_relative.dart', '''
import '../../../models/person.dart';

Person createDeepPerson() => Person();
''');
      if (Platform.isMacOS || Platform.isWindows) {
        _write(project.path, 'lib/case_consumer.dart', '''
import 'package:rename_fixture/models/Person.dart';

Person createCasePerson() => Person();
''');
      }

      final report = await PrefixRenamer(
        RenameConfig(
          projectPath: project.path,
          outputPath: output,
          targetPaths: const ['lib/models'],
          prefix: 'pre',
          resetMetadata: true,
          renameDirectories: true,
        ),
      ).run();

      expect(
        report.verificationPassed,
        isTrue,
        reason: report.newErrors.join('\n'),
      );
      expect(report.renamedFiles, 4);
      expect(report.renamedDirectories, 2);
      expect(report.renamedClasses, 5);
      expect(report.renamedAssets, 3);
      expect(report.generatedJunkFiles, 0);
      expect(report.generatedJunkClasses, 0);
      expect(report.metadataEntitiesReset, greaterThan(0));
      expect(report.metadataResetAt, isNotNull);
      final manifest = File(
        p.join(output, 'dart_prefix_renamer_manifest.json'),
      ).readAsStringSync();
      expect(manifest, contains('"metadataReset"'));
      expect(manifest, contains('"enabled": true'));
      expect(
        File(p.join(output, 'lib/pre_models/pre_person.dart')).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(output, 'lib/pre_models/pre_person_part.dart'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(output, 'lib/pre_models/person.dart')).existsSync(),
        isFalse,
      );

      final person = File(
        p.join(output, 'lib/pre_models/pre_person.dart'),
      ).readAsStringSync();
      expect(person, contains("part 'pre_person_part.dart';"));
      expect(person, contains('class PrePerson'));
      expect(person, contains('PrePerson();'));
      expect(person, contains('PrePerson.named();'));
      expect(person, contains('class _PrePrivatePerson'));
      expect(person, contains('_PrePrivatePerson();'));

      final part = File(
        p.join(output, 'lib/pre_models/pre_person_part.dart'),
      ).readAsStringSync();
      expect(part, contains("part of 'pre_person.dart';"));
      expect(part, contains('class PreHelper'));
      expect(part, contains('PrePerson create() => PrePerson.named();'));
      expect(
        part,
        contains('_PrePrivatePerson createPrivate() => _PrePrivatePerson();'),
      );

      expect(
        File(p.join(output, 'lib/api.dart')).readAsStringSync(),
        contains("export 'pre_models/pre_person.dart' show PrePerson;"),
      );
      expect(
        File(p.join(output, 'lib/consumer.dart')).readAsStringSync(),
        contains("import 'package:rename_fixture/pre_models/pre_person.dart';"),
      );
      expect(
        File(p.join(output, 'lib/consumer.dart')).readAsStringSync(),
        contains('PrePerson createPerson()'),
      );
      final consumerSource = File(
        p.join(output, 'lib/consumer.dart'),
      ).readAsStringSync();
      expect(consumerSource, contains("'assets/pre_logo.png'"));
      expect(consumerSource, contains("'config/pre_app.json'"));
      expect(File(p.join(output, 'assets/pre_logo.png')).existsSync(), isTrue);
      expect(
        File(p.join(output, 'assets/2.0x/pre_logo.png')).existsSync(),
        isTrue,
      );
      expect(File(p.join(output, 'config/pre_app.json')).existsSync(), isTrue);
      expect(
        File(
          p.join(output, 'lib/pre_models/pre_internal/readme.txt'),
        ).existsSync(),
        isTrue,
      );
      final outputPubspec = File(
        p.join(output, 'pubspec.yaml'),
      ).readAsStringSync();
      expect(outputPubspec, contains('- assets/'));
      expect(outputPubspec, contains('- config/pre_app.json'));
      expect(
        File(p.join(output, 'bin/main.dart')).readAsStringSync(),
        contains("import '../lib/pre_models/pre_person.dart';"),
      );
      expect(
        File(p.join(output, 'bin/main.dart')).readAsStringSync(),
        contains('PrePerson.named()'),
      );
      final resolvedRelative = File(
        p.join(output, 'lib/deep/one/resolved_relative.dart'),
      ).readAsStringSync();
      expect(
        resolvedRelative,
        contains("import '../../pre_models/pre_person.dart';"),
      );
      expect(resolvedRelative, contains('PrePerson createDeepPerson()'));
      if (Platform.isMacOS || Platform.isWindows) {
        final caseConsumer = File(
          p.join(output, 'lib/case_consumer.dart'),
        ).readAsStringSync();
        expect(
          caseConsumer,
          contains(
            "import 'package:rename_fixture/pre_models/pre_person.dart';",
          ),
        );
        expect(caseConsumer, contains('PrePerson createCasePerson()'));
      }
      final conditional = File(
        p.join(output, 'lib/conditional.dart'),
      ).readAsStringSync();
      expect(
        conditional,
        contains("import 'pre_models/pre_condition_stub.dart'"),
      );
      expect(
        conditional,
        contains("if (dart.library.io) 'pre_models/pre_condition_io.dart'"),
      );
      expect(conditional, contains('PreCondition createCondition()'));
      expect(
        File(p.join(output, 'dart_prefix_renamer_manifest.json')).existsSync(),
        isTrue,
      );

      final restoreReport = await PrefixRestorer(
        RestoreConfig(projectPath: output),
      ).run();
      expect(
        restoreReport.verificationPassed,
        isTrue,
        reason: restoreReport.newErrors.join('\n'),
      );
      expect(restoreReport.restoredFiles, 4);
      expect(restoreReport.restoredDirectories, 2);
      expect(restoreReport.restoredClasses, 5);
      expect(restoreReport.restoredAssets, 3);
      expect(
        File(p.join(output, 'lib/models/person.dart')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(output, 'lib/models/pre_person.dart')).existsSync(),
        isFalse,
      );
      final restoredPerson = File(
        p.join(output, 'lib/models/person.dart'),
      ).readAsStringSync();
      expect(restoredPerson, contains('class Person'));
      expect(restoredPerson, contains('class _PrivatePerson'));
      final restoredConsumer = File(
        p.join(output, 'lib/consumer.dart'),
      ).readAsStringSync();
      expect(restoredConsumer, contains('Person createPerson()'));
      expect(restoredConsumer, contains("'assets/logo.png'"));
      expect(File(p.join(output, 'assets/logo.png')).existsSync(), isTrue);
      expect(File(p.join(output, 'config/app.json')).existsSync(), isTrue);
      expect(
        File(p.join(output, 'lib/models/internal/readme.txt')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(output, 'pubspec.yaml')).readAsStringSync(),
        contains('- config/app.json'),
      );
      expect(
        File(
          p.join(output, 'dart_prefix_renamer_manifest.json'),
        ).readAsStringSync(),
        contains('"restoredAt"'),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('rewrites declared asset directories moved under lib', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'prefix_renamer_lib_asset_directory_test_',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final project = Directory(p.join(temporaryDirectory.path, 'fixture'))
      ..createSync();
    final output = p.join(temporaryDirectory.path, 'fixture_output');
    _write(project.path, 'pubspec.yaml', '''
name: lib_asset_fixture
environment:
  sdk: ^3.9.2
flutter:
  assets:
    - lib/feature/assets/
''');
    _write(project.path, 'lib/feature/assets/icon.png', 'icon');
    _write(project.path, 'lib/feature/app.dart', '''
class AppAsset {
  static const icon = 'lib/feature/assets/icon.png';
}
''');

    final report = await PrefixRenamer(
      RenameConfig(
        projectPath: project.path,
        outputPath: output,
        targetPaths: const ['lib/feature'],
        prefix: 'pre',
        renameAssets: false,
        renameDirectories: true,
      ),
    ).run();

    expect(report.verificationPassed, isTrue);
    expect(report.renamedDirectories, 2);
    expect(
      File(p.join(output, 'lib/pre_feature/pre_assets/icon.png')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(output, 'pubspec.yaml')).readAsStringSync(),
      contains('- lib/pre_feature/pre_assets/'),
    );
    expect(
      File(p.join(output, 'lib/pre_feature/pre_app.dart')).readAsStringSync(),
      contains("'lib/pre_feature/pre_assets/icon.png'"),
    );

    final restore = await PrefixRestorer(
      RestoreConfig(projectPath: output),
    ).run();
    expect(restore.verificationPassed, isTrue);
    expect(
      File(p.join(output, 'lib/feature/assets/icon.png')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(output, 'pubspec.yaml')).readAsStringSync(),
      contains('- lib/feature/assets/'),
    );
  });

  test('rejects a prefix containing non-lowercase letters', () {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'prefix_renamer_config_test_',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    File(
      p.join(temporaryDirectory.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: fixture\n');
    Directory(p.join(temporaryDirectory.path, 'lib')).createSync();

    expect(
      () => RenameConfig(
        projectPath: temporaryDirectory.path,
        outputPath: '${temporaryDirectory.path}_output',
        targetPaths: const ['lib'],
        prefix: 'Bad1',
      ),
      throwsA(isA<UsageException>()),
    );
  });

  test(
    'supports package URI rewrites across Pub Workspace members',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'prefix_renamer_workspace_test_',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));

      final project = Directory(p.join(temporaryDirectory.path, 'workspace'))
        ..createSync();
      final output = p.join(temporaryDirectory.path, 'workspace_output');
      _write(project.path, 'pubspec.yaml', '''
name: workspace_root
environment:
  sdk: ^3.9.2
workspace:
  - packages/model_pkg
  - packages/app_pkg
''');
      _write(project.path, 'packages/model_pkg/pubspec.yaml', '''
name: model_pkg
environment:
  sdk: ^3.9.2
resolution: workspace
''');
      _write(project.path, 'packages/model_pkg/lib/src/person.dart', '''
class Person {
  const Person();
}
''');
      _write(
        project.path,
        'packages/model_pkg/lib/model_pkg.dart',
        "export 'src/person.dart';\n",
      );
      _write(project.path, 'packages/app_pkg/pubspec.yaml', '''
name: app_pkg
environment:
  sdk: ^3.9.2
resolution: workspace
dependencies:
  model_pkg: any
''');
      _write(project.path, 'packages/app_pkg/lib/consumer.dart', '''
import 'package:model_pkg/src/person.dart';

Person createPerson() => const Person();
const dependencyAsset = 'packages/model_pkg/assets/icon.png';
const legacyDependencyAsset = 'assets/icon.png';
''');
      _write(project.path, 'packages/model_pkg/assets/icon.png', 'fake-icon');
      final modelPubspec = File(
        p.join(project.path, 'packages/model_pkg/pubspec.yaml'),
      );
      modelPubspec.writeAsStringSync('''
name: model_pkg
environment:
  sdk: ^3.9.2
resolution: workspace
flutter:
  assets:
    - assets/
''');

      final report = await PrefixRenamer(
        RenameConfig(
          projectPath: project.path,
          outputPath: output,
          targetPaths: const ['packages/model_pkg/lib/src'],
          prefix: 'ws',
          renameDirectories: true,
        ),
      ).run();

      expect(
        report.verificationPassed,
        isTrue,
        reason: report.newErrors.join('\n'),
      );
      expect(report.renamedFiles, 1);
      expect(report.renamedDirectories, 1);
      expect(report.renamedClasses, 1);
      expect(report.renamedAssets, 1);
      expect(report.generatedJunkFiles, 0);
      expect(report.generatedJunkClasses, 0);
      expect(
        File(
          p.join(output, 'packages/model_pkg/lib/ws_src/ws_person.dart'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(
          p.join(output, 'packages/model_pkg/lib/model_pkg.dart'),
        ).readAsStringSync(),
        contains("export 'ws_src/ws_person.dart';"),
      );
      final consumer = File(
        p.join(output, 'packages/app_pkg/lib/consumer.dart'),
      ).readAsStringSync();
      expect(
        consumer,
        contains("import 'package:model_pkg/ws_src/ws_person.dart';"),
      );
      expect(consumer, contains('WsPerson createPerson()'));
      expect(consumer, contains('const WsPerson()'));
      expect(consumer, contains("'packages/model_pkg/assets/ws_icon.png'"));
      expect(consumer, contains("'assets/ws_icon.png'"));

      final restoreReport = await PrefixRestorer(
        RestoreConfig(projectPath: output),
      ).run();
      expect(restoreReport.verificationPassed, isTrue);
      expect(restoreReport.restoredDirectories, 1);
      expect(
        File(
          p.join(output, 'packages/model_pkg/lib/src/person.dart'),
        ).existsSync(),
        isTrue,
      );
      final restoredConsumer = File(
        p.join(output, 'packages/app_pkg/lib/consumer.dart'),
      ).readAsStringSync();
      expect(
        restoredConsumer,
        contains("import 'package:model_pkg/src/person.dart';"),
      );
      expect(restoredConsumer, contains('Person createPerson()'));
      expect(
        restoredConsumer,
        contains("'packages/model_pkg/assets/icon.png'"),
      );
      expect(restoredConsumer, contains("'assets/icon.png'"));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'keeps a Flutter root main.dart bridge when all lib is targeted',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'prefix_renamer_entrypoint_test_',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));
      final project = Directory(p.join(temporaryDirectory.path, 'fixture'))
        ..createSync();
      final output = p.join(temporaryDirectory.path, 'fixture_output');
      _write(project.path, 'pubspec.yaml', '''
name: entrypoint_fixture
environment:
  sdk: ^3.9.2
dependencies:
  flutter:
    sdk: flutter
''');
      _write(project.path, 'lib/main.dart', 'void main() {}\n');
      _write(project.path, 'lib/app.dart', 'class App {}\n');
      _write(project.path, 'lib/pack/junk_code/old.dart', 'class OldJunk {}\n');

      final report = await PrefixRenamer(
        RenameConfig(
          projectPath: project.path,
          outputPath: output,
          targetPaths: const ['lib'],
          prefix: 'pre',
          renameAssets: false,
          generateJunkCode: true,
        ),
      ).run();

      expect(report.verificationPassed, isTrue);
      expect(File(p.join(output, 'lib/pre_main.dart')).existsSync(), isTrue);
      final bridge = File(p.join(output, 'lib/main.dart')).readAsStringSync();
      expect(bridge, contains("import 'pre_main.dart' as renamed_entrypoint;"));
      expect(bridge, contains('renamed_entrypoint.main();'));
      expect(report.generatedJunkFiles, inInclusiveRange(401, 600));
      final businessFileCount = report.generatedJunkFiles - 1;
      expect(
        report.generatedJunkClasses,
        inInclusiveRange(businessFileCount * 5, businessFileCount * 14),
      );
      final junkDirectory = Directory(p.join(output, 'lib/pack/junk_code'));
      expect(
        junkDirectory.listSync().whereType<File>().length,
        report.generatedJunkFiles,
      );
      expect(
        File(p.join(junkDirectory.path, 'old.dart')).existsSync(),
        isFalse,
      );
      final junkMain = File(
        p.join(junkDirectory.path, 'junk_code_main.dart'),
      ).readAsStringSync();
      expect(junkMain, contains("import 'package:flutter/foundation.dart';"));
      expect(junkMain, contains('void JunkCodeMain() async'));
      expect(junkMain, contains('compute((e) {'));

      final restoreReport = await PrefixRestorer(
        RestoreConfig(projectPath: output),
      ).run();
      expect(restoreReport.verificationPassed, isTrue);
      expect(File(p.join(output, 'lib/pre_main.dart')).existsSync(), isFalse);
      expect(
        File(p.join(output, 'lib/main.dart')).readAsStringSync(),
        'void main() {}\n',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('leaves legacy junk-code file graph untouched', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'prefix_renamer_legacy_junk_test_',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final project = Directory(p.join(temporaryDirectory.path, 'fixture'))
      ..createSync();
    final output = p.join(temporaryDirectory.path, 'fixture_output');
    _write(project.path, 'pubspec.yaml', '''
name: legacy_junk_fixture
environment:
  sdk: ^3.9.2
''');
    _write(project.path, 'lib/main.dart', 'void main() {}\n');
    _write(
      project.path,
      'lib/pack/junk_code/junk_code_main.dart',
      "import './worker.dart';\nvoid JunkCodeMain() => worker();\n",
    );
    _write(
      project.path,
      'lib/pack/junk_code/worker.dart',
      'void worker() {}\n',
    );

    final report = await PrefixRenamer(
      RenameConfig(
        projectPath: project.path,
        outputPath: output,
        targetPaths: const ['lib'],
        prefix: 'pre',
        runPubGet: false,
        verify: false,
        renameAssets: false,
      ),
    ).run();

    expect(report.renamedFiles, 1);
    final junkRoot = p.join(output, 'lib/pack/junk_code');
    expect(File(p.join(junkRoot, 'junk_code_main.dart')).existsSync(), isTrue);
    expect(File(p.join(junkRoot, 'worker.dart')).existsSync(), isTrue);
    expect(
      File(p.join(junkRoot, 'junk_code_main.dart')).readAsStringSync(),
      contains("import './worker.dart';"),
    );
  });

  test('keeps image containers and encrypted strings in output copy', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'prefix_renamer_encryption_test_',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final project = Directory(p.join(temporaryDirectory.path, 'fixture'))
      ..createSync();
    final output = p.join(temporaryDirectory.path, 'fixture_output');
    _write(project.path, 'pubspec.yaml', '''
name: encryption_fixture
environment:
  sdk: ^3.9.2
flutter:
  assets:
    - assets/images/
''');
    _write(project.path, 'lib/api.dart', '''
String api() => TbrEncrypt.decryptedPS('https://api.example.com', '');
''');
    _write(project.path, 'lib/asset_config.g.dart', '''
abstract final class AssetContainerConfig {
  static const bool enabled = false;
}
''');
    _write(project.path, 'lib/string_config.g.dart', '''
abstract final class StringCipherConfig {
  static const bool enabled = false;
}
''');
    final image = File(p.join(project.path, 'assets/images/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.generate(129, (index) => index % 127));

    final report = await PrefixRenamer(
      RenameConfig(
        projectPath: project.path,
        outputPath: output,
        targetPaths: const ['lib'],
        prefix: 'pre',
        runPubGet: false,
        verify: false,
        renameAssets: false,
        containerizeIosAssets: true,
        assetRuntimeConfig: 'lib/asset_config.g.dart',
        encryptDartStrings: true,
        stringRuntimeConfig: 'lib/string_config.g.dart',
      ),
    ).run();

    expect(report.encryptedImages, 1);
    expect(report.encryptedDartStrings, 1);
    expect(
      File(p.join(output, 'assets/images/logo.png')).existsSync(),
      isFalse,
    );
    final containers = Directory(
      p.join(output, 'assets/images'),
    ).listSync().whereType<File>().toList();
    expect(
      containers.where((file) => file.path.endsWith('.dat')),
      hasLength(1),
    );
    expect(
      containers.where((file) => file.path.endsWith('.cfg')),
      hasLength(1),
    );
    expect(
      File(p.join(output, 'lib/pre_api.dart')).readAsStringSync(),
      isNot(contains('https://api.example.com')),
    );
    expect(
      File(p.join(output, 'lib/pre_asset_config.g.dart')).readAsStringSync(),
      contains('PreAssetContainerConfig'),
    );
    expect(
      File(p.join(output, 'lib/pre_string_config.g.dart')).readAsStringSync(),
      contains('PreStringCipherConfig'),
    );
    expect(image.existsSync(), isTrue);
  });
}

void _write(String root, String relativePath, String contents) {
  final file = File(p.join(root, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
