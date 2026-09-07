import 'dart:convert';
import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:encrypt/encrypt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('keeps encrypted strings in a copied project', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'dart_string_permanent_test_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = Directory(p.join(temporary.path, 'app'))..createSync();
    _write(project.path, 'pubspec.yaml', '''
name: fixture
environment:
  sdk: ^3.9.2
''');
    _write(project.path, 'lib/api.dart', '''
String api() => TbrEncrypt.decryptedPS('https://api.example.com', '');
''');
    const runtimeRelative = 'lib/p_string_cipher_config.g.dart';
    _write(project.path, runtimeRelative, '''
abstract final class PStringCipherConfig {
  static const bool enabled = false;
}
''');

    final report = await DartStringCipherBuilder(
      DartStringBuildConfig(
        projectPath: project.path,
        runtimeConfigPath: runtimeRelative,
      ),
    ).applyPermanently();

    expect(report.files, 1);
    expect(report.strings, 1);
    expect(report.restored, isFalse);
    expect(
      File(p.join(project.path, 'lib/api.dart')).readAsStringSync(),
      isNot(contains('https://api.example.com')),
    );
    expect(
      File(p.join(project.path, runtimeRelative)).readAsStringSync(),
      contains('PStringCipherConfig'),
    );
    expect(
      Directory(
        p.join(project.path, '.dart_prefix_renamer_string_transaction'),
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'encrypts root and workspace strings for build then restores them',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'dart_string_cipher_test_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final project = Directory(p.join(temporary.path, 'app'))..createSync();
      _write(project.path, 'pubspec.yaml', '''
name: fixture
environment:
  sdk: ^3.9.2
workspace:
  - packages/config
''');
      _write(project.path, 'lib/api.dart', '''
String api() => TbrEncrypt.decryptedPS('https://api.example.com', '');
''');
      _write(project.path, 'packages/config/pubspec.yaml', '''
name: fixture_config
environment:
  sdk: ^3.9.2
resolution: workspace
''');
      const packageSource = '''
String channel() => TbrEncrypt.decryptedPS(
  "app_store",
  "",
);
''';
      _write(project.path, 'packages/config/lib/channel.dart', packageSource);
      const placeholder = '''
abstract final class StringCipherConfig {
  static const bool enabled = false;
  static const String keyBase64 = '';
  static const String ivBase64 = '';
}
''';
      final runtimeRelative = 'packages/config/lib/string_cipher_config.g.dart';
      _write(project.path, runtimeRelative, placeholder);
      final capture = Directory(p.join(temporary.path, 'capture'))
        ..createSync();
      final checker = File(p.join(temporary.path, 'checker.dart'))
        ..writeAsStringSync('''
import 'dart:io';

void main(List<String> args) {
  final root = args[0];
  final capture = args[1];
  File('\$root/lib/api.dart').copySync('\$capture/api.dart');
  File('\$root/packages/config/lib/channel.dart').copySync('\$capture/channel.dart');
  File('\$root/$runtimeRelative').copySync('\$capture/config.dart');
}
''');
      final apiFile = File(p.join(project.path, 'lib/api.dart'));
      final originalApi = apiFile.readAsStringSync();

      final report = await DartStringCipherBuilder(
        DartStringBuildConfig(
          projectPath: project.path,
          runtimeConfigPath: runtimeRelative,
          buildCommand: [
            Platform.resolvedExecutable,
            checker.path,
            project.path,
            capture.path,
          ],
        ),
      ).run();

      expect(report.files, 2);
      expect(report.strings, 2);
      expect(report.restored, isTrue);
      expect(apiFile.readAsStringSync(), originalApi);
      expect(
        File(
          p.join(project.path, 'packages/config/lib/channel.dart'),
        ).readAsStringSync(),
        packageSource,
      );
      expect(
        File(p.join(project.path, runtimeRelative)).readAsStringSync(),
        placeholder,
      );

      final protectedApi = File(
        p.join(capture.path, 'api.dart'),
      ).readAsStringSync();
      final protectedChannel = File(
        p.join(capture.path, 'channel.dart'),
      ).readAsStringSync();
      expect(protectedApi, isNot(contains('https://api.example.com')));
      expect(protectedChannel, isNot(contains('app_store')));
      final cipher = RegExp(
        r'''decryptedPS\(['"]{2},\s*['"]([^'"]+)['"]\)''',
      ).firstMatch(protectedApi)![1]!;
      final config = File(
        p.join(capture.path, 'config.dart'),
      ).readAsStringSync();
      final key = RegExp(r"keyBase64 = '([^']+)';").firstMatch(config)![1]!;
      final iv = RegExp(r"ivBase64 = '([^']+)';").firstMatch(config)![1]!;
      final decrypted = Encrypter(
        AES(Key(base64Decode(key)), mode: AESMode.cbc),
      ).decrypt64(cipher, iv: IV(base64Decode(iv)));
      expect(decrypted, 'https://api.example.com');
    },
  );
}

void _write(String root, String relative, String contents) {
  final file = File(p.join(root, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
