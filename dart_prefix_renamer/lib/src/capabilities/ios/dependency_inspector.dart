import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/capability_manifest.dart';
import '../model/capability_report.dart';
import '../model/ios_library_pool.dart';

class DependencyInspector {
  DependencyInspector({required this.projectRoot});

  final String projectRoot;

  Future<DependencyReport> inspect({
    required DependencyManifest manifest,
    required IosLibraryPool libraryPool,
  }) async {
    final statuses = <DependencyStatus>[];
    for (final entry in manifest.dependencies.entries) {
      final name = entry.key;
      final spec = entry.value;
      final candidate = libraryPool.find(name);
      String? failureCode;
      var used = false;
      var declared = false;
      var locked = false;
      var called = false;
      if (candidate == null || candidate.status != 'approved') {
        failureCode = 'DEPENDENCY_NOT_APPROVED';
      } else if (candidate.selectedVersion != spec.version) {
        failureCode = 'DEPENDENCY_POOL_VERSION_MISMATCH';
      } else if (candidate.capability != spec.capability) {
        failureCode = 'DEPENDENCY_CAPABILITY_MISMATCH';
      } else {
        declared = _declarationContains(name, spec);
        if (!declared) {
          failureCode = 'DEPENDENCY_DECLARATION_MISSING';
        } else {
          locked = _lockfileContains(name, spec);
          if (!locked) failureCode = 'LOCKFILE_MISMATCH';
        }
        if (failureCode == null && spec.productionCall == null) {
          failureCode = 'DEPENDENCY_PRODUCTION_CALL_MISSING';
        }
        if (failureCode == null) {
          final source = File(p.join(projectRoot, spec.productionCall));
          if (!source.existsSync()) {
            failureCode = 'DEPENDENCY_PRODUCTION_CALL_MISSING';
          } else {
            called = _hasRealUsage(name, await source.readAsString());
            used = called;
            if (!used) failureCode = 'DEPENDENCY_UNJUSTIFIED';
          }
        }
      }
      statuses.add(
        DependencyStatus(
          name: name,
          version: spec.version,
          reason: spec.reason,
          used: used,
          declared: declared,
          locked: locked,
          called: called,
          binaryTokens: candidate?.binaryTokens ?? const [],
          sourcePath: spec.productionCall,
          failureCode: failureCode,
        ),
      );
    }
    return DependencyReport(
      total: statuses.length,
      justified: statuses.where((status) => status.used).length,
      dependencies: statuses,
    );
  }

  bool _declarationContains(String name, DependencySpec spec) {
    final candidates = spec.manager == 'cocoapods'
        ? [
            p.join(projectRoot, 'ios', 'Podfile'),
            ...Directory(p.join(projectRoot, 'ios', 'LocalPods')).existsSync()
                ? Directory(p.join(projectRoot, 'ios', 'LocalPods'))
                      .listSync(recursive: true)
                      .whereType<File>()
                      .where((file) => file.path.endsWith('.podspec'))
                      .map((file) => file.path)
                : const <String>[],
          ]
        : [
            p.join(projectRoot, 'ios', 'Package.swift'),
            p.join(projectRoot, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
          ];
    final normalizedName = _normalized(name);
    return candidates.any((path) {
      final file = File(path);
      if (!file.existsSync()) return false;
      return _normalized(file.readAsStringSync()).contains(normalizedName);
    });
  }

  bool _lockfileContains(String name, DependencySpec spec) {
    if (spec.manager == 'cocoapods') {
      final file = File(p.join(projectRoot, 'ios', 'Podfile.lock'));
      if (!file.existsSync()) return false;
      final escaped = RegExp.escape(name);
      return RegExp(
        '- $escaped \\(${RegExp.escape(spec.version)}\\)',
      ).hasMatch(file.readAsStringSync());
    }
    if (spec.manager == 'spm') {
      final candidates = [
        p.join(projectRoot, 'ios', 'Package.resolved'),
        p.join(
          projectRoot,
          'ios',
          'Runner.xcworkspace',
          'xcshareddata',
          'swiftpm',
          'Package.resolved',
        ),
      ];
      for (final path in candidates) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final decoded =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final pins =
            (decoded['pins'] ??
                    (decoded['object'] as Map<String, dynamic>?)?['pins'])
                as List<dynamic>?;
        if (pins == null) continue;
        for (final value in pins) {
          final pin = value as Map<String, dynamic>;
          final identity = (pin['identity'] ?? pin['package']) as String?;
          final state = pin['state'] as Map<String, dynamic>?;
          if (_normalized(identity ?? '') == _normalized(name) &&
              state?['version'] == spec.version) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _hasRealUsage(String name, String source) {
    final nonImports = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('import '))
        .join('\n');
    final tokens = <String, List<String>>{
      'kingfisher': ['.kf.', 'KingfisherManager', 'ImageResource'],
      'sdwebimage': ['sd_setImage', 'SDWebImageManager'],
      'nuke': ['ImagePipeline', 'Nuke.loadImage'],
      'grdb': ['DatabaseQueue', 'DatabasePool'],
      'grdbswift': ['DatabaseQueue', 'DatabasePool'],
      'realm': ['Realm()', 'Realm.Configuration'],
      'sqliteswift': ['Connection(', 'Table('],
      'alamofire': ['AF.request', 'Session('],
      'zipfoundation': ['Archive(', 'FileManager.default.zipItem'],
      'cocoalumberjack': ['DDLog', 'DDOSLogger'],
      'swiftprotobuf': ['serializedData()', 'SwiftProtobuf'],
      'cryptoswift': ['.sha256()', 'CryptoSwift'],
      'devicekit': ['Device.current', 'isSimulator'],
      'promisekit': ['Promise<Int>.value', 'isResolved'],
      'swifterswift': ['.camelCased', 'SwifterSwift'],
      'swiftyjson': ['JSON([', 'SwiftyJSON'],
      'objectmapper': ['Map(mappingType:', 'ObjectMapper'],
      'differencekit': ['StagedChangeset(', 'DifferenceKit'],
      'swiftsoup': ['SwiftSoup.parse(', 'SwiftSoup'],
      'swinject': ['Container()', 'Swinject'],
      'starscream': ['WebSocket(', 'WebSocketDelegate'],
    };
    final expected = tokens[_normalized(name)] ?? [name];
    return expected.any(nonImports.contains);
  }

  String _normalized(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
}
