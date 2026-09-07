import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config.dart';

final class IosAssetBuildConfig {
  IosAssetBuildConfig({
    required String projectPath,
    required List<String> assetDirectories,
    List<String> animationAssetDirectories = const [],
    List<String> audioAssetDirectories = const [],
    this.buildCommand = const [],
    String containerDirectory = 'assets/images',
    String runtimeConfigPath =
        'lib/app_tools/asset_container/asset_container_config.g.dart',
  }) : projectPath = p.normalize(p.absolute(projectPath)),
       assetDirectories = assetDirectories
           .map((value) => p.normalize(p.absolute(projectPath, value)))
           .toList(growable: false),
       animationAssetDirectories = animationAssetDirectories
           .map((value) => p.normalize(p.absolute(projectPath, value)))
           .toList(growable: false),
       audioAssetDirectories = audioAssetDirectories
           .map((value) => p.normalize(p.absolute(projectPath, value)))
           .toList(growable: false),
       containerDirectory = p.normalize(
         p.absolute(projectPath, containerDirectory),
       ),
       runtimeConfigPath = p.normalize(
         p.absolute(projectPath, runtimeConfigPath),
       ) {
    _validate();
  }

  factory IosAssetBuildConfig.fromArguments(List<String> arguments) {
    final separator = arguments.indexOf('--');
    if (separator < 0 || separator == arguments.length - 1) {
      throw UsageException(
        'The iOS build command is required after `--`, for example:\n'
        '  --ios-assets-build --project=/app --asset-dir=assets/images '
        '-- fvm flutter build ipa --release',
      );
    }
    final options = arguments.sublist(0, separator);
    final buildCommand = arguments.sublist(separator + 1);
    final parser = ArgParser()
      ..addFlag('ios-assets-build', negatable: false)
      ..addOption('project', abbr: 'p', mandatory: true)
      ..addMultiOption(
        'asset-dir',
        help:
            'Project-relative image directory. May be repeated; defaults to '
            'assets/images only when no asset directory option is provided.',
      )
      ..addMultiOption(
        'animation-asset-dir',
        help: 'Project-relative SVGA/Lottie directory. May be repeated.',
      )
      ..addMultiOption(
        'audio-asset-dir',
        help: 'Project-relative audio directory. May be repeated.',
      )
      ..addOption(
        'container-dir',
        defaultsTo: 'assets/images',
        help: 'Declared Flutter asset directory for generated .dat/.cfg files.',
      )
      ..addOption(
        'runtime-config',
        defaultsTo:
            'lib/app_tools/asset_container/asset_container_config.g.dart',
        help: 'Generated Dart configuration consumed by the app runtime.',
      )
      ..addFlag('help', abbr: 'h', negatable: false);
    late final ArgResults results;
    try {
      results = parser.parse(options);
    } on FormatException catch (error) {
      throw UsageException('${error.message}\n\n${parser.usage}');
    }
    if (results.flag('help')) {
      throw UsageException(parser.usage, exitCode: 0);
    }
    final imageAssetDirectories = results.multiOption('asset-dir');
    final animationAssetDirectories = results.multiOption(
      'animation-asset-dir',
    );
    final audioAssetDirectories = results.multiOption('audio-asset-dir');
    final hasExplicitAssetDirectories =
        imageAssetDirectories.isNotEmpty ||
        animationAssetDirectories.isNotEmpty ||
        audioAssetDirectories.isNotEmpty;
    return IosAssetBuildConfig(
      projectPath: results.option('project')!,
      assetDirectories: hasExplicitAssetDirectories
          ? imageAssetDirectories
          : const ['assets/images'],
      animationAssetDirectories: animationAssetDirectories,
      audioAssetDirectories: audioAssetDirectories,
      containerDirectory: results.option('container-dir')!,
      runtimeConfigPath: results.option('runtime-config')!,
      buildCommand: buildCommand,
    );
  }

  final String projectPath;
  final List<String> assetDirectories;
  final List<String> animationAssetDirectories;
  final List<String> audioAssetDirectories;
  final String containerDirectory;
  final String runtimeConfigPath;
  final List<String> buildCommand;

  void _validate() {
    if (!File(p.join(projectPath, 'pubspec.yaml')).existsSync()) {
      throw UsageException('Flutter project has no pubspec.yaml: $projectPath');
    }
    if (allAssetDirectories.isEmpty) {
      throw UsageException('At least one asset directory is required.');
    }
    for (final directory in allAssetDirectories) {
      if (!_inside(projectPath, directory) ||
          !Directory(directory).existsSync()) {
        throw UsageException(
          'Asset directory must exist inside the project: $directory',
        );
      }
    }
    if (!_inside(projectPath, containerDirectory)) {
      throw UsageException('Container directory must be inside the project.');
    }
    if (!_inside(projectPath, runtimeConfigPath) ||
        !File(runtimeConfigPath).existsSync()) {
      throw UsageException(
        'Runtime config placeholder does not exist: $runtimeConfigPath',
      );
    }
    _validateContainerDeclaration();
  }

  List<String> get allAssetDirectories => {
    ...assetDirectories,
    ...animationAssetDirectories,
    ...audioAssetDirectories,
  }.toList(growable: false);

  void _validateContainerDeclaration() {
    final source = File(p.join(projectPath, 'pubspec.yaml')).readAsStringSync();
    final yaml = loadYaml(source);
    final flutter = yaml is YamlMap ? yaml['flutter'] : null;
    final assets = flutter is YamlMap ? flutter['assets'] : null;
    final declared = assets is YamlList
        ? assets.whereType<String>().any((value) {
            final absolute = p.normalize(p.absolute(projectPath, value));
            return absolute == containerDirectory ||
                p.isWithin(absolute, containerDirectory);
          })
        : false;
    if (!declared) {
      throw UsageException(
        'Container directory is not covered by flutter.assets: '
        '${p.relative(containerDirectory, from: projectPath)}',
      );
    }
  }
}

final class IosAssetBuildReport {
  const IosAssetBuildReport({
    required this.images,
    required this.animations,
    required this.audio,
    required this.plainBytes,
    required this.containerBytes,
    required this.buildExitCode,
    required this.restored,
  });

  final int images;
  final int animations;
  final int audio;
  final int plainBytes;
  final int containerBytes;
  final int buildExitCode;
  final bool restored;
}

final class IosAssetContainerBuilder {
  IosAssetContainerBuilder(this.config);

  static const _imageExtensions = {'.png', '.jpg', '.jpeg', '.webp', '.gif'};
  static const _animationExtensions = {'.svga', '.json'};
  static const _audioExtensions = {
    '.mp3',
    '.m4a',
    '.mp4',
    '.aac',
    '.caf',
    '.wav',
    '.ogg',
    '.flac',
  };
  static const _transactionName = '.dart_prefix_renamer_asset_transaction';

  final IosAssetBuildConfig config;
  final Random _random = Random.secure();

  /// Replaces source images with encrypted containers and keeps the result.
  ///
  /// This is intended for an already-copied output project. If preparation
  /// fails, the transaction is rolled back before the error is rethrown.
  Future<IosAssetBuildReport> applyPermanently() async {
    final transaction = Directory(p.join(config.projectPath, _transactionName));
    if (transaction.existsSync()) {
      throw StateError(
        'An unfinished asset transaction exists: ${transaction.path}. '
        'Run with --restore-ios-assets first.',
      );
    }
    final assets = _discoverAssets();
    if (assets.isEmpty) {
      throw StateError(
        'No supported files found in the selected asset directories.',
      );
    }
    transaction.createSync(recursive: true);
    final backupRoot = Directory(p.join(transaction.path, 'files'))
      ..createSync(recursive: true);
    final runtimeBackup = File(p.join(transaction.path, 'runtime_config.bak'));
    File(config.runtimeConfigPath).copySync(runtimeBackup.path);
    final pubspecPath = p.join(config.projectPath, 'pubspec.yaml');
    File(pubspecPath).copySync(p.join(transaction.path, 'pubspec.yaml.bak'));
    final records = <Map<String, Object?>>[
      for (final asset in assets)
        {
          'path': _relative(asset.file.path),
          'modifiedMicros': asset.file
              .lastModifiedSync()
              .microsecondsSinceEpoch,
        },
    ];
    File(p.join(transaction.path, 'transaction.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'project': config.projectPath,
        'runtimeConfig': _relative(config.runtimeConfigPath),
        'files': records,
      }),
      flush: true,
    );
    try {
      for (final asset in assets) {
        final backup = File(
          p.join(backupRoot.path, _relative(asset.file.path)),
        );
        backup.parent.createSync(recursive: true);
        await asset.file.rename(backup.path);
      }
      final generated = await _generate(
        backupRoot: backupRoot,
        logicalPaths: records.map((value) => value['path']! as String).toList(),
      );
      final manifest = File(p.join(transaction.path, 'transaction.json'));
      final transactionData =
          jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      transactionData['generated'] = [
        _relative(generated.containerPath),
        _relative(generated.indexPath),
      ];
      manifest.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(transactionData),
        flush: true,
      );
      _rewritePubspecForContainer(
        containerPath: generated.containerPath,
        indexPath: generated.indexPath,
      );
      await transaction.delete(recursive: true);
      return IosAssetBuildReport(
        images: assets.where((asset) => asset.kind == _AssetKind.image).length,
        animations: assets
            .where((asset) => asset.kind == _AssetKind.animation)
            .length,
        audio: assets.where((asset) => asset.kind == _AssetKind.audio).length,
        plainBytes: generated.plainBytes,
        containerBytes: generated.containerBytes,
        buildExitCode: 0,
        restored: false,
      );
    } on Object {
      await restoreIosAssetTransaction(config.projectPath);
      rethrow;
    }
  }

  Future<IosAssetBuildReport> run() async {
    final transaction = Directory(p.join(config.projectPath, _transactionName));
    if (transaction.existsSync()) {
      throw StateError(
        'An unfinished asset transaction exists: ${transaction.path}. '
        'Run with --restore-ios-assets first.',
      );
    }
    final assets = _discoverAssets();
    if (assets.isEmpty) {
      throw StateError(
        'No supported files found in the selected asset directories.',
      );
    }
    transaction.createSync(recursive: true);
    final backupRoot = Directory(p.join(transaction.path, 'files'))
      ..createSync(recursive: true);
    final runtimeBackup = File(p.join(transaction.path, 'runtime_config.bak'));
    File(config.runtimeConfigPath).copySync(runtimeBackup.path);
    final runtimeModified = File(config.runtimeConfigPath).lastModifiedSync();
    final pubspecPath = p.join(config.projectPath, 'pubspec.yaml');
    final pubspecBackup = File(p.join(transaction.path, 'pubspec.yaml.bak'));
    File(pubspecPath).copySync(pubspecBackup.path);
    final pubspecModified = File(pubspecPath).lastModifiedSync();
    final records = <Map<String, Object?>>[];
    for (final asset in assets) {
      records.add({
        'path': _relative(asset.file.path),
        'modifiedMicros': asset.file.lastModifiedSync().microsecondsSinceEpoch,
      });
    }
    final manifest = File(p.join(transaction.path, 'transaction.json'));
    manifest.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'project': config.projectPath,
        'runtimeConfig': _relative(config.runtimeConfigPath),
        'runtimeModifiedMicros': runtimeModified.microsecondsSinceEpoch,
        'pubspecModifiedMicros': pubspecModified.microsecondsSinceEpoch,
        'files': records,
      }),
      flush: true,
    );

    String? containerPath;
    String? indexPath;
    var buildExitCode = -1;
    var plainBytes = 0;
    var containerBytes = 0;
    var restored = false;
    try {
      for (final asset in assets) {
        final relative = _relative(asset.file.path);
        final backup = File(p.join(backupRoot.path, relative));
        backup.parent.createSync(recursive: true);
        await asset.file.rename(backup.path);
      }
      final generated = await _generate(
        backupRoot: backupRoot,
        logicalPaths: records.map((e) => e['path']! as String).toList(),
      );
      containerPath = generated.containerPath;
      indexPath = generated.indexPath;
      final transactionData =
          jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      transactionData['generated'] = [
        _relative(containerPath),
        _relative(indexPath),
      ];
      manifest.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(transactionData),
        flush: true,
      );
      _rewritePubspecForContainer(
        containerPath: containerPath,
        indexPath: indexPath,
      );
      plainBytes = generated.plainBytes;
      containerBytes = generated.containerBytes;
      stdout.writeln(
        'Prepared ${assets.length} encrypted iOS assets '
        '(${_relative(containerPath)}, ${_relative(indexPath)}).',
      );
      final process = await Process.start(
        config.buildCommand.first,
        config.buildCommand.sublist(1),
        workingDirectory: config.projectPath,
        mode: ProcessStartMode.inheritStdio,
      );
      buildExitCode = await process.exitCode;
      if (buildExitCode != 0) {
        throw ProcessException(
          config.buildCommand.first,
          config.buildCommand.sublist(1),
          'iOS build command failed',
          buildExitCode,
        );
      }
    } finally {
      if (containerPath != null) {
        final file = File(containerPath);
        if (file.existsSync()) file.deleteSync();
      }
      if (indexPath != null) {
        final file = File(indexPath);
        if (file.existsSync()) file.deleteSync();
      }
      await restoreIosAssetTransaction(config.projectPath);
      restored = true;
    }
    return IosAssetBuildReport(
      images: assets.where((asset) => asset.kind == _AssetKind.image).length,
      animations: assets
          .where((asset) => asset.kind == _AssetKind.animation)
          .length,
      audio: assets.where((asset) => asset.kind == _AssetKind.audio).length,
      plainBytes: plainBytes,
      containerBytes: containerBytes,
      buildExitCode: buildExitCode,
      restored: restored,
    );
  }

  List<_AssetSource> _discoverAssets() {
    final byPath = <String, _AssetSource>{};

    void addDirectories(
      List<String> directories,
      Set<String> extensions,
      _AssetKind kind,
    ) {
      for (final directory in directories) {
        for (final file in Directory(
          directory,
        ).listSync(recursive: true, followLinks: false).whereType<File>()) {
          if (extensions.contains(p.extension(file.path).toLowerCase())) {
            byPath.putIfAbsent(file.path, () => _AssetSource(file, kind));
          }
        }
      }
    }

    addDirectories(config.assetDirectories, _imageExtensions, _AssetKind.image);
    addDirectories(
      config.animationAssetDirectories,
      _animationExtensions,
      _AssetKind.animation,
    );
    addDirectories(
      config.audioAssetDirectories,
      _audioExtensions,
      _AssetKind.audio,
    );
    final result = byPath.values.toList(growable: false);
    result.sort((a, b) => a.file.path.compareTo(b.file.path));
    return result;
  }

  Future<_GeneratedContainer> _generate({
    required Directory backupRoot,
    required List<String> logicalPaths,
  }) async {
    final keyBytes = _randomBytes(32);
    final key = Key(keyBytes);
    final entries = <String, Map<String, Object?>>{};
    final container = BytesBuilder(copy: false)..add(_randomBytes(64));
    var plainBytes = 0;
    final shuffled = [...logicalPaths]..shuffle(_random);
    for (final logicalPath in shuffled) {
      final bytes = await File(
        p.join(backupRoot.path, logicalPath),
      ).readAsBytes();
      final ivBytes = _randomBytes(16);
      final encrypted = Encrypter(
        AES(key, mode: AESMode.cbc),
      ).encryptBytes(bytes, iv: IV(ivBytes));
      container.add(_randomBytes(8 + _random.nextInt(57)));
      final offset = container.length;
      container.add(encrypted.bytes);
      plainBytes += bytes.length;
      entries[logicalPath] = {
        'name': _randomToken(12 + _random.nextInt(13)),
        'offset': offset,
        'length': encrypted.bytes.length,
        'iv': base64Encode(ivBytes),
        'sha256': sha256.convert(bytes).toString(),
      };
    }
    final containerBytes = container.takeBytes();
    final salt = _randomToken(10).toLowerCase();
    final containerName = 'vc_$salt.dat';
    final indexName = 'vi_$salt.cfg';
    final containerFile = File(
      p.join(config.containerDirectory, containerName),
    );
    final indexFile = File(p.join(config.containerDirectory, indexName));
    containerFile.parent.createSync(recursive: true);
    await containerFile.writeAsBytes(containerBytes, flush: true);
    final indexIv = _randomBytes(16);
    final indexPlain = utf8.encode(
      jsonEncode({'version': 1, 'entries': entries}),
    );
    final indexEncrypted = Encrypter(
      AES(key, mode: AESMode.cbc),
    ).encryptBytes(indexPlain, iv: IV(indexIv));
    await indexFile.writeAsBytes(indexEncrypted.bytes, flush: true);
    final runtimeClassName = _runtimeClassName(
      File(config.runtimeConfigPath).readAsStringSync(),
      fallback: 'AssetContainerConfig',
    );
    await File(config.runtimeConfigPath).writeAsString(
      _runtimeConfigSource(
        className: runtimeClassName,
        containerPath: _relative(containerFile.path),
        indexPath: _relative(indexFile.path),
        key: keyBytes,
        indexIv: indexIv,
      ),
      flush: true,
    );
    return _GeneratedContainer(
      containerPath: containerFile.path,
      indexPath: indexFile.path,
      plainBytes: plainBytes,
      containerBytes: containerBytes.length + indexEncrypted.bytes.length,
    );
  }

  void _rewritePubspecForContainer({
    required String containerPath,
    required String indexPath,
  }) {
    final pubspec = File(p.join(config.projectPath, 'pubspec.yaml'));
    final source = pubspec.readAsStringSync();
    final yaml = loadYaml(source);
    final flutter = yaml is YamlMap ? yaml['flutter'] : null;
    final assets = flutter is YamlMap ? flutter['assets'] : null;
    if (assets is! YamlList) {
      throw StateError('pubspec.yaml has no flutter.assets list.');
    }
    final ranges = <(int, int)>[];
    String? indentation;
    for (final node in assets.nodes) {
      final value = node.value;
      if (value is! String) continue;
      final absolute = p.normalize(p.absolute(config.projectPath, value));
      final selected = config.allAssetDirectories.any(
        (directory) => absolute == directory || p.isWithin(directory, absolute),
      );
      if (!selected) continue;
      final start = source.lastIndexOf('\n', node.span.start.offset - 1) + 1;
      final newline = source.indexOf('\n', node.span.end.offset);
      final end = newline < 0 ? source.length : newline + 1;
      indentation ??= RegExp(r'^\s*').firstMatch(source.substring(start))![0];
      ranges.add((start, end));
    }
    if (ranges.isEmpty) {
      throw StateError(
        'No flutter.assets entries are scoped to the selected image directories.',
      );
    }
    ranges.sort((a, b) => b.$1.compareTo(a.$1));
    var rewritten = source;
    for (final range in ranges) {
      rewritten = rewritten.replaceRange(range.$1, range.$2, '');
    }
    final insertAt = ranges.last.$1;
    final indent = indentation ?? '    ';
    final declarations =
        '$indent- ${_relative(containerPath)}\n'
        '$indent- ${_relative(indexPath)}\n';
    rewritten = rewritten.replaceRange(insertAt, insertAt, declarations);
    pubspec.writeAsStringSync(rewritten, flush: true);
  }

  String _runtimeConfigSource({
    required String className,
    required String containerPath,
    required String indexPath,
    required Uint8List key,
    required Uint8List indexIv,
  }) =>
      '''// Generated by dart_prefix_renamer. Do not edit.
abstract final class $className {
  static const bool enabled = true;
  static const String containerAsset = '$containerPath';
  static const String indexAsset = '$indexPath';
  static const String keyBase64 = '${base64Encode(key)}';
  static const String indexIvBase64 = '${base64Encode(indexIv)}';
}
''';

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );

  String _randomToken(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(
      List<int>.generate(
        length,
        (_) => alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
      ),
    );
  }

  String _relative(String path) =>
      p.posix.joinAll(p.split(p.relative(path, from: config.projectPath)));

  String _runtimeClassName(String source, {required String fallback}) {
    final match = RegExp(
      r'abstract\s+final\s+class\s+([A-Za-z_$][A-Za-z0-9_$]*)',
    ).firstMatch(source);
    return match?.group(1) ?? fallback;
  }
}

Future<int> restoreIosAssetTransaction(String projectPath) async {
  final root = p.normalize(p.absolute(projectPath));
  final transaction = Directory(
    p.join(root, '.dart_prefix_renamer_asset_transaction'),
  );
  if (!transaction.existsSync()) {
    throw StateError('No unfinished iOS asset transaction exists in $root.');
  }
  final manifestFile = File(p.join(transaction.path, 'transaction.json'));
  final decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded is! Map<String, dynamic> || decoded['files'] is! List) {
    throw const FormatException('Invalid asset transaction manifest.');
  }
  final backupRoot = p.join(transaction.path, 'files');
  var restored = 0;
  for (final value in decoded['files'] as List) {
    if (value is! Map<String, dynamic>) continue;
    final relative = value['path'] as String;
    final source = File(p.join(backupRoot, relative));
    final destination = File(p.join(root, relative));
    if (!source.existsSync()) {
      if (destination.existsSync()) continue;
      throw StateError('Missing transaction backup: ${source.path}');
    }
    if (destination.existsSync()) {
      throw StateError(
        'Refusing to overwrite restored asset: ${destination.path}',
      );
    }
    destination.parent.createSync(recursive: true);
    await source.rename(destination.path);
    final micros = value['modifiedMicros'];
    if (micros is int) {
      destination.setLastModifiedSync(
        DateTime.fromMicrosecondsSinceEpoch(micros),
      );
    }
    restored++;
  }
  final runtimeRelative = decoded['runtimeConfig'] as String;
  final runtime = File(p.join(root, runtimeRelative));
  final runtimeBackup = File(p.join(transaction.path, 'runtime_config.bak'));
  if (runtimeBackup.existsSync()) {
    runtime.parent.createSync(recursive: true);
    await runtimeBackup.copy(runtime.path);
    final micros = decoded['runtimeModifiedMicros'];
    if (micros is int) {
      runtime.setLastModifiedSync(DateTime.fromMicrosecondsSinceEpoch(micros));
    }
  }
  final generated = decoded['generated'];
  if (generated is List) {
    for (final value in generated.whereType<String>()) {
      final file = File(p.join(root, value));
      if (file.existsSync()) file.deleteSync();
    }
  }
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  final pubspecBackup = File(p.join(transaction.path, 'pubspec.yaml.bak'));
  if (pubspecBackup.existsSync()) {
    await pubspecBackup.copy(pubspec.path);
    final micros = decoded['pubspecModifiedMicros'];
    if (micros is int) {
      pubspec.setLastModifiedSync(DateTime.fromMicrosecondsSinceEpoch(micros));
    }
  }
  await transaction.delete(recursive: true);
  return restored;
}

final class _GeneratedContainer {
  const _GeneratedContainer({
    required this.containerPath,
    required this.indexPath,
    required this.plainBytes,
    required this.containerBytes,
  });

  final String containerPath;
  final String indexPath;
  final int plainBytes;
  final int containerBytes;
}

enum _AssetKind { image, animation, audio }

final class _AssetSource {
  const _AssetSource(this.file, this.kind);

  final File file;
  final _AssetKind kind;
}

bool _inside(String parent, String child) =>
    parent == child || p.isWithin(parent, child);
