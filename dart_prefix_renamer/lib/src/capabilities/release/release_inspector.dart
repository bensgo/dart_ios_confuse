import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../ipa_binding.dart';
import '../model/capability_report.dart';

class ReleaseInspector {
  ReleaseInspector({required this.projectRoot});

  final String projectRoot;

  Future<CapabilityReport> inspect({
    required Map<String, String> inputHashes,
    required DartCapabilityReport dartReport,
    required NativeCapabilityReport nativeReport,
    required DependencyReport dependencyReport,
    required bool analyzerPassed,
    required bool buildSuccess,
    String? ipaPath,
    bool requireIpa = true,
  }) async {
    final failures = <String>[];
    if (!analyzerPassed) failures.add('ANALYZER_FAILED');
    if (!buildSuccess) failures.add('RELEASE_BUILD_FAILED');
    if (dartReport.capabilitiesFailed > 0 ||
        dartReport.capabilitiesReachable < dartReport.capabilitiesPlanned) {
      failures.add('DART_CAPABILITY_UNREACHABLE');
    }
    final nativeFailures = nativeReport.capabilities.values.where(
      (status) => status.enabled && !status.bridgeCalled,
    );
    if (nativeFailures.isNotEmpty) failures.add('NATIVE_BRIDGE_UNCALLED');
    if (dependencyReport.justified != dependencyReport.total) {
      failures.add('DEPENDENCY_UNJUSTIFIED');
    }

    var ipaHash = '';
    final components = <ComponentHash>[];
    var bundlePath = '';
    var infoPlistPresent = false;
    final frameworks = <String>[];
    var verifiedDependencies = dependencyReport;
    if (ipaPath == null || !File(ipaPath).existsSync()) {
      if (requireIpa) failures.add('IPA_MISSING');
    } else {
      final bytes = await File(ipaPath).readAsBytes();
      ipaHash = sha256.convert(bytes).toString();
      try {
        final archive = ZipDecoder().decodeBytes(bytes, verify: false);
        final names = archive.files
            .where((entry) => entry.isFile)
            .map((entry) => entry.name)
            .toList();
        final bundleMatch = names
            .map((name) => RegExp(r'^(Payload/[^/]+\.app)/').firstMatch(name))
            .whereType<RegExpMatch>()
            .firstOrNull;
        if (bundleMatch == null) {
          failures.add('IPA_APP_BUNDLE_MISSING');
        } else {
          bundlePath = bundleMatch.group(1)!;
          infoPlistPresent = names.contains('$bundlePath/Info.plist');
          if (!infoPlistPresent) {
            failures.add('IPA_INFO_PLIST_MISSING');
          }
          final executable =
              '$bundlePath/${p.basenameWithoutExtension(bundlePath)}';
          if (!names.contains(executable)) {
            failures.add('IPA_MAIN_EXECUTABLE_MISSING');
          }
          frameworks.addAll(
            names
                .where(
                  (name) =>
                      name.startsWith('$bundlePath/Frameworks/') &&
                      name.contains('.framework/'),
                )
                .map(
                  (name) => name.substring(
                    0,
                    name.indexOf('.framework/') + '.framework'.length,
                  ),
                )
                .map(p.basename)
                .toSet(),
          );
          frameworks.sort();
          final normalizedArchive = names
              .join('\n')
              .toLowerCase()
              .replaceAll(RegExp('[^a-z0-9]'), '');
          final linkedStatuses = <DependencyStatus>[];
          for (final dependency in dependencyReport.dependencies.where(
            (item) => item.used,
          )) {
            final tokens = dependency.binaryTokens.isEmpty
                ? [dependency.name]
                : dependency.binaryTokens;
            final linked = tokens.any(
              (value) => normalizedArchive.contains(
                value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), ''),
              ),
            );
            linkedStatuses.add(dependency.copyWith(linked: linked));
            if (!linked) {
              failures.add('DEPENDENCY_NOT_LINKED');
            }
          }
          verifiedDependencies = dependencyReport.withDependencies([
            for (final dependency in dependencyReport.dependencies)
              linkedStatuses.firstWhere(
                (item) => item.name == dependency.name,
                orElse: () => dependency,
              ),
          ]);
        }
        for (final entry in archive.files.where((entry) => entry.isFile)) {
          if (!entry.name.startsWith('Payload/') ||
              !entry.name.contains('.app/')) {
            continue;
          }
          final content = entry.content as List<int>;
          if (_isMacho(content)) {
            components.add(
              ComponentHash(
                path: entry.name,
                sha256: sha256.convert(content).toString(),
                size: content.length,
              ),
            );
          }
        }
        components.sort((a, b) => a.path.compareTo(b.path));
        if (components.isEmpty) failures.add('IPA_MACHO_MISSING');
      } on Object {
        failures.add('IPA_INVALID');
      }
    }

    final lockfile = File(p.join(projectRoot, 'pubspec.lock'));
    final lockfileHash = lockfile.existsSync()
        ? sha256.convert(await lockfile.readAsBytes()).toString()
        : '';
    final uniqueFailures = failures.toSet().toList()..sort();
    return CapabilityReport(
      schemaVersion: 1,
      toolVersion: kRenamerToolVersion,
      inputHashes: Map<String, String>.fromEntries(
        inputHashes.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      dartCapabilities: dartReport,
      nativeCapabilities: nativeReport,
      dependencies: verifiedDependencies,
      releaseValidation: ReleaseValidationReport(
        buildSuccess: buildSuccess,
        analyzerPassed: analyzerPassed,
        ipaHash: ipaHash,
        lockfileHash: lockfileHash,
        components: components,
        bundlePath: bundlePath,
        infoPlistPresent: infoPlistPresent,
        frameworks: frameworks,
      ),
      status: uniqueFailures.isEmpty ? 'passed' : 'failed',
      failureCodes: uniqueFailures,
    );
  }

  Future<File> writeReport(
    CapabilityReport report, {
    String relativePath = 'reports/release-report.json',
  }) async {
    final normalized = p.normalize(relativePath);
    if (p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw ArgumentError.value(relativePath, 'relativePath');
    }
    final file = File(p.join(projectRoot, normalized));
    await file.parent.create(recursive: true);
    await file.writeAsString('${report.toJsonString()}\n');
    return file;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

const _machoMagics = <int>{
  0xFEEDFACE,
  0xCEFAEDFE,
  0xFEEDFACF,
  0xCFFAEDFE,
  0xCAFEBABE,
  0xBEBAFECA,
};

bool _isMacho(List<int> content) {
  if (content.length < 4) return false;
  final view = ByteData.sublistView(Uint8List.fromList(content), 0, 4);
  return _machoMagics.contains(view.getUint32(0, Endian.big)) ||
      _machoMagics.contains(view.getUint32(0, Endian.little));
}
