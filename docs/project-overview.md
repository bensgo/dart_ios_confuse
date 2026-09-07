# 工程总览

## 目录

- `dart_prefix_renamer/`：Flutter/Dart 源码、资源、元数据、字符串和 iOS 差异化处理工具。
- `obfuscator/`：Dart 混淆辅助工具。
- `tbr-shell-cladding/`：业务相邻的壳层与打包代码；当前目录可能包含用户已有改动。
- `symbols/`：构建符号文件目录，不应提交新的敏感符号产物。
- `task/`：需求和工程方案资料。

## 当前实现状态（2026-08-25 盘点）

- `dart_prefix_renamer` 已具备两种隔离运行模式、Dart/目录/资源重命名、iOS 图片容器、标记字符串加密、iOS MethodChannel 差异化、确定性产品源码 Pod、Dart 百分比能力插入，以及可选的 manifest Native/第三方库能力流水线；第三方 SDK Pod 已有 15 个审核候选，可确定性选择 1–10 个。
- Dart 自动能力、iOS 自定义源码 Pod、iOS 第三方 SDK Pod 已建立三套规范命名；第三方 SDK Pod 独立入口只读取依赖清单与候选池。旧混合 capability 参数和 `ios-product-*` 参数处于兼容期，不用于新脚本。
- 可选 manifest 流水线需要五份产品配置，只用于 Pigeon Native Capability、随机第三方 CocoaPods 和 Release Inspector；它不是模式一/模式二基础重命名与产品 Pod 的前置条件。
- 根仓库忽略 `huanxin_*_output` 类输出；其中可包含私有源码副本、Pods、IPA、dSYM 和报告。盘点时这些输出目录不存在，历史构建结果仅保留在工作进度与日报中。
- 原始环信工程 `/Users/ahs/Documents/work/code/huanxin` 的 capability 配置和 reports 属于源码所有者的未提交工作；本工作区不代为提交或清理。

## 当前未完成的外部验收

- GitHub Actions 的 iOS Release Gate 仍需配置 `ENABLE_IOS_RELEASE_GATE`、`RELEASE_FIXTURE_ROOT`、`RELEASE_TARGETS`，并提供两份私有 Product Profile、签名凭据和可在 CI 使用的 Release fixture。
- 完成上述输入后，需实际运行两份 Profile 的签名 Release 构建，并保留两个 `release-report.json` 作为最终差异化证据。无签名本机构建可以验证编译与 IPA 结构，但不替代该门禁。
- 环信当前 `config/dart_capabilities.yaml` 的 `rules` 与 `integrations` 为空：这是避免虚构生产调用的正确失败关闭选择，但意味着尚未把 10 个 Dart Capability 接入环信真实业务路径，不能满足详细设计的最终全量 Capability 定义。
- 当前 `fvm dart format --output=none --set-exit-if-changed bin lib test` 已通过；工具完整测试为 82 项通过，Analyzer 无 error/warning（保留 39 条 info）。

## 必读资料

执行 `dart_prefix_renamer` 前必须阅读其 [README](../dart_prefix_renamer/README.md)。其中定义复制源码模式、事务构建模式、参数语义、验证和产物边界；本文件不重复解释命令细节。

Release 差异化能力的开发顺序、接口与验收标准见 [详细工作计划目录](work-plans/README.md)。

## 验证入口

```bash
cd dart_prefix_renamer
fvm dart pub get
fvm dart analyze
fvm dart test -r expanded
```

当前基线：`fvm dart test -r expanded` 为 82 项通过；`fvm dart analyze` 无 error/warning，保留 39 条 info；格式检查通过。
