import 'dart:convert';
import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('keeps encrypted containers in a copied project', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ios_asset_permanent_test_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = Directory(p.join(temporary.path, 'app'))..createSync();
    final image = File(p.join(project.path, 'assets/images/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.generate(257, (index) => index % 251));
    final animation =
        File(p.join(project.path, 'assets/animation/loading.svga'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(List<int>.generate(193, (index) => index % 239));
    final lottie = File(p.join(project.path, 'assets/animation/loading.json'))
      ..writeAsStringSync('{"v":"5.0.0"}');
    final audio = File(p.join(project.path, 'assets/audio/click.mp3'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.generate(211, (index) => index % 241));
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture
environment:
  sdk: ^3.9.2
flutter:
  assets:
    - assets/images/
    - assets/animation/
    - assets/audio/
''');
    final runtime = File(p.join(project.path, 'lib/p_config.g.dart'))
      ..createSync(recursive: true);
    runtime.writeAsStringSync('''
abstract final class PAssetContainerConfig {
  static const bool enabled = false;
}
''');
    final animationOnlyConfig = IosAssetBuildConfig.fromArguments([
      '--ios-assets-build',
      '--project=${project.path}',
      '--animation-asset-dir=assets/animation',
      '--container-dir=assets/animation',
      '--runtime-config=lib/p_config.g.dart',
      '--',
      Platform.resolvedExecutable,
      '--version',
    ]);
    expect(animationOnlyConfig.assetDirectories, isEmpty);
    expect(animationOnlyConfig.animationAssetDirectories, hasLength(1));
    expect(animationOnlyConfig.audioAssetDirectories, isEmpty);

    final report = await IosAssetContainerBuilder(
      IosAssetBuildConfig(
        projectPath: project.path,
        assetDirectories: const ['assets/images'],
        animationAssetDirectories: const ['assets/animation'],
        audioAssetDirectories: const ['assets/audio'],
        runtimeConfigPath: 'lib/p_config.g.dart',
      ),
    ).applyPermanently();

    expect(report.images, 1);
    expect(report.animations, 2);
    expect(report.audio, 1);
    expect(report.restored, isFalse);
    expect(image.existsSync(), isFalse);
    expect(animation.existsSync(), isFalse);
    expect(lottie.existsSync(), isFalse);
    expect(audio.existsSync(), isFalse);
    final generated = Directory(
      p.join(project.path, 'assets/images'),
    ).listSync().whereType<File>().toList();
    expect(generated.where((file) => file.path.endsWith('.dat')), hasLength(1));
    expect(generated.where((file) => file.path.endsWith('.cfg')), hasLength(1));
    expect(runtime.readAsStringSync(), contains('PAssetContainerConfig'));
    expect(
      Directory(
        p.join(project.path, '.dart_prefix_renamer_asset_transaction'),
      ).existsSync(),
      isFalse,
    );
  });

  test('builds with encrypted images and restores source files', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ios_asset_container_test_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = Directory(p.join(temporary.path, 'app'))..createSync();
    final image = File(p.join(project.path, 'assets/images/home/logo.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List<int>.generate(513, (index) => index % 251));
    final originalBytes = image.readAsBytesSync();
    final originalModified = DateTime(2020, 1, 2, 3, 4, 5);
    image.setLastModifiedSync(originalModified);
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture
environment:
  sdk: ^3.9.2
flutter:
  assets:
    - assets/images/
    - assets/images/home/
    - assets/data.json
''');
    final runtime = File(
      p.join(
        project.path,
        'lib/app_tools/asset_container/asset_container_config.g.dart',
      ),
    )..createSync(recursive: true);
    runtime.writeAsStringSync('const placeholder = true;\n');
    final checker = File(p.join(temporary.path, 'check.dart'))
      ..writeAsStringSync('''
import 'dart:io';

void main(List<String> args) {
  final root = args.single;
  if (File('\$root/assets/images/home/logo.png').existsSync()) exit(10);
  final images = Directory('\$root/assets/images').listSync();
  if (!images.any((e) => e.path.endsWith('.dat'))) exit(11);
  if (!images.any((e) => e.path.endsWith('.cfg'))) exit(12);
  final config = File('\$root/lib/app_tools/asset_container/asset_container_config.g.dart').readAsStringSync();
  if (!config.contains('enabled = true')) exit(13);
  final pubspec = File('\$root/pubspec.yaml').readAsStringSync();
  if (pubspec.contains('- assets/images/home/')) exit(14);
  if (!pubspec.contains('.dat') || !pubspec.contains('.cfg')) exit(15);
}
''');

    final report = await IosAssetContainerBuilder(
      IosAssetBuildConfig(
        projectPath: project.path,
        assetDirectories: const ['assets/images'],
        buildCommand: [Platform.resolvedExecutable, checker.path, project.path],
      ),
    ).run();

    expect(report.images, 1);
    expect(report.buildExitCode, 0);
    expect(report.restored, isTrue);
    expect(image.readAsBytesSync(), originalBytes);
    expect(image.lastModifiedSync(), originalModified);
    expect(runtime.readAsStringSync(), 'const placeholder = true;\n');
    expect(
      File(p.join(project.path, 'pubspec.yaml')).readAsStringSync(),
      contains('- assets/images/home/'),
    );
    expect(
      Directory(p.join(project.path, 'assets/images'))
          .listSync()
          .whereType<File>()
          .where((file) => ['.dat', '.cfg'].contains(p.extension(file.path))),
      isEmpty,
    );
  });

  test('manual recovery restores an interrupted transaction', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'ios_asset_recovery_test_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final project = Directory(p.join(temporary.path, 'app'))..createSync();
    final transaction = Directory(
      p.join(project.path, '.dart_prefix_renamer_asset_transaction'),
    )..createSync(recursive: true);
    final backup = File(p.join(transaction.path, 'files/assets/images/a.png'))
      ..createSync(recursive: true)
      ..writeAsStringSync('image');
    File(p.join(transaction.path, 'runtime_config.bak'))
      ..createSync(recursive: true)
      ..writeAsStringSync('runtime');
    File(
      p.join(transaction.path, 'pubspec.yaml.bak'),
    ).writeAsStringSync('pubspec');
    File(p.join(project.path, 'assets/images/temp.dat'))
      ..createSync(recursive: true)
      ..writeAsStringSync('container');
    File(p.join(transaction.path, 'transaction.json')).writeAsStringSync(
      jsonEncode({
        'runtimeConfig': 'lib/config.g.dart',
        'files': [
          {
            'path': 'assets/images/a.png',
            'modifiedMicros': DateTime(2020).microsecondsSinceEpoch,
          },
        ],
        'generated': ['assets/images/temp.dat'],
      }),
    );

    final restored = await restoreIosAssetTransaction(project.path);

    expect(restored, 1);
    expect(backup.existsSync(), isFalse);
    expect(
      File(p.join(project.path, 'assets/images/a.png')).readAsStringSync(),
      'image',
    );
    expect(
      File(p.join(project.path, 'assets/images/temp.dat')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(project.path, 'lib/config.g.dart')).readAsStringSync(),
      'runtime',
    );
    expect(
      File(p.join(project.path, 'pubspec.yaml')).readAsStringSync(),
      'pubspec',
    );
  });
}
