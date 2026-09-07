import 'dart:convert';
import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late DependencyManifest manifest;
  late IosLibraryPool pool;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dependency_inspector_');
    final swift = File(p.join(root.path, 'ios/NativeCapabilities/Image.swift'));
    await swift.parent.create(recursive: true);
    await swift.writeAsString('''
import Kingfisher
func load() { imageView.kf.setImage(with: url) }
''');
    final resolved = File(p.join(root.path, 'ios/Package.resolved'));
    await resolved.writeAsString(
      jsonEncode({
        'pins': [
          {
            'identity': 'kingfisher',
            'state': {'version': '8.11.0'},
          },
        ],
      }),
    );
    await File(p.join(root.path, 'ios/Package.swift')).writeAsString('''
dependencies: [.package(url: "https://github.com/onevcat/Kingfisher", exact: "8.11.0")]
''');
    manifest = DependencyManifest(
      schemaVersion: 1,
      dependencies: {
        'Kingfisher': DependencySpec(
          version: '8.11.0',
          manager: 'spm',
          capability: 'image_cache',
          reason: 'image_cache',
          productionCall: 'ios/NativeCapabilities/Image.swift',
        ),
      },
    );
    pool = IosLibraryPool(
      schemaVersion: 1,
      researchedAt: '2026-08-21',
      libraries: {
        'kingfisher': const IosLibraryCandidate(
          repository: 'onevcat/Kingfisher',
          capability: 'image_cache',
          selectedVersion: '8.11.0',
          packageManager: 'spm',
          license: 'MIT',
          minimumIos: '13.0',
          status: 'approved',
          reason: 'image cache',
          evidenceUrls: ['https://github.com/onevcat/Kingfisher'],
        ),
      },
    );
  });

  tearDown(() => root.delete(recursive: true));

  test(
    'accepts approved locked dependency with real production API call',
    () async {
      final report = await DependencyInspector(
        projectRoot: root.path,
      ).inspect(manifest: manifest, libraryPool: pool);
      expect(report.justified, 1);
      expect(report.dependencies.single.used, isTrue);
    },
  );

  test('rejects import-only dependency', () async {
    await File(
      p.join(root.path, 'ios/NativeCapabilities/Image.swift'),
    ).writeAsString('import Kingfisher\n');
    final report = await DependencyInspector(
      projectRoot: root.path,
    ).inspect(manifest: manifest, libraryPool: pool);
    expect(report.justified, 0);
    expect(report.dependencies.single.failureCode, 'DEPENDENCY_UNJUSTIFIED');
  });

  test(
    'rejects a locked dependency missing from package declaration',
    () async {
      await File(p.join(root.path, 'ios/Package.swift')).delete();
      final report = await DependencyInspector(
        projectRoot: root.path,
      ).inspect(manifest: manifest, libraryPool: pool);
      expect(
        report.dependencies.single.failureCode,
        'DEPENDENCY_DECLARATION_MISSING',
      );
    },
  );
}
