import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/capability_manifest.dart';
import '../model/capability_report.dart';

class PigeonBridgeGenerator {
  PigeonBridgeGenerator({required this.projectRoot});

  final String projectRoot;

  Future<PigeonBridgeReport> generate(NativeCapabilityManifest manifest) async {
    final enabled = manifest.native.entries
        .where((entry) => entry.value.enabled)
        .map((entry) => entry.key)
        .toSet();
    final bridges =
        manifest.bridges
            .where((bridge) => enabled.contains(_capabilityForApi(bridge.api)))
            .toList()
          ..sort((a, b) => a.api.compareTo(b.api));
    final pigeonFile = File(
      p.join(projectRoot, 'pigeons', 'native_capability_api.dart'),
    );
    await pigeonFile.parent.create(recursive: true);
    await pigeonFile.writeAsString(_schemaSource(bridges));
    final optionsFile = File(p.join(projectRoot, 'pigeon_options.yaml'));
    await optionsFile.writeAsString('''
input: pigeons/native_capability_api.dart
dart_out: lib/platform/generated/native_capability_api.g.dart
swift_out: ios/NativeCapabilities/Generated/NativeCapabilityApi.g.swift
swift_options:
  module: NativeCapabilities
''');
    final generation = await _runPigeon(pigeonFile);
    final handlerFile = await _writeSwiftHandler(bridges);
    final installerFile = await _writeSwiftInstaller();
    await _wireAppDelegate();

    final statuses = <String, NativeCapabilityStatus>{};
    for (final entry in manifest.native.entries) {
      final bridge = bridges.where(
        (candidate) => _capabilityForApi(candidate.api) == entry.key,
      );
      var called = false;
      for (final item in bridge) {
        final consumer = File(p.join(projectRoot, item.consumer));
        if (consumer.existsSync()) {
          final source = await consumer.readAsString();
          called = _consumerTokens(item.api).any(source.contains);
        }
      }
      statuses[entry.key] = NativeCapabilityStatus(
        enabled: entry.value.enabled,
        bridgeCalled: called,
        provider: entry.value.provider,
      );
    }
    return PigeonBridgeReport(
      pigeonFile: pigeonFile.path,
      optionsFile: optionsFile.path,
      generatorVersion: generation.version,
      generatedFiles: [
        ...generation.files,
        handlerFile.path,
        installerFile.path,
      ],
      report: NativeCapabilityReport(
        enabledCount: statuses.values.where((item) => item.enabled).length,
        registeredCount: bridges.length,
        calledCount: statuses.values.where((item) => item.bridgeCalled).length,
        capabilities: statuses,
      ),
    );
  }

  Future<File> _writeSwiftHandler(List<BridgeSpec> bridges) async {
    final file = File(
      p.join(
        projectRoot,
        'ios/NativeCapabilities/Generated/NativeCapabilityHostHandler.swift',
      ),
    );
    await file.parent.create(recursive: true);
    final methods = bridges
        .map(
          (bridge) => switch (bridge.api) {
            'crypto' =>
              '    func crypto(data: FlutterStandardTypedData, completion: @escaping (Result<String, Error>) -> Void) { completion(.success(bridge.crypto(data.data))) }',
            'deviceInfo' =>
              '    func deviceInfo(completion: @escaping (Result<String, Error>) -> Void) { complete(completion) { try bridge.deviceInfo() } }',
            'diagnostics' =>
              '    func diagnostics(completion: @escaping (Result<String, Error>) -> Void) { complete(completion) { try bridge.diagnostics() } }',
            'networkState' =>
              '    func networkState(completion: @escaping (Result<String, Error>) -> Void) { complete(completion) { try bridge.networkState() } }',
            'performance' =>
              '    func performance(name: String, completion: @escaping (Result<Void, Error>) -> Void) { bridge.performance(name); completion(.success(())) }',
            'secureStorage' =>
              '    func secureStorage(operation: String, key: String, value: String?, completion: @escaping (Result<String?, Error>) -> Void) { complete(completion) { try bridge.secureStorage(operation: operation, key: key, value: value) } }',
            _ => throw StateError(
              'Unsupported native bridge API: ${bridge.api}',
            ),
          },
        )
        .join('\n');
    await file.writeAsString('''
import Flutter
import Foundation

final class NativeCapabilityHostHandler: NativeCapabilityHostApi {
    private let bridge = NativeCapabilityBridge()
$methods
    private func complete<T>(_ completion: @escaping (Result<T, Error>) -> Void, _ body: () throws -> T) { do { completion(.success(try body())) } catch { completion(.failure(NativeCapabilityError.operationFailed)) } }
    private enum NativeCapabilityError: String, Error { case operationFailed }
}
''');
    return file;
  }

  Future<File> _writeSwiftInstaller() async {
    final file = File(
      p.join(
        projectRoot,
        'ios/NativeCapabilities/Generated/NativeCapabilityInstaller.swift',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('''
import Flutter
import Foundation

public enum NativeCapabilityInstaller {
    public static func install(binaryMessenger: FlutterBinaryMessenger) {
        NativeCapabilityHostApiSetup.setUp(
            binaryMessenger: binaryMessenger,
            api: NativeCapabilityHostHandler()
        )
    }
}
''');
    return file;
  }

  Future<void> _wireAppDelegate() async {
    final file = File(p.join(projectRoot, 'ios/Runner/AppDelegate.swift'));
    if (!file.existsSync()) {
      throw StateError('Missing ios/Runner/AppDelegate.swift.');
    }
    var source = await file.readAsString();
    const begin = '// dart-prefix-renamer:native-capabilities:begin';
    const end = '// dart-prefix-renamer:native-capabilities:end';
    const importBegin =
        '// dart-prefix-renamer:native-capabilities-import:begin';
    const importEnd = '// dart-prefix-renamer:native-capabilities-import:end';
    const block = '''$begin
        NativeCapabilityInstaller.install(binaryMessenger: controller.binaryMessenger)
        $end''';
    const fallbackBlock = '''$begin
    if let nativeCapabilityController = window?.rootViewController as? FlutterViewController {
      NativeCapabilityInstaller.install(binaryMessenger: nativeCapabilityController.binaryMessenger)
    }
    $end''';
    if (!source.contains(begin)) {
      final controller = RegExp(
        r'let\s+controller\s*=\s*window\?\.rootViewController\s+as!\s+FlutterViewController',
      ).firstMatch(source);
      if (controller != null) {
        source = source.replaceRange(
          controller.end,
          controller.end,
          '\n        $block',
        );
      } else {
        final registrant = RegExp(
          r'GeneratedPluginRegistrant\.register\(with:\s*self\)',
        ).firstMatch(source);
        if (registrant == null) {
          throw StateError(
            'AppDelegate FlutterViewController binding not found.',
          );
        }
        source = source.replaceRange(
          registrant.end,
          registrant.end,
          '\n    $fallbackBlock',
        );
      }
    }
    if (!source.contains(importBegin)) {
      final imports = RegExp(
        r'^import\s+[A-Za-z_][A-Za-z0-9_]*\s*$',
        multiLine: true,
      ).allMatches(source).toList(growable: false);
      if (imports.isEmpty) throw StateError('AppDelegate imports not found.');
      source = source.replaceRange(
        imports.last.end,
        imports.last.end,
        '\n$importBegin\nimport NativeCapabilities\n$importEnd',
      );
    }
    await file.writeAsString(source);
  }

  Future<({String version, List<String> files})> _runPigeon(File input) async {
    final runner = Directory(
      p.join(Directory.current.path, 'tool', 'pigeon_runner'),
    );
    if (!File(p.join(runner.path, 'pubspec.yaml')).existsSync()) {
      throw StateError('Pigeon runner not found: ${runner.path}');
    }
    final dartOut = p.join(
      projectRoot,
      'lib/platform/generated/native_capability_api.g.dart',
    );
    final swiftOut = p.join(
      projectRoot,
      'ios/NativeCapabilities/Generated/NativeCapabilityApi.g.swift',
    );
    await File(dartOut).parent.create(recursive: true);
    await File(swiftOut).parent.create(recursive: true);
    final runnerInput = File(
      p.join(runner.path, '.dart_tool', 'native_capability_api.dart'),
    );
    await runnerInput.parent.create(recursive: true);
    await input.copy(runnerInput.path);
    final pubGet = await Process.run('fvm', [
      'dart',
      'pub',
      'get',
      '--offline',
    ], workingDirectory: runner.path);
    if (pubGet.exitCode != 0) {
      throw StateError('Pigeon runner pub get failed: ${pubGet.stderr}');
    }
    final process = await Process.start('fvm', [
      'dart',
      'run',
      'pigeon',
      '--input',
      runnerInput.path,
      '--dart_out',
      dartOut,
      '--swift_out',
      swiftOut,
      '--package_name',
      _projectPackageName(),
    ], workingDirectory: runner.path);
    final stdoutFuture = process.stdout
        .transform(systemEncoding.decoder)
        .join();
    final stderrFuture = process.stderr
        .transform(systemEncoding.decoder)
        .join();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      process.kill();
      throw StateError('Pigeon generation timed out after 30 seconds.');
    }
    final output = await stdoutFuture;
    final error = await stderrFuture;
    if (exitCode != 0) {
      throw StateError('Pigeon generation failed: $output$error');
    }
    return (version: '26.3.4', files: [dartOut, swiftOut]);
  }

  String _projectPackageName() {
    final pubspec = File(
      p.join(projectRoot, 'pubspec.yaml'),
    ).readAsStringSync();
    final match = RegExp(
      r'^name:\s*([a-zA-Z0-9_]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    if (match == null) {
      throw StateError('Cannot read package name from pubspec.yaml.');
    }
    return match.group(1)!;
  }

  String _schemaSource(List<BridgeSpec> bridges) {
    final methods = bridges
        .map((bridge) {
          final methodName = switch (bridge.api) {
            'deviceInfo' => 'String deviceInfo();',
            'networkState' => 'String networkState();',
            'secureStorage' =>
              'String? secureStorage(String operation, String key, String? value);',
            'crypto' => 'String crypto(Uint8List data);',
            'diagnostics' => 'String diagnostics();',
            'performance' => 'void performance(String name);',
            _ => 'Map<String?, Object?> ${bridge.api}();',
          };
          return '  @async\n  $methodName';
        })
        .join('\n\n');
    return '''
import 'package:pigeon/pigeon.dart';

@HostApi()
abstract class NativeCapabilityHostApi {
$methods
}
''';
  }

  String _capabilityForApi(String api) => switch (api) {
    'deviceInfo' => 'device',
    'networkState' => 'network',
    'secureStorage' => 'secure_storage',
    'crypto' => 'crypto',
    'diagnostics' => 'diagnostics',
    'performance' => 'performance',
    _ => api,
  };

  List<String> _consumerTokens(String api) => switch (api) {
    'deviceInfo' => ['getDeviceInfo', 'deviceInfo'],
    'networkState' => ['getNetworkStatus', 'networkState'],
    'secureStorage' => ['getString', 'setString', 'secureStorage'],
    'crypto' => ['sha256', 'crypto'],
    'diagnostics' => ['getDiagnostics', 'diagnostics'],
    'performance' => ['markPerformance', '.mark(', 'performance'],
    _ => [api],
  };
}

class PigeonBridgeReport {
  const PigeonBridgeReport({
    required this.pigeonFile,
    required this.optionsFile,
    required this.generatorVersion,
    required this.generatedFiles,
    required this.report,
  });

  final String pigeonFile;
  final String optionsFile;
  final String generatorVersion;
  final List<String> generatedFiles;
  final NativeCapabilityReport report;
}
