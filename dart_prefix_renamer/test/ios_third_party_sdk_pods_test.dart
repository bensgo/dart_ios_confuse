import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('parses the isolated iOS third-party SDK Pod CLI', () {
    final fixture = p.absolute('test/fixtures/wp00_baseline');
    final config = IosThirdPartySdkPodsConfig.fromArguments([
      '--prepare-ios-third-party-sdk-pods',
      '--project=$fixture',
      '--ios-third-party-sdk-product-id=product_abc',
      '--ios-third-party-sdk-seed=7',
    ]);
    expect(config.productId, 'product_abc');
    expect(config.seed, 7);
    expect(config.dependenciesPath, 'config/dependencies.yaml');
    expect(config.libraryPoolPath, 'config/ios_library_pool.yaml');
  });

  test('does not require Dart or Native capability manifests', () async {
    final fixture = Directory(p.absolute('test/fixtures/wp00_baseline'));
    final root = await Directory.systemTemp.createTemp('third_party_sdk_pods_');
    addTearDown(() => root.delete(recursive: true));
    await _copyDirectory(fixture, root);
    await File(p.join(root.path, 'config/dart_capabilities.yaml')).delete();
    await File(p.join(root.path, 'config/native_capabilities.yaml')).delete();

    final report = await IosThirdPartySdkPodsRunner(
      IosThirdPartySdkPodsConfig(
        projectRoot: root.path,
        productId: 'product_abc',
        dependenciesPath: 'config/dependencies_random.yaml',
        seed: 0,
        runPodInstall: false,
      ),
    ).run();

    expect(
      report.passed,
      isFalse,
      reason: 'Podfile.lock is intentionally absent',
    );
    expect(report.generation.podName, 'ProductAbcThirdPartyKit');
    expect(report.dependencies.selected, 7);
    expect(
      File(
        p.join(root.path, 'reports/ios-third-party-sdk-pods/selection.json'),
      ).existsSync(),
      isTrue,
    );
  });
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    if (entity is Directory) {
      await Directory(
        p.join(destination.path, relative),
      ).create(recursive: true);
    } else if (entity is File) {
      final target = File(p.join(destination.path, relative));
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
    }
  }
}
