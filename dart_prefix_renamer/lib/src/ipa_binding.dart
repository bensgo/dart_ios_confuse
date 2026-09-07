import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'config.dart';

/// 与 `pubspec.yaml` 的 `version` 保持同步的工具版本。
/// Tool version kept in sync with `pubspec.yaml`.
const String kRenamerToolVersion = '0.1.0';

const List<int> _machoMagics = [
  0xFEEDFACE, // MH_MAGIC
  0xCEFAEDFE, // MH_CIGAM
  0xFEEDFACF, // MH_MAGIC_64
  0xCFFAEDFE, // MH_CIGAM_64
  0xCAFEBABE, // FAT_MAGIC
  0xBEBAFECA, // FAT_CIGAM
];

final class IpaBindingConfig {
  IpaBindingConfig({required String projectPath, required String ipaPath})
    : projectPath = p.normalize(p.absolute(projectPath)),
      ipaPath = p.normalize(p.absolute(ipaPath)) {
    _validate();
  }

  factory IpaBindingConfig.fromArguments(List<String> arguments) {
    final parser = ArgParser()
      ..addFlag(
        'bind-ipa',
        negatable: false,
        help: 'Bind the final IPA build identity into the rename manifest.',
      )
      ..addOption(
        'project',
        abbr: 'p',
        mandatory: true,
        help: 'Renamed output project root containing the manifest.',
      )
      ..addOption(
        'ipa',
        mandatory: true,
        help: 'Absolute path to the final built IPA.',
      )
      ..addFlag('help', abbr: 'h', negatable: false);
    late final ArgResults results;
    try {
      results = parser.parse(arguments);
    } on FormatException catch (error) {
      throw UsageException('${error.message}\n\n${parser.usage}');
    }
    if (results.flag('help')) {
      throw UsageException(parser.usage, exitCode: 0);
    }
    return IpaBindingConfig(
      projectPath: results.option('project')!,
      ipaPath: results.option('ipa')!,
    );
  }

  final String projectPath;
  final String ipaPath;

  void _validate() {
    if (!Directory(projectPath).existsSync()) {
      throw UsageException('Project directory does not exist: $projectPath');
    }
    if (!File(ipaPath).existsSync()) {
      throw UsageException('IPA file does not exist: $ipaPath');
    }
  }
}

final class IpaComponentRecord {
  const IpaComponentRecord({
    required this.path,
    required this.sha256,
    required this.size,
  });

  final String path;
  final String sha256;
  final int size;

  Map<String, Object> toJson() => {
    'path': path,
    'sha256': sha256,
    'size': size,
  };
}

final class IpaBindingReport {
  const IpaBindingReport({
    required this.manifestPath,
    required this.ipaSha256,
    required this.ipaSize,
    required this.mainBundleSha256,
    required this.components,
    required this.toolVersion,
    required this.prefix,
    required this.seed,
    required this.builtAt,
    required this.lockfileSha256,
    required this.alreadyBound,
  });

  final String manifestPath;
  final String ipaSha256;
  final int ipaSize;
  final String mainBundleSha256;
  final List<IpaComponentRecord> components;
  final String toolVersion;
  final String? prefix;
  final int? seed;
  final DateTime builtAt;
  final String? lockfileSha256;
  final bool alreadyBound;
}

final class IpaBinder {
  IpaBinder(this.config);

  final IpaBindingConfig config;

  Future<IpaBindingReport> run() async {
    final manifestFile = File(
      p.join(config.projectPath, 'dart_prefix_renamer_manifest.json'),
    );
    if (!manifestFile.existsSync()) {
      throw UsageException(
        'Rename manifest does not exist: ${manifestFile.path}',
      );
    }
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw UsageException('Rename manifest root must be a JSON object.');
    }

    final ipaFile = File(config.ipaPath);
    final ipaBytes = await ipaFile.readAsBytes();
    final ipaSha256 = sha256.convert(ipaBytes).toString();
    final ipaSize = ipaBytes.length;

    final existing = decoded['artifact_identity'];
    if (existing is Map<String, dynamic>) {
      final existingHash = existing['ipa_sha256'];
      if (existingHash is String && existingHash != ipaSha256) {
        throw UsageException(
          'Manifest is already bound to a different IPA ($existingHash); '
          'refusing to rebind.',
        );
      }
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(ipaBytes, verify: false);
    } on ArchiveException catch (error) {
      throw UsageException('Not a readable ZIP IPA: ${error.message}');
    } on Object catch (error) {
      throw UsageException('Not a readable ZIP IPA: $error');
    }

    final appRoot = _findSingleAppBundle(archive);
    final bundleFiles = <ArchiveFile>[
      for (final entry in archive.files)
        if (entry.isFile && entry.name.startsWith(appRoot)) entry,
    ]..sort((a, b) => a.name.compareTo(b.name));

    final bundleManifest = StringBuffer();
    final components = <IpaComponentRecord>[];
    for (final file in bundleFiles) {
      final content = file.content as List<int>;
      final fileHash = sha256.convert(content).toString();
      bundleManifest
        ..write(file.name)
        ..write('|')
        ..write(fileHash)
        ..write('\n');
      if (_isMacho(content)) {
        components.add(
          IpaComponentRecord(
            path: file.name,
            sha256: fileHash,
            size: content.length,
          ),
        );
      }
    }
    final mainBundleSha256 = sha256
        .convert(utf8.encode(bundleManifest.toString()))
        .toString();

    final lockfile = File(p.join(config.projectPath, 'pubspec.lock'));
    final lockfileSha256 = lockfile.existsSync()
        ? sha256.convert(await lockfile.readAsBytes()).toString()
        : null;

    final podSection = decoded['iosProductPod'];
    final seed = podSection is Map<String, dynamic> ? podSection['seed'] : null;
    final builtAt = DateTime.now().toUtc();

    final identity = <String, Object?>{
      'ipa_sha256': ipaSha256,
      'ipa_size': ipaSize,
      'main_bundle_sha256': mainBundleSha256,
      'components': [for (final component in components) component.toJson()],
      'tool_version': kRenamerToolVersion,
      'prefix': decoded['prefix'],
      'seed': seed,
      'built_at': builtAt.toIso8601String(),
      'lockfile_sha256': lockfileSha256,
    };
    decoded['artifact_identity'] = identity;
    final encoder = JsonEncoder.withIndent('  ');
    await manifestFile.writeAsString('${encoder.convert(decoded)}\n');

    return IpaBindingReport(
      manifestPath: manifestFile.path,
      ipaSha256: ipaSha256,
      ipaSize: ipaSize,
      mainBundleSha256: mainBundleSha256,
      components: components,
      toolVersion: kRenamerToolVersion,
      prefix: decoded['prefix'] as String?,
      seed: seed as int?,
      builtAt: builtAt,
      lockfileSha256: lockfileSha256,
      alreadyBound: existing is Map<String, dynamic>,
    );
  }
}

String _findSingleAppBundle(Archive archive) {
  final appBundles = <String>{
    for (final entry in archive.files)
      if (_isAppEntry(entry.name)) _appRootOf(entry.name),
  }.toList()..sort();
  if (appBundles.isEmpty) {
    throw UsageException('IPA contains no Payload/*.app bundle.');
  }
  if (appBundles.length > 1) {
    throw UsageException(
      'IPA contains multiple app bundles; refusing ambiguous binding: '
      '${appBundles.join(', ')}',
    );
  }
  return appBundles.single;
}

bool _isAppEntry(String name) {
  final normalized = name.replaceAll('\\', '/');
  return normalized.startsWith('Payload/') && normalized.contains('.app/');
}

String _appRootOf(String name) {
  final normalized = name.replaceAll('\\', '/');
  final start = normalized.indexOf('Payload/');
  final end = normalized.indexOf('.app/') + '.app/'.length;
  return normalized.substring(start, end);
}

bool _isMacho(List<int> content) {
  if (content.length < 4) return false;
  final view = ByteData.sublistView(Uint8List.fromList(content), 0, 4);
  return _machoMagics.contains(view.getUint32(0, Endian.big)) ||
      _machoMagics.contains(view.getUint32(0, Endian.little));
}
