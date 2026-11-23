# 短剧放映厅 v0.2.1：Apple TV 与 Mac 试用源码

这是同一项目的两套原生构建目标，不是可直接安装的 IPA/DMG，也不是四平台内容已经整合的正式版本。SwiftUI 片库与 AVKit 播放逻辑共用，Apple TV 使用遥控器，Mac 使用键鼠。两个设备各自保存观看进度，不同步。

## v0.2 有什么

- **离线示例**：打开即可选两段不同的、原始合成的 24 秒本地 MP4，无需访问网盘或账号。测试片明确标记为示例。
- **真实开放影片**：联网可尝试《WING IT!》，(CC) Blender Foundation | studio.blender.org，[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)，链接到[官方公开分发](https://video.blender.org/w/pkDDcE7HiLU3UTGmRV1nJG)，未修改该作品。片库版本并不代表红果授权。
- **导入**：单个 HTTPS 视频/直播（兼容的 MP4、HLS）、HTTPS M3U 频道清单、HTTPS JSON 剧集清单。可以命名单个链接、搜索片库、浏览分集/频道、从头或续播、移除本机导入。直播不会保存位置。
- **异常**：片源不可读或缓冲超时有返回与重试；格式错误留在来源表单，不清空现有片库。
- **Mac B 站试验入口**：仅手动填写 BV 号后加载 B 站官方公开分享播放器页面，不抓媒体流、不接账号、不走 Safari；公开拥有站外嵌入资格的内容才有机会播放。没有做 macOS 播放实测；不支持这条路径的 tvOS 没有入口。

| 用户要求的内容 | 此版本状态 |
| --- | --- |
| B 站 | Mac 新增公开 BV 分享播放器试验入口。tvOS、直播、登录、会员内容尚未接入；未做实播验收。 |
| 红果短剧 | 尚无已获准的原生跨端剧源，不用跳转、示例或保护绕过替代。 |
| 抖音 | 尚未接入。官方公开分享播放器是 Mac 备选，不等于拥有全站目录或原生 tvOS 接口。 |
| 央视、卫视、地方电视台 | App 有授权 HTTPS IPTV 清单与单流入口，不自带未经核验频道，也未做具体授权频道实播。 |

## 构建和运行

1. 在有完整 Xcode 和所需 SDK 的获准 macOS 环境解压，打开 `SuperTV.xcodeproj`。v0.2 两端编译、Mac 解码/续播探针与 2 个 tvOS 播放用例通过，导入页遥控焦点用例失败。此 v0.2.1 将 Apple TV 的地址、导入、返回排列到同列，保留原回归用例并检查错误后可返回输入；此补丁的模拟器验收尚未执行。
2. **Apple TV**：选择 `SuperTV` 和 tvOS 17 或更高的模拟器，按 Run；选择遥控器方向键、Select 和返回键。真机测试另用你自己的 Bundle ID 和签名 Team，与 Xcode 配对后部署。不要用此包作为已签名安装包。
3. **Mac**：选择 `SuperTV-macOS` 和 My Mac（macOS 14 或更高），按 Run；鼠标或 Tab/空格选片，在播放器中使用系统播放控件，Esc 或「返回分集」关闭。第三方分发另需签名、公证及发行配置，本工程不执行。

两端无签名编译：

```bash
xcodebuild -project SuperTV.xcodeproj -scheme SuperTV \
  -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SuperTV.xcodeproj -scheme SuperTV-macOS \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## 导入格式与限制

- 直接链接选「单个视频」或「单个直播」，输入你有权使用的 HTTPS MP4/HLS 媒体地址。节目网页、登录凭据、第三方会员页面、HTTP、UDP、RTMP、DRM 原始密钥均不是本版支持项。
- M3U 是 **IPTV 频道清单**，不是单条 HLS 的 `#EXT-X-` 播放清单；每条以 `#EXTINF:-1,名称` 和下一行链接组成，相对链接随来源解析。仅保留 HTTPS，统一播放器仍需要实际兼容的编码和可访问网络。
- JSON 示例见 `tests/import-example.json`。需把 JSON 放到自己有权限的 HTTPS 位置，再在 App 选「JSON 短剧清单」。每部和每集需要非空、稳定的唯一 ID。更换具体媒体建议使用新 ID，避免引用原进度。
- 远程清单单份 256 KiB，片库最多 160 个剧目/清单，每个最多 400 集/频道。App 仅在设备内存/本机储存片库和进度；启动不会后台上传片库。只有主动播放/导入才联系来源服务器；Mac 官方分享入口会联系 B 站。带访问令牌的链接可能留在本机片库里，切勿使用长期凭据或将其提交到公开仓库。
- tvOS 片库文件位于该 App 缓存，系统可能清理；Mac 放在该 App 的 Application Support。进度保存在本机偏好，最多 80 集。两端均无云同步、自动刷新或下载外部内容。公开外链是否在你的网络能播，以实际为准。

## 实测分层

- 可在 Linux/macOS 有 Swift 的环境运行 Foundation 导入/片库/续播数据断言：

  ```bash
  tmp="$(mktemp -d)"
  swiftc -module-cache-path "$tmp/cache" -swift-version 5 \
    SuperTV/Catalog.swift tests/CoreSmoke.swift -o "$tmp/CoreSmoke"
  "$tmp/CoreSmoke" SuperTV/DemoCatalog.json
  python3 scripts/verify-source.py
  ```

- tvOS UI 验收需要 Xcode 模拟器，运行：

  ```bash
  xcrun simctl list devices available
  xcodebuild -project SuperTV.xcodeproj -scheme SuperTV \
    -destination 'platform=tvOS Simulator,id=<UDID>' -parallel-testing-enabled NO test
  ```

  XCTest 用方向键/Select、读取 AVPlayer 时钟，覆盖离线第 1 集开始-推进-退出、重启 App 后同集续播、第 2 集从头、导入校验失败仍可修改、AVPlayer 对真实缺失文件报错并可返回。它不保证主观听感、实际图像色彩或 Apple TV 真机表现。
- Mac 手工用键鼠走同一路径，另验证授权源的 MP4/HLS、M3U/JSON 导入、故障与重开、公开 BV 样例。最终 **四类都在两端同 App 播放** 需逐路实播，不能以通用链接、公开电影或 Mac 页面推断已经完成。
