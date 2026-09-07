# 工作计划

## 当前工作包

| 工作包 | 状态 | 负责人 | 开始日期 | 验收标准 |
|---|---|---|---|---|
| 发布本地工具库到 GitHub | 已完成（100%） | Agent | 2026-09-07 | 目标仓库可访问；公开分支包含可发布源码；排除 IPA、dSYM、symbols、混淆 map、私有源码、敏感日志和本地构建输出；远端克隆与内容检查通过 |
| 建立 Agent 协作与 skill 管理流程 | 已完成（100%） | Agent + 人工 | 2026-08-21 | Agent 必读入口、skill 管理规则、计划/进度/日报齐全，文档检查通过 |
| Release 差异化工程详细设计 | 已完成（100%） | Agent + 人工 | 2026-08-21 | 形成带目录、依赖顺序、`dart_prefix_renamer` 功能增量和逐项验收标准的可执行计划 |
| Dart 候选类分类扩展 | 已完成（100%） | Agent + 人工 | 2026-08-24 | Utility、Manager、Logic 分类、候选统计和完整扫描 JSON 均可复现 |
| Dart 百分比自动能力插入 | 已完成（100%） | Agent + 人工 | 2026-08-24 | 全量建议 JSON、可复用选择配置、安全源码插入和 Analyzer 回归通过 |
| Manager/Logic/Widget Capability 模板 | 已完成（100%） | Agent + 人工 | 2026-08-25 | 三类均具备专属建议、可达调用、源码定义与完整回归 |
| iOS 第三方库随机接入与安全调用 | 已完成（100%） | Agent + 人工 | 2026-08-25 | 10 库审核池、每产品确定性选择 3 个、CocoaPods 源码接入、安全后台调用、环信 Release/IPA 实测通过 |
| 全项目状态盘点与文档校准 | 已完成（100%） | Agent + 人工 | 2026-08-25 | 已核对代码、Git、测试、CI 和输出证据；已统一当前事实、未完成项、边界和后续验收条件 |
| 模式一完整示例纳入 Dart 自动能力插入 | 已完成（100%） | Agent | 2026-08-25 | README 的模式一完整示例明确包含 50%、seed 0 的 `--auto-dart-capabilities` 后续步骤，且路径、目标范围和构建顺序一致 |
| 模式二完整示例纳入 Dart 自动能力插入 | 已完成（100%） | Agent | 2026-08-25 | 事务构建在临时副本中执行 50%、seed 0 的自动插入，完整示例及 CLI 行为一致，原工程不被修改 |
| Dart、自定义 Pod 与第三方 SDK Pod 解耦 | 已完成（100%） | Agent | 2026-08-25 | 三类功能拥有清晰独立入口和命名；第三方 Pod 不再依赖 Dart/Native manifest；兼容删除清单、README、专项测试和完整回归一致 |
| 工具文档拆分为功能与完整模式用法 | 已完成（100%） | Agent | 2026-08-25 | `README.md` 仅包含功能/参数/单项用法；`USAGE.md` 仅包含完整模式一、模式二流程；链接、代码围栏与 CLI 参数核验通过 |
| iOS 第三方 SDK Pod 候选池扩容与数量范围 | 已完成（100%） | Agent + 人工 | 2026-08-26 | 新增 5 个已审核 CocoaPods、安全 probe 调用生成；`count` 接受 1–10；配置、测试和文档一致 |
| 模式一完整流程脚本 | 已完成（100%） | Agent | 2026-08-26 | 一个可执行脚本串联模式一副本、Dart 能力、7 个第三方 Pod、无签名 IPA 和 linkage 验证，并拒绝覆盖已有输出 |

## Release 差异化工程实施总表

完整设计、文件落点和测试矩阵见 [Release 差异化工程详细设计](work-plans/release-differentiation/README.md)。其他 Agent 不得跳过前置质量门禁直接实施后续阶段。

| 阶段 | 工作包 | 依赖 | 状态 | 核心交付 |
|---|---|---|---|---|
| P0 | WP-00 基线、fixture 与配置契约 | 无 | 已完成（100%） | 可复现测试工程、schema、失败关闭规则 |
| P1 | WP-01 Product Profile 与 Manifest 解析 | WP-00 | 已完成（100%） | 强类型配置、路径与语义校验 |
| P1 | WP-02 第三方库在线调研与候选池 | WP-01 | 已完成（100%） | 带证据、时间戳和批准状态的 library pool |
| P2 | WP-03 Dart 扫描、职责分类与能力规划 | WP-01 | 已完成（100%） | Analyzer 扫描报告、确定性 capability plan |
| P2 | WP-04 Dart Capability 生成与真实调用接线 | WP-03 | 已完成（100%） | 首批 10 个模板、显式生产调用锚点 |
| P2 | WP-05 Dart 可达性与语义验证 | WP-04 | 已完成（100%） | 定义—调用—业务影响证据链 |
| P3 | WP-06 Native Capability 模块池与生成器 | WP-01 | 已完成（100%） | 6 个 Apple Framework MVP 模块 |
| P3 | WP-07 Pigeon Bridge 与业务调用接线 | WP-06 | 已完成（100%） | Dart—Pigeon—Swift—系统能力真实链路 |
| P3 | WP-08 第三方依赖选择、接入与检查 | WP-02、WP-06 | 已完成（100%） | 锁定版本、用途记录、真实 API 调用检查 |
| P4 | WP-09 Release Inspector 与二进制验证 | WP-05、WP-07、WP-08 | 已完成（100%） | 统一 release report 与失败门禁 |
| P4 | WP-10 CLI、主处理管线、manifest 与 restore 集成 | WP-03～WP-09 | 已完成（100%） | `prepare` / `verify-release` 及两模式兼容 |
| P5 | WP-11 CI、回归、文档与迁移 | WP-10 | 阻塞（95%） | 工具回归、README、CI 骨架与本机无签名证据已完成；等待私有双 Profile、签名凭据和 CI Release fixture 运行正式门禁 |

## 未完成项与解除条件

| 项目 | 当前状态 | 已有证据 | 解除条件 |
|---|---|---|---|
| 环信 Dart Capability 真实接线 | 阻塞（0/10） | `config/dart_capabilities.yaml` 为 `rules: {}`、`integrations: []`；历史实测 `Dart ready/reachable=0`，未生成虚假调用 | 源码所有者确认 10 个可接受的真实业务方法与效果；补齐 integration、生成代码并在新的输出副本验证可达性 |
| WP-11 格式门禁 | 已完成 | 全量格式化已修正原有 9 个文件；82 项工具测试通过；Analyzer 无 error/warning | 无 |
| WP-11 正式 CI Release Gate | 阻塞（95%） | 80 项工具测试、Native/Pigeon Swift typecheck、历史本机无签名 IPA/Inspector 记录 | 配置私有 CI 变量、两份 Product Profile、签名凭据和 Release fixture；实际运行两份签名 Release 并校验报告差异 |
| 环信输出副本复现 | 未开始（按需） | 历史 `huanxin_all_output` 与 `huanxin_third_party_output` 验收记录 | 选择新的不存在输出路径，从原始环信重新运行；输出已被 Git 忽略 |

## Skill 管理规则

1. 用户明确指定的 skill 必须先读取完整 `SKILL.md`，再执行任务。
2. 任务命中可用 skill 时，Agent 在开始工作时说明使用原因，并遵守其工具路由和安全约束。
3. 远程 skill/仓库先验证 URL、仓库存在性和 README；读取失败记录为 `unavailable`，不得伪造安装成功。
4. 新增或调整本地 skill 时，必须同时说明触发条件、输入输出、边界、验证方式和回滚方式。
5. skill 只提供流程和工具约束；项目事实仍以 `AGENTS.md`、工程总览、工作计划、工作进度和最新日报为准。
6. 任何 skill 导致的实质文件变更都要在工作进度和日报中记录。
