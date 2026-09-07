import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

final class AddJunkCodeReport {
  const AddJunkCodeReport({
    required this.directory,
    required this.files,
    required this.classes,
  });

  final String directory;
  final int files;
  final int classes;
}

final class AddJunkCodeConfig {
  const AddJunkCodeConfig({
    this.seed,
    this.minFiles = 400,
    this.maxFiles = 599,
    this.minImportsPerFile = 1,
    this.maxImportsPerFile = 5,
    this.minClassesPerFile = 5,
    this.maxClassesPerFile = 14,
    this.minPropertiesPerClass = 10,
    this.maxPropertiesPerClass = 29,
    this.minMethodsPerClass = 5,
    this.maxMethodsPerClass = 14,
    this.minStatementsPerMethod = 3,
    this.maxStatementsPerMethod = 12,
    this.commentProbability = 0.55,
  }) : assert(minFiles > 0 && maxFiles >= minFiles),
       assert(minImportsPerFile >= 0 && maxImportsPerFile >= minImportsPerFile),
       assert(minClassesPerFile > 0 && maxClassesPerFile >= minClassesPerFile),
       assert(
         minPropertiesPerClass > 0 &&
             maxPropertiesPerClass >= minPropertiesPerClass,
       ),
       assert(
         minMethodsPerClass > 0 && maxMethodsPerClass >= minMethodsPerClass,
       ),
       assert(
         minStatementsPerMethod > 0 &&
             maxStatementsPerMethod >= minStatementsPerMethod,
       ),
       assert(commentProbability >= 0 && commentProbability <= 1);

  /// 设置后可重现同一批生成结果；留空则每次不同。
  final int? seed;
  final int minFiles;
  final int maxFiles;
  final int minImportsPerFile;
  final int maxImportsPerFile;
  final int minClassesPerFile;
  final int maxClassesPerFile;
  final int minPropertiesPerClass;
  final int maxPropertiesPerClass;
  final int minMethodsPerClass;
  final int maxMethodsPerClass;
  final int minStatementsPerMethod;
  final int maxStatementsPerMethod;
  final double commentProbability;
}

/// 完整移植自 tbr-shell-cladding 的 Dart 垃圾代码生成器。
final class AddJunkCode {
  AddJunkCode(this.projectPath, {this.config = const AddJunkCodeConfig()})
    : random = config.seed == null ? Random() : Random(config.seed);

  final String projectPath;
  final AddJunkCodeConfig config;
  final Random random;
  final classNames = <String>[];
  final functionNames = <String>[];
  final generateClassList = <String>[];
  final _generatedNames = <String>{};
  late String className;

  Future<AddJunkCodeReport> addJunkCode() async {
    final projectDir = Directory(
      p.join(projectPath, 'lib', 'pack', 'junk_code'),
    );
    className = getRandom(8);
    final fileCount = _between(config.minFiles, config.maxFiles);

    if (projectDir.existsSync()) {
      await projectDir.delete(recursive: true);
    }
    await projectDir.create(recursive: true);

    for (var i = 0; i < fileCount; i++) {
      generateJunkFile(projectDir, i, fileCount);
    }
    generateMainFile(projectDir.path, fileCount);

    return AddJunkCodeReport(
      directory: projectDir.path,
      files: fileCount + 1,
      classes: generateClassList.length,
    );
  }

  void generateMainFile(String path, int count) {
    final file = File(p.join(path, 'junk_code_main.dart'));
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }

    final imports = StringBuffer()
      ..writeln("import 'package:flutter/foundation.dart';")
      ..writeln();
    for (var i = 0; i < count; i++) {
      final fileName = '${className}_${i.toString().padLeft(3, '0')}.dart';
      imports.writeln("import './$fileName';");
    }

    final mainBody = StringBuffer()
      ..writeln('void JunkCodeMain() async {')
      ..writeln('  // 垃圾代码入口点')
      ..writeln()
      ..writeln('  compute((e) {');
    for (final generatedClass in generateClassList) {
      final instanceName = '${getRandom(12)}_${random.nextInt(100000)}';
      mainBody.writeln(
        '    $generatedClass $instanceName = $generatedClass();',
      );
    }
    mainBody
      ..writeln('  }, "message");')
      ..writeln('}');

    file.writeAsStringSync('${imports.toString()}\n${mainBody.toString()}');
  }

  void generateJunkFile(Directory dir, int index, int totalFiles) {
    final fileName = '${className}_${index.toString().padLeft(3, '0')}.dart';
    final file = File(p.join(dir.path, fileName));
    final buffer = StringBuffer()
      ..writeln('// 由自动代码生成器创建的垃圾文件 - 请勿手动修改')
      ..writeln('// 文件路径: ${file.path}')
      ..writeln('// 生成时间: ${DateTime.now()}')
      ..writeln('// ==============================')
      ..writeln();

    final importCount = _between(
      config.minImportsPerFile,
      config.maxImportsPerFile,
    );
    for (var i = 0; i < importCount; i++) {
      final importIndex = random.nextInt(totalFiles);
      if (importIndex != index) {
        final importFile =
            '${className}_${importIndex.toString().padLeft(3, '0')}.dart';
        buffer.writeln("import './$importFile';");
      }
    }
    buffer.writeln();

    final classCount = _between(
      config.minClassesPerFile,
      config.maxClassesPerFile,
    );
    for (var i = 0; i < classCount; i++) {
      generateClassList.add(generateClass(buffer));
      buffer.writeln();
    }
    file.writeAsStringSync(buffer.toString());
  }

  String generateClass(StringBuffer buffer) {
    final generatedClassName = _generateName(getRandom(8));
    classNames.add(generatedClassName);
    buffer.writeln('class $generatedClassName {');

    final propCount = _between(
      config.minPropertiesPerClass,
      config.maxPropertiesPerClass,
    );
    const propTypes = <String>[
      'String',
      'int',
      'double',
      'bool',
      'List<String>',
      'Map<String, dynamic>',
      'DateTime',
    ];
    final propList = <String>[];
    final generateMethodList = <String>[];

    for (var i = 0; i < propCount; i++) {
      final propName = _generateName('prop');
      final propType = propTypes[random.nextInt(propTypes.length)];
      if (_shouldWriteComment()) {
        buffer.writeln('  // ${_randomComment()}');
      }
      buffer.writeln('  $propType? $propName;');
      propList.add(propName);
    }

    buffer
      ..writeln()
      ..writeln('  $generatedClassName({');
    for (var i = 0; i < min(3, propCount); i++) {
      buffer.writeln('    this.${propList[i]},');
    }
    buffer
      ..writeln('  }){')
      ..writeln('      callMain();')
      ..writeln('  }');

    final methodCount = _between(
      config.minMethodsPerClass,
      config.maxMethodsPerClass,
    );
    for (var i = 0; i < methodCount; i++) {
      generateMethodList.add(generateMethod(buffer, generatedClassName));
    }

    buffer.writeln('  void callMain(){');
    for (final methodName in generateMethodList) {
      buffer.writeln('    $methodName();');
    }
    buffer
      ..writeln('  }')
      ..writeln()
      ..writeln('}');
    return generatedClassName;
  }

  String getRandom([int? count]) {
    count ??= 5;
    const letters = <String>[
      'a',
      'b',
      'c',
      'd',
      'e',
      'f',
      'g',
      'h',
      'i',
      'j',
      'k',
      'l',
      'm',
      'n',
      'o',
      'p',
      'q',
      'r',
      's',
      't',
      'u',
      'v',
      'w',
      'x',
      'y',
      'z',
    ];
    return List.generate(
      count,
      (_) => letters[random.nextInt(letters.length)],
    ).join();
  }

  String generateMethod(StringBuffer buffer, [String? generatedClassName]) {
    final methodName = _generateName('junkMethod');
    final prefix = generatedClassName != null ? '  ' : '';
    if (_shouldWriteComment()) {
      buffer.writeln('$prefix// ${_randomComment()}');
    }

    const returnTypes = ['void', 'int', 'String', 'double', 'bool'];
    final returnType = returnTypes[random.nextInt(returnTypes.length)];
    buffer.writeln('$prefix$returnType $methodName() {');
    final contentLines = _between(
      config.minStatementsPerMethod,
      config.maxStatementsPerMethod,
    );
    for (var j = 0; j < contentLines; j++) {
      buffer.write('$prefix  ');
      switch (random.nextInt(10)) {
        case 0:
          buffer.writeln('final ${_generateName('var')} = ${_randomValue()};');
          break;
        case 1:
          buffer.writeln('if (${_randomBool()}) {');
          buffer.writeln('$prefix    print(${_randomStringValue()});');
          buffer.writeln('$prefix  } else {');
          buffer.writeln('$prefix    print(${_randomStringValue()});');
          buffer.writeln('$prefix  }');
          break;
        case 2:
          buffer.writeln(
            'for (var i = 0; i < ${random.nextInt(5) + 1}; i++) {',
          );
          buffer.writeln('$prefix    ${_randomValue()};');
          buffer.writeln('$prefix  }');
          break;
        case 3:
          if (functionNames.isNotEmpty && random.nextBool()) {
            buffer.writeln(
              '${functionNames[random.nextInt(functionNames.length)]}();',
            );
          } else {
            buffer.writeln('print(${_randomStringValue()});');
          }
          break;
        case 4:
          buffer.writeln(
            'final ${getRandom(6)} = ${random.nextInt(100)} * '
            '${random.nextInt(100)} - ${random.nextInt(50)};',
          );
          break;
        default:
          buffer.writeln('${_randomJunkStatement()};');
      }
    }
    if (returnType != 'void') {
      buffer.writeln('$prefix  return ${_randomValue(returnType)};');
    }
    buffer.writeln('$prefix}');
    if (generatedClassName == null) {
      functionNames.add(methodName);
    }
    return methodName;
  }

  void generateFunction(StringBuffer buffer) => generateMethod(buffer);

  String _generateName(String prefix) {
    const domains = <String>[
      'Cache',
      'Index',
      'Queue',
      'Signal',
      'Metric',
      'Token',
      'Buffer',
      'Channel',
      'Snapshot',
      'Registry',
      'Pipeline',
      'Session',
    ];
    const roles = <String>[
      'Coordinator',
      'Resolver',
      'Tracker',
      'Reducer',
      'Mapper',
      'Policy',
      'Store',
      'Adapter',
      'Delegate',
      'Provider',
      'Validator',
      'Worker',
    ];
    final safePrefix = prefix.replaceAll(RegExp('[^a-zA-Z0-9_]'), 'x');

    while (true) {
      final domain = domains[random.nextInt(domains.length)];
      final role = roles[random.nextInt(roles.length)];
      final serial = random.nextInt(0xffffff).toRadixString(36);
      final candidate = switch (random.nextInt(4)) {
        0 => '${safePrefix}_$domain${role}_$serial',
        1 => '$safePrefix$domain$role$serial',
        2 =>
          '${safePrefix}_${domain.toLowerCase()}_${role.toLowerCase()}$serial',
        _ => '${safePrefix}_${getRandom(4)}${role}_$serial',
      };
      if (_generatedNames.add(candidate)) {
        return candidate;
      }
    }
  }

  String _randomStringValue() {
    const prefixes = ['DEBUG', 'INFO', 'WARN', 'ERROR', 'TRACE'];
    const subjects = ['app', 'system', 'module', 'service', 'function'];
    const actions = [
      'starting',
      'stopping',
      'initializing',
      'processing',
      'validating',
    ];
    const suffixes = ['request', 'data', 'module', 'component', 'transaction'];
    return "'${prefixes[random.nextInt(prefixes.length)]}: "
        '${subjects[random.nextInt(subjects.length)]} '
        '${actions[random.nextInt(actions.length)]} '
        '${suffixes[random.nextInt(suffixes.length)]}${random.nextInt(999)}\'';
  }

  String _randomValue([String? type]) {
    final valueType =
        type ?? ['int', 'String', 'double', 'bool', 'List'][random.nextInt(5)];
    switch (valueType) {
      case 'int':
        return random.nextInt(999).toString();
      case 'double':
        return (random.nextDouble() * 100).toStringAsFixed(2);
      case 'bool':
        return random.nextBool().toString();
      case 'List':
        return '[${random.nextInt(5)}, ${random.nextInt(5)}, '
            '${random.nextInt(5)}]';
      default:
        return _randomStringValue();
    }
  }

  String _randomComment() {
    const scopes = <String>[
      '本地缓存',
      '会话快照',
      '状态索引',
      '任务队列',
      '配置映射',
      '度量采样',
      '事件通道',
      '数据缓冲',
      '标识解析',
      '版本兼容',
    ];
    const actions = <String>[
      '保留中间态',
      '合并重复项',
      '校验边界值',
      '回收过期记录',
      '维持稳定顺序',
      '延迟计算结果',
      '同步内部标记',
      '构建轻量索引',
    ];
    const reasons = <String>[
      '避免频繁重算',
      '用于降级路径',
      '供调试采样使用',
      '确保批处理一致性',
      '兼容历史数据',
      '为后续扩展预留',
    ];
    return '${scopes[random.nextInt(scopes.length)]}：'
        '${actions[random.nextInt(actions.length)]}，'
        '${reasons[random.nextInt(reasons.length)]}';
  }

  bool _shouldWriteComment() => random.nextDouble() < config.commentProbability;

  int _between(int minValue, int maxValue) =>
      minValue + random.nextInt(maxValue - minValue + 1);

  String _randomBool() {
    const conditions = <String>[
      'true',
      'false',
      'DateTime.now().millisecondsSinceEpoch % 2 == 0',
      'List.generate(5, (i) => i).length > 3',
    ];
    return conditions[random.nextInt(conditions.length)];
  }

  String _randomJunkStatement() {
    final statements = <String>[
      'int ${_generateName('count')} = ${random.nextInt(100)};',
      'double ${_generateName('value')} = ${random.nextDouble() * 100};',
      'List<int> ${_generateName('list')} = [${random.nextInt(10)}, ${random.nextInt(10)}, ${random.nextInt(10)}];',
      "Map<String, dynamic> ${_generateName('map')} = {'key${random.nextInt(10)}': 'value${random.nextInt(10)}'};",
      'if (${random.nextInt(100)} > 50) { /* 条件执行 */ }',
      'for (var i = 0; i < ${random.nextInt(5) + 1}; i++) { /* 循环 */ }',
      "String ${_generateName('text')} = '随机文本${random.nextInt(100)}';",
      'Object ${_generateName('obj')} = Object();',
      'final bool ${_generateName('flag')} = ${random.nextBool()};',
      'final DateTime ${_generateName('time')} = DateTime.now();',
      'try { /* 尝试执行 */ } catch (e) { /* 错误处理 */ }',
      'switch (${random.nextInt(3)}) { case 0: break; default: break; }',
      'dynamic ${_generateName('result')} = null;',
      'int ${_generateName('product')} = ${random.nextInt(10)} * ${random.nextInt(10)};',
      'double ${_generateName('sum')} = ${random.nextDouble() + random.nextDouble()};',
      "List<String> ${_generateName('items')} = ['itemA', 'itemB', 'itemC'];",
      'String ${_generateName('message')} = "操作${random.nextInt(10)}执行完成";',
      'while (${random.nextInt(100)} > 20) { /* 循环 */ }',
      'final Duration ${_generateName('delay')} = Duration(milliseconds: ${random.nextInt(1000)});',
      "Map<int, String> ${_generateName('mapInt')} = {1: 'one', 2: 'two'};",
      'int ${_generateName('factorial')} = [1,1,2,6,24,120][${random.nextInt(5)}];',
      "final RegExp ${_generateName('regex')} = RegExp(r'd+');",
      "Set<String> ${_generateName('unique')} = {'a', 'b', 'c', 'd', 'e'};",
      "Future.delayed(Duration(milliseconds: ${random.nextInt(1000)}), () => print('延迟回调'));",
      'final double ${_generateName('root')} = ${random.nextInt(100) + 1};',
      'final bool ${_generateName('isValid')} = ${random.nextBool()} && ${random.nextBool()};',
      "Runes ${_generateName('runes')} = Runes('😁😅');",
      'Symbol ${_generateName('symbol')} = #symbol_name;',
      'Null ${_generateName('empty')} = null;',
    ];
    return statements[random.nextInt(statements.length)];
  }
}
