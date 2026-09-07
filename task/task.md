Task 0：第三方库在线搜索与候选池建立
不能先在代码里写死 10 个库名，而应该每个项目执行前从 GitHub 等公开源筛选一遍，确认库仍在维护、支持当前 Xcode/iOS/SPM，再进入候选池。

我刚按 2026 年 8 月的状态查了一轮，首批可以这样建立：

库    GitHub    用途    当前判断
Alamofire    Alamofire/Alamofire    HTTP 网络    ✅ 推荐候选，最新 release 5.12.0，2026-05-04
Kingfisher    onevcat/Kingfisher    图片下载/缓存/处理    ✅ 推荐，8.x，支持 SPM
SDWebImage    SDWebImage/SDWebImage    图片缓存/格式处理    ✅ 推荐，5.21.7
GRDB.swift    groue/GRDB.swift    SQLite 数据库    ✅ 推荐，7.10.0，iOS 13+
KeychainAccess    kishikawakatsumi/KeychainAccess    Keychain    ✅ 推荐候选，支持 SPM/CocoaPods
ZIPFoundation    weichsel/ZIPFoundation    ZIP 压缩/解压    ✅ 推荐，0.9.20
CocoaLumberjack    CocoaLumberjack/CocoaLumberjack    日志    ✅ 可用，仓库 2026-07 仍有更新，支持 SPM
SwiftProtobuf    apple/swift-protobuf    Protobuf    ✅ 推荐，1.38.1，Apple 官方维护
Starscream    daltoniam/Starscream    WebSocket    ⚠️ 条件候选，最新 release 4.0.8 是 2024 年，项目有真实 WebSocket 需求再采用
Reachability.swift    ashleymills/Reachability.swift    网络状态    ⚠️ 不建议作为默认候选，已有 iOS 26 / Privacy Manifest 等开放问题；现代项目优先 NWPathMonitor

这里还有一个重要调整：候选池最好不是只有 10 个，而是 20～30 个。 每个项目先根据业务能力筛出 10～15 个“合理候选”，最后实际启用其中真正需要的几个。

Task 0 应该这样设计
输入
↓
当前项目 Product Profile
↓
提取需要的 Native 能力
↓
GitHub 搜索候选库
↓
获取仓库信息
↓
过滤
↓
生成 ios_library_pool.yaml
↓
后续 Native Capability Generator 使用

搜索阶段至少检查：

GitHub repository
Latest Release
Latest Commit
Stars
Open Issues
License
SPM Support
CocoaPods Support
Minimum iOS
Swift Version
Xcode Compatibility
Privacy Manifest
Repository Archived?
真实功能是否适合当前 App

例如生成：

libraries:


  alamofire:
    repository: Alamofire/Alamofire
    capability: networking
    version: 5.12.0
    package_manager: spm
    status: approved


  kingfisher:
    repository: onevcat/Kingfisher
    capability: image_cache
    package_manager: spm
    status: approved


  grdb:
    repository: groue/GRDB.swift
    capability: database
    version: 7.10.0
    package_manager: spm
    status: approved


  starscream:
    repository: daltoniam/Starscream
    capability: websocket
    status: conditional


  reachability:
    repository: ashleymills/Reachability.swift
    capability: network_monitor
    status: rejected
    reason: prefer_native_nwpathmonitor
AI Agent 应该负责“搜索库”

这部分可以专门增加一个 Agent：

IOSLibraryResearchAgent

它的任务不是：

随机找 10 个库

而是：

分析项目
   ↓
需要 image cache
需要 database
需要 secure storage
需要 compression
   ↓
GitHub 搜索
   ↓
每个类别寻找 3～5 个候选
   ↓
比较维护情况
   ↓
选出最佳候选

例如图片：

image_cache


GitHub Search
├── Kingfisher
├── SDWebImage
└── Nuke


        ↓


比较


维护状态
SPM
Swift版本
iOS最低版本
功能
Binary影响


        ↓


选择 Kingfisher

数据库也一样：

database


├── GRDB
├── Realm
└── SQLite.swift


↓
评分
↓
选择

这样整个系统才真正适合长期使用。

最终方案顺序修改成
Task 0
GitHub 第三方库调研
        ↓
生成 Library Pool


Task 1
扫描 Dart 工程


Task 2
分析 Product Profile


Task 3
分配 Dart Capability


Task 4
验证 Dart 调用关系


Task 5
分析需要哪些 Native Capability


Task 6
从 Library Pool 选择真正需要的第三方库


Task 7
CocoaPods 集成


Task 8
实现真实 Native 功能


Task 9
Pigeon Flutter ↔ iOS 调用


Task 10
Release 验证
