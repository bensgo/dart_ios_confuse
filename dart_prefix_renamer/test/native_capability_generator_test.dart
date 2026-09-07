import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'generates only enabled system capabilities deterministically',
    () async {
      final root = await Directory.systemTemp.createTemp('native_capability_');
      addTearDown(() => root.delete(recursive: true));
      final fixture = p.absolute('test/fixtures/wp00_baseline');
      await _copyDirectory(Directory(fixture), root);
      final manifest = CapabilityConfigLoader(
        projectRoot: fixture,
      ).loadNativeCapabilities('config/native_capabilities.yaml');
      final generator = NativeCapabilityGenerator(projectRoot: root.path);
      final first = await generator.generate(manifest);
      final second = await generator.generate(manifest);

      expect(
        first.enabled,
        containsAll(NativeCapabilityGenerator.supportedCapabilities),
      );
      expect(first.contentHash, second.contentHash);
      expect(
        File(
          p.join(root.path, 'ios/NativeCapabilities/ImageCapability.swift'),
        ).existsSync(),
        isFalse,
      );
      final network = File(
        p.join(root.path, 'ios/NativeCapabilities/NetworkCapability.swift'),
      ).readAsStringSync();
      expect(network, contains('NWPathMonitor'));
      final secureStorage = File(
        p.join(
          root.path,
          'ios/NativeCapabilities/SecureStorageCapability.swift',
        ),
      ).readAsStringSync();
      expect(secureStorage, contains('SecItemAdd'));
      expect(secureStorage.toLowerCase(), isNot(contains('deviceidentifier')));
      expect(
        File(
          p.join(
            root.path,
            'ios/NativeCapabilities/NativeCapabilities.podspec',
          ),
        ).existsSync(),
        isTrue,
      );
      final podfile = File(p.join(root.path, 'ios/Podfile')).readAsStringSync();
      expect("pod 'NativeCapabilities'".allMatches(podfile), hasLength(1));
      final performance = File(
        p.join(root.path, 'ios/NativeCapabilities/PerformanceCapability.swift'),
      ).readAsStringSync();
      expect(performance, contains('func mark(_ name: String)'));

      if (Platform.isMacOS && _commandExists('xcrun')) {
        final sdk = Process.runSync('xcrun', [
          '--sdk',
          'iphoneos',
          '--show-sdk-path',
        ]);
        expect(sdk.exitCode, 0, reason: '${sdk.stderr}');
        final swiftFiles =
            Directory(p.join(root.path, 'ios/NativeCapabilities'))
                .listSync()
                .whereType<File>()
                .where((file) => file.path.endsWith('.swift'))
                .map((file) => file.path)
                .toList();
        final compile = Process.runSync('xcrun', [
          'swiftc',
          '-target',
          'arm64-apple-ios13.0',
          '-sdk',
          (sdk.stdout as String).trim(),
          '-parse-as-library',
          '-typecheck',
          ...swiftFiles,
        ]);
        expect(
          compile.exitCode,
          0,
          reason: '${compile.stdout}\n${compile.stderr}',
        );
      }
    },
  );

  test('generates Pigeon contract and verifies production consumers', () async {
    final fixture = p.absolute('test/fixtures/wp00_baseline');
    final root = await Directory.systemTemp.createTemp('pigeon_bridge_');
    addTearDown(() => root.delete(recursive: true));
    await _copyDirectory(Directory(fixture), root);
    final manifest = CapabilityConfigLoader(
      projectRoot: root.path,
    ).loadNativeCapabilities('config/native_capabilities.yaml');
    await NativeCapabilityGenerator(projectRoot: root.path).generate(manifest);
    final result = await PigeonBridgeGenerator(
      projectRoot: root.path,
    ).generate(manifest);
    expect(File(result.pigeonFile).readAsStringSync(), contains('@HostApi()'));
    expect(result.generatorVersion, '26.3.4');
    expect(result.generatedFiles, hasLength(4));
    expect(
      result.generatedFiles.every((path) => File(path).existsSync()),
      isTrue,
    );
    expect(
      result.generatedFiles.every((path) => p.isWithin(root.path, path)),
      isTrue,
    );
    final appDelegate = File(
      p.join(root.path, 'ios/Runner/AppDelegate.swift'),
    ).readAsStringSync();
    expect(
      'NativeCapabilityInstaller.install'.allMatches(appDelegate),
      hasLength(1),
    );
    expect(appDelegate, contains('import NativeCapabilities'));
    expect(result.report.enabledCount, 6);
    expect(result.report.calledCount, 6);
    expect(result.report.capabilities['image']!.enabled, isFalse);
    if (Platform.isMacOS && _commandExists('xcrun')) {
      _typecheckPigeonBridge(root, result);
    }
  });
}

bool _commandExists(String command) {
  final result = Process.runSync('/usr/bin/which', [command]);
  return result.exitCode == 0;
}

void _typecheckPigeonBridge(Directory root, PigeonBridgeReport result) {
  final sdk =
      (Process.runSync('xcrun', ['--sdk', 'iphoneos', '--show-sdk-path']).stdout
              as String)
          .trim();
  final nativeFiles = Directory(p.join(root.path, 'ios/NativeCapabilities'))
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.swift'))
      .map((file) => file.path)
      .toList();
  var flutterRoot = Platform.resolvedExecutable;
  for (var index = 0; index < 5; index++) {
    flutterRoot = p.dirname(flutterRoot);
  }
  final flutterFramework = p.join(
    flutterRoot,
    'bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64',
  );
  final bridgeCompile = Process.runSync('xcrun', [
    'swiftc',
    '-target',
    'arm64-apple-ios13.0',
    '-sdk',
    sdk,
    '-typecheck',
    '-F',
    flutterFramework,
    '-module-name',
    'NativeCapabilities',
    ...nativeFiles,
  ]);
  expect(
    bridgeCompile.exitCode,
    0,
    reason: '${bridgeCompile.stdout}\n${bridgeCompile.stderr}',
  );
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
