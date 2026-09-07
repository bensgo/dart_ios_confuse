## Unreleased

- Expand the reviewed third-party iOS CocoaPods pool from 10 to 15 and add offline probes for SwiftyJSON, ObjectMapper, DifferenceKit, SwiftSoup, and Swinject.
- Allow deterministic third-party SDK selection counts from 1 through 10; retain image-provider conflict exclusion.
- Separate Dart automation, custom iOS Pods, and third-party SDK Pods into clearly named entry points.
- Add `--prepare-ios-third-party-sdk-pods` without Dart/Native manifest or Product Profile requirements.
- Add canonical `--ios-custom-pod-*` options; keep `--ios-product-*` as hidden compatibility aliases.
- Add deterministic per-product local iOS source Pod generation.
- Integrate generated Pods into Podfile and AppDelegate with safe restore markers.
- Add an offline Dart MethodChannel client, product manifests, reports, and transactional-build support.
- Add full Dart capability suggestion scans and reusable percentage-based insertion selections.
- Add dedicated Manager, Logic, and Widget capability templates.

## 1.0.0

- Initial version.
# Unreleased

- 将审核 iOS 第三方 CocoaPods 候选池从 10 扩至 15，新增 SwiftyJSON、ObjectMapper、DifferenceKit、SwiftSoup 和 Swinject 的离线 probe。
- 第三方 SDK 的确定性选择数量改为允许 1–10，图片库冲突互斥规则保持不变。
- 增加 schema v2 的 10 个审核 CocoaPods 候选池与确定性 3 库选择。
- 增加安全后台 run-once Swift 探针、本地 ThirdPartyKit Pod 和幂等启动接线。
- 增加 selection、lock、真实 API token、IPA linkage 报告及 hash-safe restore。
- 增加 Product Profile、Dart/Native capability、依赖清单和 iOS library pool 的 schema 与严格解析。
- 增加 Analyzer 能力扫描、确定性规划、真实调用生成和可达性验证。
- 增加六类系统 Native Capability、Pigeon contract、依赖用途检查和 Release Inspector。
- 增加 `--prepare-capabilities`、能力子报告和稳定 failure code；旧重命名命令保持兼容。
- 明确 `--junk-code` 为 legacy/non-compliant，不参与能力报告。
