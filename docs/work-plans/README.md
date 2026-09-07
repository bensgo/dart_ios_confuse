# 详细工作计划目录

本目录存放可由其他 Agent 直接执行的详细设计。执行前仍须先阅读项目根目录 `AGENTS.md`、工程总览、工作计划、工作进度、最新日报和目标工具 README。

| 计划 | 状态 | 入口 | 影响范围 |
|---|---|---|---|
| Flutter + iOS Release 差异化工程 | 已实施；正式 CI 门禁阻塞（95%） | [详细设计](release-differentiation/README.md) | `dart_prefix_renamer` CLI、处理管线、Dart/Native Capability、Release 验证 |

当前仅剩两份私有 Product Profile、签名凭据和可在 CI 使用的 Release fixture 未提供；详见[工作计划](../work-plan.md)的“未完成项与解除条件”。

## 执行规则

1. 一个 Agent 一次只领取一个无重叠工作包；开始前在 `docs/work-progress.md` 登记负责人和 0% 状态。
2. 工作包必须按详细设计中的依赖顺序实施；缺少前置产物时记录 `missing`，不能用临时硬编码绕过。
3. 每个工作包都必须包含实现、单元/集成测试、README 更新和 manifest/report 证据。
4. 涉及第三方库调研时必须重新在线核验，附件中的版本与维护状态只作为历史输入。
5. 不允许把随机垃圾代码、仅 import、仅注册、测试专用调用或 `vm:entry-point` 标记当成生产可达性证据。
