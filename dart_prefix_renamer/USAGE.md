# 完整使用：模式一与模式二

本文件只提供完整流程；功能和参数见 [README.md](README.md)。以下命令面向当前环信工程，运行前确认 FVM 可用。

也可以直接运行仓库脚本完成下面全部步骤：

```bash
/Users/ahs/Documents/flutter_ios_混淆/scripts/run_mode1_product_abc.sh
```

脚本默认使用 `product_abc`、seed `0`、7 个第三方库，并拒绝覆盖已有输出目录。会自动安装 `fluwx` Pod 安装脚本所需的用户级 Ruby `plist` gem。可通过 `MODE1_PREFIX` 指定本次小写混淆前缀；也可通过 `HUANXIN_PROJECT`、`MODE1_OUTPUT_DIR`、`IOS_THIRD_PARTY_PRODUCT_ID`、`IPA_OUTPUT_DIR` 和 `SYMBOL_OUTPUT_DIR` 覆盖路径或产品 ID。

若脚本在第三方 Pod、构建或 IPA 阶段失败，保留的输出副本可用以下命令继续；该选项跳过源码复制和 Dart 自动能力步骤：

```bash
/Users/ahs/Documents/flutter_ios_混淆/scripts/run_mode1_product_abc.sh --resume
```

## 模式一：保留源码副本

适合需要继续接入 iOS 第三方 SDK Pod、检查生成源码或手动构建的场景。输出目录必须不存在，原工程不会被修改。

### 1. 生成副本、基础差异化与自定义 Pod

```bash
cd /Users/ahs/Documents/flutter_ios_混淆/dart_prefix_renamer

fvm dart run bin/dart_prefix_renamer.dart \
  --project="/Users/ahs/Documents/work/code/huanxin" \
  --output="/Users/ahs/Documents/flutter_ios_混淆/huanxin_mode1_product_abc_output" \
  --target="lib,packages/aixi_event_logger/lib,packages/aixi_foundation/lib,packages/aixi_design_system/lib,packages/aixi_ui/lib,packages/aixi_network/lib,packages/aixi_platform_bridge/lib,packages/aixi_logging/lib,packages/aixi_media/lib,packages/aixi_audio/lib,packages/aixi_im/lib,packages/aixi_rtc/lib,packages/aixi_gift/lib,packages/aixi_app_config/lib,packages/aixi_feedback/lib" \
  --prefix="deisoekdi" \
  --assets \
  --rename-directories \
  --junk-code \
  --reset-metadata \
  --containerize-ios-assets \
  --asset-dir="assets/images" \
  --asset-dir="assets/icons" \
  --animation-asset-dir="assets/animation" \
  --audio-asset-dir="assets/audio" \
  --container-dir="assets/images" \
  --runtime-config="lib/app_tools/asset_container/asset_container_config.g.dart" \
  --encrypt-dart-strings \
  --string-runtime-config="packages/aixi_app_config/lib/src/string_cipher_config.g.dart" \
  --decrypt-method="decryptedPS" \
  --ios-method-channel-diff \
  --ios-method-channel-include="com.aixi.app/native" \
  --ios-dummy-method-channel-count=12 \
  --ios-method-channel-seed=20260818 \
  --ios-method-channel-entrypoint="lib/main.dart" \
  --ios-custom-pod \
  --ios-custom-pod-id="product_abc" \
  --ios-custom-pod-theme="resource_catalog" \
  --ios-custom-pod-seed=0
```

### 2. 插入 Dart 自动能力

```bash
fvm dart run bin/dart_prefix_renamer.dart \
  --auto-dart-capabilities \
  --project="/Users/ahs/Documents/flutter_ios_混淆/huanxin_mode1_product_abc_output" \
  --target="lib,packages/aixi_foundation/lib" \
  --dart-differentiation-percent=50 \
  --dart-capability-seed=0
```

### 3. 可选：验证真实 Dart Capability 接线

仅当输出副本已在生产方法中连接了 Capability 调用，且已完整配置五份 `config/*.yaml` manifest 时执行。它生成缺失定义、验证可达性并写入 `reports/`；不会代替、也不会自动创建业务调用。如果未定义真实锚点，跳过此步骤即可。

```bash
fvm dart run bin/dart_prefix_renamer.dart \
  --prepare-dart-capabilities \
  --project="/Users/ahs/Documents/flutter_ios_混淆/huanxin_mode1_product_abc_output" \
  --target="lib" \
  --dart-capability-seed=0
```

期待：`Capabilities ready` 与 `Dart reachable` 与声明的接线数一致，`Passed=true`。具体配置合约和安全边界见 [README.md](README.md#真实-dart-capability-接线)。

### 4. 接入 iOS 第三方 SDK Pod

当前 `config/dependencies.yaml` 设置 `count: 7`。`product_abc + seed 0` 选择 SwiftSoup、Swinject、DifferenceKit、SwiftyJSON、Kingfisher、GRDB.swift、PromiseKit；命令会生成本地 ThirdPartyKit、更新 Podfile/AppDelegate 并执行 `pod install`。如需其他数量，仅把该配置中的 `count` 改为 1–10 的整数后，从原始工程重新生成模式一副本。

```bash
fvm dart run bin/dart_prefix_renamer.dart \
  --prepare-ios-third-party-sdk-pods \
  --project="/Users/ahs/Documents/flutter_ios_混淆/huanxin_mode1_product_abc_output" \
  --ios-third-party-sdk-product-id="product_abc" \
  --ios-third-party-sdk-dependencies="config/dependencies.yaml" \
  --ios-third-party-sdk-library-pool="config/ios_library_pool.yaml" \
  --ios-third-party-sdk-report-dir="reports/ios-third-party-sdk-pods" \
  --ios-third-party-sdk-seed=0
```

### 5. 无签名构建和第三方 SDK 验证

```bash
cd /Users/ahs/Documents/flutter_ios_混淆/huanxin_mode1_product_abc_output

fvm flutter build ios \
  --release \
  --no-codesign \
  --obfuscate \
  --split-debug-info="/Users/ahs/Documents/flutter_ios_混淆/symbols/product_abc"
```

打包符合 IPA 目录结构的 unsigned IPA：

```bash
IPA_STAGE="$(mktemp -d)"
mkdir -p "$IPA_STAGE/Payload"
mkdir -p "/Users/ahs/Documents/flutter_ios_混淆/ipa/product_abc"
ditto \
  "/Users/ahs/Documents/flutter_ios_混淆/huanxin_mode1_product_abc_output/build/ios/iphoneos/Runner.app" \
  "$IPA_STAGE/Payload/Runner.app"
ditto -c -k --sequesterRsrc --keepParent \
  "$IPA_STAGE/Payload" \
  "/Users/ahs/Documents/flutter_ios_混淆/ipa/product_abc/product_abc_unsigned.ipa"
rm -rf "$IPA_STAGE"
```

再执行第三方 SDK linkage 验证：

```bash
cd /Users/ahs/Documents/flutter_ios_混淆/dart_prefix_renamer

fvm dart run bin/dart_prefix_renamer.dart \
  --prepare-ios-third-party-sdk-pods \
  --verify-ios-third-party-sdk-pods \
  --project="/Users/ahs/Documents/flutter_ios_混淆/huanxin_mode1_product_abc_output" \
  --ios-third-party-sdk-product-id="product_abc" \
  --ios-third-party-sdk-dependencies="config/dependencies.yaml" \
  --ios-third-party-sdk-library-pool="config/ios_library_pool.yaml" \
  --ios-third-party-sdk-report-dir="reports/ios-third-party-sdk-pods" \
  --ios-third-party-sdk-seed=0 \
  --ios-third-party-sdk-release-artifact="/Users/ahs/Documents/flutter_ios_混淆/ipa/product_abc/product_abc_unsigned.ipa"
```

预期：`Selected=Declared=Locked=Called=Linked=7`，`Passed=true`。

## 模式二：临时副本构建后自动清理

适合只需要 IPA/archive/reports。原工程源码不会被修改；临时副本会在成功、失败或异常后删除。第三方 SDK Pod 当前不支持模式二，需使用模式一。

```bash
cd /Users/ahs/Documents/flutter_ios_混淆/dart_prefix_renamer

fvm dart run bin/dart_prefix_renamer.dart \
  --transactional-build \
  --project="/Users/ahs/Documents/work/code/huanxin" \
  --target="lib,packages/aixi_event_logger/lib,packages/aixi_foundation/lib,packages/aixi_design_system/lib,packages/aixi_ui/lib,packages/aixi_network/lib,packages/aixi_platform_bridge/lib,packages/aixi_logging/lib,packages/aixi_media/lib,packages/aixi_audio/lib,packages/aixi_im/lib,packages/aixi_rtc/lib,packages/aixi_gift/lib,packages/aixi_app_config/lib,packages/aixi_feedback/lib" \
  --prefix="deisoekdi" \
  --assets \
  --rename-directories \
  --junk-code \
  --reset-metadata \
  --containerize-ios-assets \
  --asset-dir="assets/images" \
  --asset-dir="assets/icons" \
  --animation-asset-dir="assets/animation" \
  --audio-asset-dir="assets/audio" \
  --container-dir="assets/images" \
  --runtime-config="lib/app_tools/asset_container/asset_container_config.g.dart" \
  --encrypt-dart-strings \
  --string-runtime-config="packages/aixi_app_config/lib/src/string_cipher_config.g.dart" \
  --decrypt-method="decryptedPS" \
  --ios-method-channel-diff \
  --ios-method-channel-include="com.aixi.app/native" \
  --ios-dummy-method-channel-count=12 \
  --ios-method-channel-seed=20260818 \
  --ios-method-channel-entrypoint="lib/main.dart" \
  --ios-custom-pod \
  --ios-custom-pod-id="product_abc" \
  --ios-custom-pod-theme="resource_catalog" \
  --ios-custom-pod-seed=0 \
  --auto-dart-capabilities \
  --dart-differentiation-percent=50 \
  --dart-capability-seed=0 \
  --artifact-dir="build/ios/ipa" \
  --artifact-dir="build/ios/archive" \
  --artifact-dir="reports" \
  -- \
  fvm flutter build ipa \
    --release \
    --obfuscate \
    --split-debug-info="/Users/ahs/Documents/flutter_ios_混淆/symbols/product_abc"
```

构建完成后，IPA/archive 会复制到原工程对应的 `build/ios/ipa`、`build/ios/archive`，reports 会复制到原工程 `reports/`。正式发布时按签名环境补齐签名配置；无签名验收请使用模式一的 `--no-codesign`。
