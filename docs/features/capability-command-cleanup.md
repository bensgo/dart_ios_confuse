# Dart 与 iOS Pod 指令清理清单

## 规范后的三类入口

| 类别 | 保留的规范入口 | 不属于该入口的配置 |
|---|---|---|
| Dart 自动能力 | `--scan-dart-capabilities`、`--auto-dart-capabilities`、`--dart-*` | iOS Pod、Product Profile、Native manifest |
| iOS 自定义源码 Pod | `--ios-custom-pod`、`--ios-custom-pod-id`、`--ios-custom-pod-theme`、`--ios-custom-pod-seed` | 第三方候选池、Dart/Native manifest |
| iOS 第三方 SDK Pod | `--prepare-ios-third-party-sdk-pods`、`--ios-third-party-sdk-*` | `dart_capabilities.yaml`、`native_capabilities.yaml`、`product_profile.yaml`、`--target` |

## 已从新流程移除的多余要求

- 第三方 SDK Pod 不再要求 `--target`。
- 第三方 SDK Pod 不再要求 `product_profile.yaml`；产品 ID 直接使用 `--ios-third-party-sdk-product-id`。
- 第三方 SDK Pod 不再读取 `dart_capabilities.yaml` 或 `native_capabilities.yaml`。
- 第三方 SDK Pod 的 seed、配置路径和报告参数全部使用 `--ios-third-party-sdk-*` 前缀，不再与 Dart/Native 报告混名。

## 下一兼容窗口可删除的旧指令

以下指令已有明确替代入口，但当前仍作为兼容层保留。确认 CI、私有脚本和调用方均已迁移后可以删除：

| 旧指令 | 替代项 | 删除前检查 |
|---|---|---|
| `--ios-product-pod` | `--ios-custom-pod` | 模式一、模式二脚本均不再引用旧名 |
| `--ios-product-id` | `--ios-custom-pod-id` | 同上 |
| `--ios-product-theme` | `--ios-custom-pod-theme` | 同上 |
| `--ios-product-pod-seed` | `--ios-custom-pod-seed` | 同上 |
| `--prepare-capabilities` | 三条独立入口 | Native/Pigeon 若仍需要，必须先获得独立入口 |
| `--capabilities` | 三条独立入口 | CI release gate 不再使用旧混合流水线 |
| `--product-profile`、`--dart-capabilities`、`--native-capabilities`、`--dependency-manifest`、`--library-pool`、`--capability-report-dir`、`--capability-seed` | 各领域前缀参数 | 不再有旧混合入口调用 |

## 可删除代码候选

下面代码只服务旧混合流水线，不能在同一提交中直接删除；应在 Native/Pigeon 是否继续保留确定后处理：

- `lib/src/capabilities/capability_pipeline.dart`：旧 Dart + Native/Pigeon + 第三方 Pod 总编排。
- `CapabilityOptions` 及 `RenameConfig.capabilities`：复制/事务模式中的旧混合开关。
- `DartCapabilityPlanner`、旧 manifest 驱动的 generator/validator：Dart 百分比自动能力已使用独立入口，但需先核对 catalog/scanner 的共享引用。
- `ProductProfile`、`NativeCapabilityGenerator`、`PigeonBridgeGenerator`：当前只由旧混合流水线和专项测试使用；是否删除取决于 Native/Pigeon 功能是否继续作为第四类能力存在。
- `CapabilityReport` 中 Dart/Native/Dependency 聚合结构：第三方 SDK 独立报告已不需要聚合字段，但正式 Release Gate 仍引用，迁移 CI 后才能拆除。

另外，`--dart-strings-build`、`--ios-assets-build` 及对应专项 restore 已被统一事务构建替代，`--junk-code` 也已标记为 legacy/non-compliant。它们与本次三类能力解耦无关，可作为下一批独立清理任务，不能混在本次改名中直接删除。

## 删除门禁

删除任何兼容指令或代码前必须满足：仓库内 `rg` 无调用、README/CI/私有脚本完成迁移、完整测试通过，并至少保留一个版本的废弃提示。这样可以避免把“命名清理”变成不可预期的构建中断。
