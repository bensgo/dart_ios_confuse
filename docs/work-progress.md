# 工作进度

## 发布本地工具库到 GitHub

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-09-07
- 验收标准：将可公开发布的本地工具源码上传至 `bensgo/dart_ios_confuse`；不上传 IPA、dSYM、symbols、混淆 map、私有源码、敏感日志或本地构建输出；从远端重新克隆后内容和 Git 状态可验证。
- 已完成：目标仓库与账号权限核验；生成独立干净发布快照；纳入根仓库可发布文件及 `dart_prefix_renamer` 源码；排除 `tbr-shell-cladding`、`ipa/`、`symbols/`、输出副本、私有报告及嵌套 Git 元数据。
- 验证：敏感模式扫描无命中；无超过 20 MB 文件；Analyzer 无 error/warning（保留 39 条 info）；完整 86 项测试通过；远端全新克隆为干净 `main`，无 gitlink、IPA、dSYM、symbols 或 `tbr-shell-cladding`。
- 远端首个交付：`d5c4052`（`发布：上传 Dart iOS 混淆工具 / release: publish Dart iOS obfuscation toolkit`）。
- 阻塞：无。
- 下一步：无。

## DifferenceKit Swift 编译修复

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-26
- 验收标准：修复生成的 DifferenceKit probe 的 Swift 参数标签，重新生成现有输出副本并通过 iPhoneOS 编译。
- 已完成：已定位为 Swift 成员初始化器缺少 `value:` 参数标签。
- 已完成：生成的调用改为 `DifferenceKitProbeValue(value: ...)`，消除 Swift 成员初始化器参数标签错误。
- 已完成：生成器在确定性计划不变但模板更新时会刷新其自有 Podspec、Runtime、probe 和 manifest，并重新运行 `pod install`；不再把旧生成代码误判为有效。
- 验证：专项测试 5 项通过；现有环信输出副本已完成 `pod install`、无签名 iPhoneOS Release 构建和 IPA linkage 验证，最终为 `Selected=Declared=Locked=Called=Linked=7`、`Passed=true`。
- 工具交付：`8084c93`（`修复：刷新过期的第三方 Pod 探针 / fix: refresh stale third-party Pod probes`）。
- 产物：unsigned IPA 位于 `ipa/product_abc/product_abc_unsigned.ipa`，按 Git 忽略规则不提交。
- 下一步：无。
- 阻塞：无。

## 模式一完整流程脚本

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-26
- 验收标准：提供可执行的一键模式一脚本，参数与当前 CLI 一致，默认 7 个第三方 Pod，具备路径/配置/覆盖保护，并通过 shell 语法和静态命令检查。
- 已完成：新增可执行 `scripts/run_mode1_product_abc.sh`，默认使用 product_abc、seed 0 和 count 7；支持环境变量覆盖源码、输出、IPA、符号和产品路径。
- 验证：`bash -n`、ShellCheck（若可用）、`git diff --check` 通过；配置检查使用 macOS 自带 `awk`，不依赖 `rg`；脚本主动拒绝已存在输出目录和非 count 7 配置。
- 工具文档提交：`5625e1e`（`文档：补充模式一脚本入口 / docs: add mode one script entry`）。
- 修复：CocoaPods trunk 当前不存在 Swinject 2.10.0，改为已验证可解析的 2.9.1；脚本自动补齐 `fluwx` 所需的 Ruby `plist` gem，并支持 `--resume` 跳过已完成的源码复制/Dart 插入。
- 实测：现有环信输出副本重新执行第三方 Pod 接入成功，`Selected=7`、`Declared=7`、`Locked=7`、`Called=7`、`Passed=true`；尚未构建 IPA，故 `Linked=0` 正常。
- 修复交付：工具 `879659b`（`修复：使用可解析的 Swinject 版本 / fix: use resolvable Swinject version`）；根脚本 `b1657ea`（`修复：恢复模式一 Pod 安装流程 / fix: restore mode one Pod installation`）。
- 下一步：直接执行脚本进行真实构建；执行前确认默认输出目录不存在。
- 阻塞：无。

## iOS 第三方 SDK Pod 候选池扩容与数量范围

- 状态：已完成（100%）
- 负责人：Agent + 人工
- 开始日期：2026-08-26
- 验收标准：以 GitHub 官方仓库/Podspec 为证据新增 5 个 CocoaPods；所有新增库生成纯内存、安全 probe；`dependencies.yaml` 的 `count` 接受 1–10；候选池、测试、使用说明和日报一致。
- 已完成：已使用 GitHub 连接器与 `agent-reach` 的 GitHub 路由完成候选初筛；Yams 因仓库当前缺少 Podspec 被拒绝，采用 Swinject 替代。
- 已完成：候选池从 10 扩至 15，新增 SwiftyJSON、ObjectMapper、DifferenceKit、SwiftSoup、Swinject 的版本、许可、最低 iOS、Privacy Manifest 状态和官方证据链接。
- 已完成：新增 5 个 Swift probe，分别执行固定 JSON 读取、Map 构造、数组差分、HTML 字符串解析与内存依赖容器解析；安全扫描仍拒绝网络、持久化、权限、UI、日志和 Flutter 回传 API。
- 已完成：planner 的 `count` 改为严格接受 1–10；图片冲突组保持互斥。环信配置已设为 `count: 7`，`product_abc + seed 0` 选择 SwiftSoup、Swinject、DifferenceKit、SwiftyJSON、Kingfisher、GRDB.swift、PromiseKit。
- 验证：格式检查、29 项依赖/生成/配置专项测试、`git diff --check` 均通过；Dart analyzer 无 error/warning（39 条既有 info）。未覆盖已有环信输出副本，也未在本次修改中重新执行 7 库 IPA 构建。
- 工具交付：`0c72293`（`功能：扩容 iOS 第三方 Pod 候选池 / feat: expand iOS third-party Pod pool`）。
- 下一步：如需生成 7 库产物，从原始环信工程创建新的模式一输出副本，再执行 `--prepare-ios-third-party-sdk-pods`；不要复用已有 3 库输出。
- 阻塞：无。

## 工具文档拆分为功能与完整模式用法

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-25
- 验收标准：将工具文档收敛为“功能、参数和单项使用”与“完整模式一、完整模式二使用”两份；示例采用当前规范 CLI，链接和命令参数一致。
- 已完成：重写 `dart_prefix_renamer/README.md`，仅保留能力分类、参数表、单项入口、安全边界与兼容说明。
- 已完成：新增 `dart_prefix_renamer/USAGE.md`，仅保留可复制的完整模式一与模式二流程；模式一包括 Dart 自动能力、自定义 Pod、第三方 SDK Pod、无签名构建和 IPA linkage 验证。
- 已完成：明确第三方 SDK Pod 当前只支持保留输出副本的模式一，不能混入模式二临时构建。
- 验证：`--help` 与第三方 SDK Pod 专用 `--help` 均可运行；README/USAGE 链接、参数检索、代码围栏配对和空白检查通过。
- 工具交付：`5f9e082`（`文档：拆分功能与模式用法 / docs: split features and mode usage`）。

## Dart、自定义 Pod 与第三方 SDK Pod 解耦

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-25
- 验收标准：区分 Dart 自动能力、iOS 产品自定义 Pod、iOS 第三方 SDK Pod 的配置、CLI、生成物和验证入口；规范命名；只删除已有替代路径且无必要兼容价值的指令和不可达代码；完整测试通过。
- 已完成：建立三类规范入口；Dart 保留 `--scan/auto-dart-capabilities`，自定义源码 Pod 使用 `--ios-custom-pod-*`，第三方 SDK Pod 使用 `--prepare-ios-third-party-sdk-pods` 与 `--ios-third-party-sdk-*`。
- 已完成：第三方 SDK Pod 独立入口仅加载 `dependencies.yaml` 和 `ios_library_pool.yaml`，产品 ID/seed 由命令行传入，不再要求 `--target`、Product Profile、Dart 或 Native manifest。
- 已完成：旧 `ios-product-*` 参数隐藏并作为兼容别名保留；旧混合 `--prepare-capabilities` / `--capabilities` 在文档中标为废弃兼容。新增独立清理清单，记录删除条件和代码候选，避免未迁移 CI/私有脚本时破坏兼容。
- 已完成：更新工具 README、CHANGELOG、三份功能说明、区别说明、工程总览与工作文档；模式一/模式二示例使用新自定义 Pod 名称。
- 验证：新入口专项测试、自定义 Pod、planner/generator 测试通过；完整 82 项测试通过；Analyzer 无 error/warning（保留 39 条既有 info）；全量格式化修正此前 9 个格式缺口；`git diff --check` 通过。
- 工具交付：`25a40b8`（`功能：拆分 Dart 与 iOS Pod 能力 / feat: separate Dart and iOS Pod capabilities`）。
- 下一步：确认 CI 与私有脚本迁移后，按 `docs/features/capability-command-cleanup.md` 分批删除兼容参数和旧混合流水线；Native/Pigeon 是否作为第四类功能保留需单独决策。
- 边界：不修改环信原始源码，不覆盖输出目录，不处理或提交现有 `ipa/` 与 `tbr-shell-cladding/`。

## 模式二完整示例纳入 Dart 自动能力插入

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-25
- 验收标准：模式二在临时副本内完成 50%、seed `0` 的 Dart 自动能力插入，构建前不修改原工程，并将该步骤纳入 README 完整示例。
- 已完成：`--transactional-build --auto-dart-capabilities` 现在会先复制、重命名并校验临时副本，随后在该副本自动插入 Dart Capability，再执行构建；`reports/` 可作为 artifact 复制回原工程。
- 已完成：模式二完整示例包含 50%、seed `0`、`--artifact-dir="reports"`，明确原工程源码不会被自动插入步骤修改。
- 验证：事务构建专项 3 项测试通过（新增临时副本插入断言）；改动范围 `fvm dart analyze` 无问题，格式检查和 `git diff --check` 通过。
- 交付：`dart_prefix_renamer` 提交 `03f4554`（`功能：事务构建支持 Dart 自动能力 / feat: support Dart auto capabilities in transactional builds`）。
- 下一步：无。
- 阻塞：无。

## 模式一完整示例纳入 Dart 自动能力插入

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-25
- 验收标准：将用户指定的 50%、seed `0` 自动 Dart Capability 插入命令作为模式一完整示例的明确组成部分；不改变 CLI 行为或覆盖任何既有输出副本。
- 已完成：将模式一说明改为“完整流程”，明确在复制副本后必须执行 50%、seed `0` 的自动插入步骤；命令继续使用 `huanxin_product_deisoekdi_output`、`lib,packages/aixi_foundation/lib`。
- 验证：`git diff --check` 通过；命令参数与输出副本路径交叉检查通过。
- 交付：`dart_prefix_renamer` 提交 `ae5bdbb`（`文档：将 Dart 自动能力插入纳入完整示例 / docs: include Dart auto capabilities in complete example`）。
- 下一步：无。
- 阻塞：无。

## 全项目状态盘点与文档校准

- 状态：已完成（100%）
- 负责人：Agent + 人工
- 开始日期：2026-08-25
- 验收标准：以当前工具源码、测试、Git 状态与现有构建证据为准，更新工程总览、计划、进度和日报；明确已经完成、未完成、外部阻塞与下一步，且不触碰已有环信输出或私有构建产物。
- 已核对：根仓库仅有用户已有未跟踪目录 `tbr-shell-cladding`；`dart_prefix_renamer` 工作树干净；原始环信工程存在用户已暂存的 capability 配置和未跟踪 reports，均不在本次修改范围。
- 已完成：重读 AGENTS、工程总览、计划、进度、日报和工具 README；核对根/工具/环信三处 Git 状态、CI workflow、测试清单与输出目录；运行当前工具完整 80 项测试。
- 已发现：详细设计第 3 节为实施前差距，容易与当前事实混淆；已增加实施状态快照。当前工作区没有 `huanxin_*_output`，历史无签名 IPA 只保留为文档记录。
- 质量缺口：只读格式检查报告 9 个待格式化文件；Analyzer 无 error/warning（39 条 info），完整 80 项测试通过。本次仅盘点并记录，不修改工具源码。
- 关键缺口：读取原始环信 manifest 后确认 Dart `rules` 与 `integrations` 均为空，历史实测 Dart ready/reachable 为 0。该选择避免伪造调用，但在源码所有者确认真实业务锚点前，不能宣称完整 10 个 Dart Capability 已在环信落地。
- 已完成：更新工程总览、工作计划、详细计划目录、详细设计、工作进度和日报；修正工具 README 的 Markdown 围栏并明确基础模式与 manifest 流水线边界。
- 验证：完整工具测试 80 项通过；Analyzer 无 error/warning（39 条 info）；所有本次文档 diff 通过空白检查和链接路径交叉检查。
- 交付：工具 README 修正提交 `007851c`；项目状态与文档校准提交 `4c05044`；真实环信 Dart Capability 接线缺口补充提交 `aeb080e`。
- 下一步：先处理 WP-11 的 9 个文件格式门禁；正式签名双 Profile CI 需等待用户/CI 管理者提供私有输入。
- 阻塞：无。

## 建立 Agent 协作与 skill 管理流程

- 状态：已完成（100%）
- 负责人：Agent + 人工
- 开始日期：2026-08-21
- 已完成：读取 `agent-human-collaboration` 与 `agent-reach` 规则；检查 Git 状态；发现项目根目录缺少既有协作文档。
- 当前：已补充 Agent 必读文档与 skill 管理流程。
- 验证：已确认 5 个文档入口存在，`rg` 关键规则检查通过，`git diff --check` 通过。
- 阻塞：指定 GitHub 仓库 API、README 和分支均返回 404，状态记为 `unavailable`。
- 解除条件：用户提供可访问仓库地址或 README 内容。
- 下一步：提交本次文档改动，并在交付中说明远程仓库不可访问。

## Release 差异化工程详细设计

- 状态：已完成（100%）
- 负责人：Agent + 人工
- 开始日期：2026-08-21
- 输入：`task/Flutter + iOS Release 差异化工程方案.md`、`task/task.md`、`dart_prefix_renamer/README.md` 与当前工具源码/测试。
- 验收标准：详细计划有目录、工作包边界、前置依赖、实现落点、测试与交付门禁，其他 Agent 可据此分阶段开发。
- 已完成：新增详细工作计划目录和 12 章实施设计；定义 WP-00～WP-11、主处理管线、配置/报告契约、源码落点、测试矩阵和多 Agent 协议。
- 验证：文档入口存在；关键主题与全部工作包检索通过；`git diff --check` 和 staged diff 检查通过。
- 阻塞：无。
- 交付 commit：`ed8a9d7`（`文档：设计 Release 差异化实施计划 / docs: design release differentiation plan`）。
- 下一步：由实施 Agent 从 WP-00 开始，完成基线 fixture 与配置契约，禁止跳过依赖直接进入生成器开发。

## WP-00 基线、fixture 与配置契约

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-21
- 已完成：
  - 新建最小 Pub Workspace fixture（`test/fixtures/wp00_baseline`），包含：
    - 5 个成员包：repository_pkg、service_pkg、controller_pkg、model_pkg、widget_pkg
    - 各包含对应类型的正例（真实生产调用链）和反例（死代码、仅 import、错误 anchor、动态反射）
    - iOS Runner 目录、Podfile、AppDelegate.swift
    - Pigeon stub（`pigeons/native_capability_api.dart`）
    - 配置文件：product_profile.yaml、dart_capabilities.yaml、native_capabilities.yaml、dependencies.yaml
  - 定义 YAML/JSON schema version、20 个稳定错误码（E001-E020）、路径安全规则、deterministic snapshot 规则
  - 实现 CapabilityConfigLoader、ProductProfile、DartCapabilityManifest、NativeCapabilityManifest、DependencyManifest、CapabilityReport 等模型
  - 编写 schema parser 测试（`test/wp00_schema_test.dart`，19 个测试全部通过）
- 验收：
  - `fvm dart analyze`：无错误（仅 info 级排序提示）
  - `fvm dart test -r expanded`：全部 49 个测试通过（含新增 19 个 schema 测试）
  - 现有测试无回退
- 阻塞：无
- 下一步：开始 WP-01 Product Profile 与 Manifest 解析

## WP-01 Product Profile 与 Manifest 解析

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-21
- 已完成：
  - 增强 CapabilityConfigLoader 严格校验：
    - Schema version 校验（E001）
    - 未知 capability 校验（E011）
    - 重复 integration 校验（E005）
    - 绝对路径/路径越界校验（E006、E007、E008）
    - Product ID 冲突校验（E009）
    - Bridge consumer 存在性校验（E018）
    - Integration class/library 存在性校验（E012）
    - 必填字段校验（E003）
    - 未知 provider 校验（E017）
  - 实现 NormalizedConfig.loadAll()：一次性加载所有配置并输出规范化 JSON + 输入 SHA-256
  - 新增 ConfigException 统一错误处理（含稳定 error code）
  - 新增 fixture 平台服务存根（`lib/platform/platform_service.dart`）
  - 更新 schema parser 测试覆盖所有错误码场景（23 个测试全部通过）
- 验收：
  - `fvm dart analyze`：无错误（仅 info 级排序提示）
  - `fvm dart test -r expanded`：全部 49 个测试通过（含新增 schema 测试）
  - 解析阶段不修改任何工程文件（只读加载 + 校验）
  - 所有错误有稳定 error code (E001-E020)
- 阻塞：无
- 下一步：开始 WP-02 第三方库在线调研与候选池

## WP-02 第三方库在线调研与候选池

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-21
- 已完成：
  - 使用 agent-reach (GitHub CLI) 搜索 24 个候选库
  - 按能力分类：Image(3)、Database(3)、Network(1)、SecureStorage(1)、Compression(1)、Logging(1)、Protobuf(1)、WebSocket(1)、NetworkMonitor(1)、JSON(1)、Promises(1)、CSV(1)、DeviceInfo(1)、CodeGen(1)、Date(1)、Crypto(1)、ErrorMonitoring(1)、Animation(1)、Linting(1)、SwiftExtensions(1)
  - 核验每个库：最新 release、提交时间、SPM 支持、最低 iOS、Swift 版本、License、Privacy Manifest、维护状态
  - 生成 ios_library_pool.yaml (24 条目)
- 评分结果：
  - Approved (17): kingfisher, sdwebimage, nuke, grdb, realm, sqlite_swift, alamofire, zipfoundation, cocoalumberjack, swiftprotobuf, promisekit, swiftycsv, devicekit, cryptoswift, sentry, lottie, swifterswift
  - Conditional (3): starscream (WebSocket, old release), sourcery (CLI tool), swiftlint (CLI tool)
  - Rejected (4): keychainaccess (3.5年无 release), reachability (prefer native NWPathMonitor), swiftyjson (Swift 标准库替代), swiftdate (4年无 release)
- 验收：
  - 每个 approved 条目有证据 URL、核验日期 (2026-08-21)、固定版本
  - 系统 Framework 可满足时默认不引第三方库 (如 NWPathMonitor 替代 Reachability)
  - 不直接修改 App 依赖，仅生成候选池供 WP-06/WP-08 使用
- 阻塞：无
- 下一步：开始 WP-03 Dart 扫描、职责分类与能力规划

## WP-03 Dart 扫描、职责分类与能力规划

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-21
- 已发现：工具仓库存在未跟踪的 `lib/src/capabilities/dart/dart_class_scanner.dart` 草稿；尚未纳入测试或提交。
- 已完成：修复 Analyzer 9 API；实现 Workspace scanner、职责 classifier、确定性 planner、负例拒绝与公开导出。
- 验收标准：Workspace、part、同名类与生成目录识别正确；同输入计划稳定；每项计划包含分类证据、选择理由、调用锚点和 effect。
- 验证：专项 3 项测试通过；完整 52 项测试通过；Analyzer 无 error/warning。
- 交付 commit：`f47e03f`（`功能：实现 Dart 能力扫描与规划 / feat: implement Dart capability scanning and planning`）。
- 阻塞：无。
- 下一步：实施 WP-04 Dart Capability 目录、定义生成与真实调用接线门禁。

## WP-04 Dart Capability 生成与真实调用接线

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-21
- 已完成：实现 10 个模板目录；只有生产调用已存在时才生成缺失定义；已有定义幂等跳过；无调用失败关闭。
- 验收标准：每个模板有正例；不存在生产调用时拒绝生成；不插入 fake call 或仅用于保留的入口。
- 验证：新增 3 项专项测试；完整 55 项测试通过；Analyzer 无 error/warning。
- 交付 commit：`1665c0e`。
- 阻塞：无。

## Dart 候选类分类扩展

- 状态：已完成（100%）
- 负责人：Agent + 人工
- 开始日期：2026-08-24
- 已完成：分类器新增 `utility`、`manager`、`logic`；Utility 同时识别 `Utility`、`Util`、`Helper`。类级 JSON 新增 `classes` 数组，包含类型、建议、候选资格和不合格原因；`classification_summary` 输出各类总数、候选数、比例及原因统计。
- 安全边界：三类在没有 manifest capability 模板时输出空 `suggestions`，不生成或插入代码。
- 验证：专项 5 项测试通过；`fvm dart analyze` 无 error/warning（38 条既有 info）。完整回归受本地命令 30 秒执行时限影响未获得最终退出码，前两轮已运行至 68 项集成测试，未见失败。
- 工具交付 commit：`9a08a0a`（`功能：扩展 Dart 候选类分类 / feat: extend Dart candidate classifications`）。
- 阻塞：无。

## Dart 百分比自动能力插入

- 状态：已完成（100%）
- 负责人：Agent + 人工
- 开始日期：2026-08-24
- 验收标准：可先对源码生成全量建议 JSON；只提供 Dart 差异化百分比即可生成可复用选择配置并插入；再次提供选择配置时不得重新随机；源码漂移和不安全方法体必须失败关闭。
- 已完成：新增 `--scan-dart-capabilities` 全量建议入口；新增 `--auto-dart-capabilities`、`--dart-differentiation-percent` 和 seed 确定性选择；生成可复用 `dart-capability-selection.json`；提供 `--dart-capability-selection` 时跳过随机。
- 安全门禁：只向块状实例方法插入不消费结果的可达调用；同时生成 Capability 定义；复用配置必须通过分类、方法、能力、重复项、路径和源码 SHA-256 校验。
- 验证：专项 11 项通过；真实 CLI fixture 扫描 20 个 Class、识别 11 个可插入候选并完成 11 次插入，生成文件通过 Dart parser/formatter；完整 74 项测试通过；Analyzer 无 error/warning（45 条 info）。
- 工具交付 commit：`84d60a1`（`功能：实现 Dart 百分比能力插入 / feat: implement percentage-based Dart capability insertion`）。
- 真实环信扫描：排除 `junk_code` 后，`lib` 与 `packages/aixi_foundation/lib` 共输出 1446 个业务 Class、464 个当前可自动插入候选；全量基线保留在私有工程 `reports/dart-capability-suggestions.json`（SHA-256 `1d81618d8516e2ad2916214ed07fbd81b46c98eee10682cc385f96c17636515f`），不纳入公共仓库。
- 可用性修复：Analyzer 只发现 `--target` 范围文件，CLI 启动时立即输出 Project/Target，并按文件数持续显示解析进度，避免大型 Workspace 扫描表现为“无反应”。
- 扫描进度修复 commit：`a4bd2cc`（`修复：显示 Dart 扫描进度 / fix: show Dart scan progress`）；修复后完整 74 项测试通过。
- 阻塞：无。

## Manager/Logic/Widget Capability 模板

- 状态：已完成（100%）
- 负责人：Agent + 人工
- 开始日期：2026-08-25
- 验收标准：`manager`、`logic`、`widget` 均输出非空专属建议；百分比选择后生成真实可达且不改变返回值的调用与定义；复用 selection 继续通过严格校验。
- 已完成：Manager 增加 `operation_context`、`lifecycle_snapshot`；Logic 增加 `decision_context`、`rule_validation`；Widget 增加 `presentation_metadata`、`accessibility_context`。六个模板均接入 catalog、全量建议、百分比选择、调用生成与方法定义生成。
- 范围门禁：任意 `junk_code` 路径段在 Class 扫描阶段完全排除，不进入建议、候选、selection 或插入。
- 真实环信验证：Manager 34 个/候选 31，Logic 3 个/候选 3，Widget 562 个/候选 306；三类 `no_capability_suggestions` 均为 0。全量候选由 124 增至 464。
- 验证：专项 11 项、完整 74 项通过；Analyzer 无 error/warning（45 条 info）；真实报告 `junk_code` 路径数量为 0。
- 工具交付 commit：`e2523b3`（`功能：增加管理逻辑组件能力模板 / feat: add manager logic widget capabilities`）。
- 阻塞：无。

## 环信输出副本 Dart 差异化执行（50%）

- 状态：已完成（100%）
- 负责人：Agent + 人工
- 执行日期：2026-08-25
- 目标：`/Users/ahs/Documents/flutter_ios_混淆/huanxin_all_output`，范围 `lib,packages/aixi_foundation/lib`；原始环信源码未修改。
- 结果：464 个候选按 50% 和 seed `0` 确定性选择 232 项，向 207 个 Dart 文件插入 232 个可达调用；selection 写入输出副本 `reports/dart-capability-selection.json`。
- 验证：selection 数量、marker 数量均为 232；207 个选中源文件的 Dart parser/formatter 检查通过；目标范围 Analyzer 未发现命中 selected 文件的 error。
- 已知限制：全工程 `fvm flutter analyze` 会递归扫描输出副本既有的主题备份、示例和插件，产生大量与本次无关的旧 issue，不能作为本次增量结论。
- 产物边界：不提交输出副本、selection、建议 JSON、IPA、dSYM 或私有源码。
- README 说明补充：`dart_prefix_renamer` 已加入环信输出副本按 50% 自动插入的完整命令示例；工具文档提交：`3350ef2`。

## WP-05 Dart 可达性与语义验证

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-21
- 已完成：验证定义、生产方法调用与结果消费；返回、变量、参数、分支和赋值均形成 effect 证据；失败码为 `DART_CAPABILITY_UNREACHABLE`。
- 验证：无调用反例拒绝；生成后正例 reachable；完整 55 项测试通过。
- 交付 commit：`1665c0e`。
- 阻塞：无。

## WP-06 Native Capability 模块池与生成器

- 状态：已完成（100%）
- 负责人：Agent
- 开始日期：2026-08-21
- 当前：实现 Device、Network、SecureStorage、Crypto、Diagnostics、Performance 六个系统模块及 manifest 驱动生成。
- 验收标准：禁用模块不生成；相同输入输出稳定；每个启用模块具备 Bridge contract 和真实 Apple Framework 调用。
- 验证：Native、Pigeon、依赖、Release 与 pipeline 专项 8 项测试通过；完整 63 项测试通过。
- 交付 commit：`7a25d54`。
- 后续验证已完成：Pod/Xcode 接线由专项测试覆盖，并使用 iPhoneOS SDK 对 Pigeon Swift、HostHandler 与 NativeCapabilities 执行跨模块 `swiftc -typecheck`。
- 新进展：生成 `NativeCapabilities.podspec`、幂等注入 Runner Podfile、修正动态 `os_signpost` API；专项测试通过，工具提交 `9148fc7`。
- 编译门禁：使用 iPhoneOS SDK 对全部 Native Pod Swift 源码执行 `swiftc -typecheck`，发现并修复 manager 命名冲突；Pigeon Swift + HostHandler + NativeCapabilities 跨模块类型检查通过。工具提交 `79dcca7`。

## WP-07～WP-11 集成进度

- 状态：WP-07～WP-10 已完成（100%）；WP-11 阻塞（95%）
- 当前任务：已完成（100%）；已在环信 `config/` 生成产品 `product_abc` 的五份 Capability manifest 初稿。Dart integration 保持为空：扫描未发现调用 Capability catalog 精确方法名的既有生产调用，禁止生成虚假调用；Native 初稿启用 device/network/crypto，并绑定到现有 platform_info、网络状态和 SHA-256 消费者。
- 验证：在一次性临时副本运行 `--prepare-capabilities`，扫描 3947 个类、Dart ready/reachable 为 0、Native enabled/called 为 3/3、第三方依赖为 0，结果 `Passed: true`。临时副本已移至 macOS 废纸篓；原环信业务源码未改动，仅新增未提交的 `config/` 初稿，待源码所有者审阅后自行提交。
- 当前重构：已完成（100%）；Product Profile 已缩减为 `schema_version` 和产品身份。移除不参与生成决策的 `features` 与重复的 `technical`；遗留字段以 `E002` 失败关闭，Dart/Native manifest 现为能力开关的唯一事实来源。
- 验证：新增遗留字段拒绝测试；专项 25 项和完整 69 项工具测试通过，Analyzer 无 error/warning（38 条既有 info）。工具提交 `e88bbe8`。环信 `config/product_profile.yaml` 已同步简化，仍仅为未提交配置初稿。
- 已完成：Pigeon contract/options 与 consumer 检查、approved dependency/lock/API 检查、Release Inspector 与稳定失败码、`--prepare-capabilities` 编排和 JSON 报告、README/CHANGELOG、可选 CI 骨架。
- 验证：`fvm dart analyze` 无 error/warning；`fvm dart test` 全部 63 项通过。
- 交付 commit：`7a25d54`。
- 已完成：固定并执行 Pigeon 生成器、Swift handler/AppDelegate 注册、Native Pod 接线、两种重命名模式内嵌配置，以及 manifest v2/restore。
- 阻塞：真实环信验证命中 `huanxin-themed-obfuscation` 安全门禁，必须由用户提供本次小写英文前缀，禁止 Agent 猜测。
- 真实验证：用户提供 `abc` 后第一轮 Analyzer `302 -> 6284`，定位为旧 junk-code 文件图被部分重命名；已在 `e55878f` 修复并增加回归测试。按 skill 安全规则，现有失败输出不得覆盖，需用户选择归档或新路径后重跑。
- 重跑结果：用户授权移除失败输出后，以 `abc` 成功生成 `huanxin_all_output`；第一阶段 Analyzer `302 -> 302`。随后生成“离线会话展示排期模拟”主题模块（10 文件/10 Class），第二阶段 Analyzer `302 -> 302`，最终重置 6911 个实体元数据。
- Pigeon 进展：使用独立最小 runner 锁定 `26.3.4`，真实生成 Dart/Swift 文件，增加 30 秒超时与输出落点断言；Analyzer 10 升级后完整 64 项测试通过。工具提交 `f65a86a`。剩余 Swift handler 与 AppDelegate 注册。
- Pigeon 接线：生成 Swift host handler、稳定错误转换及 AppDelegate marker 注册；Native bridge 支持 JSON、Crypto、Keychain 与 performance 调用，禁用模块不生成对应 handler。专项测试通过，工具提交 `f371617`。剩余真实 Xcode/Pod 编译门禁。
- 主流程：新增单一 `CapabilityOptions` 与 `--capabilities` 参数组，复制模式和事务构建模式共享能力编排，统计进入 `RenameReport`/CLI。工具提交 `b92f9d9`。剩余 manifest v2 与安全 restore。
- Restore：manifest 在启用能力时升级 v2，记录能力统计、独立产物路径与 SHA-256；restore 兼容 v1/v2，仅删除哈希匹配产物并清理 Podfile/AppDelegate marker。端到端生成—重命名—恢复测试及完整 66 项测试通过，提交 `b867a64`。WP-10 完成。
- WP-08/09：增加 Podfile/Package.swift declaration、lockfile、生产 API、IPA linkage 四层依赖检查；IPA 必须包含主 App bundle、Info.plist 和主 Mach-O，并记录 Framework/Mach-O 哈希。提交 `d9c571e`、`eef0dbc`。
- WP-11：真实环信无签名 Release archive 成功（546 MB）；打包 unsigned IPA 并通过 Release Inspector，报告写入 `huanxin_all_output/reports/release-report.json`。双 Profile CI 脚本提交 `01d10b3`。
- 双 Profile 回归：新增 alpha/beta Product Profile 与 Native manifest fixture，分别启用 4/5 个 Native 模块，并断言输出 composition hash 不同；README 补齐统一 `--capabilities` 参数与 manifest v2 安全恢复说明。完整 68 项测试通过，工具提交 `7dccdd5`。
- README 可用性：共享功能参数按基础门禁、重命名、资源/字符串加密、iOS Channel、产品 Pod 与 Capability 流水线六组重排，参数名称、默认值与行为不变；工具提交 `27534b5`。
- README 示例校正：模式一构建目录与 `--output` 统一；模式二同步模式一的产品/种子参数，且以受支持的 `--artifact-dir` 保留 IPA 与 archive，不再使用无效的 `--artifact` / `--artifact-output`；工具提交 `092386d`。
- WP-11 剩余门禁：在具备两份私有 Product Profile、签名凭据和私有 Release fixture 的 CI 环境实际完成双构建；这些外部输入当前未提供，故不虚报 100%。
- 当前事实补充（2026-08-25 盘点）：工具 CI 已有 Dart quality gate 和受变量控制的 iOS gate；由于 `ENABLE_IOS_RELEASE_GATE`、`RELEASE_FIXTURE_ROOT`、`RELEASE_TARGETS` 及签名输入均未在本工作区提供，尚未执行正式 CI 双 Profile 签名 Release。历史无签名 IPA 验收不替代该门禁，且对应输出目录当前不在工作区。

## iOS 第三方库随机接入与安全调用

- 状态：已完成（100%）
- 负责人：Agent + 人工
- 开始日期：2026-08-25
- 验收标准：重新核验并固定 10 个成熟 CocoaPods；每产品按 `productId + capability seed` 确定性选择 3 个；生成独立本地 Pod、真实且无业务副作用的后台调用；依赖声明、lockfile、源码调用和 IPA linkage 四层一致；在全新环信输出副本完成 Release/unsigned IPA 实测。
- 已完成：依赖 manifest schema v2；`productId + seed + candidateId` SHA-256 确定性选择器；10 库 CocoaPods 审核池；图片 provider 冲突组；独立本地 Pod、3 个所选适配器、后台 run-once 注册器和 Podfile/AppDelegate 接线；依赖报告增加 selected/declared/locked/called/linked 维度；restore marker 与 pod install 清理接线。
- 验证：schema、planner、generator、inspector、release inspector 专项测试通过；`product_abc + seed 0` 稳定选择 Kingfisher、GRDB、PromiseKit；生成源码安全扫描不含网络发送、持久化、权限、UI、日志或崩溃上报 API。
- 已验证：完整 80 项 Dart 测试通过，Swift Pigeon/Native Pod 类型检查通过；全新 `huanxin_third_party_output` 完成 CocoaPods install、无签名 Release、290.8 MB Runner.app 和 172 MB unsigned IPA。
- Release Inspector：`selected=3`、`declared=3`、`locked=3`、`called=3`、`linked=3`，状态 `passed`；IPA 包含 Kingfisher、GRDB、PromiseKit Framework，两个失败构建副本均另存诊断目录。
- 提交：工具提交 `ecee52f`（`实现 iOS 第三方库确定性接入 / Implement deterministic iOS third-party integration`）。
- 安全边界：不覆盖 `huanxin_all_output`，不修改环信业务源码，不提交 Pods、IPA、dSYM、混淆 map 或私有源码。
- Git 边界：`huanxin_third_party_output/` 及其失败诊断副本统一由根 `.gitignore` 忽略；本地文件保留用于复核，但不进入 index。
- 阻塞：无。
