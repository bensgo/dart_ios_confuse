# Agent 工作说明

本项目是 Flutter/iOS 工程差异化与 `dart_prefix_renamer` 工具工作区。开始任何任务前，Agent 必须先阅读本文件、[工程总览](docs/project-overview.md)、[工作计划](docs/work-plan.md)、[工作进度](docs/work-progress.md)，以及 [dart_prefix_renamer README](dart_prefix_renamer/README.md)。README 是命令参数、模式边界、构建方式和安全约束的主要事实来源。

## 混淆目标工程

**混淆目标工程是 huanxin（环信）**：

- 源码路径：`/Users/ahs/Documents/work/code/huanxin`
- 类型：Flutter iOS 工程，包含 Pub Workspace（根 App + 多个成员 Package）
- 成员 Package：`aixi_foundation`、`aixi_app_config`、`aixi_event_logger`、`aixi_design_system`、`aixi_ui`、`aixi_network`、`aixi_platform_bridge`、`aixi_logging`、`aixi_media`、`aixi_audio`、`aixi_im`、`aixi_rtc`、`aixi_gift`、`aixi_feedback` 等
- 已接入运行时：`EncryptedAssetBundle`、`StringCipherRuntime`（见 dart_prefix_renamer README 环境要求）
- 构建产物输出约定目录：`/Users/ahs/Documents/flutter_ios_混淆/huanxin_*_output`、`/Users/ahs/Documents/flutter_ios_混淆/ipa/product_*`、`/Users/ahs/Documents/flutter_ios_混淆/symbols/product_*`

## 协作与 skill 管理

本项目采用 [agent-human-collaboration](https://github.com/bensgo/agent-human-collaboration) 的协作流程。远程仓库当前不可访问时，以本地协作 skill 和本项目文档为准，并在进度中记录 `missing` / `unavailable`，不得猜测远程内容。

Agent 必须：

1. 开始前检查 `git status`，确认任务包、负责人、开始日期和验收标准。
2. 将任务标记为“开发中（0%）”，每完成一个可验证子项就更新工作进度。
3. 需要选择方案时给出选项和推荐项；方向确认等待超过 10 分钟可按推荐项继续，并记录假设。
4. 不提交 IPA、dSYM、混淆 map、凭证、私有源码或敏感日志。
5. 结束前执行相称的测试/检查，更新进度和当天日报，并记录 commit hash。
6. Git 提交信息使用“中文说明 / English summary”格式。

## 工作边界

- 未经明确授权，不覆盖或删除用户已有输出，不修改与当前任务无关的脏工作树。
- 修改混淆工具前，先阅读 `dart_prefix_renamer/README.md` 和相关测试。
- 运行命令时优先使用 FVM；涉及真实 Flutter 工程时先确认输入目录和输出目录。
- 产物、符号文件和临时文件应放在项目约定目录，不把敏感构建产物纳入 Git。
