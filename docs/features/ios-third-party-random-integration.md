# iOS 第三方 SDK Pod 随机接入与安全调用

## 目标

在隔离输出副本中，从经过审核的 iOS CocoaPods 候选池中，为每个产品确定性选择 1–10 个库，生成本地 Pod、真实 API 调用和二进制验证证据。

目的不是给业务增加网络或 UI 功能，而是在不影响业务逻辑的前提下，形成可复现的第三方依赖组成与安全调用链。

## 能力与安全边界

- 当前候选池包含 15 个审核通过的 CocoaPods：Kingfisher、SDWebImage、Alamofire、GRDB.swift、ZIPFoundation、SwiftProtobuf、CryptoSwift、DeviceKit、PromiseKit、SwifterSwift、SwiftyJSON、ObjectMapper、DifferenceKit、SwiftSoup、Swinject。
- 选择排序为 `SHA-256(productId|capabilitySeed|candidateId)`；相同输入稳定复现。
- 每个产品可选择 1–10 个，并处理冲突组（例如 Kingfisher 与 SDWebImage 不同时入选）。
- 新增 5 个 probe 均使用固定内存输入：JSON 读取、Map 构造、数组差分、HTML 字符串解析和依赖容器解析；不发送请求、不持久化、不修改 UI。
- 启动后在 utility 队列执行一次 run-once probe，只保留线程安全的内存摘要。
- probe 只执行离线 API：例如内存 GRDB 查询、本地 URLRequest 编码、固定文本 SHA-256、已完成 Promise 转换。
- 禁止网络发送、权限请求、持久化数据库、UserDefaults、Keychain、设备标识、UI 改动、Flutter Channel 回传、日志和分析 SDK。

## 前置条件

该功能使用独立流水线，只需要：

```text
config/dependencies.yaml
config/ios_library_pool.yaml
```

其中 `dependencies.yaml` 必须启用 schema v2 的确定性随机选择；`ios_library_pool.yaml` 必须包含审核状态、版本、模块名、probe 模板、二进制 token 和冲突组等候选信息。产品 ID 和 seed 由命令行传入；Dart 与 Native capability 配置不属于此功能。

## 最小配置示意

`config/dependencies.yaml`：

```yaml
schema_version: 2
selection:
  enabled: true
  mode: deterministic_random
  count: 7 # 支持 1-10
  execution: startup_background_once
  candidates:
    - kingfisher
    - sdwebimage
    - alamofire
    - grdb
    - zipfoundation
    - swiftprotobuf
    - cryptoswift
    - devicekit
    - promisekit
    - swifterswift
    - swiftyjson
    - objectmapper
    - differencekit
    - swiftsoup
    - swinject
dependencies: {}
```

随机模式不能与 `dependencies` 中的显式依赖混用。未知、未审核、非 CocoaPods、重复候选、`count` 不在 1–10、或冲突后候选不足都会在写文件前失败关闭。

## 使用方式

先在新输出副本中完成模式一复制，随后执行能力流水线：

```bash
cd /Users/ahs/Documents/flutter_ios_混淆/dart_prefix_renamer

fvm dart run bin/dart_prefix_renamer.dart \
  --prepare-ios-third-party-sdk-pods \
  --project=/absolute/path/to/huanxin_third_party_output \
  --ios-third-party-sdk-product-id=product_abc \
  --ios-third-party-sdk-dependencies=config/dependencies.yaml \
  --ios-third-party-sdk-library-pool=config/ios_library_pool.yaml \
  --ios-third-party-sdk-report-dir=reports/ios-third-party-sdk-pods \
  --ios-third-party-sdk-seed=0
```

生成器会在输出副本中执行 `pod install --project-directory=ios`。失败会回滚本次写入的 Podfile/AppDelegate 与本地 Pod，原始工程不受影响。

## 生成物与报告

```text
ios/LocalPods/<ProductId>ThirdPartyKit/
├── <ProductId>ThirdPartyKit.podspec
├── Sources/<ProductId>ThirdPartyKitRuntime.swift
├── Sources/<SelectedLibrary>Probe.swift
└── third_party_manifest.json

reports/ios-third-party-sdk-pods/
├── selection.json
└── integration-report.json
```

报告记录候选排序分数、选中/跳过原因、源文件哈希、API token，以及 `selected`、`declared`、`locked`、`called`、`linked` 计数。

## Release 验证

构建 IPA 后再次运行同一命令并增加：

```bash
--verify-ios-third-party-sdk-pods \
--ios-third-party-sdk-release-artifact=/absolute/path/to/app.ipa
```

Release Inspector 校验 IPA Framework/Mach-O linkage，并将 linkage 结果写入 `dependency-report.json` 和 `release-report.json`。验收目标为：

```text
selected=declared=locked=called=linked=<count>
status=passed
```

## 恢复与当前验证状态

- capability manifest v2 记录生成文件哈希；restore 仅删除哈希未变化的生成物并移除专用 marker。
- 历史环信无签名验证曾选择 Kingfisher、GRDB.swift、PromiseKit，并达到五项计数均为 3；盘点时对应输出目录不在工作区，需要重新生成才可再次复查。
- 正式双 Profile 签名 CI Release Gate 仍需私有 Profile、签名凭据和 CI fixture。
