import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:args/args.dart';
import 'package:encrypt/encrypt.dart';
import 'package:path/path.dart' as p;

import 'config.dart';
import 'project_layout.dart';
import 'source_edit.dart';

final class DartStringBuildConfig {
  DartStringBuildConfig({
    required String projectPath,
    this.buildCommand = const [],
    String runtimeConfigPath =
        'packages/aixi_app_config/lib/src/string_cipher_config.g.dart',
    this.methodName = 'decryptedPS',
  }) : projectPath = p.normalize(p.absolute(projectPath)),
       runtimeConfigPath = p.normalize(
         p.absolute(projectPath, runtimeConfigPath),
       ) {
    _validate();
  }

  factory DartStringBuildConfig.fromArguments(List<String> arguments) {
    final separator = arguments.indexOf('--');
    if (separator < 0 || separator == arguments.length - 1) {
      throw UsageException(
        'The build command is required after `--`, for example:\n'
        '  --dart-strings-build --project=/app '
        '-- fvm flutter build ipa --release',
      );
    }
    final parser = ArgParser()
      ..addFlag('dart-strings-build', negatable: false)
      ..addOption('project', abbr: 'p', mandatory: true)
      ..addOption(
        'string-runtime-config',
        defaultsTo:
            'packages/aixi_app_config/lib/src/string_cipher_config.g.dart',
      )
      ..addOption(
        'decrypt-method',
        defaultsTo: 'decryptedPS',
        help: 'Two-string-argument method used to mark protected literals.',
      )
      ..addFlag('help', abbr: 'h', negatable: false);
    late final ArgResults results;
    try {
      results = parser.parse(arguments.sublist(0, separator));
    } on FormatException catch (error) {
      throw UsageException('${error.message}\n\n${parser.usage}');
    }
    if (results.flag('help')) {
      throw UsageException(parser.usage, exitCode: 0);
    }
    return DartStringBuildConfig(
      projectPath: results.option('project')!,
      runtimeConfigPath: results.option('string-runtime-config')!,
      methodName: results.option('decrypt-method')!,
      buildCommand: arguments.sublist(separator + 1),
    );
  }

  final String projectPath;
  final String runtimeConfigPath;
  final String methodName;
  final List<String> buildCommand;

  void _validate() {
    if (!File(p.join(projectPath, 'pubspec.yaml')).existsSync()) {
      throw UsageException('Dart project has no pubspec.yaml: $projectPath');
    }
    if (!File(runtimeConfigPath).existsSync() ||
        !_inside(projectPath, runtimeConfigPath)) {
      throw UsageException(
        'String cipher runtime config placeholder does not exist: '
        '$runtimeConfigPath',
      );
    }
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(methodName)) {
      throw UsageException('Invalid decrypt method name: $methodName');
    }
  }
}

final class DartStringBuildReport {
  const DartStringBuildReport({
    required this.files,
    required this.strings,
    required this.buildExitCode,
    required this.restored,
  });

  final int files;
  final int strings;
  final int buildExitCode;
  final bool restored;
}

final class DartStringCipherBuilder {
  DartStringCipherBuilder(this.config);

  static const _transactionName = '.dart_prefix_renamer_string_transaction';

  final DartStringBuildConfig config;
  final Random _random = Random.secure();

  /// Encrypts marked literals in an already-copied project and keeps them.
  /// Failed preparation is rolled back using the same transaction mechanism
  /// as build mode.
  Future<DartStringBuildReport> applyPermanently() async {
    final transaction = Directory(p.join(config.projectPath, _transactionName));
    if (transaction.existsSync()) {
      throw StateError(
        'An unfinished string transaction exists: ${transaction.path}. '
        'Run with --restore-dart-strings first.',
      );
    }
    final plans = _discoverPlans();
    final stringCount = plans.fold<int>(
      0,
      (sum, plan) => sum + plan.values.length,
    );
    if (stringCount == 0) {
      throw StateError(
        'No ${config.methodName}(plainText, "") string markers were found.',
      );
    }
    transaction.createSync(recursive: true);
    final backupRoot = Directory(p.join(transaction.path, 'files'))
      ..createSync(recursive: true);
    File(
      config.runtimeConfigPath,
    ).copySync(p.join(transaction.path, 'runtime_config.bak'));
    final records = <Map<String, Object?>>[];
    for (final plan in plans) {
      final relative = _relative(plan.file.path);
      final backup = File(p.join(backupRoot.path, relative));
      backup.parent.createSync(recursive: true);
      plan.file.copySync(backup.path);
      records.add({
        'path': relative,
        'modifiedMicros': plan.file.lastModifiedSync().microsecondsSinceEpoch,
      });
    }
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
      final keyBytes = _randomBytes(32);
      final ivBytes = _randomBytes(16);
      final encrypter = Encrypter(AES(Key(keyBytes), mode: AESMode.cbc));
      for (final plan in plans) {
        final edits = <SourceEdit>[];
        for (final value in plan.values) {
          final cipher = encrypter
              .encrypt(value.plainText, iv: IV(ivBytes))
              .base64;
          edits
            ..add(
              SourceEdit(
                offset: value.plainOffset,
                length: value.plainLength,
                replacement: '',
                reason: 'clear protected Dart plaintext',
              ),
            )
            ..add(
              SourceEdit(
                offset: value.cipherOffset,
                length: value.cipherLength,
                replacement: cipher,
                reason: 'write protected Dart ciphertext',
              ),
            );
        }
        await plan.file.writeAsString(
          applySourceEdits(plan.source, edits),
          flush: true,
        );
      }
      await File(
        config.runtimeConfigPath,
      ).writeAsString(_runtimeConfigSource(keyBytes, ivBytes), flush: true);
      await transaction.delete(recursive: true);
      return DartStringBuildReport(
        files: plans.length,
        strings: stringCount,
        buildExitCode: 0,
        restored: false,
      );
    } on Object {
      await restoreDartStringTransaction(config.projectPath);
      rethrow;
    }
  }

  Future<DartStringBuildReport> run() async {
    final transaction = Directory(p.join(config.projectPath, _transactionName));
    if (transaction.existsSync()) {
      throw StateError(
        'An unfinished string transaction exists: ${transaction.path}. '
        'Run with --restore-dart-strings first.',
      );
    }
    final plans = _discoverPlans();
    final stringCount = plans.fold<int>(
      0,
      (sum, plan) => sum + plan.values.length,
    );
    if (stringCount == 0) {
      throw StateError(
        'No ${config.methodName}(plainText, "") string markers were found.',
      );
    }
    transaction.createSync(recursive: true);
    final backupRoot = Directory(p.join(transaction.path, 'files'))
      ..createSync(recursive: true);
    final runtimeBackup = File(p.join(transaction.path, 'runtime_config.bak'));
    File(config.runtimeConfigPath).copySync(runtimeBackup.path);
    final runtimeModified = File(config.runtimeConfigPath).lastModifiedSync();
    final records = <Map<String, Object?>>[];
    for (final plan in plans) {
      final relative = _relative(plan.file.path);
      final backup = File(p.join(backupRoot.path, relative));
      backup.parent.createSync(recursive: true);
      plan.file.copySync(backup.path);
      records.add({
        'path': relative,
        'modifiedMicros': plan.file.lastModifiedSync().microsecondsSinceEpoch,
      });
    }
    final manifest = File(p.join(transaction.path, 'transaction.json'));
    manifest.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'project': config.projectPath,
        'runtimeConfig': _relative(config.runtimeConfigPath),
        'runtimeModifiedMicros': runtimeModified.microsecondsSinceEpoch,
        'files': records,
      }),
      flush: true,
    );

    var exitCode = -1;
    var restored = false;
    try {
      final keyBytes = _randomBytes(32);
      final ivBytes = _randomBytes(16);
      final encrypter = Encrypter(AES(Key(keyBytes), mode: AESMode.cbc));
      for (final plan in plans) {
        final edits = <SourceEdit>[];
        for (final value in plan.values) {
          final cipher = encrypter
              .encrypt(value.plainText, iv: IV(ivBytes))
              .base64;
          edits
            ..add(
              SourceEdit(
                offset: value.plainOffset,
                length: value.plainLength,
                replacement: '',
                reason: 'clear protected Dart plaintext',
              ),
            )
            ..add(
              SourceEdit(
                offset: value.cipherOffset,
                length: value.cipherLength,
                replacement: cipher,
                reason: 'write protected Dart ciphertext',
              ),
            );
        }
        await plan.file.writeAsString(
          applySourceEdits(plan.source, edits),
          flush: true,
        );
      }
      await File(
        config.runtimeConfigPath,
      ).writeAsString(_runtimeConfigSource(keyBytes, ivBytes), flush: true);
      stdout.writeln(
        'Encrypted $stringCount Dart strings in ${plans.length} files for the build.',
      );
      final process = await Process.start(
        config.buildCommand.first,
        config.buildCommand.sublist(1),
        workingDirectory: config.projectPath,
        mode: ProcessStartMode.inheritStdio,
      );
      exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw ProcessException(
          config.buildCommand.first,
          config.buildCommand.sublist(1),
          'Dart string protected build command failed',
          exitCode,
        );
      }
    } finally {
      await restoreDartStringTransaction(config.projectPath);
      restored = true;
    }
    return DartStringBuildReport(
      files: plans.length,
      strings: stringCount,
      buildExitCode: exitCode,
      restored: restored,
    );
  }

  List<_FileStringPlan> _discoverPlans() {
    final layout = ProjectLayout.discover(config.projectPath);
    final files = <File>[];
    for (final package in layout.packages.values) {
      final lib = Directory(p.join(package.rootPath, 'lib'));
      if (!lib.existsSync()) continue;
      files.addAll(
        lib
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.dart') &&
                  p.normalize(file.path) != config.runtimeConfigPath,
            ),
      );
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final plans = <_FileStringPlan>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      if (!source.contains(config.methodName)) continue;
      final parsed = parseString(content: source, path: file.path);
      final visitor = _ProtectedStringVisitor(config.methodName);
      parsed.unit.accept(visitor);
      if (visitor.values.isNotEmpty) {
        plans.add(
          _FileStringPlan(file: file, source: source, values: visitor.values),
        );
      }
    }
    return plans;
  }

  String _runtimeConfigSource(Uint8List key, Uint8List iv) =>
      '''// Generated by dart_prefix_renamer. Do not edit.
abstract final class ${_runtimeClassName()} {
  static const bool enabled = true;
  static const String keyBase64 = '${base64Encode(key)}';
  static const String ivBase64 = '${base64Encode(iv)}';
}
''';

  String _runtimeClassName() {
    final source = File(config.runtimeConfigPath).readAsStringSync();
    final match = RegExp(
      r'abstract\s+final\s+class\s+([A-Za-z_$][A-Za-z0-9_$]*)',
    ).firstMatch(source);
    return match?.group(1) ?? 'StringCipherConfig';
  }

  Uint8List _randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );

  String _relative(String path) =>
      p.posix.joinAll(p.split(p.relative(path, from: config.projectPath)));
}

Future<int> restoreDartStringTransaction(String projectPath) async {
  final root = p.normalize(p.absolute(projectPath));
  final transaction = Directory(
    p.join(root, '.dart_prefix_renamer_string_transaction'),
  );
  if (!transaction.existsSync()) {
    throw StateError('No unfinished Dart string transaction exists in $root.');
  }
  final decoded = jsonDecode(
    await File(p.join(transaction.path, 'transaction.json')).readAsString(),
  );
  if (decoded is! Map<String, dynamic> || decoded['files'] is! List) {
    throw const FormatException('Invalid Dart string transaction manifest.');
  }
  var restored = 0;
  for (final value in decoded['files'] as List) {
    if (value is! Map<String, dynamic>) continue;
    final relative = value['path'] as String;
    final backup = File(p.join(transaction.path, 'files', relative));
    final destination = File(p.join(root, relative));
    if (!backup.existsSync()) {
      throw StateError('Missing string transaction backup: ${backup.path}');
    }
    await backup.copy(destination.path);
    final micros = value['modifiedMicros'];
    if (micros is int) {
      destination.setLastModifiedSync(
        DateTime.fromMicrosecondsSinceEpoch(micros),
      );
    }
    restored++;
  }
  final runtime = File(p.join(root, decoded['runtimeConfig'] as String));
  final runtimeBackup = File(p.join(transaction.path, 'runtime_config.bak'));
  await runtimeBackup.copy(runtime.path);
  final runtimeMicros = decoded['runtimeModifiedMicros'];
  if (runtimeMicros is int) {
    runtime.setLastModifiedSync(
      DateTime.fromMicrosecondsSinceEpoch(runtimeMicros),
    );
  }
  await transaction.delete(recursive: true);
  return restored;
}

final class _ProtectedStringVisitor extends RecursiveAstVisitor<void> {
  _ProtectedStringVisitor(this.methodName);

  final String methodName;
  final List<_ProtectedString> values = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == methodName &&
        node.argumentList.arguments.length == 2) {
      final plain = node.argumentList.arguments[0];
      final cipher = node.argumentList.arguments[1];
      if (plain is SimpleStringLiteral && cipher is SimpleStringLiteral) {
        final plainValue = plain.stringValue;
        final cipherValue = cipher.stringValue;
        if (plainValue != null &&
            plainValue.isNotEmpty &&
            cipherValue != null &&
            cipherValue.isEmpty) {
          values.add(
            _ProtectedString(
              plainText: plainValue,
              plainOffset: plain.contentsOffset,
              plainLength: plain.contentsEnd - plain.contentsOffset,
              cipherOffset: cipher.contentsOffset,
              cipherLength: cipher.contentsEnd - cipher.contentsOffset,
            ),
          );
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

final class _FileStringPlan {
  const _FileStringPlan({
    required this.file,
    required this.source,
    required this.values,
  });

  final File file;
  final String source;
  final List<_ProtectedString> values;
}

final class _ProtectedString {
  const _ProtectedString({
    required this.plainText,
    required this.plainOffset,
    required this.plainLength,
    required this.cipherOffset,
    required this.cipherLength,
  });

  final String plainText;
  final int plainOffset;
  final int plainLength;
  final int cipherOffset;
  final int cipherLength;
}

bool _inside(String parent, String child) =>
    parent == child || p.isWithin(parent, child);
