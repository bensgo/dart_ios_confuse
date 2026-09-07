import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dart_prefix_renamer/dart_prefix_renamer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'passes a release with reachable capabilities and a Mach-O IPA',
    () async {
      final root = await Directory.systemTemp.createTemp('release_inspector_');
      addTearDown(() => root.delete(recursive: true));
      await File(p.join(root.path, 'pubspec.lock')).writeAsString('lock');
      final ipa = File(p.join(root.path, 'app.ipa'));
      final archive = Archive()
        ..addFile(
          ArchiveFile('Payload/App.app/Info.plist', 5, 'plist'.codeUnits),
        )
        ..addFile(
          ArchiveFile('Payload/App.app/App', 8, [
            0xFE,
            0xED,
            0xFA,
            0xCF,
            0,
            0,
            0,
            0,
          ]),
        );
      await ipa.writeAsBytes(ZipEncoder().encode(archive)!);

      final report = await ReleaseInspector(projectRoot: root.path).inspect(
        inputHashes: {'profile': 'abc'},
        dartReport: _dartReport(failed: false),
        nativeReport: _nativeReport(called: true),
        dependencyReport: DependencyReport(
          total: 0,
          justified: 0,
          dependencies: const [],
        ),
        analyzerPassed: true,
        buildSuccess: true,
        ipaPath: ipa.path,
      );
      expect(report.status, 'passed');
      expect(report.failureCodes, isEmpty);
      expect(report.releaseValidation.components, hasLength(1));
      final file = await ReleaseInspector(
        projectRoot: root.path,
      ).writeReport(report);
      expect(file.existsSync(), isTrue);
    },
  );

  test('aggregates stable failure codes instead of stopping early', () async {
    final root = await Directory.systemTemp.createTemp('release_failure_');
    addTearDown(() => root.delete(recursive: true));
    final report = await ReleaseInspector(projectRoot: root.path).inspect(
      inputHashes: const {},
      dartReport: _dartReport(failed: true),
      nativeReport: _nativeReport(called: false),
      dependencyReport: DependencyReport(
        total: 1,
        justified: 0,
        dependencies: [
          DependencyStatus(
            name: 'Example',
            version: '1.0.0',
            reason: 'example',
            used: false,
          ),
        ],
      ),
      analyzerPassed: false,
      buildSuccess: false,
      requireIpa: true,
    );
    expect(report.status, 'failed');
    expect(
      report.failureCodes,
      containsAll({
        'ANALYZER_FAILED',
        'RELEASE_BUILD_FAILED',
        'DART_CAPABILITY_UNREACHABLE',
        'NATIVE_BRIDGE_UNCALLED',
        'DEPENDENCY_UNJUSTIFIED',
        'IPA_MISSING',
      }),
    );
  });
}

DartCapabilityReport _dartReport({required bool failed}) =>
    DartCapabilityReport(
      classesAnalyzed: 1,
      capabilitiesPlanned: 1,
      capabilitiesApplied: failed ? 0 : 1,
      capabilitiesReachable: failed ? 0 : 1,
      capabilitiesFailed: failed ? 1 : 0,
      integrations: const [],
    );

NativeCapabilityReport _nativeReport({required bool called}) =>
    NativeCapabilityReport(
      enabledCount: 1,
      registeredCount: 1,
      calledCount: called ? 1 : 0,
      capabilities: {
        'network': NativeCapabilityStatus(
          enabled: true,
          bridgeCalled: called,
          provider: 'nw_path_monitor',
        ),
      },
    );
