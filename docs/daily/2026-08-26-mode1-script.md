# 日报补充 · 2026-08-26

## 模式一完整流程脚本

- 新增可执行脚本：`scripts/run_mode1_product_abc.sh`。
- 脚本顺序执行源码副本、50% Dart 自动能力、7 个第三方 SDK Pod、无签名 Release、unsigned IPA 和 linkage 验证。
- 默认输出为 `huanxin_mode1_product_abc_output`；输出目录已存在时立即停止，避免覆盖。
- 支持环境变量：`HUANXIN_PROJECT`、`MODE1_OUTPUT_DIR`、`IOS_THIRD_PARTY_PRODUCT_ID`、`IPA_OUTPUT_DIR`、`SYMBOL_OUTPUT_DIR`。
- 验证：`bash -n`、ShellCheck（环境可用时）和 `git diff --check` 通过。
- 工具文档提交：`5625e1e`；根脚本与项目文档提交待完成。
