# iOS 自定义 Pod 与第三方 SDK Pod 的区别

## 结论

这是两个独立功能，可以单独使用，也可以在同一个输出副本中同时启用。产品 Pod 生成产品专属的离线本地模块；第三方库随机接入生成并验证确定性选择的 CocoaPods 组合。它们都使用 Podfile/AppDelegate marker，但 marker、目录、运行时和恢复范围各自独立。

| 对比项 | iOS 自定义 Pod | iOS 第三方 SDK Pod |
|---|---|---|
| 核心目标 | 形成产品专属的本地配置、展示规则和资源校验模块 | 形成可复现的第三方 CocoaPods 组合及真实离线 API 调用证据 |
| 启用入口 | 主命令的 `--ios-custom-pod` | 独立 `--prepare-ios-third-party-sdk-pods` 流水线 |
| 配置来源 | CLI：产品 ID、主题、seed | CLI 产品 ID/seed，以及 `dependencies.yaml`、`ios_library_pool.yaml` |
| 候选/主题 | 3 个内置主题 | 15 个审核 CocoaPods 候选，确定性选 1–10 个 |
| 生成语言 | Objective-C + Dart 客户端 + JSON 资源 | Swift + 本地 Pod + JSON 选择 manifest |
| App 启动行为 | 注册 MethodChannel，并校验本地 bundle 资源 | utility 队列后台一次 probe，只保存内存摘要 |
| Flutter 通信 | 生成可由业务主动调用的 MethodChannel 客户端 | 不向 Flutter、日志或分析 SDK 回传 probe 结果 |
| 外部依赖 | 仅 Flutter、Foundation | 所选 CocoaPods + 本地 ThirdPartyKit Pod |
| 网络/权限/持久化 | 不使用 | 不使用 |
| 验证重点 | 生成确定性、marker 接线、资源与 restore | 选择稳定、Podfile.lock、真实 API token、IPA linkage |
| 恢复 | 删除产品 Pod、Dart client 和自身 marker | 删除 ThirdPartyKit、自身 marker，并重新安装 Pods |

## 选择建议

仅需要产品差异化的本地模块时，使用产品 Pod：

```text
--ios-custom-pod + --ios-custom-pod-id + （可选）theme/seed
```

需要可审计的第三方依赖组成和 IPA 中的库链接证据时，使用第三方库随机接入：

```text
--prepare-ios-third-party-sdk-pods + product-id + dependencies.yaml + ios_library_pool.yaml
```

需要两者时，先生成模式一输出副本并启用自定义 Pod，再在同一输出副本运行 `--prepare-ios-third-party-sdk-pods`。不要对同一输出副本重复执行首次复制命令；输出目录必须被 Git 忽略。

## 不应混淆的事项

- 产品 Pod 不是第三方库候选池的一个候选，也不会随机挑选 CocoaPods。
- 第三方 probe 不是产品业务模块，不会把结果传给 Flutter 或改变 UI。
- 两者都不替代环信真实 Dart Capability 接线；当前该接线仍需源码所有者确认业务锚点后实施。
- 本机无签名 IPA 检查可证明编译和结构，不替代正式双 Profile 签名 CI Release Gate。
