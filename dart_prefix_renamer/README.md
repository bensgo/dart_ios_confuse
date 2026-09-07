# Dart Prefix Renamer

`dart_prefix_renamer` 在隔离副本中处理 Flutter iOS 工程：重命名 Dart 源码和资源、处理 iOS 资源与字符串、生成 iOS 差异化代码，并提供 Dart 自动能力、真实 Dart Capability 接线、iOS 自定义源码 Pod 和 iOS 第三方 SDK Pod 等独立功能。

完整的模式一、模式二命令见 [USAGE.md](USAGE.md)。本文件只说明功能、参数和单项使用。

## 初始化

```bash
cd /Users/ahs/Documents/flutter_ios_混淆/dart_prefix_renamer
fvm dart pub get
fvm dart analyze
fvm dart test -r expanded
```

需要 FVM；目标工程必须能运行 `fvm flutter pub get`。资源容器与字符串加密分别要求工程已有 `EncryptedAssetBundle` 与 `StringCipherRuntime`。

## 模式边界

| 模式 | 入口 | 结果 |
|---|---|---|
| 模式一 | 默认复制模式，必须传 `--output` | 保留处理后的源码副本 |
| 模式二 | `--transactional-build` | 临时副本构建，只复制指定产物回原工程 |

两种模式都不会直接修改 `--project` 原始源码。模式一的 `--output` 必须不存在；`--target` 是逗号分隔的项目相对目录，不支持通配符。

## 功能分类

| 功能 | 用途 | 规范入口 |
|---|---|---|
| 基础重命名 | Dart 文件、Class、引用、目录和 Flutter asset 重写 | 默认模式参数 |
| iOS 资源/字符串 | 图片、动画、音频容器化与标记字符串 AES 加密 | `--containerize-ios-assets`、`--encrypt-dart-strings` |
| iOS MethodChannel | 指定真实 Channel 改名与 inert Channel | `--ios-method-channel-diff` |
| Dart 自动能力 | 扫描、确定性选择并插入不改变返回值的调用 | `--scan-dart-capabilities`、`--auto-dart-capabilities` |
| 真实 Dart Capability 接线 | 对显式业务锚点生成定义并校验“定义—调用—effect”可达性 | `--prepare-dart-capabilities` |
| iOS 自定义源码 Pod | 生成离线本地 Pod、资源和 Flutter 客户端 | `--ios-custom-pod` |
| iOS 第三方 SDK Pod | 审核池中确定性选择 1–10 个 CocoaPods 并安全 probe | `--prepare-ios-third-party-sdk-pods` |

## 参数参考

### 基础复制与重命名

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `--project`, `-p` | 必填 | 原始 Flutter/Pub Workspace 根目录 |
| `--output`, `-o` | 模式一必填 | 不存在的新输出目录 |
| `--target`, `-t` | 必填 | 要处理的相对目录，逗号分隔 |
| `--prefix` | 必填 | 小写 ASCII 前缀 |
| `--pub-get` / `--no-pub-get` | 开启 | 是否在副本执行 `fvm flutter pub get` |
| `--verify` / `--no-verify` | 开启 | 是否比较变换前后的 Analyzer error |
| `--assets` / `--no-assets` | 开启 | 重命名 Flutter assets 并重写静态路径 |
| `--rename-directories` | 关闭 | 给目标 `lib` 下目录加前缀 |
| `--reset-metadata` | 关闭 | 重置副本元数据 |
| `--junk-code` | 关闭 | legacy/non-compliant，不属于能力证据 |

### iOS 资源、字符串与 Channel

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `--containerize-ios-assets` | 关闭 | 资源 AES 容器化并移除副本明文 |
| `--asset-dir` | `assets/images` | 图片目录；可重复传入 |
| `--animation-asset-dir` | 空 | SVGA/Lottie 动画目录；支持 `.svga`、`.json`，可重复传入 |
| `--audio-asset-dir` | 空 | 音频目录；支持 `.mp3`、`.m4a`、`.mp4`、`.aac`、`.caf`、`.wav`、`.ogg`、`.flac`，可重复传入 |
| `--container-dir` | `assets/images` | 容器输出目录 |
| `--runtime-config` | 工程默认路径 | 资源容器运行时配置 |
| `--encrypt-dart-strings` | 关闭 | 加密显式标记的静态字符串 |
| `--string-runtime-config` | 工程默认路径 | 字符串解密运行时配置 |
| `--decrypt-method` | `decryptedPS` | 加密标记方法名 |
| `--ios-method-channel-diff` | 关闭 | 启用 iOS MethodChannel 差异化 |
| `--ios-method-channel-include` | 空 | 允许改名的静态真实 Channel；可重复 |
| `--ios-method-channel-exclude` | 空 | 禁止改名的 Channel；优先级更高 |
| `--ios-dummy-method-channel-count` | `12` | Dart/iOS 成对 inert Channel 数量 |
| `--ios-method-channel-seed` | 随机 | 固定 Channel 名称的可选 seed |
| `--ios-method-channel-entrypoint` | `lib/main.dart` | 初始化生成 Channel 的入口；可重复 |

三类目录写入同一套随机 AES 容器和索引，但扩展名严格按入口过滤。重复目录或重叠目录中的同一文件只处理一次。`EncryptedAssetBundle.load()` 返回解密后的原始 bytes；图片可通过 `DefaultAssetBundle` 使用，SVGA 应将 bytes 交给 `decodeFromBuffer`，Lottie 应使用内存 bytes/composition 入口，音频播放器应使用 bytes/stream source。仍直接调用 `SVGAParser.decodeFromAssets`、`Lottie.asset` 或 `AudioSource.asset` 的代码不会自动改写，启用对应目录前必须先完成这些运行时接线。

### Dart 自动能力

| 参数 | 说明 |
|---|---|
| `--scan-dart-capabilities` | 只扫描，生成建议 JSON |
| `--auto-dart-capabilities` | 确定性选择并插入调用 |
| `--dart-differentiation-percent` | 自动选择百分比 |
| `--dart-capability-seed` | 选择 seed |
| `--dart-capability-suggestions-out` | 建议 JSON 输出路径 |
| `--dart-capability-selection-out` | selection JSON 输出路径 |
| `--dart-capability-selection` | 复用 selection，跳过重新随机 |

```bash
fvm dart run bin/dart_prefix_renamer.dart \
  --auto-dart-capabilities \
  --project=/absolute/path/to/output-copy \
  --target=lib,packages/aixi_foundation/lib \
  --dart-differentiation-percent=50 \
  --dart-capability-seed=0
```

只处理有块状实例方法的 Class；调用不消费结果、不修改原方法返回值。`junk_code` 目录会被排除。

### 真实 Dart Capability 接线

这个功能用于少量、明确的业务级 Capability，与 Dart 自动能力不同：自动能力按百分比产生低风险差异，不消费调用结果；真实接线必须让结果参与返回值、分支、字段或 UI 语义，并记录可验证的 `effect`。

先在模式一输出副本中手工连接生产方法，再在 `config/dart_capabilities.yaml` 为每个连接明确声明 `class`、`library`、`capability`、`call_site.method`、`call_site.anchor` 和 `effect`。命令不会自动向业务方法插入调用；未找到已存在的精确 Capability 调用时会失败关闭。

独立入口只读取 `config/product_profile.yaml` 和 `config/dart_capabilities.yaml`：前者用于产品身份与确定性计划，后者定义业务锚点。`config/native_capabilities.yaml`、`config/dependencies.yaml` 和 `config/ios_library_pool.yaml` 不是 Dart 接线的依赖；它们只在 Native/Pigeon 或 iOS 第三方 SDK Pod 流程中需要。输出副本完成重命名后，需确保 manifest 中的路径使用实际重命名后的路径。

```bash
fvm dart run bin/dart_prefix_renamer.dart \
  --prepare-dart-capabilities \
  --project=/absolute/path/to/output-copy \
  --target=lib \
  --dart-capability-seed=0
```

成功时会生成缺失的 Capability 定义，并在 `reports/` 写入 `dart-capability-plan.json` 和 `dart-capability-report.json`。验收重点是 `Capabilities ready` 与 `Dart reachable` 与声明数一致、`failed=0` 且 `Passed=true`。每个产品输出副本独立执行，不修改原始 `--project` 源码。如需 Dart、Native/Pigeon 和依赖的联合 Release 校验，仍使用 `--prepare-capabilities`。

### iOS 自定义源码 Pod

| 参数 | 说明 |
|---|---|
| `--ios-custom-pod` | 启用本地源码 Pod |
| `--ios-custom-pod-id` | 必填；小写字母开头，仅小写字母、数字和下划线 |
| `--ios-custom-pod-theme` | `resource_catalog`、`display_rules` 或 `configuration_profile` |
| `--ios-custom-pod-seed` | 可选确定性 seed |

Pod 只依赖 Flutter 和 Foundation，提供本地配置规范化、展示规则与资源校验；不使用网络、权限、设备标识、持久化或第三方 SDK。会写入 `ios/LocalPods/`、Podfile/AppDelegate marker 和 Dart 客户端。旧 `--ios-product-*` 是隐藏兼容别名，新脚本不要使用。

### iOS 第三方 SDK Pod

该功能只读取：

```text
config/dependencies.yaml
config/ios_library_pool.yaml
```

不读取 Dart/Native manifest、Product Profile，也不要求 `--target`。`dependencies.yaml` 必须使用 schema v2，固定 `deterministic_random`、`count: 1–10`、`startup_background_once`。当前审核池有 15 个候选；Kingfisher 和 SDWebImage 属于同一图片冲突组，不能同时选择。

| 参数 | 说明 |
|---|---|
| `--prepare-ios-third-party-sdk-pods` | 生成、接线并执行 `pod install` |
| `--project` | 模式一输出副本 |
| `--ios-third-party-sdk-product-id` | 必填产品 ID |
| `--ios-third-party-sdk-dependencies` | 默认 `config/dependencies.yaml` |
| `--ios-third-party-sdk-library-pool` | 默认 `config/ios_library_pool.yaml` |
| `--ios-third-party-sdk-report-dir` | 默认 `reports/ios-third-party-sdk-pods` |
| `--ios-third-party-sdk-seed` | 默认 `0` |
| `--verify-ios-third-party-sdk-pods` | 对已有 IPA 做 linkage 验证 |
| `--ios-third-party-sdk-release-artifact` | 验证时必填 IPA 路径 |

probe 在启动后 utility 队列只执行一次，仅保存内存摘要；禁止网络、权限、持久化、UI 变化、Flutter 回传、日志和分析 SDK。验收值：`selected=declared=locked=called=linked=<count>`。

### 模式二、恢复与兼容

| 参数 | 说明 |
|---|---|
| `--transactional-build` | 模式二入口 |
| `--artifact-dir` | 模式二复制回原工程的相对产物目录；可重复 |
| `--` | 分隔工具参数和实际构建命令 |
| `--restore --project=<output>` | 恢复模式一记录的重命名和生成物 |
| `--bind-ipa --project=<output> --ipa=<ipa>` | 向模式一 manifest 绑定最终 IPA 身份 |

第三方 SDK Pod 当前要求保留的模式一输出副本，不能加入模式二临时构建。`--prepare-capabilities` 是真实 Dart Capability 与 Native/Pigeon 联合校验入口，需显式 manifest 和已存在的业务调用；`--capabilities` 及其旧 manifest 参数仍属兼容路径，删除条件见 [清理清单](../docs/features/capability-command-cleanup.md)。

## 安全与边界

- 只重命名 Class，不重命名 enum、mixin、extension、typedef、方法、字段或变量。
- 动态字符串、反射、服务端下发名称、动态 Asset 路径与动态 MethodChannel 名称不会自动改写。
- 图片和字符串密钥、IV 与解密代码随 IPA 分发，只提升静态提取成本，不能保护服务端密钥。
- 模式一包含图片容器或永久字符串加密时，应从原始工程重新生成副本，不应依赖 restore 还原明文。
- 输出副本、IPA、dSYM、混淆 map、私有 reports 不应提交 Git。
