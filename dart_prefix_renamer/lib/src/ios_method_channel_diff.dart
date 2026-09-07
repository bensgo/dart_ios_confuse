import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import 'source_edit.dart';

const _dartImportMarker = '// dart_prefix_renamer:ios-method-channel-import';
const _dartInitMarker = '// dart_prefix_renamer:ios-method-channel-init';
const _dartExpressionMarker =
    '// dart_prefix_renamer:ios-method-channel-expression';
const _dartExpressionEndMarker =
    '// dart_prefix_renamer:ios-method-channel-expression-end';
const _swiftPropertyMarker =
    '// dart_prefix_renamer:ios-method-channel-property';
const _swiftInitMarker = '// dart_prefix_renamer:ios-method-channel-init';
const _objcInitMarker = '// dart_prefix_renamer:ios-method-channel-init';

/// iOS MethodChannel 差异化的内部配置。
///
/// 该功能只修改工作副本；原工程在普通复制模式和事务构建模式下都不会被直接改写。
final class IosMethodChannelDiffConfig {
  const IosMethodChannelDiffConfig({
    required this.projectPath,
    required this.prefix,
    required this.includes,
    required this.excludes,
    required this.dummyCount,
    required this.entrypoints,
    this.seed,
  });

  final String projectPath;
  final String prefix;

  /// 允许改名的真实 Channel 名称。每个名称必须同时在 Dart 和 iOS 找到。
  final List<String> includes;

  /// 禁止改名的名称。exclude 的优先级高于 include。
  final List<String> excludes;

  /// 需要生成的 Dart+iOS 成对无用 Channel 数量。
  final int dummyCount;

  /// 需要接入生成代码的 Dart main 文件，使用项目相对路径。
  final List<String> entrypoints;

  /// 固定后生成结果可复现；不设置则每次使用安全随机源生成不同名称。
  final int? seed;
}

final class IosMethodChannelDiffReport {
  const IosMethodChannelDiffReport({
    required this.renames,
    required this.dummyNames,
    required this.dartEdits,
    required this.iosEdits,
    required this.generatedDartFile,
    required this.entrypoints,
    required this.iosInjectionFile,
  });

  final Map<String, String> renames;
  final List<String> dummyNames;
  final int dartEdits;
  final int iosEdits;
  final String? generatedDartFile;
  final List<String> entrypoints;
  final String? iosInjectionFile;
}

/// 同步处理 Dart MethodChannel 和 iOS FlutterMethodChannel。
///
/// 真实 Channel 的两端名称必须保持完全一致，因此先确认 Dart/iOS 都存在，
/// 再把同一个 replacement 应用到两端，避免只改一端造成通信中断。
final class IosMethodChannelDifferentiator {
  IosMethodChannelDifferentiator(this.config)
    : _random = config.seed == null ? Random.secure() : Random(config.seed);

  final IosMethodChannelDiffConfig config;
  final Random _random;

  Future<IosMethodChannelDiffReport> apply() async {
    // test、Pods、build 和 .dart_tool 不会进入 IPA 业务源码，扫描时主动排除。
    final dartFiles = _sourceFiles('.dart', excludedTopLevel: const {'build'});
    final iosFiles = _iosSourceFiles();
    // 先执行 exclude，再排序 include。排序保证相同 seed 和配置得到相同映射。
    final excludes = config.excludes.toSet();
    final includes = config.includes.toSet().difference(excludes).toList()
      ..sort();
    // 收集已有名称用于碰撞检查，新名称不会与工程中已有 Channel 重名。
    final allNames = <String>{};
    for (final file in [...dartFiles, ...iosFiles]) {
      allNames.addAll(
        _discoverStaticNames(await file.readAsString(), file.path),
      );
    }

    final renames = <String, String>{};
    final editsByFile = <String, List<SourceEdit>>{};
    var dartEdits = 0;
    var iosEdits = 0;
    for (final name in includes) {
      // 真实 Channel 必须在 Dart 和 iOS 两边都有静态字符串匹配。
      // 找不到任意一端时立即终止，不能冒险生成一个失联的 Channel。
      final dartMatches = await _matchingEdits(dartFiles, name);
      final iosMatches = await _matchingEdits(iosFiles, name);
      if (dartMatches.isEmpty || iosMatches.isEmpty) {
        throw StateError(
          'Included MethodChannel must have static Dart and iOS matches: '
          '$name (Dart: ${dartMatches.length}, iOS: ${iosMatches.length}). '
          'Only app-owned native sources under ios/** are eligible; do not '
          'include third-party plugin channels.',
        );
      }
      // 真实名称格式：<prefix>.mc.<14位小写字母或数字>。
      final replacement = _uniqueName('${config.prefix}.mc', allNames);
      renames[name] = replacement;
      allNames.add(replacement);
      for (final match in dartMatches) {
        editsByFile
            .putIfAbsent(match.file, () => [])
            .add(
              SourceEdit(
                offset: match.offset,
                length: name.length,
                replacement: replacement,
                reason: 'differentiate iOS MethodChannel',
              ),
            );
        dartEdits++;
      }
      for (final match in iosMatches) {
        editsByFile
            .putIfAbsent(match.file, () => [])
            .add(
              SourceEdit(
                offset: match.offset,
                length: name.length,
                replacement: replacement,
                reason: 'differentiate iOS FlutterMethodChannel',
              ),
            );
        iosEdits++;
      }
    }
    for (final entry in editsByFile.entries) {
      final file = File(entry.key);
      final source = await file.readAsString();
      await file.writeAsString(applySourceEdits(source, entry.value));
    }

    // 无用名称格式：<prefix>.ios.<14位小写字母或数字>。
    // Dart 和 iOS 共用本列表，因此每一组名称在两端严格对应。
    final dummyNames = <String>[];
    for (var index = 0; index < config.dummyCount; index++) {
      final name = _uniqueName('${config.prefix}.ios', allNames);
      allNames.add(name);
      dummyNames.add(name);
    }
    if (dummyNames.isEmpty) {
      return IosMethodChannelDiffReport(
        renames: renames,
        dummyNames: const [],
        dartEdits: dartEdits,
        iosEdits: iosEdits,
        generatedDartFile: null,
        entrypoints: const [],
        iosInjectionFile: null,
      );
    }

    // Dart 生成文件不放入 junk_code，避免垃圾代码目录重建时被删除。
    final generated = File(
      p.join(
        config.projectPath,
        'lib',
        'app_tools',
        'ios_method_channel_diff.g.dart',
      ),
    );
    await generated.parent.create(recursive: true);
    await generated.writeAsString(_generatedDart(dummyNames));
    final wiredEntrypoints = <String>[];
    for (final relative in config.entrypoints) {
      final entrypoint = File(p.join(config.projectPath, relative));
      if (!entrypoint.existsSync()) {
        throw StateError(
          'iOS MethodChannel Dart entrypoint does not exist: $relative',
        );
      }
      await _wireDartEntrypoint(entrypoint, generated);
      wiredEntrypoints.add(entrypoint.path);
    }
    // 直接接入现有 AppDelegate，无需向 project.pbxproj 添加新的 Swift 文件。
    final iosInjection = await _wireIosAppDelegate(dummyNames);
    return IosMethodChannelDiffReport(
      renames: renames,
      dummyNames: dummyNames,
      dartEdits: dartEdits,
      iosEdits: iosEdits,
      generatedDartFile: generated.path,
      entrypoints: wiredEntrypoints,
      iosInjectionFile: iosInjection.path,
    );
  }

  List<File> _sourceFiles(
    String extension, {
    Set<String> excludedTopLevel = const {},
  }) {
    final root = Directory(config.projectPath);
    return root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => p.extension(file.path) == extension)
        .where((file) {
          final relative = p.relative(file.path, from: config.projectPath);
          final parts = p.split(relative);
          return !parts.any(
                (part) =>
                    part == '.dart_tool' || part == 'Pods' || part == 'test',
              ) &&
              (parts.isEmpty || !excludedTopLevel.contains(parts.first));
        })
        .toList(growable: false);
  }

  // 只扫描应用自有的 ios/** 源码；第三方插件的 MethodChannel
  // 是插件内部通信契约，不应被应用级差异化改写。
  // Scan app-owned ios/** only. Third-party plugin channels remain untouched.
  List<File> _iosSourceFiles() => Directory(p.join(config.projectPath, 'ios'))
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where(
        (file) =>
            const {'.swift', '.m', '.mm'}.contains(p.extension(file.path)),
      )
      .where((file) => !p.split(file.path).contains('Pods'))
      .toList(growable: false);

  Iterable<String> _discoverStaticNames(String source, String path) sync* {
    for (final match in _channelPattern(path).allMatches(source)) {
      yield match.namedGroup('name')!;
    }
  }

  Future<List<_TextMatch>> _matchingEdits(List<File> files, String name) async {
    final matches = <_TextMatch>[];
    for (final file in files) {
      final source = await file.readAsString();
      for (final match in _channelPattern(file.path).allMatches(source)) {
        if (match.namedGroup('name') == name) {
          matches.add(
            _TextMatch(file.path, match.start + match[0]!.indexOf(name)),
          );
        }
      }
    }
    return matches;
  }

  RegExp _channelPattern(String path) {
    // 仅处理构造函数参数中的静态字符串。变量、插值和字符串拼接会被跳过。
    switch (p.extension(path)) {
      case '.dart':
        return RegExp(
          r'''\bMethodChannel\s*\(\s*(?<quote>['"])(?<name>[^'"\r\n]+)\k<quote>''',
          multiLine: true,
        );
      case '.swift':
        return RegExp(
          r'''\bFlutterMethodChannel\s*\(\s*name\s*:\s*(?<quote>["])(?<name>[^"\r\n]+)\k<quote>''',
          multiLine: true,
        );
      default:
        return RegExp(
          r'''(?:methodChannelWithName|initWithName)\s*:\s*@(?<quote>["])(?<name>[^"\r\n]+)\k<quote>''',
          multiLine: true,
        );
    }
  }

  String _uniqueName(String stem, Set<String> existing) {
    // token 固定为 14 位，字符集为 a-z 和 0-9，共 36^14 种组合。
    // 如果极小概率碰到已有名称，则重新生成，直到得到唯一名称。
    while (true) {
      final token = List.generate(
        14,
        (_) => _alphabet[_random.nextInt(_alphabet.length)],
      ).join();
      final candidate = '$stem.$token';
      if (!existing.contains(candidate)) return candidate;
    }
  }

  String _generatedDart(List<String> names) =>
      '''// Generated by dart_prefix_renamer. Do not edit.
// 这些 Channel 只用于 iOS IPA 差异化，不参与业务通信。
import 'package:flutter/services.dart';

// vm:entry-point 防止 AOT tree shaking 删除生成的 Channel 列表。
@pragma('vm:entry-point')
final List<MethodChannel> _iosDifferentiatedChannels = <MethodChannel>[
${names.map((name) => "  const MethodChannel('$name'),").join('\n')}
];

@pragma('vm:entry-point')
int _iosDifferentiatedChannelChecksum = 0;

@pragma('vm:entry-point')
void initializeIosDifferentiatedMethodChannels() {
  // 读取每个名称并保存计算结果，让生成列表从 main() 保持可达。
  // 此处不访问 BinaryMessenger，因而可以安全地放在 main() 的最前面。
  _iosDifferentiatedChannelChecksum = Object.hashAll(
    _iosDifferentiatedChannels.map((channel) => channel.name),
  );
}
''';

  Future<void> _wireDartEntrypoint(File entrypoint, File generated) async {
    var source = await entrypoint.readAsString();
    if (source.contains(_dartImportMarker) ||
        source.contains(_dartInitMarker)) {
      throw StateError(
        'Dart entrypoint already contains MethodChannel generated markers: ${entrypoint.path}',
      );
    }
    final relative = p.posix.joinAll(
      p.split(p.relative(generated.path, from: entrypoint.parent.path)),
    );
    final importPath = relative.startsWith('.') ? relative : './$relative';
    // 使用 Dart AST 定位真正的顶层 main，避免文本搜索误改注释或其他函数。
    final unit = parseString(content: source, path: entrypoint.path).unit;
    final main = unit.declarations
        .whereType<FunctionDeclaration>()
        .where((node) => node.name.lexeme == 'main')
        .firstOrNull;
    if (main == null) {
      throw StateError('No top-level main() found in ${entrypoint.path}');
    }
    final importOffset = unit.directives.isEmpty ? 0 : unit.directives.last.end;
    source = applySourceEdits(source, [
      SourceEdit(
        offset: importOffset,
        length: 0,
        replacement: "\n$_dartImportMarker\nimport '$importPath';",
        reason: 'import iOS MethodChannel initializer',
      ),
      _mainBodyEdit(main),
    ]);
    await entrypoint.writeAsString(source);
  }

  SourceEdit _mainBodyEdit(FunctionDeclaration main) {
    final body = main.functionExpression.body;
    const call =
        '\n  $_dartInitMarker\n  initializeIosDifferentiatedMethodChannels();';
    // 同时支持 `void main() {}` 和 `void main() => runApp(...)` 两种入口。
    if (body is BlockFunctionBody) {
      return SourceEdit(
        offset: body.block.leftBracket.end,
        length: 0,
        replacement: call,
        reason: 'initialize iOS MethodChannels',
      );
    }
    if (body is ExpressionFunctionBody) {
      final asyncPrefix = body.isAsynchronous ? 'async ' : '';
      return SourceEdit(
        offset: body.offset,
        length: body.length,
        replacement:
            '$asyncPrefix{$call\n  $_dartExpressionMarker\n'
            '  ${body.expression.toSource()};\n'
            '  $_dartExpressionEndMarker\n}',
        reason: 'initialize iOS MethodChannels',
      );
    }
    throw StateError('Unsupported main() body in generated entrypoint.');
  }

  Future<File> _wireIosAppDelegate(List<String> names) async {
    final runner = Directory(p.join(config.projectPath, 'ios', 'Runner'));
    final swift = runner
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path) == 'AppDelegate.swift')
        .firstOrNull;
    // Flutter 新工程通常使用 Swift；找不到 Swift 时再回退到 Objective-C。
    if (swift != null) {
      var source = await swift.readAsString();
      if (source.contains(_swiftInitMarker)) {
        throw StateError(
          'AppDelegate already contains generated MethodChannel markers.',
        );
      }
      final classMatch = RegExp(
        r'class\s+AppDelegate[^\{]*\{',
      ).firstMatch(source);
      final controllerMatch = RegExp(
        r'(?:let|var)\s+(\w+)\s*=\s*[^\n]*FlutterViewController[^\n]*',
      ).firstMatch(source);
      if (classMatch == null || controllerMatch == null) {
        throw StateError(
          'Cannot locate Swift AppDelegate FlutterViewController initialization.',
        );
      }
      final controller = controllerMatch.group(1)!;
      // 保存为 AppDelegate 属性，确保 Channel 生命周期覆盖整个应用运行期。
      final property =
          '\n    $_swiftPropertyMarker\n    private var differentiatedMethodChannels: [FlutterMethodChannel] = []\n';
      final init =
          '''\n        $_swiftInitMarker
        differentiatedMethodChannels = [
${names.map((name) => '            FlutterMethodChannel(name: "$name", binaryMessenger: $controller.binaryMessenger),').join('\n')}
        ]
''';
      source = applySourceEdits(source, [
        SourceEdit(
          offset: classMatch.end,
          length: 0,
          replacement: property,
          reason: 'retain iOS MethodChannels',
        ),
        SourceEdit(
          offset: controllerMatch.end,
          length: 0,
          replacement: init,
          reason: 'initialize iOS MethodChannels',
        ),
      ]);
      await swift.writeAsString(source);
      return swift;
    }
    final objc = runner
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path) == 'AppDelegate.m')
        .firstOrNull;
    if (objc == null) {
      throw StateError(
        'No ios/Runner AppDelegate.swift or AppDelegate.m found.',
      );
    }
    var source = await objc.readAsString();
    final controllerMatch = RegExp(
      r'FlutterViewController\s*\*\s*(\w+)\s*=\s*[^;]+;',
    ).firstMatch(source);
    if (controllerMatch == null) {
      throw StateError(
        'Cannot locate Objective-C AppDelegate FlutterViewController initialization.',
      );
    }
    final controller = controllerMatch.group(1)!;
    // Objective-C 使用 static NSArray 达到同样的强引用保留效果。
    final init =
        '''\n  $_objcInitMarker
  static NSArray<FlutterMethodChannel *> *differentiatedMethodChannels;
  differentiatedMethodChannels = @[
${names.map((name) => '    [FlutterMethodChannel methodChannelWithName:@"$name" binaryMessenger:$controller.binaryMessenger],').join('\n')}
  ];
''';
    source = source.replaceRange(
      controllerMatch.end,
      controllerMatch.end,
      init,
    );
    await objc.writeAsString(source);
    return objc;
  }
}

const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

final class _TextMatch {
  const _TextMatch(this.file, this.offset);
  final String file;
  final int offset;
}

Future<void> restoreIosMethodChannelDiff({
  required String projectPath,
  required Map<String, dynamic> manifest,
}) async {
  final section = manifest['iosMethodChannelDiff'];
  if (section is! Map<String, dynamic> || section['enabled'] != true) {
    return;
  }
  // manifest 保存的是 original -> replacement，这里按反方向恢复真实名称。
  final renamesValue = section['renames'];
  if (renamesValue is Map<String, dynamic>) {
    for (final entity in Directory(
      projectPath,
    ).listSync(recursive: true, followLinks: false).whereType<File>()) {
      if (!const {
            '.dart',
            '.swift',
            '.m',
            '.mm',
          }.contains(p.extension(entity.path)) ||
          p.split(entity.path).contains('Pods')) {
        continue;
      }
      var source = await entity.readAsString();
      var changed = false;
      for (final entry in renamesValue.entries) {
        if (entry.value is String && source.contains(entry.value as String)) {
          source = source.replaceAll(entry.value as String, entry.key);
          changed = true;
        }
      }
      if (changed) {
        await entity.writeAsString(source);
      }
    }
  }
  // 只删除带专用 marker 的注入块，不触碰用户原有的入口和 AppDelegate 代码。
  for (final key in ['entrypoints', 'iosInjectionFile']) {
    final values = key == 'entrypoints' ? section[key] : [section[key]];
    if (values is! List) continue;
    for (final relative in values.whereType<String>()) {
      final file = File(p.join(projectPath, relative));
      if (!file.existsSync()) continue;
      var source = await file.readAsString();
      source = _removeMarkedLines(source, key == 'entrypoints');
      await file.writeAsString(source);
    }
  }
  final generated = section['generatedDartFile'];
  if (generated is String) {
    final file = File(p.join(projectPath, generated));
    if (file.existsSync()) await file.delete();
  }
}

String _removeMarkedLines(String source, bool dart) {
  if (dart) {
    source = source.replaceAllMapped(
      RegExp(
        r'(async\s+)?\{\s*// dart_prefix_renamer:ios-method-channel-init\s*initializeIosDifferentiatedMethodChannels\(\);\s*// dart_prefix_renamer:ios-method-channel-expression\s*([\s\S]*?);\s*// dart_prefix_renamer:ios-method-channel-expression-end\s*\}',
      ),
      (match) => '${match.group(1) ?? ''}=> ${match.group(2)!.trim()};',
    );
    source = source.replaceAll(
      RegExp(
        r"\n?// dart_prefix_renamer:ios-method-channel-import\nimport '[^']+';",
      ),
      '',
    );
    source = source.replaceAll(
      RegExp(
        r'\n\s*// dart_prefix_renamer:ios-method-channel-init\n\s*initializeIosDifferentiatedMethodChannels\(\);',
      ),
      '',
    );
  } else {
    source = source.replaceAll(
      RegExp(
        r'\n\s*// dart_prefix_renamer:ios-method-channel-property\n\s*private var differentiatedMethodChannels: \[FlutterMethodChannel\] = \[\]\n',
      ),
      '\n',
    );
    source = source.replaceAll(
      RegExp(
        r'\n\s*// dart_prefix_renamer:ios-method-channel-init\n\s*differentiatedMethodChannels = \[[\s\S]*?\n\s*\]\n',
      ),
      '\n',
    );
    source = source.replaceAll(
      RegExp(
        r'\n\s*// dart_prefix_renamer:ios-method-channel-init\n\s*static NSArray<FlutterMethodChannel \*> \*differentiatedMethodChannels;[\s\S]*?\n\s*\];\n',
      ),
      '\n',
    );
  }
  return source;
}
