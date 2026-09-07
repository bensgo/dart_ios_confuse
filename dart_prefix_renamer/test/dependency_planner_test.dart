import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:test/test.dart';

void main() {
  test('selects three deterministic dependencies for product_abc seed 0', () {
    final plan = DependencyPlanner(
      productId: 'product_abc',
      seed: 0,
      manifest: _manifest(),
      libraryPool: _pool(),
    ).createPlan();

    expect(plan.selected.map((item) => item.id), [
      'swiftsoup',
      'swinject',
      'differencekit',
    ]);
    expect(plan.resolvedManifest.dependencies, hasLength(3));
  });

  test('never selects both image providers', () {
    for (var seed = 0; seed < 100; seed++) {
      final plan = DependencyPlanner(
        productId: 'product_$seed',
        seed: seed,
        manifest: _manifest(),
        libraryPool: _pool(),
      ).createPlan();
      final selected = plan.selected.map((item) => item.id).toSet();
      expect(
        selected.contains('kingfisher') && selected.contains('sdwebimage'),
        isFalse,
      );
    }
  });

  test('accepts every configured selection count from 1 through 10', () {
    for (var count = 1; count <= 10; count++) {
      final plan = DependencyPlanner(
        productId: 'product_abc',
        seed: 0,
        manifest: _manifest(count: count),
        libraryPool: _pool(),
      ).createPlan();
      expect(plan.selected, hasLength(count));
    }
  });

  test('rejects counts outside the supported range before generation', () {
    final invalid = DependencyManifest(
      schemaVersion: 2,
      dependencies: const {},
      selection: DependencySelection(
        enabled: true,
        mode: 'deterministic_random',
        count: 11,
        execution: 'startup_background_once',
        candidates: const ['kingfisher', 'grdb', 'promisekit'],
      ),
    );
    expect(
      () => DependencyPlanner(
        productId: 'product_abc',
        seed: 0,
        manifest: invalid,
        libraryPool: _pool(),
      ).createPlan(),
      throwsFormatException,
    );
  });
}

DependencyManifest _manifest({int count = 3}) => DependencyManifest(
  schemaVersion: 2,
  dependencies: const {},
  selection: DependencySelection(
    enabled: true,
    mode: 'deterministic_random',
    count: count,
    execution: 'startup_background_once',
    candidates: const [
      'kingfisher',
      'sdwebimage',
      'alamofire',
      'grdb',
      'zipfoundation',
      'swiftprotobuf',
      'cryptoswift',
      'devicekit',
      'promisekit',
      'swifterswift',
      'swiftyjson',
      'objectmapper',
      'differencekit',
      'swiftsoup',
      'swinject',
    ],
  ),
);

IosLibraryPool _pool() {
  const metadata = <String, List<String>>{
    'kingfisher': ['Kingfisher', 'Kingfisher', 'image'],
    'sdwebimage': ['SDWebImage', 'SDWebImage', 'image'],
    'alamofire': ['Alamofire', 'Alamofire', ''],
    'grdb': ['GRDB.swift', 'GRDB', ''],
    'zipfoundation': ['ZIPFoundation', 'ZIPFoundation', ''],
    'swiftprotobuf': ['SwiftProtobuf', 'SwiftProtobuf', ''],
    'cryptoswift': ['CryptoSwift', 'CryptoSwift', ''],
    'devicekit': ['DeviceKit', 'DeviceKit', ''],
    'promisekit': ['PromiseKit', 'PromiseKit', ''],
    'swifterswift': ['SwifterSwift', 'SwifterSwift', ''],
    'swiftyjson': ['SwiftyJSON', 'SwiftyJSON', ''],
    'objectmapper': ['ObjectMapper', 'ObjectMapper', ''],
    'differencekit': ['DifferenceKit', 'DifferenceKit', ''],
    'swiftsoup': ['SwiftSoup', 'SwiftSoup', ''],
    'swinject': ['Swinject', 'Swinject', ''],
  };
  return IosLibraryPool(
    schemaVersion: 1,
    researchedAt: '2026-08-25',
    libraries: {
      for (final entry in metadata.entries)
        entry.key: IosLibraryCandidate(
          repository: 'example/${entry.key}',
          capability: entry.key,
          selectedVersion: '1.0.0',
          packageManager: 'cocoapods',
          license: 'MIT',
          minimumIos: '13.0',
          status: 'approved',
          reason: entry.key,
          evidenceUrls: const ['https://github.com/example/example'],
          podName: entry.value[0],
          moduleName: entry.value[1],
          probeTemplate: entry.key,
          binaryTokens: [entry.value[1]],
          conflictGroup: entry.value[2].isEmpty ? null : entry.value[2],
        ),
    },
  );
}
