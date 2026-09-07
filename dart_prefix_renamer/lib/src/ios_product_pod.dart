import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// 成对 marker 是可逆注入的边界。restore 只删除边界内代码，不做宽泛文本替换。
// Paired markers bound reversible edits so restore never removes unrelated code.
const _podfileBegin = '# dart_prefix_renamer:ios-product-pod-begin';
const _podfileEnd = '# dart_prefix_renamer:ios-product-pod-end';
const _swiftImportBegin = '// dart_prefix_renamer:ios-product-pod-import-begin';
const _swiftImportEnd = '// dart_prefix_renamer:ios-product-pod-import-end';
const _swiftInitBegin = '// dart_prefix_renamer:ios-product-pod-init-begin';
const _swiftInitEnd = '// dart_prefix_renamer:ios-product-pod-init-end';

const supportedIosProductPodThemes = <String>[
  'resource_catalog',
  'display_rules',
  'configuration_profile',
];

final class IosProductPodConfig {
  IosProductPodConfig({
    required String projectPath,
    required this.prefix,
    required this.productId,
    this.theme,
    this.seed,
  }) : projectPath = p.normalize(p.absolute(projectPath));

  final String projectPath;
  final String prefix;
  final String productId;
  final String? theme;
  final int? seed;
}

final class IosProductPodReport {
  const IosProductPodReport({
    required this.productId,
    required this.podName,
    required this.classPrefix,
    required this.theme,
    required this.seed,
    required this.channelName,
    required this.podDirectory,
    required this.dartClientFile,
    required this.podfile,
    required this.appDelegate,
    required this.sourceFiles,
    required this.resourceFiles,
    required this.generatedFiles,
    required this.contentHash,
    required this.manifestHash,
  });

  final String productId;
  final String podName;
  final String classPrefix;
  final String theme;
  final int seed;
  final String channelName;
  final String podDirectory;
  final String dartClientFile;
  final String podfile;
  final String appDelegate;
  final int sourceFiles;
  final int resourceFiles;
  final int generatedFiles;
  final String contentHash;
  final String manifestHash;
}

/// 生成确定性的源码 CocoaPod，包含离线产品配置、展示规则和资源目录能力。
/// Generates a deterministic source CocoaPod containing offline configuration,
/// display-rule, and resource-catalog behavior.
///
/// 生成模块刻意不提供网络、权限、设备标识、后台任务、统计或第三方 SDK API。
/// The generated module deliberately exposes no networking, permissions,
/// device identifiers, background execution, analytics, or third-party APIs.
final class IosProductPodGenerator {
  IosProductPodGenerator(this.config);

  final IosProductPodConfig config;

  Future<IosProductPodReport> generate() async {
    _validateProject();
    // seed 控制名称、规则和资源内容；相同输入必须得到逐字节相同的输出。
    // The seed controls names, rules, and resources for byte-stable generation.
    final resolvedSeed =
        config.seed ?? _deriveSeed(config.productId, config.prefix);
    final random = Random(resolvedSeed);
    final resolvedTheme =
        config.theme ??
        supportedIosProductPodThemes[_deriveSeed(config.productId, 'theme') %
            supportedIosProductPodThemes.length];
    if (!supportedIosProductPodThemes.contains(resolvedTheme)) {
      throw ArgumentError.value(
        resolvedTheme,
        'theme',
        'Expected one of ${supportedIosProductPodThemes.join(', ')}',
      );
    }

    // productId 区分产品，prefix 区分本次源码命名；短哈希进一步避免 ObjC 类冲突。
    // Product id, rename prefix, and a short hash jointly prevent name clashes.
    final productName = _pascalCase(config.productId);
    final prefixName = _pascalCase(config.prefix);
    final podName = '$productName${prefixName}LocalKit';
    final classPrefix =
        '${config.prefix.toUpperCase()}${_shortHash(config.productId)}';
    final channelName =
        'com.dartprefixrenamer.product.${config.productId}.${_token(random, 10)}';
    final podDirectory = Directory(
      p.join(config.projectPath, 'ios', 'LocalPods', podName),
    );
    if (podDirectory.existsSync()) {
      throw StateError(
        'Generated iOS product Pod directory already exists: ${podDirectory.path}',
      );
    }

    final sourceDirectory = Directory(p.join(podDirectory.path, 'Sources'));
    final bundleDirectory = Directory(
      p.join(podDirectory.path, 'Resources', '$podName.bundle'),
    );
    await sourceDirectory.create(recursive: true);
    await bundleDirectory.create(recursive: true);

    // 这些参数驱动真实的本地展示规则，而不是不可达的占位代码。
    // These values drive reachable offline behavior rather than dead placeholders.
    final minimumScore = 25 + random.nextInt(36);
    final preferredStates = _rotatedStates(random.nextInt(4));
    final stateWeights = <String, int>{
      for (var index = 0; index < preferredStates.length; index++)
        preferredStates[index]: 4 + random.nextInt(13) + index,
    };
    final revision = 1000 + random.nextInt(9000);
    final variationToken = _token(random, 16);
    final rules = <String, Object>{
      'product_id': config.productId,
      'theme': resolvedTheme,
      'revision': revision,
      'minimum_score': minimumScore,
      'preferred_states': preferredStates,
      'state_weights': stateWeights,
      'fallback_layout': _fallbackLayout(resolvedTheme),
      'variation_token': variationToken,
    };
    final catalog = <String, Object>{
      'product_id': config.productId,
      'module': podName,
      'required_files': ['product_rules.json', 'resource_catalog.json'],
      'capabilities': _capabilities(resolvedTheme),
      'revision': revision,
    };

    final sourceFiles = <File>[
      await _write(
        sourceDirectory,
        '${classPrefix}ProductRuntime.h',
        _runtimeHeader(classPrefix),
      ),
      await _write(
        sourceDirectory,
        '${classPrefix}ProductRuntime.m',
        _runtimeImplementation(
          classPrefix: classPrefix,
          productId: config.productId,
          podName: podName,
          theme: resolvedTheme,
          seed: resolvedSeed,
          channelName: channelName,
          revision: revision,
        ),
      ),
      await _write(
        sourceDirectory,
        '${classPrefix}ConfigurationResolver.h',
        _configurationHeader(classPrefix),
      ),
      await _write(
        sourceDirectory,
        '${classPrefix}ConfigurationResolver.m',
        _configurationImplementation(classPrefix, variationToken),
      ),
      await _write(
        sourceDirectory,
        '${classPrefix}DisplayRuleEngine.h',
        _displayRuleHeader(classPrefix),
      ),
      await _write(
        sourceDirectory,
        '${classPrefix}DisplayRuleEngine.m',
        _displayRuleImplementation(classPrefix, resolvedTheme),
      ),
      await _write(
        sourceDirectory,
        '${classPrefix}ResourceCatalog.h',
        _resourceCatalogHeader(classPrefix),
      ),
      await _write(
        sourceDirectory,
        '${classPrefix}ResourceCatalog.m',
        _resourceCatalogImplementation(classPrefix, podName),
      ),
    ];
    final resourceFiles = <File>[
      await _writeJson(bundleDirectory, 'product_rules.json', rules),
      await _writeJson(bundleDirectory, 'resource_catalog.json', catalog),
    ];
    final podspec = await _write(
      podDirectory,
      '$podName.podspec',
      _podspec(podName, classPrefix),
    );
    final dartClient = await _write(
      Directory(p.join(config.projectPath, 'lib', 'pack', 'product_runtime')),
      '${config.prefix}_product_runtime.dart',
      _dartClient(
        className: '${prefixName}ProductRuntimeClient',
        channelName: channelName,
      ),
    );

    final payloadFiles = <File>[
      podspec,
      ...sourceFiles,
      ...resourceFiles,
      dartClient,
    ];
    // contentHash 覆盖 podspec、源码、资源和 Dart 客户端，但不包含 manifest 自身，
    // 从而避免自引用哈希。
    // Hash the payload before the manifest to avoid a self-referential digest.
    final contentHash = await _hashFiles(payloadFiles);
    final productManifest = <String, Object>{
      'version': 1,
      'productId': config.productId,
      'prefix': config.prefix,
      'podName': podName,
      'classPrefix': classPrefix,
      'theme': resolvedTheme,
      'seed': resolvedSeed,
      'channelName': channelName,
      'sourceFiles': sourceFiles
          .map((file) => _relative(file.path, podDirectory.path))
          .toList(growable: false),
      'resourceFiles': resourceFiles
          .map((file) => _relative(file.path, podDirectory.path))
          .toList(growable: false),
      'dartClient': _relative(dartClient.path, config.projectPath),
      'contentHash': contentHash,
      'constraints': {
        'network': false,
        'permissions': false,
        'deviceIdentifiers': false,
        'backgroundTasks': false,
        'dataCollection': false,
        'thirdPartyDependencies': false,
      },
    };
    final manifestFile = await _writeJson(
      podDirectory,
      'product_pod_manifest.json',
      productManifest,
    );
    final manifestHash = sha256
        .convert(await manifestFile.readAsBytes())
        .toString();

    final podfile = await _wirePodfile(podName);
    final appDelegate = await _wireAppDelegate(podName, classPrefix);
    return IosProductPodReport(
      productId: config.productId,
      podName: podName,
      classPrefix: classPrefix,
      theme: resolvedTheme,
      seed: resolvedSeed,
      channelName: channelName,
      podDirectory: podDirectory.path,
      dartClientFile: dartClient.path,
      podfile: podfile.path,
      appDelegate: appDelegate.path,
      sourceFiles: sourceFiles.length,
      resourceFiles: resourceFiles.length,
      generatedFiles: payloadFiles.length + 1,
      contentHash: contentHash,
      manifestHash: manifestHash,
    );
  }

  void _validateProject() {
    if (!RegExp(r'^[a-z]+$').hasMatch(config.prefix)) {
      throw ArgumentError.value(config.prefix, 'prefix');
    }
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(config.productId)) {
      throw ArgumentError.value(config.productId, 'productId');
    }
    final ios = Directory(p.join(config.projectPath, 'ios'));
    final podfile = File(p.join(ios.path, 'Podfile'));
    final appDelegate = File(p.join(ios.path, 'Runner', 'AppDelegate.swift'));
    if (!ios.existsSync() ||
        !podfile.existsSync() ||
        !appDelegate.existsSync()) {
      throw StateError(
        'iOS product Pod generation requires ios/Podfile and '
        'ios/Runner/AppDelegate.swift in ${config.projectPath}.',
      );
    }
  }

  Future<File> _wirePodfile(String podName) async {
    final file = File(p.join(config.projectPath, 'ios', 'Podfile'));
    var source = await file.readAsString();
    if (source.contains(_podfileBegin) || source.contains(_podfileEnd)) {
      throw StateError('Podfile already contains an iOS product Pod marker.');
    }
    // 插到 Flutter 自动安装调用之前，保证声明位于 Runner target 内，且不依赖
    // 用户 Podfile 中其他第三方 Pod 的排列方式。
    // Insert before Flutter's install call while remaining inside Runner target.
    final marker = RegExp(
      r'^([ \t]*)flutter_install_all_ios_pods\b',
      multiLine: true,
    ).firstMatch(source);
    if (marker == null) {
      throw StateError(
        'Cannot find flutter_install_all_ios_pods in ios/Podfile.',
      );
    }
    final indent = marker.group(1)!;
    final block =
        '$indent$_podfileBegin\n'
        "$indent pod '$podName', :path => './LocalPods/$podName'\n"
        '$indent$_podfileEnd\n';
    source = source.replaceRange(marker.start, marker.start, block);
    await file.writeAsString(source);
    return file;
  }

  Future<File> _wireAppDelegate(String podName, String classPrefix) async {
    final file = File(
      p.join(config.projectPath, 'ios', 'Runner', 'AppDelegate.swift'),
    );
    var source = await file.readAsString();
    if (source.contains(_swiftImportBegin) ||
        source.contains(_swiftInitBegin)) {
      throw StateError(
        'AppDelegate already contains an iOS product Pod marker.',
      );
    }
    // 优先复用项目已有 controller，避免重复取 rootViewController；新模板没有该
    // 变量时，则在 GeneratedPluginRegistrant 之后安全获取一次。
    // Reuse an existing controller, with a modern Flutter-template fallback.
    final controller = RegExp(
      r'let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*window\?\.rootViewController\s+as!\s+FlutterViewController',
    ).firstMatch(source);
    if (controller != null) {
      final variable = controller.group(1)!;
      source = source.replaceRange(
        controller.end,
        controller.end,
        '\n        $_swiftInitBegin\n'
        '        ${classPrefix}ProductRuntime.install(messenger: $variable.binaryMessenger)\n'
        '        $_swiftInitEnd',
      );
    } else {
      final registrant = RegExp(
        r'GeneratedPluginRegistrant\.register\(with:\s*self\)',
      ).firstMatch(source);
      if (registrant == null) {
        throw StateError(
          'Cannot find a FlutterViewController binding or '
          'GeneratedPluginRegistrant registration in AppDelegate.swift.',
        );
      }
      source = source.replaceRange(
        registrant.end,
        registrant.end,
        '\n    $_swiftInitBegin\n'
        '    if let productRuntimeController = window?.rootViewController as? FlutterViewController {\n'
        '      ${classPrefix}ProductRuntime.install(messenger: productRuntimeController.binaryMessenger)\n'
        '    }\n'
        '    $_swiftInitEnd',
      );
    }
    final imports = RegExp(
      r'^import\s+[A-Za-z_][A-Za-z0-9_]*\s*$',
      multiLine: true,
    ).allMatches(source).toList(growable: false);
    if (imports.isEmpty) {
      throw StateError('Cannot find Swift imports in AppDelegate.swift.');
    }
    final importOffset = imports.last.end;
    source = source.replaceRange(
      importOffset,
      importOffset,
      '\n$_swiftImportBegin\nimport $podName\n$_swiftImportEnd',
    );
    await file.writeAsString(source);
    return file;
  }
}

/// 只依据总 manifest 和专用 marker 恢复产品 Pod 接入。
/// Restores only manifest-declared product Pod artifacts and marked edits.
Future<int> restoreIosProductPod({
  required String projectPath,
  required Map<String, dynamic> manifest,
}) async {
  final section = manifest['iosProductPod'];
  if (section is! Map<String, dynamic> || section['enabled'] != true) return 0;

  // manifest 属于输入数据，删除前仍需将每个路径约束在预期子目录中。
  // Treat manifest paths as input and constrain every deletion to an allowlist.
  final podfile = _safeGeneratedPath(
    projectPath,
    section['podfile'],
    p.join(projectPath, 'ios'),
  );
  final appDelegate = _safeGeneratedPath(
    projectPath,
    section['appDelegate'],
    p.join(projectPath, 'ios', 'Runner'),
  );
  if (podfile != null && File(podfile).existsSync()) {
    final file = File(podfile);
    await file.writeAsString(
      _removeMarkedBlock(await file.readAsString(), _podfileBegin, _podfileEnd),
    );
  }
  if (appDelegate != null && File(appDelegate).existsSync()) {
    final file = File(appDelegate);
    var source = await file.readAsString();
    source = _removeMarkedBlock(source, _swiftImportBegin, _swiftImportEnd);
    source = _removeMarkedBlock(source, _swiftInitBegin, _swiftInitEnd);
    await file.writeAsString(source);
  }

  var removed = 0;
  final dartClient = _safeGeneratedPath(
    projectPath,
    section['dartClientFile'],
    p.join(projectPath, 'lib', 'pack', 'product_runtime'),
  );
  if (dartClient != null && File(dartClient).existsSync()) {
    await File(dartClient).delete();
    removed++;
    final parent = File(dartClient).parent;
    if (parent.existsSync() && parent.listSync().isEmpty) await parent.delete();
  }
  final podDirectory = _safeGeneratedPath(
    projectPath,
    section['podDirectory'],
    p.join(projectPath, 'ios', 'LocalPods'),
  );
  if (podDirectory != null && Directory(podDirectory).existsSync()) {
    removed += Directory(
      podDirectory,
    ).listSync(recursive: true, followLinks: false).whereType<File>().length;
    await Directory(podDirectory).delete(recursive: true);
  }
  return removed;
}

String? _safeGeneratedPath(String root, Object? relative, String allowedRoot) {
  if (relative is! String || relative.isEmpty || p.isAbsolute(relative)) {
    return null;
  }
  final resolved = p.normalize(p.absolute(root, relative));
  final allowed = p.normalize(p.absolute(allowedRoot));
  if (resolved != allowed && !p.isWithin(allowed, resolved)) {
    throw StateError('Generated path escapes its allowed directory: $relative');
  }
  return resolved;
}

String _removeMarkedBlock(String source, String begin, String end) {
  final expression = RegExp(
    '\\n?[ \\t]*${RegExp.escape(begin)}[\\s\\S]*?'
    '${RegExp.escape(end)}\\n?',
  );
  return source.replaceAll(expression, '\n');
}

int _deriveSeed(String productId, String prefix) {
  // 仅使用 digest 前 63 bit，保证 Random seed 在所有 Dart 平台上都是正整数。
  // Use 63 digest bits so the Random seed stays positive on every Dart platform.
  final bytes = sha256.convert(utf8.encode('$productId|$prefix')).bytes;
  var value = 0;
  for (final byte in bytes.take(8)) {
    value = ((value << 8) | byte) & 0x7fffffffffffffff;
  }
  return value;
}

String _shortHash(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 4).toUpperCase();

String _pascalCase(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

String _token(Random random, int length) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(
    length,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

List<String> _rotatedStates(int offset) {
  const values = ['ready', 'active', 'paused', 'completed'];
  return [
    for (var index = 0; index < values.length; index++)
      values[(index + offset) % values.length],
  ];
}

String _fallbackLayout(String theme) => switch (theme) {
  'display_rules' => 'focused',
  'configuration_profile' => 'balanced',
  _ => 'catalog',
};

List<String> _capabilities(String theme) => switch (theme) {
  'display_rules' => [
    'display_rule_evaluation',
    'state_weighting',
    'configuration_normalization',
    'resource_verification',
  ],
  'configuration_profile' => [
    'configuration_normalization',
    'profile_resolution',
    'display_rule_evaluation',
    'resource_verification',
  ],
  _ => [
    'resource_catalog',
    'resource_verification',
    'configuration_normalization',
    'display_rule_evaluation',
  ],
};

Future<File> _write(Directory directory, String name, String contents) async {
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, name));
  await file.writeAsString(contents);
  return file;
}

Future<File> _writeJson(
  Directory directory,
  String name,
  Map<String, Object> value,
) => _write(
  directory,
  name,
  '${const JsonEncoder.withIndent('  ').convert(value)}\n',
);

Future<String> _hashFiles(List<File> files) async {
  // 先排序再加入“文件名 + NUL + 内容”，消除文件系统遍历顺序造成的差异。
  // Sort and frame each payload so filesystem enumeration cannot affect the hash.
  final sorted = files.toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  final accumulator = BytesBuilder(copy: false);
  for (final file in sorted) {
    accumulator
      ..add(utf8.encode(p.basename(file.path)))
      ..addByte(0)
      ..add(await file.readAsBytes())
      ..addByte(0);
  }
  return sha256.convert(accumulator.takeBytes()).toString();
}

String _relative(String path, String root) =>
    p.posix.joinAll(p.split(p.relative(path, from: root)));

String _podspec(String podName, String classPrefix) =>
    '''
Pod::Spec.new do |s|
  s.name = '$podName'
  s.version = '1.0.0'
  s.summary = 'Generated offline product runtime for this application variant.'
  s.homepage = 'https://invalid.local/$podName'
  s.license = { :type => 'Proprietary', :text => 'Internal generated source module.' }
  s.author = { 'dart_prefix_renamer' => 'generated@invalid.local' }
  s.source = { :path => '.' }
  s.platform = :ios, '13.0'
  # 静态 Framework 让被启动代码引用的对象进入 App Mach-O，而非额外动态库。
  # Static linking folds reachable product objects into the application binary.
  s.static_framework = true
  s.requires_arc = true
  s.source_files = 'Sources/**/*.{h,m}'
  s.public_header_files = 'Sources/${classPrefix}ProductRuntime.h'
  s.resources = 'Resources/$podName.bundle'
  s.frameworks = 'Foundation'
  s.dependency 'Flutter'
end
''';

String _runtimeHeader(String prefix) =>
    '''
#import <Foundation/Foundation.h>
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface ${prefix}ProductRuntime : NSObject
+ (void)installWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger
    NS_SWIFT_NAME(install(messenger:));
+ (NSDictionary<NSString *, id> *)runtimeInfo;
@end

NS_ASSUME_NONNULL_END
''';

String _runtimeImplementation({
  required String classPrefix,
  required String productId,
  required String podName,
  required String theme,
  required int seed,
  required String channelName,
  required int revision,
}) =>
    '''
#import "${classPrefix}ProductRuntime.h"
#import "${classPrefix}ConfigurationResolver.h"
#import "${classPrefix}DisplayRuleEngine.h"
#import "${classPrefix}ResourceCatalog.h"

@implementation ${classPrefix}ProductRuntime

static FlutterMethodChannel *${classPrefix}RuntimeChannel;
static NSDictionary<NSString *, id> *${classPrefix}BootSnapshot;

+ (void)installWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger {
  // 强引用 Channel，并在启动时执行一次资源校验，使模块保持在真实运行路径中。
  // Retain the channel and verify resources once so the module is truly reachable.
  if (${classPrefix}RuntimeChannel != nil) { return; }
  ${classPrefix}ResourceCatalog *catalog = [[${classPrefix}ResourceCatalog alloc] init];
  ${classPrefix}BootSnapshot = @{
    @"resource_status": [catalog verificationResult],
    @"runtime": [self runtimeInfo]
  };
  ${classPrefix}RuntimeChannel = [FlutterMethodChannel
      methodChannelWithName:@"$channelName"
            binaryMessenger:messenger];
  [${classPrefix}RuntimeChannel setMethodCallHandler:^(FlutterMethodCall *call,
                                                        FlutterResult result) {
    if ([call.method isEqualToString:@"runtimeInfo"]) {
      result([self runtimeInfo]);
      return;
    }
    if ([call.method isEqualToString:@"resolveConfiguration"]) {
      NSDictionary *input = [call.arguments isKindOfClass:[NSDictionary class]]
          ? call.arguments : @{};
      ${classPrefix}ConfigurationResolver *resolver =
          [[${classPrefix}ConfigurationResolver alloc] init];
      result([resolver resolveConfiguration:input]);
      return;
    }
    if ([call.method isEqualToString:@"evaluateDisplayRules"]) {
      NSDictionary *input = [call.arguments isKindOfClass:[NSDictionary class]]
          ? call.arguments : @{};
      ${classPrefix}ResourceCatalog *resources =
          [[${classPrefix}ResourceCatalog alloc] init];
      ${classPrefix}DisplayRuleEngine *engine =
          [[${classPrefix}DisplayRuleEngine alloc] initWithRules:[resources productRules]];
      result([engine evaluateState:input[@"state"] score:input[@"score"]]);
      return;
    }
    if ([call.method isEqualToString:@"verifyResources"]) {
      ${classPrefix}ResourceCatalog *resources =
          [[${classPrefix}ResourceCatalog alloc] init];
      result([resources verificationResult]);
      return;
    }
    result(FlutterMethodNotImplemented);
  }];
}

+ (NSDictionary<NSString *, id> *)runtimeInfo {
  return @{
    @"product_id": @"$productId",
    @"module": @"$podName",
    @"theme": @"$theme",
    @"seed": @($seed),
    @"revision": @($revision),
    @"channel": @"$channelName"
  };
}

@end
''';

String _configurationHeader(String prefix) =>
    '''
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface ${prefix}ConfigurationResolver : NSObject
- (NSDictionary<NSString *, id> *)resolveConfiguration:(NSDictionary *)input;
@end
NS_ASSUME_NONNULL_END
''';

String _configurationImplementation(String prefix, String variationToken) =>
    '''
#import "${prefix}ConfigurationResolver.h"

@implementation ${prefix}ConfigurationResolver

- (NSDictionary<NSString *, id> *)resolveConfiguration:(NSDictionary *)input {
  NSMutableDictionary<NSString *, id> *resolved = [NSMutableDictionary dictionary];
  // 排序键名保证同一输入得到稳定结果，只保留 StandardMessageCodec 支持的值。
  // Sort keys for stable output and keep only StandardMessageCodec-safe values.
  NSArray *keys = [[input allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
    return [[a description] compare:[b description]];
  }];
  for (id key in keys) {
    if (![key isKindOfClass:[NSString class]]) { continue; }
    id value = input[key];
    if (value == nil || value == [NSNull null]) { continue; }
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSArray class]] ||
        [value isKindOfClass:[NSDictionary class]]) {
      resolved[key] = value;
    }
  }
  resolved[@"local_resolution"] = @"$variationToken";
  resolved[@"field_count"] = @(resolved.count);
  return [resolved copy];
}

@end
''';

String _displayRuleHeader(String prefix) =>
    '''
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface ${prefix}DisplayRuleEngine : NSObject
- (instancetype)initWithRules:(NSDictionary<NSString *, id> *)rules;
- (NSDictionary<NSString *, id> *)evaluateState:(nullable id)state
                                           score:(nullable id)score;
@end
NS_ASSUME_NONNULL_END
''';

String _displayRuleImplementation(String prefix, String theme) =>
    '''
#import "${prefix}DisplayRuleEngine.h"

@interface ${prefix}DisplayRuleEngine ()
@property(nonatomic, copy) NSDictionary<NSString *, id> *rules;
@end

@implementation ${prefix}DisplayRuleEngine

- (instancetype)initWithRules:(NSDictionary<NSString *, id> *)rules {
  self = [super init];
  if (self) { _rules = [rules copy] ?: @{}; }
  return self;
}

- (NSDictionary<NSString *, id> *)evaluateState:(id)state score:(id)score {
  // 状态权重和阈值来自产品 Bundle，因此不同产品可以拥有独立的离线展示策略。
  // Product-bundle weights and thresholds define an independent offline policy.
  NSString *normalizedState = [state isKindOfClass:[NSString class]]
      ? [state lowercaseString] : @"ready";
  NSInteger numericScore = [score respondsToSelector:@selector(integerValue)]
      ? [score integerValue] : 0;
  NSDictionary *weights = [self.rules[@"state_weights"] isKindOfClass:[NSDictionary class]]
      ? self.rules[@"state_weights"] : @{};
  NSInteger weightedScore = numericScore + [weights[normalizedState] integerValue];
  NSInteger minimumScore = [self.rules[@"minimum_score"] integerValue];
  NSArray *preferred = [self.rules[@"preferred_states"] isKindOfClass:[NSArray class]]
      ? self.rules[@"preferred_states"] : @[];
  BOOL preferredState = [preferred containsObject:normalizedState];
  return @{
    @"visible": @(preferredState && weightedScore >= minimumScore),
    @"state": normalizedState,
    @"weighted_score": @(weightedScore),
    @"layout": self.rules[@"fallback_layout"] ?: @"balanced",
    @"policy": @"$theme"
  };
}

@end
''';

String _resourceCatalogHeader(String prefix) =>
    '''
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface ${prefix}ResourceCatalog : NSObject
- (NSDictionary<NSString *, id> *)productRules;
- (NSDictionary<NSString *, id> *)verificationResult;
@end
NS_ASSUME_NONNULL_END
''';

String _resourceCatalogImplementation(String prefix, String podName) =>
    '''
#import "${prefix}ResourceCatalog.h"

@implementation ${prefix}ResourceCatalog

- (NSBundle *)resourceBundle {
  // 静态 Pod 的类可能位于主 Bundle；先查宿主 Bundle，再回退到 mainBundle。
  // Static Pod classes may live in the host bundle, with mainBundle as fallback.
  NSBundle *host = [NSBundle bundleForClass:[self class]];
  NSURL *url = [host URLForResource:@"$podName" withExtension:@"bundle"];
  if (url == nil) {
    url = [[NSBundle mainBundle] URLForResource:@"$podName" withExtension:@"bundle"];
  }
  return url == nil ? host : [NSBundle bundleWithURL:url];
}

- (NSDictionary<NSString *, id> *)readJSON:(NSString *)name {
  NSURL *url = [[self resourceBundle] URLForResource:name withExtension:@"json"];
  NSData *data = url == nil ? nil : [NSData dataWithContentsOfURL:url];
  if (data == nil) { return @{}; }
  id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

- (NSDictionary<NSString *, id> *)productRules {
  return [self readJSON:@"product_rules"];
}

- (NSDictionary<NSString *, id> *)verificationResult {
  NSDictionary *catalog = [self readJSON:@"resource_catalog"];
  NSArray *required = [catalog[@"required_files"] isKindOfClass:[NSArray class]]
      ? catalog[@"required_files"] : @[];
  NSMutableArray<NSString *> *missing = [NSMutableArray array];
  for (id entry in required) {
    if (![entry isKindOfClass:[NSString class]]) { continue; }
    NSString *extension = [entry pathExtension];
    NSString *name = [entry stringByDeletingPathExtension];
    if ([[self resourceBundle] URLForResource:name withExtension:extension] == nil) {
      [missing addObject:entry];
    }
  }
  return @{
    @"valid": @(catalog.count > 0 && missing.count == 0),
    @"required_count": @(required.count),
    @"missing": [missing copy]
  };
}

@end
''';

String _dartClient({required String className, required String channelName}) =>
    '''
// Generated by dart_prefix_renamer. Do not edit.
// 该客户端与原生生成器共享同一个确定性 Channel 名称。
// This client shares the generator's deterministic native channel name.
import 'package:flutter/services.dart';

final class $className {
  const $className();

  static const MethodChannel _channel = MethodChannel('$channelName');

  Future<Map<String, Object?>> runtimeInfo() async =>
      _map(await _channel.invokeMapMethod<String, Object?>('runtimeInfo'));

  Future<Map<String, Object?>> resolveConfiguration(
    Map<String, Object?> input,
  ) async => _map(
    await _channel.invokeMapMethod<String, Object?>(
      'resolveConfiguration',
      input,
    ),
  );

  Future<Map<String, Object?>> evaluateDisplayRules({
    required String state,
    required int score,
  }) async => _map(
    await _channel.invokeMapMethod<String, Object?>(
      'evaluateDisplayRules',
      <String, Object?>{'state': state, 'score': score},
    ),
  );

  Future<Map<String, Object?>> verifyResources() async =>
      _map(await _channel.invokeMapMethod<String, Object?>('verifyResources'));

  static Map<String, Object?> _map(Map<String, Object?>? value) =>
      Map<String, Object?>.unmodifiable(value ?? const <String, Object?>{});
}
''';
