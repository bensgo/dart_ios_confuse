import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'dependency_planner.dart';

const _podfileBegin = '# dart_prefix_renamer:third-party-pod-begin';
const _podfileEnd = '# dart_prefix_renamer:third-party-pod-end';
const _importBegin = '// dart_prefix_renamer:third-party-import-begin';
const _importEnd = '// dart_prefix_renamer:third-party-import-end';
const _startBegin = '// dart_prefix_renamer:third-party-start-begin';
const _startEnd = '// dart_prefix_renamer:third-party-start-end';

class DependencyGenerator {
  DependencyGenerator({
    required this.projectRoot,
    this.runPodInstall = true,
    this.processRunner = Process.run,
  });

  final String projectRoot;
  final bool runPodInstall;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  })
  processRunner;

  Future<DependencyGenerationReport> generate(
    DependencySelectionPlan plan,
  ) async {
    if (!plan.enabled) return DependencyGenerationReport.disabled();
    final podName = dependencyPodName(plan.productId);
    final ios = Directory(p.join(projectRoot, 'ios'));
    final podfile = File(p.join(ios.path, 'Podfile'));
    final appDelegate = File(p.join(ios.path, 'Runner', 'AppDelegate.swift'));
    final podDirectory = Directory(p.join(ios.path, 'LocalPods', podName));
    if (!ios.existsSync() ||
        !podfile.existsSync() ||
        !appDelegate.existsSync()) {
      throw StateError(
        'Dependency generation requires ios/Podfile and '
        'ios/Runner/AppDelegate.swift.',
      );
    }
    if (podDirectory.existsSync()) {
      return _verifyExisting(
        plan: plan,
        podName: podName,
        podDirectory: podDirectory,
        podfile: podfile,
        appDelegate: appDelegate,
      );
    }
    final originalPodfile = await podfile.readAsString();
    final originalAppDelegate = await appDelegate.readAsString();
    _validateMarkers(originalPodfile, originalAppDelegate);

    final generated = <File>[];
    try {
      final sources = Directory(p.join(podDirectory.path, 'Sources'));
      await sources.create(recursive: true);
      generated.add(
        await _write(podDirectory, '$podName.podspec', _podspec(podName, plan)),
      );
      generated.add(
        await _write(
          sources,
          '${podName}Runtime.swift',
          _runtime(podName, plan),
        ),
      );
      for (final selected in plan.selected) {
        generated.add(
          await _write(
            sources,
            '${probeClassName(selected.id)}.swift',
            _probe(selected.id, selected.candidate.moduleName!),
          ),
        );
      }
      generated.add(
        await _write(
          podDirectory,
          'third_party_manifest.json',
          '${const JsonEncoder.withIndent('  ').convert(plan.toJson())}\n',
        ),
      );
      await podfile.writeAsString(_wirePodfile(originalPodfile, podName, plan));
      await appDelegate.writeAsString(
        _wireAppDelegate(originalAppDelegate, podName),
      );
      if (runPodInstall) {
        await _runPodInstall();
      }
    } catch (_) {
      await podfile.writeAsString(originalPodfile);
      await appDelegate.writeAsString(originalAppDelegate);
      if (podDirectory.existsSync()) {
        await podDirectory.delete(recursive: true);
      }
      rethrow;
    }
    final hashes = <String, String>{
      for (final file in generated)
        p.posix.joinAll(p.split(p.relative(file.path, from: projectRoot))):
            sha256.convert(await file.readAsBytes()).toString(),
    };
    return DependencyGenerationReport(
      enabled: true,
      podName: podName,
      podDirectory: podDirectory.path,
      podfile: podfile.path,
      appDelegate: appDelegate.path,
      generatedFiles: generated
          .map((file) => file.path)
          .toList(growable: false),
      artifactHashes: hashes,
    );
  }

  Future<DependencyGenerationReport> _verifyExisting({
    required DependencySelectionPlan plan,
    required String podName,
    required Directory podDirectory,
    required File podfile,
    required File appDelegate,
  }) async {
    final manifest = File(
      p.join(podDirectory.path, 'third_party_manifest.json'),
    );
    if (!manifest.existsSync() ||
        jsonEncode(jsonDecode(await manifest.readAsString())) !=
            jsonEncode(plan.toJson())) {
      throw StateError(
        'Existing dependency Pod does not match the deterministic plan.',
      );
    }
    final podfileSource = await podfile.readAsString();
    final appDelegateSource = await appDelegate.readAsString();
    if (!podfileSource.contains(_podfileBegin) ||
        !podfileSource.contains(_podfileEnd) ||
        !appDelegateSource.contains(_importBegin) ||
        !appDelegateSource.contains(_startBegin)) {
      throw StateError('Existing dependency Pod wiring is incomplete.');
    }
    final files = <File>[
      File(p.join(podDirectory.path, '$podName.podspec')),
      File(p.join(podDirectory.path, 'Sources', '${podName}Runtime.swift')),
      for (final selected in plan.selected)
        File(
          p.join(
            podDirectory.path,
            'Sources',
            '${probeClassName(selected.id)}.swift',
          ),
        ),
      manifest,
    ];
    final missing = files.where((file) => !file.existsSync()).toList();
    if (missing.isNotEmpty) {
      throw StateError('Existing dependency Pod is missing generated files.');
    }
    final expectedContents = <File, String>{
      File(p.join(podDirectory.path, '$podName.podspec')): _podspec(
        podName,
        plan,
      ),
      File(p.join(podDirectory.path, 'Sources', '${podName}Runtime.swift')):
          _runtime(podName, plan),
      for (final selected in plan.selected)
        File(
          p.join(
            podDirectory.path,
            'Sources',
            '${probeClassName(selected.id)}.swift',
          ),
        ): _probe(
          selected.id,
          selected.candidate.moduleName!,
        ),
      manifest:
          '${const JsonEncoder.withIndent('  ').convert(plan.toJson())}\n',
    };
    var refreshed = false;
    for (final entry in expectedContents.entries) {
      if (await entry.key.readAsString() != entry.value) {
        await entry.key.writeAsString(entry.value);
        refreshed = true;
      }
    }
    if (refreshed && runPodInstall) {
      await _runPodInstall();
    }
    final hashes = <String, String>{
      for (final file in files)
        p.posix.joinAll(p.split(p.relative(file.path, from: projectRoot))):
            sha256.convert(await file.readAsBytes()).toString(),
    };
    return DependencyGenerationReport(
      enabled: true,
      podName: podName,
      podDirectory: podDirectory.path,
      podfile: podfile.path,
      appDelegate: appDelegate.path,
      generatedFiles: files.map((file) => file.path).toList(growable: false),
      artifactHashes: hashes,
    );
  }

  Future<void> _runPodInstall() async {
    final result = await processRunner('pod', [
      'install',
      '--project-directory=ios',
    ], workingDirectory: projectRoot);
    if (result.exitCode != 0) {
      throw ProcessException(
        'pod',
        const ['install', '--project-directory=ios'],
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
  }

  void _validateMarkers(String podfile, String appDelegate) {
    if (podfile.contains(_podfileBegin) || podfile.contains(_podfileEnd)) {
      throw StateError('Podfile already contains third-party Pod markers.');
    }
    if (appDelegate.contains(_importBegin) ||
        appDelegate.contains(_startBegin)) {
      throw StateError('AppDelegate already contains third-party Pod markers.');
    }
    if (!RegExp(
      r'^([ \t]*)flutter_install_all_ios_pods\b',
      multiLine: true,
    ).hasMatch(podfile)) {
      throw StateError('Cannot find flutter_install_all_ios_pods in Podfile.');
    }
    if (!appDelegate.contains(
      'GeneratedPluginRegistrant.register(with: self)',
    )) {
      throw StateError('Cannot find GeneratedPluginRegistrant in AppDelegate.');
    }
  }

  String _wirePodfile(
    String source,
    String podName,
    DependencySelectionPlan plan,
  ) {
    final marker = RegExp(
      r'^([ \t]*)flutter_install_all_ios_pods\b',
      multiLine: true,
    ).firstMatch(source)!;
    final indent = marker.group(1)!;
    final externalSources = plan.selected
        .where((item) => item.candidate.sourceGit != null)
        .map(
          (item) =>
              "$indent pod '${item.candidate.podName}', :git => '${item.candidate.sourceGit}', :tag => '${item.candidate.sourceTag}'",
        )
        .join('\n');
    final block =
        '$indent$_podfileBegin\n'
        '${externalSources.isEmpty ? '' : '$externalSources\n'}'
        "$indent pod '$podName', :path => './LocalPods/$podName'\n"
        '$indent$_podfileEnd\n';
    return source.replaceRange(marker.start, marker.start, block);
  }

  String _wireAppDelegate(String source, String podName) {
    final imports = RegExp(
      r'^import\s+[A-Za-z_][A-Za-z0-9_]*\s*$',
      multiLine: true,
    ).allMatches(source).toList(growable: false);
    if (imports.isEmpty) throw StateError('Cannot find Swift imports.');
    var wired = source.replaceRange(
      imports.last.end,
      imports.last.end,
      '\n$_importBegin\nimport $podName\n$_importEnd',
    );
    final registrant = RegExp(
      r'GeneratedPluginRegistrant\.register\(with:\s*self\)',
    ).firstMatch(wired)!;
    wired = wired.replaceRange(
      registrant.end,
      registrant.end,
      '\n        $_startBegin\n'
      '        ${podName}Runtime.start()\n'
      '        $_startEnd',
    );
    return wired;
  }
}

class DependencyGenerationReport {
  const DependencyGenerationReport({
    required this.enabled,
    required this.podName,
    required this.podDirectory,
    required this.podfile,
    required this.appDelegate,
    required this.generatedFiles,
    required this.artifactHashes,
  });

  factory DependencyGenerationReport.disabled() =>
      const DependencyGenerationReport(
        enabled: false,
        podName: '',
        podDirectory: '',
        podfile: '',
        appDelegate: '',
        generatedFiles: [],
        artifactHashes: {},
      );

  final bool enabled;
  final String podName;
  final String podDirectory;
  final String podfile;
  final String appDelegate;
  final List<String> generatedFiles;
  final Map<String, String> artifactHashes;
}

Future<File> _write(Directory directory, String name, String contents) async {
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, name));
  await file.writeAsString(contents);
  return file;
}

String _podspec(String podName, DependencySelectionPlan plan) =>
    '''
Pod::Spec.new do |spec|
  spec.name = '$podName'
  spec.version = '1.0.0'
  spec.summary = 'Generated offline third-party capability probes.'
  spec.homepage = 'https://localhost.invalid/$podName'
  spec.license = { :type => 'Private' }
  spec.author = { 'dart_prefix_renamer' => 'local' }
  spec.source = { :path => '.' }
  spec.platform = :ios, '13.0'
  spec.swift_version = '5.0'
  spec.source_files = 'Sources/**/*.swift'
${plan.selected.map((item) => "  spec.dependency '${item.candidate.podName}', '= ${item.candidate.selectedVersion}'").join('\n')}
end
''';

String _runtime(String podName, DependencySelectionPlan plan) =>
    '''
import Foundation

protocol ThirdPartyProbe {
    static var identifier: String { get }
    static func run() throws -> [String: Any]
}

public final class ${podName}Runtime {
    private static let stateLock = NSLock()
    private static var started = false
    private static var results: [String: [String: Any]] = [:]

    public static func start() {
        stateLock.lock()
        guard !started else {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()
        DispatchQueue.global(qos: .utility).async {
            let probes: [ThirdPartyProbe.Type] = [
${plan.selected.map((item) => '                ${probeClassName(item.id)}.self,').join('\n')}
            ]
            var snapshot: [String: [String: Any]] = [:]
            for probe in probes {
                let startedAt = DispatchTime.now().uptimeNanoseconds
                do {
                    var value = try probe.run()
                    value["status"] = "ok"
                    value["duration_ns"] = DispatchTime.now().uptimeNanoseconds - startedAt
                    snapshot[probe.identifier] = value
                } catch {
                    snapshot[probe.identifier] = [
                        "status": "error",
                        "error_type": String(describing: type(of: error))
                    ]
                }
            }
            stateLock.lock()
            results = snapshot
            stateLock.unlock()
        }
    }

    public static func snapshot() -> [String: [String: Any]] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return results
    }
}
''';

String _probe(String id, String module) {
  final className = probeClassName(id);
  final body = switch (id) {
    'kingfisher' =>
      '''
        let url = URL(string: "https://localhost.invalid/probe.png")!
        let resource = KF.ImageResource(downloadURL: url, cacheKey: "offline-image-probe")
        return ["cache_key": resource.cacheKey]
''',
    'sdwebimage' =>
      '''
        let url = URL(string: "https://localhost.invalid/probe.png")!
        let key = SDWebImageManager.shared.cacheKey(for: url) ?? ""
        return ["cache_key": key]
''',
    'alamofire' =>
      '''
        let request = URLRequest(url: URL(string: "https://localhost.invalid/probe")!)
        let encoded = try URLEncoding.default.encode(request, with: ["mode": "offline"])
        return ["query_length": encoded.url?.query?.count ?? 0]
''',
    'grdb' =>
      '''
        let queue = try DatabaseQueue()
        let value = try queue.read { database in
            try Int.fetchOne(database, sql: "SELECT 7 * 6") ?? 0
        }
        return ["value": value]
''',
    'zipfoundation' =>
      '''
        let archive = try Archive(accessMode: .create)
        let data = Data("offline-archive-probe".utf8)
        try archive.addEntry(with: "probe.txt", type: .file, uncompressedSize: Int64(data.count), bufferSize: 8) { position, size in
            data.subdata(in: Int(position)..<(Int(position) + size))
        }
        return ["archive_bytes": archive.data?.count ?? 0]
''',
    'swiftprotobuf' =>
      '''
        var timestamp = Google_Protobuf_Timestamp()
        timestamp.seconds = 42
        let data = try timestamp.serializedData()
        return ["serialized_bytes": data.count]
''',
    'cryptoswift' =>
      '''
        return ["digest": "offline-capability-probe".sha256()]
''',
    'devicekit' =>
      '''
        let device = Device.current
        return [
            "family": device.isPad ? "pad" : (device.isPhone ? "phone" : "other"),
            "simulator": device.isSimulator
        ]
''',
    'promisekit' =>
      '''
        let promise = Promise<Int>.value(42)
        return ["resolved": promise.isResolved, "value": promise.value ?? 0]
''',
    'swifterswift' =>
      '''
        return ["normalized": "Offline Capability Probe".camelCased]
''',
    'swiftyjson' =>
      '''
        let json = JSON(["probe": ["value": 42]])
        return ["value": json["probe"]["value"].intValue]
''',
    'objectmapper' =>
      '''
        let map = Map(mappingType: .fromJSON, JSON: ["probe": 42])
        return ["keys": map.JSON.count]
''',
    'differencekit' =>
      '''
        let changeset = StagedChangeset(
            source: [DifferenceKitProbeValue(value: 1), DifferenceKitProbeValue(value: 2)],
            target: [DifferenceKitProbeValue(value: 2), DifferenceKitProbeValue(value: 3)]
        )
        return ["stages": changeset.count]
''',
    'swiftsoup' =>
      '''
        let document = try SwiftSoup.parse("<p>offline-probe</p>")
        return ["text_length": try document.text().count]
''',
    'swinject' =>
      '''
        let container = Container()
        container.register(Int.self) { _ in 42 }
        return ["value": container.resolve(Int.self) ?? 0]
''',
    _ => throw ArgumentError.value(id, 'id', 'Unsupported probe template'),
  };
  return '''
import Foundation
import $module

${_probeSupportingSource(id)}

enum $className: ThirdPartyProbe {
    static let identifier = "$id"

    static func run() throws -> [String: Any] {$body    }
}
''';
}

String _probeSupportingSource(String id) => switch (id) {
  'differencekit' =>
    '''
private struct DifferenceKitProbeValue: Differentiable, Equatable {
    let value: Int
    var differenceIdentifier: Int { value }
}
''',
  _ => '',
};

Future<int> restoreGeneratedDependencies({
  required String projectRoot,
  required DependencyGenerationReport report,
}) async {
  if (!report.enabled) return 0;
  final podfile = File(report.podfile);
  final appDelegate = File(report.appDelegate);
  var restored = 0;
  if (podfile.existsSync()) {
    final source = await podfile.readAsString();
    final cleaned = source.replaceFirst(
      RegExp(
        '${RegExp.escape(_podfileBegin)}.*?${RegExp.escape(_podfileEnd)}\\n?',
        dotAll: true,
      ),
      '',
    );
    if (cleaned != source) {
      await podfile.writeAsString(cleaned);
      restored++;
    }
  }
  if (appDelegate.existsSync()) {
    var source = await appDelegate.readAsString();
    for (final pair in [
      [_importBegin, _importEnd],
      [_startBegin, _startEnd],
    ]) {
      source = source.replaceFirst(
        RegExp(
          '${RegExp.escape(pair[0])}.*?${RegExp.escape(pair[1])}\\n?',
          dotAll: true,
        ),
        '',
      );
    }
    await appDelegate.writeAsString(source);
    restored++;
  }
  final directory = Directory(report.podDirectory);
  if (directory.existsSync()) {
    await directory.delete(recursive: true);
    restored += report.generatedFiles.length;
  }
  return restored;
}
