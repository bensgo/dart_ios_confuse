# 目标：
**Dart：**根据类职责补充真实可解释的辅助能力；新增能力必须至少存在一条真实生产调用链，并通过 Release AOT 验证，不允许单纯使用死代码或伪造调用来保持代码。

**iOS：**维护 Native Capability 模块池，每个 App 根据实际 feature manifest 选择对应模块；第三方依赖必须存在真实功能用途和真实调用路径，版本由 lockfile 固定，不允许随机修改依赖版本。

# Flutter + iOS Release 差异化工程方案

## 1. 目标

建立一套可重复执行的 Flutter / iOS 工程增强机制，使不同产品根据自身功能自然形成不同的：

* Dart 代码结构
* AOT 调用图
* Native 模块组成
* iOS Framework / Library 依赖
* Flutter ↔ Native 调用关系

所有新增代码和依赖必须满足：

1. 存在真实用途；
2. 存在真实生产调用路径；
3. Release 构建中实际保留；
4. 能解释为什么存在；
5. 不允许纯 dead code；
6. 不允许为了产生二进制差异随机引入无关依赖；
7. 第三方库版本固定，可复现；
8. 能通过自动化工具验证。

---

# 2. 总体架构

```text
Project
│
├── lib/
│   ├── core/
│   ├── features/
│   ├── shared/
│   └── platform/
│
├── ios/
│   ├── Runner/
│   └── NativeCapabilities/
│
├── config/
│   ├── dart_capabilities.yaml
│   └── native_capabilities.yaml
│
├── tools/
│   ├── dart_capability_generator/
│   ├── native_capability_generator/
│   ├── call_graph_checker/
│   ├── dependency_checker/
│   └── release_inspector/
│
└── reports/
    ├── dart-capability-report.json
    ├── native-capability-report.json
    └── release-report.json
```

整体流程：

```text
项目源码
   ↓
分析 Dart 类
   ↓
根据类职责生成/选择辅助能力
   ↓
建立真实调用路径
   ↓
读取 Native Feature Manifest
   ↓
启用对应 Native Capability
   ↓
生成 Flutter ↔ Native Bridge
   ↓
Release Build
   ↓
验证 Dart AOT
   ↓
验证 Native Binary
   ↓
验证 Dependency
   ↓
生成 Release Report
```

---

# 3. Dart 层设计

## 3.1 原则

不采用：

```text
每个类强制增加一个随机方法
```

而采用：

```text
根据类的职责，
从对应 Capability Pool 中选择适合的真实能力。
```

例如：

```text
Repository
→ cache
→ validation
→ request context
→ response normalization

Service
→ health check
→ retry policy
→ request metadata
→ input sanitation

Controller
→ state validation
→ analytics context
→ lifecycle diagnostics

Model
→ normalize
→ validate
→ serialization helper
→ debug summary

Widget
→ accessibility
→ presentation normalization
→ layout metadata
```

---

# 4. Dart Capability Pool

建议第一版准备 20～30 个能力模板。

## 4.1 Repository

### Cache Key

```dart
String buildCacheKey(String id) {
  return '${runtimeType.toString()}:${id.trim().toLowerCase()}';
}
```

真实调用：

```dart
Future<User?> loadUser(String id) async {
  final key = buildCacheKey(id);

  final cached = await cache.get(key);

  if (cached != null) {
    return cached;
  }

  return api.fetchUser(id);
}
```

---

## 4.2 Cache Validation

```dart
bool isCacheValid(User user) {
  if (user.id.isEmpty) {
    return false;
  }

  final updatedAt = user.updatedAt;

  return DateTime.now()
      .difference(updatedAt)
      .inMinutes < 30;
}
```

调用：

```dart
if (cached != null && isCacheValid(cached)) {
  return cached;
}
```

---

# 5. Service Capability

例如：

```dart
Map<String, String> buildRequestMetadata() {
  return {
    'client_time':
        DateTime.now().millisecondsSinceEpoch.toString(),
    'source': runtimeType.toString(),
  };
}
```

业务调用：

```dart
Future<Response> request() {
  return api.request(
    headers: buildRequestMetadata(),
  );
}
```

---

# 6. Model Capability

例如：

```dart
bool validate() {
  return id.isNotEmpty &&
      name.trim().isNotEmpty;
}
```

真实使用：

```dart
final user = User.fromJson(json);

if (!user.validate()) {
  throw InvalidUserException();
}
```

---

# 7. Controller Capability

例如：

```dart
Map<String, Object?> buildAnalyticsContext() {
  return {
    'screen': runtimeType.toString(),
    'state': state.runtimeType.toString(),
  };
}
```

调用：

```dart
analytics.track(
  'page_open',
  buildAnalyticsContext(),
);
```

---

# 8. Capability 分配规则

建议配置：

```yaml
dart_capabilities:

  repository:
    min: 1
    max: 3

    allowed:
      - cache_key
      - cache_validation
      - response_normalizer
      - request_context

  controller:
    min: 1
    max: 2

    allowed:
      - analytics_context
      - state_validation
      - lifecycle_diagnostics

  model:
    min: 0
    max: 2

    allowed:
      - validate
      - normalize
      - debug_summary

  service:
    min: 1
    max: 3

    allowed:
      - request_metadata
      - input_sanitizer
      - health_check
```

注意：

这里的选择不是完全随机。

应该同时考虑：

```text
类名称
类职责
已有成员
已有依赖
业务上下文
```

---

# 9. Dart 类扫描

工具：

```text
tools/dart_capability_generator
```

建议使用 Dart Analyzer API。

流程：

```text
扫描 lib/
 ↓
构建 AST
 ↓
识别 ClassDeclaration
 ↓
判断类类型
 ↓
检测已有方法
 ↓
匹配 Capability
 ↓
生成建议
```

示例输出：

```json
{
  "class": "UserRepository",
  "type": "repository",
  "suggestions": [
    "cache_key",
    "cache_validation"
  ]
}
```

---

# 10. Capability 决策

不要使用：

```dart
Random()
```

直接随机。

建议使用：

```text
Project Profile
+
Class Type
+
Existing Dependencies
+
Feature Configuration
```

进行 deterministic selection。

例如：

```text
UserRepository
→ cache_validation
→ cache_key

ProductRepository
→ response_normalizer
→ request_context

MessageRepository
→ deduplication
→ cache_validation
```

这样同一代码版本：

```text
每次构建结果一致
```

不会造成 CI 无法复现。

---

# 11. Dart 新增代码验收标准

一个 Capability 要进入正式工程必须满足：

```text
定义
 ↓
至少一个生产调用
 ↓
调用结果影响业务逻辑 / 日志 / 状态 / 数据处理
 ↓
Release AOT 可达
```

禁止：

```dart
void fakeCall() {
  generatedMethod();
}
```

然后：

```dart
fakeCall();
```

只为了形成调用关系。

---

# 12. 推荐增加 Capability Registry

```dart
abstract interface class AppCapability {
  String get name;

  bool get enabled;

  Map<String, Object?> diagnostics();
}
```

例如：

```dart
class NetworkCapability
    implements AppCapability {

  @override
  String get name => 'network';

  @override
  bool get enabled => true;

  @override
  Map<String, Object?> diagnostics() {
    return {
      'enabled': enabled,
      'checkedAt':
          DateTime.now().toIso8601String(),
    };
  }
}
```

---

# 13. Native 层设计

建立：

```text
ios/NativeCapabilities/
```

第一版建议准备 10 个 Capability。

```text
NativeCapabilities
│
├── Device/
├── Network/
├── Security/
├── Storage/
├── Image/
├── Logging/
├── Compression/
├── Crypto/
├── Performance/
└── Diagnostics/
```

---

# 14. 10 个 Native Capability

## Capability 1：Device Information

优先：

```text
UIDevice
ProcessInfo
```

功能：

```text
系统版本
设备类型
Low Power Mode
内存信息
Locale
```

Flutter：

```dart
final info =
    await nativeDevice.deviceInfo();
```

---

# 15. Capability 2：Network Diagnostics

使用：

```text
Network.framework
NWPathMonitor
```

功能：

```text
Wi-Fi / Cellular
是否在线
Expensive Network
Constrained Network
```

Flutter：

```dart
final network =
    await nativeNetwork.currentStatus();
```

---

# 16. Capability 3：Secure Storage

优先：

```text
Security.framework
Keychain
```

或者确实需要时：

```text
KeychainAccess
```

用途：

```text
Token
Device Identifier
敏感配置
```

---

# 17. Capability 4：Image Processing

系统能力：

```text
CoreImage
ImageIO
```

或者：

```text
SDWebImage
Kingfisher
```

真实用途：

```text
图片缓存
缩略图
图片格式转换
压缩
```

---

# 18. Capability 5：Compression

可以使用：

```text
Compression.framework
```

或：

```text
ZIPFoundation
```

用途：

```text
离线资源包
日志归档
缓存压缩
文件下载
```

---

# 19. Capability 6：Logging

优先：

```text
os.Logger
```

如果项目确实需要：

```text
CocoaLumberjack
```

真实用途：

```text
Native Error
Flutter Bridge Error
Network Error
Performance Event
```

---

# 20. Capability 7：Crypto

使用：

```text
CryptoKit
```

用途：

```text
SHA256
HMAC
缓存完整性
文件校验
```

例如：

```swift
func sha256(
    _ data: Data
) -> String
```

Flutter 可用于：

```text
文件下载完整性验证
```

---

# 21. Capability 8：Database

项目需要时使用：

```text
SQLite
GRDB
```

用途：

```text
Native缓存
离线数据
事件队列
```

不需要数据库的项目不要强制添加。

---

# 22. Capability 9：Performance

使用：

```text
MetricKit
os_signpost
ProcessInfo
```

用途：

```text
Launch Metrics
Memory
Critical Hang
Native操作耗时
```

Flutter：

```dart
await nativePerformance.mark(
  'home_load',
);
```

---

# 23. Capability 10：Diagnostics

系统能力：

```text
Bundle
ProcessInfo
FileManager
```

用途：

```text
App Version
Build Number
Available Storage
Cache Size
Runtime Information
```

例如：

```dart
final diagnostics =
    await nativeDiagnostics.snapshot();
```

---

# 24. 第三方库候选池

第一版可以维护：

```text
1. Alamofire
2. Kingfisher
3. SDWebImage
4. KeychainAccess
5. GRDB
6. ZIPFoundation
7. CocoaLumberjack
8. SwiftProtobuf
9. Reachability.swift
10. Starscream
```

但是：

**这不是每个 App 随机选 5 个。**

而是：

```text
业务需要什么
→ 使用什么
```

例如 IM App：

```text
Starscream
GRDB
KeychainAccess
Kingfisher
CocoaLumberjack
```

内容类 App：

```text
Kingfisher
ZIPFoundation
KeychainAccess
GRDB
Alamofire
```

工具类 App：

```text
ZIPFoundation
KeychainAccess
GRDB
CocoaLumberjack
```

允许数量不同。

---

# 25. Native Feature Manifest

建立：

```text
config/native_capabilities.yaml
```

示例：

```yaml
native:

  device:
    enabled: true

  network:
    enabled: true

  secure_storage:
    enabled: true

  image:
    enabled: true
    provider: kingfisher

  compression:
    enabled: false

  database:
    enabled: true
    provider: grdb

  logging:
    enabled: true
    provider: os_logger

  crypto:
    enabled: true

  performance:
    enabled: true

  diagnostics:
    enabled: true
```

---

# 26. Dependency Manifest

单独维护：

```yaml
dependencies:

  Kingfisher:
    version: "8.0.0"
    reason: image_cache

  GRDB:
    version: "7.0.0"
    reason: native_database
```

最终具体版本应由当前项目经过验证后锁定。

不要：

```text
每次 build 自动改变版本。
```

---

# 27. Flutter ↔ iOS Bridge

推荐：

```text
Pigeon
```

优先于大量手写 MethodChannel。

目录：

```text
pigeons/
   native_api.dart
```

示例：

```dart
@HostApi()
abstract class NativeDiagnosticsApi {

  @async
  Map<String, String> deviceInfo();

  @async
  String sha256(Uint8List data);

  @async
  NetworkState networkState();
}
```

生成：

```text
Dart
+
Swift
```

Bridge。

---

# 28. Native Capability Manager

Swift：

```swift
final class NativeCapabilityManager {

    let network:
        NetworkCapability

    let secureStorage:
        SecureStorageCapability

    let diagnostics:
        DiagnosticsCapability

    init() {
        network =
            NetworkCapability()

        secureStorage =
            SecureStorageCapability()

        diagnostics =
            DiagnosticsCapability()
    }
}
```

---

# 29. Flutter Platform Service

Flutter：

```dart
class PlatformService {

  PlatformService(
    this._api,
  );

  final NativeDiagnosticsApi _api;

  Future<bool>
      isNetworkAvailable() async {

    final status =
        await _api.networkState();

    return status.available;
  }
}
```

业务层：

```dart
if (!await platformService
    .isNetworkAvailable()) {

  emit(
    const AppState.offline(),
  );

  return;
}
```

形成：

```text
UI
 ↓
Controller
 ↓
UseCase
 ↓
PlatformService
 ↓
Pigeon
 ↓
Swift
 ↓
NWPathMonitor
```

完整真实调用路径。

---

# 30. Native 模块注册

不要把所有模块都初始化。

根据 Manifest 生成：

```swift
struct AppNativeFeatures {

    static let network = true

    static let secureStorage = true

    static let database = false

}
```

然后：

```swift
if AppNativeFeatures.network {
    registerNetworkCapability()
}
```

---

# 31. 第三方依赖真实调用检查

例如 Kingfisher。

不能只：

```swift
import Kingfisher
```

必须存在类似：

```swift
imageView.kf.setImage(
    with: url
)
```

并且这个功能存在真实调用链。

---

# 32. Release 验证系统

新增：

```text
tools/release_inspector/
```

执行：

```bash
dart run tools/release_inspector
```

---

# 33. Dart 验证

检查：

```text
新增 Capability 数量
调用入口
调用位置
所属 Feature
是否测试
是否参与 Release
```

报告：

```json
{
  "UserRepository": {
    "capabilities": [
      {
        "name":
          "cache_validation",

        "defined":
          true,

        "called":
          true,

        "productionCallCount":
          2
      }
    ]
  }
}
```

---

# 34. Native 验证

输出：

```json
{
  "nativeCapabilities": {

    "network": {
      "enabled": true,
      "bridgeCalled": true
    },

    "crypto": {
      "enabled": true,
      "bridgeCalled": true
    },

    "database": {
      "enabled": false
    }
  }
}
```

---

# 35. Dependency 验证

生成：

```json
{
  "dependencies": [

    {
      "name":
        "Kingfisher",

      "version":
        "8.x",

      "reason":
        "image_cache",

      "used":
        true
    }
  ]
}
```

---

# 36. Release Gate

CI 最后运行：

```text
Capability Validator
        ↓
Dependency Validator
        ↓
Flutter Test
        ↓
iOS Unit Test
        ↓
flutter build ios --release
        ↓
Binary Inspector
        ↓
Release Report
```

任何以下情况直接失败：

```text
新增 Capability 没有调用
第三方依赖没有用途记录
Manifest 与 Pod/SPM 不一致
Release Build 失败
Bridge 未注册
Unit Test 失败
```

---

# 37. CI Pipeline

例如：

```yaml
steps:

  - analyze

  - capability_check

  - flutter_test

  - native_dependency_check

  - ios_test

  - flutter_build_ios

  - binary_inspection

  - generate_release_report
```

---

# 38. 建议加入 Architecture Profile

每个产品维护：

```text
config/product_profile.yaml
```

例如：

```yaml
product:
  type: social

features:
  chat: true
  image: true
  payment: false
  offline: true

technical:
  native_network: true
  native_storage: true
  native_crypto: true
```

工具根据：

```text
Product Profile
```

决定哪些能力合理。

---

# 39. 社交 App 示例

如果产品：

```text
Flutter 社交 App
+
IM
+
图片
+
本地数据库
```

推荐：

### Dart

```text
MessageRepository
→ deduplication
→ cache validation
→ message normalization

ConversationController
→ state validation
→ analytics context

ImageService
→ request metadata
→ retry policy
```

### Native

```text
Network
Security
Image
Database
Logging
Performance
Diagnostics
```

### 第三方库

可能：

```text
Kingfisher
GRDB
KeychainAccess
```

其余优先系统 Framework。

---

# 40. 工作拆分

## Task 1

实现：

```text
Dart Class Scanner
```

能力：

```text
扫描 lib
识别 class
识别类型
统计 method
```

---

## Task 2

实现：

```text
Capability Rules
```

配置：

```text
Repository
Service
Controller
Model
Widget
```

---

## Task 3

建立：

```text
Dart Capability Pool
```

第一版：

```text
10～15 个模板
```

不要一开始做几十个。

---

## Task 4

实现：

```text
Call Graph Validator
```

检查：

```text
Capability 是否被生产代码调用
```

---

## Task 5

建立：

```text
NativeCapabilities/
```

先实现系统 Framework：

```text
Device
Network
Security
Crypto
Diagnostics
Performance
```

---

## Task 6

使用：

```text
Pigeon
```

建立：

```text
Flutter ↔ iOS API
```

---

## Task 7

增加：

```text
Image
Database
Compression
Logging
```

根据实际项目需求逐步启用。

---

## Task 8

实现：

```text
Native Manifest Generator
```

读取：

```text
native_capabilities.yaml
```

生成 Swift Configuration。

---

## Task 9

实现：

```text
Dependency Inspector
```

读取：

```text
Package.swift
Podfile.lock
```

检查依赖。

---

## Task 10

实现：

```text
Release Inspector
```

最终生成：

```text
release-report.json
```

---

# 41. 第一阶段 MVP

第一版不要把系统做得过重。

建议只实现：

```text
Dart Scanner
+
10 个 Dart Capability
+
6 个 Native Capability
+
Pigeon
+
Manifest
+
Release Validator
```

目录：

```text
tools/
├── capability_scanner/
├── capability_validator/
└── release_inspector/
```

---

# 42. MVP Native Capability

只做：

```text
Device
Network
SecureStorage
Crypto
Diagnostics
Performance
```

因为基本都可以依靠 Apple Framework：

```text
Foundation
Network
Security
CryptoKit
MetricKit
os
```

不会额外增加过多 dependency 风险。

---

# 43. MVP Dart Capability

先实现：

```text
cache_key
cache_validation
response_normalizer
request_context
input_validation
analytics_context
state_validation
debug_summary
request_metadata
retry_context
```

10 个足够。

---

# 44. 推荐技术栈

工具程序：

```text
Dart
```

优先。

原因：

```text
可以直接使用 analyzer
与 Flutter 项目统一语言
方便 Codex 修改
方便做 AST
方便作为 CLI
```

依赖：

```yaml
dependencies:
  analyzer:
  yaml:
  args:
  path:
```

CLI：

```bash
dart run tools/app_tool.dart scan

dart run tools/app_tool.dart validate

dart run tools/app_tool.dart release
```

---

# 45. 最终 CLI

建议最后做到：

```bash
dart run tools/app_tool.dart prepare
```

执行：

```text
扫描源码
 ↓
加载 Product Profile
 ↓
检查 Dart Capability
 ↓
检查 Native Capability
 ↓
生成配置
 ↓
运行验证
```

然后：

```bash
dart run tools/app_tool.dart verify
```

输出：

```text
✓ Dart capabilities

  18 capabilities
  18 reachable

✓ Native capabilities

  7 enabled
  7 registered
  6 currently called

✓ Dependencies

  3 third-party dependencies
  3 justified

✓ Bridge

  8 APIs
  8 registered

✓ Release

  Passed
```

---

# 46. Release Report

最终 CI 保存：

```text
reports/release-report.json
```

格式：

```json
{
  "release": {
    "status":
      "passed"
  },

  "dart": {
    "classesAnalyzed":
      213,

    "capabilities":
      28,

    "reachable":
      28
  },

  "native": {
    "enabled":
      7,

    "called":
      7
  },

  "dependencies": {
    "total":
      3,

    "justified":
      3
  }
}
```

---

# 47. 核心规则

整个系统必须始终遵循：

```text
功能差异
      ↓
代码差异
      ↓
调用图差异
      ↓
Binary 差异
```

而不是：

```text
为了 Binary 差异
      ↓
制造无意义代码
```

这一区别非常重要。

最终应该实现成一个：

```text
Flutter / iOS Project Capability Generator
+
Release Compliance Validator
```

而不是单纯的“随机代码插入器”。

---

# 48. 推荐执行顺序

第一周：

```text
Task 1
Dart Scanner

Task 2
Class Classifier

Task 3
10 个 Capability

Task 4
Capability Validator
```

第二阶段：

```text
Task 5
Native Capability Framework

Task 6
Pigeon Bridge

Task 7
Manifest Generator
```

第三阶段：

```text
Task 8
Dependency Inspector

Task 9
Release Inspector

Task 10
CI 集成
```

最终开发入口统一为：

```bash
dart run tools/app_tool.dart verify
```

这可以作为后续 Codex / Claude Code / AI Agent 的主要执行入口。
