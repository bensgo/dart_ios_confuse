import 'dart:io';

import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dependency_generator_');
    await _write(root, 'ios/Podfile', '''
target 'Runner' do
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
''');
    await _write(root, 'ios/Runner/AppDelegate.swift', '''
import UIKit
import Flutter

@main
class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
''');
  });

  tearDown(() => root.delete(recursive: true));

  test('generates selected Pod and safe background probes', () async {
    final report = await DependencyGenerator(
      projectRoot: root.path,
      runPodInstall: false,
    ).generate(_plan());

    expect(report.enabled, isTrue);
    expect(report.generatedFiles, hasLength(11));
    final podspec = File(
      p.join(report.podDirectory, '${report.podName}.podspec'),
    ).readAsStringSync();
    expect(podspec, contains("spec.dependency 'Kingfisher', '= 8.11.0'"));
    expect(podspec, contains("spec.dependency 'GRDB.swift', '= 7.11.1'"));
    expect(podspec, contains("spec.dependency 'PromiseKit', '= 8.2.0'"));
    expect(podspec, contains("spec.dependency 'SwiftyJSON', '= 5.0.2'"));
    expect(podspec, contains("spec.dependency 'ObjectMapper', '= 4.4.2'"));
    expect(podspec, contains("spec.dependency 'DifferenceKit', '= 1.3.0'"));
    expect(podspec, contains("spec.dependency 'SwiftSoup', '= 2.11.3'"));
    expect(podspec, contains("spec.dependency 'Swinject', '= 2.9.1'"));
    final runtime = File(
      p.join(report.podDirectory, 'Sources/${report.podName}Runtime.swift'),
    ).readAsStringSync();
    expect(runtime, contains('DispatchQueue.global(qos: .utility).async'));
    expect(runtime, contains('private static var started = false'));
    final allSources = Directory(p.join(report.podDirectory, 'Sources'))
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');
    for (final forbidden in [
      'Session.request',
      '.kf.setImage',
      'sd_setImage',
      'UserDefaults',
      'Keychain',
      'requestAuthorization',
      'UIApplication.shared',
      'DDLog',
      'SentrySDK',
    ]) {
      expect(allSources, isNot(contains(forbidden)), reason: forbidden);
    }
    for (final token in [
      'JSON([',
      'Map(mappingType:',
      'StagedChangeset(',
      'DifferenceKitProbeValue(value:',
      'SwiftSoup.parse(',
      'Container()',
    ]) {
      expect(allSources, contains(token), reason: token);
    }
    expect(
      File(p.join(root.path, 'ios/Podfile')).readAsStringSync(),
      allOf(
        contains('dart_prefix_renamer:third-party-pod-begin'),
        contains("pod 'GRDB.swift', :git =>"),
      ),
    );
    expect(
      File(
        p.join(root.path, 'ios/Runner/AppDelegate.swift'),
      ).readAsStringSync(),
      contains('${report.podName}Runtime.start()'),
    );
  });

  test('reuses an identical generated Pod without duplicate wiring', () async {
    final generator = DependencyGenerator(
      projectRoot: root.path,
      runPodInstall: false,
    );
    final first = await generator.generate(_plan());
    final second = await generator.generate(_plan());
    expect(second.artifactHashes, first.artifactHashes);
    final appDelegate = File(
      p.join(root.path, 'ios/Runner/AppDelegate.swift'),
    ).readAsStringSync();
    expect(
      'dart_prefix_renamer:third-party-start-begin'.allMatches(appDelegate),
      hasLength(1),
    );
  });

  test('refreshes stale generated probe sources for the same plan', () async {
    final generator = DependencyGenerator(
      projectRoot: root.path,
      runPodInstall: false,
    );
    final first = await generator.generate(_plan());
    final probe = File(
      p.join(first.podDirectory, 'Sources/DifferencekitProbe.swift'),
    );
    await probe.writeAsString('stale generated source');

    await generator.generate(_plan());

    expect(
      probe.readAsStringSync(),
      contains('DifferenceKitProbeValue(value:'),
    );
  });
}

DependencySelectionPlan _plan() {
  final selected = [
    _selected('kingfisher', 'Kingfisher', 'Kingfisher', '8.11.0'),
    _selected('grdb', 'GRDB.swift', 'GRDB', '7.11.1'),
    _selected('promisekit', 'PromiseKit', 'PromiseKit', '8.2.0'),
    _selected('swiftyjson', 'SwiftyJSON', 'SwiftyJSON', '5.0.2'),
    _selected('objectmapper', 'ObjectMapper', 'ObjectMapper', '4.4.2'),
    _selected('differencekit', 'DifferenceKit', 'DifferenceKit', '1.3.0'),
    _selected('swiftsoup', 'SwiftSoup', 'SwiftSoup', '2.11.3'),
    _selected('swinject', 'Swinject', 'Swinject', '2.9.1'),
  ];
  return DependencySelectionPlan(
    productId: 'product_abc',
    seed: 0,
    requestedCount: selected.length,
    selected: selected,
    decisions: [
      for (final item in selected)
        DependencySelectionDecision(
          id: item.id,
          score: item.score,
          selected: true,
          reason: 'selected',
        ),
    ],
    resolvedManifest: DependencyManifest(
      schemaVersion: 2,
      dependencies: {
        for (final item in selected)
          item.candidate.podName!: DependencySpec(
            version: item.candidate.selectedVersion,
            manager: 'cocoapods',
            capability: item.candidate.capability,
            reason: item.id,
            productionCall:
                'ios/LocalPods/ProductAbcThirdPartyKit/Sources/${probeClassName(item.id)}.swift',
          ),
      },
    ),
  );
}

SelectedDependency _selected(
  String id,
  String podName,
  String module,
  String version,
) => SelectedDependency(
  id: id,
  score: id.padRight(64, '0'),
  candidate: IosLibraryCandidate(
    repository: 'example/$id',
    capability: id,
    selectedVersion: version,
    packageManager: 'cocoapods',
    license: 'MIT',
    minimumIos: '13.0',
    status: 'approved',
    reason: id,
    evidenceUrls: const ['https://github.com/example/example'],
    podName: podName,
    moduleName: module,
    probeTemplate: id,
    binaryTokens: [module],
    sourceGit: id == 'grdb' ? 'https://github.com/groue/GRDB.swift.git' : null,
    sourceTag: id == 'grdb' ? 'v7.11.1' : null,
  ),
);

Future<void> _write(Directory root, String relative, String contents) async {
  final file = File(p.join(root.path, relative));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}
