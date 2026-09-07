# iOS 自定义源码 Pod

## 目标

为某个产品变体生成一个独立、确定性、仅离线运行的本地 iOS Pod。它用于提供产品专属的配置规范化、展示规则计算和资源目录校验，不引入第三方 SDK，也不修改原始工程。

该功能属于 `dart_prefix_renamer` 的基础可选能力，**不依赖** `product_profile.yaml`、Dart/Native capability manifest 或第三方库候选池。

## 能力与边界

- 支持三个主题：`resource_catalog`、`display_rules`、`configuration_profile`。
- 生成 Objective-C 源码、本地 JSON 资源、podspec 和 Flutter MethodChannel Dart 客户端。
- 在 AppDelegate 启动阶段注册专属 MethodChannel，并执行一次本地资源完整性校验。
- Dart 客户端提供 `runtimeInfo`、`resolveConfiguration`、`evaluateDisplayRules`、`verifyResources` 四个 API；只有业务代码主动调用时才会消费对应结果。
- 仅依赖 `Flutter` 与 `Foundation`；不联网、不申请权限、不读取设备标识、不创建后台任务、不采集数据、不依赖第三方库。
- 相同的 `productId + prefix + theme + seed` 产生稳定的模块名、Channel 名称、资源和哈希。

## 前置条件

1. 在模式一输出副本或模式二临时副本中运行；不能直接修改唯一原始工程。
2. 工程必须有 `ios/Podfile` 与 `ios/Runner/AppDelegate.swift`。
3. 产品 ID 必须以小写字母开头，只包含小写字母、数字和下划线。

## 使用方式

模式一示例。`--output` 必须是不存在的新目录：

```bash
cd /Users/ahs/Documents/flutter_ios_混淆/dart_prefix_renamer

fvm dart run bin/dart_prefix_renamer.dart \
  --project=/absolute/path/to/huanxin \
  --output=/absolute/path/to/huanxin_product_output \
  --target=lib,packages/aixi_platform_bridge/lib \
  --prefix=abc \
  --ios-custom-pod \
  --ios-custom-pod-id=product_abc \
  --ios-custom-pod-theme=resource_catalog \
  --ios-custom-pod-seed=0
```

省略 `--ios-custom-pod-theme` 时，工具会按产品身份稳定选择一个主题；省略 seed 时，工具会从 product id 与 prefix 稳定派生 seed。

## 生成与接线结果

```text
ios/LocalPods/<ProductPodName>/
├── <ProductPodName>.podspec
├── Sources/                         # Runtime、配置、展示规则、资源目录实现
├── Resources/<ProductPodName>.bundle/
│   ├── product_rules.json
│   └── resource_catalog.json
└── product_pod_manifest.json

lib/pack/product_runtime/
└── <prefix>_product_runtime.dart
```

同时工具会：

1. 在 Podfile 的 Runner target 中添加本地 Pod 声明和专用 marker。
2. 在 AppDelegate 导入 Pod，并用现有 `FlutterViewController` 的 BinaryMessenger 注册 Runtime。
3. 在总 manifest 中记录文件、主题、seed、Channel 和 SHA-256。

随后按正常 Flutter iOS 构建流程执行 `pod install`/构建即可。

## 验证与恢复

- 生成阶段会拒绝缺少 iOS Podfile/AppDelegate、非法产品 ID、非法主题或已有同类 marker 的工程。
- `product_pod_manifest.json` 记录生成内容哈希和离线约束。
- 模式一可运行 `--restore`：它只删除 manifest 中声明的本地 Pod、Dart 客户端，以及 Podfile/AppDelegate 的成对 marker；不会宽泛删除用户代码。
- 图片容器或永久字符串加密启用时，应从原始工程重新生成输出副本，而不是依赖 restore 还原明文。

## 当前验证状态

工具层已有确定性、不同产品差异、接线、约束声明和 restore 测试。该功能不等价于 manifest Native Capability，也不代表自动产生业务 UI 或业务状态变化。
