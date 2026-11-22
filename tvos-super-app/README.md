# 短剧放映厅 · Apple TV 原生原型

这是独立的 tvOS 工程源码，不是 iPhone App、电视网页或可直接安装的 IPA。第一版只验证一种体验：在 Apple TV 上用遥控器搜剧、选集、在 App 内播放、退出再续播。

| 范围 | 现状 |
| --- | --- |
| 浏览和搜索、选集 | 有原生 SwiftUI 源码；需在 tvOS 验证视觉与遥控器焦点 |
| 内嵌播放、失败提示和重试、按剧和集保存进度 | 有 AVKit / AVFoundation 和本机进度源码；需在 tvOS 验证播放、实际定位与退出保存 |
| 内置样片 | Apple 开发者文档公开的 Bip Bop HLS；演示目录的两集使用同一色卡素材、各有独立进度 |
| 红果短剧 | **未接入**。没有红果账号、榜单、搜索或真实剧集 |
| B 站和大陆电视直播 | 尚未实现 |
| 通用 M3U、短剧清单入口 | TV 应用内导入尚未实现。开发者可改内置演示 JSON 来测试已有授权的片源 |

App 不需要后端或账号，不包含第三方软件代码和影视片段。样片由 Apple CDN 提供，打开播放时才请求媒体；进度仅保存在设备的本地 `UserDefaults`，上限 80 个分集，不上传、不做跨设备同步。不使用红果商标、保护密钥、账号或非公开播放接口。不能把演示目录或官方网页跳转当作红果已接通。

## 如何试跑

1. 在**有完整 Xcode 和 tvOS 平台组件**的 macOS 开发环境解压并打开 `SuperTV.xcodeproj`。建议最低 Xcode 16，目标系统 tvOS 17+。无需安装依赖。
2. 选择 `SuperTV` scheme 和 Apple TV 模拟器，再点 Run。也可先做无签名构建：

   ```bash
   xcodebuild -project SuperTV.xcodeproj -scheme SuperTV \
     -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
   ```

3. 首次验收用模拟器；真机另需在 Xcode 配对 Apple TV、选自己的 Team，并将示例 Bundle ID 改为自己的唯一值。此源码包没有签名、安装或上架，请勿把示例标识用于分发。

没有完整 Xcode 的环境可执行 `python3 scripts/verify-source.py` 检查工程引用与清单；若有 Swift 编译器，可执行下面的纯 Foundation 测试。二者都**不代替** Xcode 构建及 tvOS 播放验收。

```bash
tmpdir="$(mktemp -d)"
swiftc SuperTV/Catalog.swift tests/CoreSmoke.swift -o "$tmpdir/CoreSmoke"
"$tmpdir/CoreSmoke" SuperTV/DemoCatalog.json
```

## 遥控器验收顺序

1. 打开 App，看到「演示系列 · Bip Bop」和片源提示。用遥控器选「搜索剧名」，输入 `bip bop` 应有结果，输入不存在的内容应看到空状态，清空恢复目录。
2. 进入分集页，从第 1 集开始播放。确认同时有图像和声音，遥控器能暂停、快进、返回；不跳出 App。播放 15 秒后返回；第 1 集应显示可续播，第 2 集没有进度且从头播。
3. 再打开第 1 集，确认恢复到上次位置附近；「从头播放」应从零开始。播到结束后返回，原集续播位置应清除。断网试播时检查失败提示、重试与返回流程。
4. **真实红果单独验收**：先取得允许第三方 tvOS 客户端使用的来源，至少一部真实红果短剧须在 App 内经搜索、选集、播放、退出及续播实测通过。公开的红果官网可用于确认片名，但不是第三方播放器授权；抖音的小程序方案也不等于原生 tvOS 接入。

## 修改演示清单

`SuperTV/DemoCatalog.json` 的顶层是 `shows` 数组。每部用稳定的 `id`、`title`、`subtitle` 和 `episodes`，每集有唯一 `id`、`title`、`streamURL`。只放自己拥有使用权的 HTTPS 媒体地址，请勿填入账号、令牌、保密链接或第三方未授权的流。若换片，改集 ID 避免误用旧进度。

公开参考：[Apple HLS 示例](https://developer.apple.com/streaming/examples/) · [Apple 文档所用的 Bip Bop URL](https://developer.apple.com/documentation/applenewsformat/video) · [红果官方目录](https://hongguoduanju.com/) · [抖音短剧小程序方案](https://developer.open-douyin.com/capacity-center-page/solution-detail/7403242123836784680)
