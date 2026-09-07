import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('binds final IPA build identity into the manifest', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ipa_binding_test_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = Directory(p.join(temporary.path, 'project'))..createSync();
    _write(project.path, 'pubspec.lock', 'lock: 1\n');
    _write(
      project.path,
      'dart_prefix_renamer_manifest.json',
      jsonEncode({
        'version': 1,
        'prefix': 'abc',
        'targets': ['lib'],
        'iosProductPod': {
          'enabled': true,
          'productId': 'product_alpha',
          'seed': 42,
        },
      }),
    );

    final ipa = p.join(temporary.path, 'final.ipa');
    final runnerBytes = Uint8List.fromList(
      List<int>.filled(64, 0)..setRange(0, 4, [0xFE, 0xED, 0xFA, 0xCF]),
    );
    final appBytes = Uint8List.fromList(
      List<int>.filled(64, 0)..setRange(0, 4, [0xFE, 0xED, 0xFA, 0xCF]),
    );
    _writeZip(ipa, {
      'Payload/Test.app/Info.plist': utf8.encode('plist'),
      'Payload/Test.app/Runner': runnerBytes,
      'Payload/Test.app/Resources/a.txt': utf8.encode('resource'),
      'Payload/Test.app/Frameworks/App.framework/App': appBytes,
    });

    final report = await IpaBinder(
      IpaBindingConfig(projectPath: project.path, ipaPath: ipa),
    ).run();

    final bytes = File(ipa).readAsBytesSync();
    final expectedIpaSha = sha256.convert(bytes).toString();
    expect(report.ipaSha256, expectedIpaSha);
    expect(report.ipaSize, bytes.length);
    expect(report.toolVersion, kRenamerToolVersion);
    expect(report.prefix, 'abc');
    expect(report.seed, 42);
    expect(
      report.lockfileSha256,
      sha256.convert(utf8.encode('lock: 1\n')).toString(),
    );

    final components = {for (final c in report.components) c.path: c};
    expect(
      components.keys,
      containsAll([
        'Payload/Test.app/Runner',
        'Payload/Test.app/Frameworks/App.framework/App',
      ]),
    );
    expect(
      components['Payload/Test.app/Runner']!.sha256,
      sha256.convert(runnerBytes).toString(),
    );

    final stored =
        jsonDecode(
              File(
                p.join(project.path, 'dart_prefix_renamer_manifest.json'),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final identity = stored['artifact_identity'] as Map<String, dynamic>;
    expect(identity['ipa_sha256'], expectedIpaSha);
    expect(identity['main_bundle_sha256'], report.mainBundleSha256);
    expect(identity['tool_version'], kRenamerToolVersion);
    expect(identity['built_at'], report.builtAt.toIso8601String());
    expect(identity['lockfile_sha256'], report.lockfileSha256);
    expect(report.alreadyBound, isFalse);
  });

  test('rebinding the same IPA is idempotent', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ipa_binding_idempotent_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = Directory(p.join(temporary.path, 'project'))..createSync();
    _write(project.path, 'pubspec.lock', 'lock: 1\n');
    _write(
      project.path,
      'dart_prefix_renamer_manifest.json',
      jsonEncode({'version': 1, 'prefix': 'abc'}),
    );
    final ipa = p.join(temporary.path, 'final.ipa');
    _writeZip(ipa, {
      'Payload/Test.app/Runner': Uint8List.fromList([0xFE, 0xED, 0xFA, 0xCF]),
    });

    final first = await IpaBinder(
      IpaBindingConfig(projectPath: project.path, ipaPath: ipa),
    ).run();
    final second = await IpaBinder(
      IpaBindingConfig(projectPath: project.path, ipaPath: ipa),
    ).run();

    expect(second.ipaSha256, first.ipaSha256);
    expect(second.mainBundleSha256, first.mainBundleSha256);
    expect(second.alreadyBound, isTrue);
  });

  test('refuses to rebind a different IPA', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ipa_binding_rebind_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = Directory(p.join(temporary.path, 'project'))..createSync();
    _write(project.path, 'pubspec.lock', 'lock: 1\n');
    _write(
      project.path,
      'dart_prefix_renamer_manifest.json',
      jsonEncode({'version': 1, 'prefix': 'abc'}),
    );
    final first = p.join(temporary.path, 'first.ipa');
    final second = p.join(temporary.path, 'second.ipa');
    _writeZip(first, {
      'Payload/Test.app/Runner': Uint8List.fromList([0x01]),
    });
    _writeZip(second, {
      'Payload/Test.app/Runner': Uint8List.fromList([0x02]),
    });

    await IpaBinder(
      IpaBindingConfig(projectPath: project.path, ipaPath: first),
    ).run();
    await expectLater(
      IpaBinder(
        IpaBindingConfig(projectPath: project.path, ipaPath: second),
      ).run(),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('refusing to rebind'),
        ),
      ),
    );
  });

  test('rejects missing manifest, missing IPA and non-zip IPA', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ipa_binding_missing_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = Directory(p.join(temporary.path, 'project'))..createSync();
    final ipa = p.join(temporary.path, 'final.ipa');
    File(ipa).writeAsStringSync('not a zip');

    await expectLater(
      IpaBinder(
        IpaBindingConfig(projectPath: project.path, ipaPath: ipa),
      ).run(),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('Rename manifest does not exist'),
        ),
      ),
    );

    _write(project.path, 'dart_prefix_renamer_manifest.json', '{}');
    expect(
      () => IpaBindingConfig(
        projectPath: project.path,
        ipaPath: p.join(temporary.path, 'missing.ipa'),
      ),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('IPA file does not exist'),
        ),
      ),
    );

    File(ipa).writeAsStringSync('not a zip');
    await expectLater(
      IpaBinder(
        IpaBindingConfig(projectPath: project.path, ipaPath: ipa),
      ).run(),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('Not a readable ZIP'),
        ),
      ),
    );
  });
}

void _write(String root, String relative, String contents) {
  final file = File(p.join(root, relative));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _writeZip(String path, Map<String, Object> entries) {
  final archive = Archive();
  for (final entry in entries.entries) {
    final content = entry.value is Uint8List
        ? entry.value as Uint8List
        : utf8.encode(entry.value as String);
    archive.addFile(ArchiveFile(entry.key, content.length, content));
  }
  final bytes = ZipEncoder().encode(archive)!;
  File(path).writeAsBytesSync(bytes);
}
