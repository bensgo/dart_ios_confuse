# Flutter + iOS Release 差异化工程详细设计

> 实施状态快照（2026-08-25）：WP-00～WP-10 已实现，WP-11 的工具回归、README、CI 骨架和本机无签名 IPA 检查已完成；正式双 Profile 签名 CI Release Gate 因缺少私有 Profile、签名凭据和 Release fixture 而阻塞在 95%。本文件第 3 节保留的是实施前差距与设计依据，不应覆盖 [工作计划](../../work-plan.md) 和 [工作进度](../../work-progress.md) 的当前事实。

| 范围 | 当前事实 |
|---|---|
| 基础工具链 | 复制/事务模式、restore、Analyzer 差异检查和现有 CLI 回归均已实现并由工具测试覆盖。 |
| Capability | Dart 扫描/百分比插入、6 个 Native 模块、Pigeon、依赖 Planner/Inspector、Release Inspector 已实现；manifest 流水线是可选能力。 |
| 第三方库 | 15 个审核候选、确定性 1–10 库选择与无副作用后台 probe 已实现；历史无签名 IPA 记录为 `selected=declared=locked=called=linked=3`，不代表新的 7 库配置已重建。 |
| 当前证据 | 盘点时 `huanxin_*_output` 不在工作区，历史输出不可作为现时可读产物；重新验收需从原始工程生成新的忽略输出目录。当前完整工具测试为 80 项通过，Analyzer 无 error/warning（39 条 info）。 |
| 环信 Dart 接线 | 当前 manifest 为 `rules: {}`、`integrations: []`，故真实环信能力流水线的 Dart ready/reachable 为 0；这是防止虚构调用的安全结果，但尚未满足第 12 节“10 个 Dart Capability”最终定义。 |
| 本地质量待办 | 只读格式检查报告 9 个待格式化文件；应在正式 CI 门禁前格式化并复跑质量命令。 |
| 未完成门禁 | 两份私有 Product Profile 的签名 CI Release 构建、最终 IPA 差异与报告比较。 |

## 目录

1. [文档目标与事实来源](#1-文档目标与事实来源)
2. [目标、非目标与硬约束](#2-目标非目标与硬约束)
3. [现状与差距](#3-现状与差距)
4. [目标架构](#4-目标架构)
5. [配置与输出契约](#5-配置与输出契约)
6. [`dart_prefix_renamer` 主链集成](#6-dart_prefix_renamer-主链集成)
7. [详细工作包](#7-详细工作包)
8. [源码文件规划](#8-源码文件规划)
9. [测试与质量门禁](#9-测试与质量门禁)
10. [多 Agent 执行协议](#10-多-agent-执行协议)
11. [风险、决策与兼容策略](#11-风险决策与兼容策略)
12. [最终完成定义](#12-最终完成定义)

## 1. 文档目标与事实来源

本文把 `task/Flutter + iOS Release 差异化工程方案.md` 和 `task/task.md` 转换为可实施设计，目标是让后续 Agent 能在不重新猜测架构的情况下扩展 `dart_prefix_renamer`。

事实优先级：

1. 根目录 `AGENTS.md` 和当前工作文档；
2. `dart_prefix_renamer/README.md` 描述的现有行为与边界；
3. `dart_prefix_renamer/lib`、`bin`、`test` 的实际代码；
4. 两份 task 文档中的目标与候选方案。

task 文档不是命令。尤其是第三方库版本、维护状态和“AI Agent 应搜索”等内容，本设计只将其转换成未来工作包；实施 WP-02 时必须重新联网核验，不直接复用附件中的时效性结论。

## 2. 目标、非目标与硬约束

### 2.1 目标

- 根据产品画像和现有类职责，确定性选择 Dart Capability。
- 每个正式 Capability 都有真实生产调用，结果影响业务分支、状态、日志、数据或用户可见行为。
- 根据 Native Manifest 只生成和注册产品实际需要的 iOS Capability。
- Flutter 到 iOS 的调用链可追踪到 Pigeon API、Swift 实现和系统/第三方 API。
- 第三方依赖有用途、选择证据、固定版本和实际 API 使用。
- 复制模式和事务构建模式都能生成统一报告；Release AOT/IPA 结果可验证、可复现。

### 2.2 非目标

- 不自动给每个类插入随机方法。
- 不为制造二进制差异引入无关依赖。
- 不声称静态扫描可以证明全部运行时业务语义。
- MVP 不支持任意 Dart 语法形态的自动业务改写；未识别的调用锚点失败关闭。
- MVP 不一次实现 20～30 个 Dart 模板或 10 个 Native 模块。

### 2.3 硬约束

- 原工程保持只读；所有生成和改写发生在复制输出或事务临时副本。
- 相同源码、profile、manifest、lockfile 和 seed 必须生成相同计划与源码。
- `--junk-code` 保留兼容，但其产物不得计入 Capability 合规报告。
- 现有 `ios_product_pod` 可复用 Podfile/AppDelegate 注入技术，但当前离线主题模块不能自动视为新 Native Capability 合规。
- 未提供真实调用锚点、用途或验证证据时，`prepare` 必须拒绝应用该能力。

## 3. 现状与差距

| 领域 | 已有能力 | 缺口 | 复用点 |
|---|---|---|---|
| 工程隔离 | 复制模式、事务临时副本、失败清理 | 无统一 capability prepare/verify 阶段 | `ProjectCopier`、`TransactionalBuildRunner` |
| Dart 分析 | Analyzer 语义解析、Class/引用重命名 | 无职责分类、能力规划、调用可达性报告 | `AnalysisContextCollection`、`ProjectLayout` |
| Dart 生成 | 随机 junk code | 缺少有业务语义的模板和真实调用接线 | `SourceEdit` 基础设施；不复用随机生成逻辑 |
| 配置 | CLI 参数 | 无 Product Profile、Dart/Native/Dependency Manifest | `args`、`yaml` 已存在 |
| iOS 生成 | 确定性本地 Pod、MethodChannel 注入 | 无 Native Capability 池、Pigeon、按 manifest 注册 | `IosProductPodGenerator` 的文件/Pod 注入模式 |
| 依赖 | 本地 Pod，无第三方依赖 | 无在线候选池、lockfile 一致性和真实 API 检查 | Podfile 解析与 manifest 扩展 |
| 验证 | Analyzer 前后差异、IPA hash 绑定 | 无 AOT 可达性、Native 符号/依赖/Bridge 检查 | `validator.dart`、`IpaBinder`、总 manifest |
| 恢复 | 名称、Channel、本地 Pod 恢复 | 新生成文件和注入块尚无恢复记录 | manifest 驱动的恢复流程 |

## 4. 目标架构

```text
Product Profile + Capability Manifests + Library Pool
                         │
                         ▼
              CapabilityPreflight
                         │
          ┌──────────────┴──────────────┐
          ▼                             ▼
 Dart Scanner / Planner        Native Planner / Dependency Planner
          │                             │
          ▼                             ▼
 Dart Generator + Call Wiring  Native Modules + Pigeon + Pod/SPM Wiring
          └──────────────┬──────────────┘
                         ▼
              Existing Rename Pipeline
                         ▼
          Analyzer + Manifest + Build + IPA Bind
                         ▼
                   ReleaseInspector
```

设计分层：

- `model`：纯配置、计划、证据和报告模型，不读写文件。
- `loader`：YAML/JSON/lockfile 读取与 schema 校验。
- `scanner`：只读分析 Dart/iOS/依赖事实。
- `planner`：根据事实确定性产生计划，不直接改文件。
- `generator`：只执行已通过 preflight 的计划。
- `validator`：验证定义、调用、注册、依赖与构建证据。
- `orchestrator`：把新阶段接入现有两种运行模式。

## 5. 配置与输出契约

### 5.1 `config/product_profile.yaml`

```yaml
schema_version: 1
product:
  id: product_deisoekdi
  type: social
```

要求：Product Profile 只表达产品身份；Dart 能力只在 `dart_capabilities.yaml` 声明，Native 开关/Provider/Bridge 只在 `native_capabilities.yaml` 声明。`features` 与 `technical` 已移除，遗留字段以 `E002` 失败关闭；`product.id` 与 `--ios-product-id` 同时提供时必须一致。

### 5.2 `config/dart_capabilities.yaml`

规则层定义允许能力和数量，应用层必须为每次实际改写给出显式 integration：

```yaml
schema_version: 1
rules:
  repository:
    min: 1
    max: 3
    allowed: [cache_key, cache_validation, response_normalizer, request_context]
integrations:
  - class: UserRepository
    library: packages/aixi_network/lib/src/user_repository.dart
    capability: cache_key
    call_site:
      method: loadUser
      anchor: before_cache_read
    effect: cache_lookup_key
```

`class + library + method + anchor` 唯一定位生产调用。MVP 不允许只写 class 名后猜测调用位置。

### 5.3 `config/native_capabilities.yaml`

```yaml
schema_version: 1
native:
  device: {enabled: true, provider: system}
  network: {enabled: true, provider: nw_path_monitor}
  secure_storage: {enabled: true, provider: keychain}
  crypto: {enabled: true, provider: crypto_kit}
  diagnostics: {enabled: true, provider: system}
  performance: {enabled: true, provider: os_signpost}
bridges:
  - api: networkState
    consumer: lib/platform/platform_service.dart
    effect: offline_state
```

### 5.4 `config/ios_library_pool.yaml`

该文件由 WP-02 生成，至少记录 `repository`、`capability`、`selected_version`、`package_manager`、`license`、`minimum_ios`、`last_release_at`、`last_commit_at`、`privacy_manifest`、`status`、`reason`、`researched_at` 和证据 URL。没有时间戳和证据 URL 的条目不得批准。

### 5.5 `config/dependencies.yaml`

只记录本产品实际选择的依赖：

```yaml
schema_version: 1
dependencies:
  Kingfisher:
    version: 8.0.0
    manager: spm
    capability: image
    reason: image_cache
    production_call: ios/NativeCapabilities/Image/ImageCapability.swift
```

实际版本最终以 `Package.resolved` 或 `Podfile.lock` 为准，两者不一致时失败。

### 5.6 输出

```text
reports/
├── capability-plan.json
├── dart-capability-report.json
├── native-capability-report.json
├── dependency-report.json
└── release-report.json
```

所有 JSON 包含 `schemaVersion`、`toolVersion`、输入文件 SHA-256、生成时间、状态和 failure codes。可复现比较忽略生成时间字段。

## 6. `dart_prefix_renamer` 主链集成

### 6.1 新 CLI

在兼容现有入口的前提下增加：

```text
--prepare-capabilities
--product-profile=<relative path>
--dart-capabilities=<relative path>
--native-capabilities=<relative path>
--dependency-manifest=<relative path>
--library-pool=<relative path>
--capability-report-dir=reports
--capability-seed=<int>
--verify-release-capabilities
--release-artifact=<absolute IPA path>
```

建议在内部引入子命令模型 `prepare`、`verify-release`，但第一阶段先保留 flag 入口，避免破坏现有脚本。CLI 参数和配置文件冲突时，命令行只允许覆盖路径/seed，不允许覆盖能力语义。

### 6.2 流水线顺序

```text
1. 校验参数和所有 manifest
2. 复制原工程 / 创建事务副本
3. pub get + Analyzer baseline
4. 扫描未改名副本，生成 capability plan
5. preflight 验证调用锚点、依赖和文件冲突
6. 应用 Dart Capability 与真实调用接线
7. 执行现有文件/目录/Class/Asset 等处理
8. 生成 Native Capability、Pigeon 和依赖接线
9. 写统一 manifest，记录所有生成文件和注入块
10. Analyzer final；失败则阻止构建
11. 执行 Release build
12. 对 IPA、lockfile、符号和报告执行 Release Inspector
13. 事务模式只复制显式产物与 reports，最后删除临时副本
```

Dart Capability 必须在现有 `_analyzeProject` 前应用，使后续 Class/URI 语义改写覆盖新代码。Native/Pigeon 生成放在 Dart 重命名后，生成器直接使用最终路径和最终符号，避免再次被重命名。

### 6.3 失败与回滚

- preflight 失败时不开始任何源码改写。
- 复制模式应用中失败时保留输出目录用于诊断，但 manifest 标记 `failed`；仍不覆盖既有输出。
- 事务模式沿用 `finally` 删除临时目录。
- manifest 记录新增文件、原文件 hash、注入块 marker 和配置 hash；`--restore` 只删除 hash 仍匹配的生成文件，用户修改过的文件拒绝静默删除。

## 7. 详细工作包

### WP-00 基线、fixture 与配置契约

目标：先冻结测试事实和 schema，防止后续 Agent 各自发明格式。

实现：

- 新建最小 Pub Workspace fixture，包含 repository/service/controller/model/widget、iOS Runner、Podfile 和可构建 Pigeon stub。
- 为真实调用准备正例，为死代码、仅 import、错误 anchor、动态反射准备反例。
- 定义 YAML/JSON schema version、错误码、路径安全和 deterministic snapshot 规则。
- 记录当前 `fvm dart analyze`、`fvm dart test -r expanded` 基线。

验收：fixture 可重复生成；现有测试不回退；schema 示例均有 parser 测试。完成后提交一个独立 commit。

### WP-01 Product Profile 与 Manifest 解析

目标：提供所有后续规划的强类型输入。

实现：

- 增加 `ProductProfile`、`DartCapabilityManifest`、`NativeCapabilityManifest`、`DependencyManifest`。
- 严格校验 schema version、未知 capability、重复 integration、绝对路径、`..` 越界、product ID 冲突。
- 输出规范化 JSON 和输入 SHA-256，供确定性选择与报告使用。

测试：合法/缺字段/未知字段/重复 ID/路径越界/产品不一致/稳定序列化。

验收：所有错误有稳定 error code；解析阶段不改工程文件。

### WP-02 第三方库在线调研与候选池

目标：按产品能力建立 20～30 个候选，再筛成 10～15 个合理候选；实际启用数量由真实需求决定。

实现流程：Product Profile → 能力类别 → 每类 3～5 个候选 → 官方仓库/发布/包管理证据 → 评分 → approved/conditional/rejected。

必须核验：最新 release/commit、归档状态、license、SPM/CocoaPods、最低 iOS、Swift/Xcode 兼容、Privacy Manifest、维护风险、真实功能匹配。附件中 Alamofire、Kingfisher、SDWebImage、GRDB、KeychainAccess、ZIPFoundation、CocoaLumberjack、SwiftProtobuf、Starscream、Reachability.swift 仅作为搜索种子。

验收：每个 approved 条目有证据 URL、核验日期和固定版本；系统 Framework 可满足时默认不引第三方库；该工作包不直接修改 App 依赖。

### WP-03 Dart 扫描、职责分类与能力规划

目标：扫描 root App 和 Pub Workspace 成员 Package，形成可解释、确定性的 plan。

实现：

- 复用 `ProjectLayout` 和 Analyzer context，收集类名、库 URI、注解、父类/接口、字段、方法、依赖引用和被调用位置。
- 分类优先级：显式 manifest/annotation > 接口/父类 > 文件路径 > 类名后缀；低于置信阈值标记 `unclassified`，不自动应用。
- 根据 profile、类型、已有依赖和允许列表选择 capability；禁止 `Random()`。
- 稳定选择键：`profileHash + libraryUri + className + policyVersion + seed`。

测试：五种类类型、同名跨 package 类、part 文件、生成代码排除、同输入稳定、不同 profile 合理变化。

验收：`capability-plan.json` 对每项给出分类证据、选择原因、目标调用锚点和预期 effect；无 anchor 的项只能是 suggestion，不能进入 apply。

### WP-04 Dart Capability 生成与真实调用接线

目标：实现首批 10 个模板：`cache_key`、`cache_validation`、`response_normalizer`、`request_context`、`input_validation`、`analytics_context`、`state_validation`、`debug_summary`、`request_metadata`、`retry_context`。

实现：

- 每个模板定义适用类、依赖前提、参数/返回类型、允许 anchor、代码生成器、调用接线器和业务 effect validator。
- 使用 Analyzer node offset + `SourceEdit` 修改；禁止字符串全文替换。
- 对 cache key、validation、normalizer 等改变返回值/分支的能力，验证生成变量确实被下游使用。
- `debug_summary` 只有接入现有生产日志/诊断出口才合规；没有日志出口则拒绝。
- 一次只应用 preflight 完整通过的 plan；任何 edit 冲突导致整个 capability 阶段失败。

测试：每模板至少正例、无依赖反例、错误 anchor 反例、幂等性、格式化后 Analyzer 无新增错误。

验收：10 个模板全部有至少一个 fixture 生产调用链；不生成 `fakeCall`、无条件启动调用或仅为保留代码的入口。

### WP-05 Dart 可达性与语义验证

目标：证明“定义—生产调用—结果消费”三段链，不只统计方法名文本出现次数。

实现：

- Analyzer element identity 关联声明和调用，排除 test、example、生成验证 helper 和注释/字符串。
- 结果消费分为 `branch`、`return`、`argument`、`state_write`、`log_payload`、`data_transform`。
- 生成源码级证据（库 URI、类、方法、offset、effect）和 Release 级证据。
- Release AOT MVP 使用构建成功 + 入口静态可达 + 产物检查组合；不能可靠证明时状态为 `unverified` 并使严格模式失败。

验收：死代码、测试调用、仅声明、仅 `vm:entry-point` 均失败；正例报告 `defined=true`、`productionCallCount>=1`、`effectVerified=true`。

### WP-06 Native Capability 模块池与生成器

目标：先实现 6 个无额外第三方依赖的模块：Device、Network、SecureStorage、Crypto、Diagnostics、Performance。

实现：

- 建立统一 Swift protocol、result/error 模型和 `NativeCapabilityManager`。
- 按 manifest 仅生成启用模块，使用 Foundation、Network、Security、CryptoKit、MetricKit/os。
- 每个模块定义权限、数据边界、线程模型、最低 iOS 和不可用降级。
- 复用本地 Pod 生成/Podfile/AppDelegate marker 技术，但模块目录、manifest 和 restore 独立于旧 `ios_product_pod`。

测试：Swift 单元测试或可运行 host fixture；启用/禁用快照；重复生成稳定；缺少 framework/最低 iOS 不满足时失败。

验收：禁用模块不生成、不注册；启用模块有 Bridge consumer；SecureStorage 不生成或记录设备标识符。

### WP-07 Pigeon Bridge 与业务调用接线

目标：形成 `UI/Controller → PlatformService → Pigeon Dart → Swift → Capability` 的真实链路。

实现：

- 固定 Pigeon 版本到 lockfile；输入定义进入 `pigeons/native_capability_api.dart`。
- 生成 Dart/Swift 文件并记录生成器版本/hash；禁止手改生成文件。
- 为每个 bridge 在 manifest 声明 consumer 和 effect；先支持显式文件/类/方法 anchor。
- AppDelegate 只注册启用模块；错误转换为稳定 domain code，不透传敏感 native 信息。

测试：Pigeon golden、mock host API、Swift handler、未注册/异常/超时路径、Dart 业务 effect。

验收：每个启用 Native Capability 至少一个生产 consumer；仅注册未调用视为失败。

### WP-08 第三方依赖选择、接入与检查

目标：仅在系统 Framework 无法满足已启用能力时，从 approved pool 选择依赖。

实现：

- MVP 先支持一种包管理器端到端，建议沿用项目现有 CocoaPods；SPM 在接口稳定后增加。
- 依赖决策由 capability/provider 显式绑定，版本来自 dependency manifest，并由 lockfile 固定。
- 扫描 Swift element/import 与 API 调用；仅 import、仅类型别名、只在测试使用均不算 used。
- 比较 manifest、Podfile/Package.swift、Podfile.lock/Package.resolved 与最终 app binary。

验收：无用途、版本漂移、lockfile 缺失、未调用、未链接、重复 provider 任一情况失败；系统实现可用时报告选择第三方的额外理由。

### WP-09 Release Inspector 与二进制验证

目标：聚合 Dart、Native、Bridge、Dependency、Build 和 IPA 身份，产出唯一 Release 结论。

实现：

- 扩展 `IpaBinder` 或新增 inspector，读取 IPA 中 Mach-O、Frameworks、资源、Info.plist 和主 bundle hash。
- 对照 capability manifest 检查预期模块/依赖存在、禁用模块不存在。
- 合并 Analyzer、Flutter test、iOS test、Release build、lockfile 和 capability 子报告。
- 使用稳定 failure codes，例如 `DART_CAPABILITY_UNREACHABLE`、`NATIVE_BRIDGE_UNCALLED`、`DEPENDENCY_UNJUSTIFIED`、`LOCKFILE_MISMATCH`。

验收：任一门禁失败时 CLI 非 0；报告仍完整写出失败原因；相同 IPA 重复检查幂等。

### WP-10 CLI、主处理管线、manifest 与 restore 集成

目标：将 WP-01～09 接入现有 `RenameConfig`、`PrefixRenamer`、`RenameReport`、事务构建和恢复流程。

实现：

- 拆分 CLI parser，避免继续把所有入口堆入 `main()`。
- `RenameConfig` 增加 capability 配置对象，不让十余路径字段散落到 pipeline。
- `PrefixRenamer.run()` 按第 6 节顺序编排；生成步骤封装为 orchestration service。
- manifest 升级 schema version，并兼容读取 version 1；新增 `productProfile`、`dartCapabilities`、`nativeCapabilities`、`dependencies`、`releaseValidation`。
- `RenameReport` 增加 planned/applied/reachable/failed、native enabled/called、dependency justified 等统计。
- 事务模式允许显式复制 `reports`，但绝不隐式复制源码或敏感符号。

验收：两种模式覆盖所有新 flag；旧命令输出与测试保持兼容；restore 可安全清除未被用户修改的新产物。

### WP-11 CI、回归、文档与迁移

目标：建立可重复的 Release Gate，并把真实使用方式写入 README。

CI 顺序：format → analyze → capability unit tests → Flutter tests → native tests → prepare dry-run → transactional Release build → binary inspection → release report validation。

实现：

- 更新 `README.md` 的模式总览、参数表、完整示例、报告、恢复限制和常见失败。
- `CHANGELOG.md` 记录 manifest schema 与 CLI 变化。
- 明确 `--junk-code` 是 legacy/non-compliant，不参与新报告；暂不删除，避免破坏旧脚本。
- 用至少两个不同 Product Profile 构建，证明计划、调用图、Native 模块和最终 IPA 组成按功能差异变化。

验收：完整测试、两个 Release fixture、报告 schema 校验全部通过；提交中不包含 IPA、dSYM、split-debug-info 或私有工程源码。

## 8. 源码文件规划

建议新增：

```text
lib/src/capabilities/
├── model/
│   ├── product_profile.dart
│   ├── capability_manifest.dart
│   └── capability_report.dart
├── config/
│   └── capability_config_loader.dart
├── dart/
│   ├── dart_class_scanner.dart
│   ├── dart_class_classifier.dart
│   ├── dart_capability_catalog.dart
│   ├── dart_capability_planner.dart
│   ├── dart_capability_generator.dart
│   └── dart_capability_validator.dart
├── ios/
│   ├── native_capability_planner.dart
│   ├── native_capability_generator.dart
│   ├── pigeon_bridge_generator.dart
│   └── dependency_inspector.dart
└── release/
    ├── release_inspector.dart
    └── release_report_writer.dart
```

建议修改：

| 文件 | 修改内容 |
|---|---|
| `bin/dart_prefix_renamer.dart` | 新入口路由、退出码和汇总输出 |
| `lib/src/config.dart` | capability 配置聚合与参数校验 |
| `lib/src/prefix_renamer.dart` | preflight、Dart apply、Native generate、manifest 编排 |
| `lib/src/report.dart` | 新统计和严格验证结论 |
| `lib/src/transactional_build.dart` | Release inspector、报告产物复制 |
| `lib/src/ipa_binding.dart` | 复用 IPA 解析与组件 hash，或抽出公共 reader |
| `lib/src/ios_product_pod.dart` | 抽取 Podfile/AppDelegate marker/writer 公共组件，不直接塞入新模块逻辑 |
| `lib/dart_prefix_renamer.dart` | 导出稳定公共 API |
| `README.md`、`CHANGELOG.md` | 用户契约和迁移说明 |

每个新增生产文件应有对应测试文件；集成测试集中到 `test/capability_pipeline_integration_test.dart`，避免把所有情形继续堆入现有 prefix 集成测试。

## 9. 测试与质量门禁

| 层级 | 必测内容 | 通过标准 |
|---|---|---|
| Parser | schema、未知字段、路径、版本 | 错误码稳定，无文件写入 |
| Scanner | Workspace、part、同名类、生成目录 | element identity 正确，输出稳定 |
| Planner | 分类、选择、seed、冲突 | 同输入逐字节稳定，可解释 |
| Generator | 10 个 Dart 模板、6 个 Native 模块 | 幂等、无 edit 冲突、格式化通过 |
| Reachability | 声明、生产调用、effect | 反例失败，正例证据完整 |
| Bridge | Dart/Pigeon/Swift/consumer | 启用项端到端，禁用项不存在 |
| Dependency | manifest、lockfile、源码、binary | 四方一致且真实调用 |
| Pipeline | 复制/事务/失败清理/restore | 原工程源码不变，产物边界正确 |
| Release | AOT、IPA、报告 | 严格模式全绿，失败返回非 0 |

每个工作包完成前至少运行：

```bash
cd dart_prefix_renamer
fvm dart format --output=none --set-exit-if-changed bin lib test
fvm dart analyze
fvm dart test -r expanded
```

涉及 iOS/Pigeon/Release 的工作包还必须运行对应 fixture 的 iOS unit test 和 `fvm flutter build ipa --release`。没有可用签名环境时记录 `unavailable`，不得宣称 Release 验证通过；可使用 `flutter build ios --release --no-codesign` 作为较低等级证据，但不能替代最终 IPA 门禁。

## 10. 多 Agent 执行协议

每个 Agent 开始时：

1. 阅读必读文档和本详细设计；检查父仓库及 `dart_prefix_renamer` 仓库状态。
2. 只领取依赖已完成的一个 WP，在 `docs/work-progress.md` 登记负责人、0%、文件范围和验收标准。
3. 先读取将修改的现有实现与相关测试；不得仅按本文猜测 API。
4. 在独立分支/工作树实施，默认分支前缀 `codex/`；避免多个 Agent 修改 `config.dart`、`prefix_renamer.dart` 或同一测试文件。
5. 每完成一个可验证子项更新百分比和证据；发现设计冲突先记录 decision，不隐式扩展范围。

交付时必须提供：实现摘要、文件列表、测试命令与结果、未验证项、manifest/report 示例、兼容影响、commit hash。提交信息使用“中文说明 / English summary”。

推荐并行边界：WP-03 与 WP-06 可在 WP-01 后并行；WP-02 可与它们并行；WP-04/05、WP-07、WP-08 分属不同 Agent；WP-10 必须等接口冻结后由单一集成 Agent 执行。

## 11. 风险、决策与兼容策略

| 风险 | 决策 |
|---|---|
| 自动改业务代码容易误判语义 | MVP 只允许显式 integration + 支持的 anchor；否则只建议不应用 |
| 现有 junk code 与“禁止 dead code”冲突 | 保留 legacy flag，但从 Capability 统计与 Release 合规中排除 |
| Pigeon 与现有 MethodChannel 并存 | 新 Native Capability 使用 Pigeon；旧 Channel 差异化功能保持原行为 |
| `ios_product_pod` 与 Native 模块职责重叠 | 抽取接线基础设施；不把旧离线主题模块伪装成新能力 |
| 第三方库信息随时间变化 | library pool 强制 researched_at、证据 URL 和 CI 过期策略 |
| 静态分析无法完全证明运行时路径 | 报告区分 source-reachable、build-retained、runtime-observed；严格门禁明确所需等级 |
| manifest schema 升级破坏 restore | 新 writer 使用 version 2；reader 同时支持 version 1；未知新版本失败关闭 |
| 多 Agent 同改主链冲突 | 先做独立模块，最后由 WP-10 单 Agent 集成公共文件 |

## 12. 最终完成定义

只有同时满足以下条件，整个工程才可标记 `已完成（100%）`：

- 10 个 Dart Capability 均有生产调用与 effect 证据。
- 6 个 Native MVP Capability 可按 manifest 独立启停，启用项均有 Pigeon consumer。
- 第三方依赖只来自重新核验的 approved pool，版本由 lockfile 固定且在源码和 binary 中真实使用。
- 复制模式、事务模式、restore、旧 CLI 回归全部通过。
- 至少两个 Product Profile 的 Release 构建证明功能配置会产生可解释的 Dart/Native/依赖/IPA 差异。
- `release-report.json` 状态为 `passed`，且所有输入 hash、子报告和 IPA 身份完整。
- README、CHANGELOG、工作进度、日报和双语 Git 提交齐全；仓库不包含敏感构建产物。
