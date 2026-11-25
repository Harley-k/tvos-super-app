# SuperTV · 私家放映厅 0.3.0

同一个原生播放器用于 Apple TV（tvOS 17+）和 Apple 芯片 Mac（macOS 14+）。能直接观看开放授权的《WING IT!》，也支持自有或获准的 HTTPS 直播和短剧。无需注册本 App 账号。

**先看起来：** 从 [构建记录](https://github.com/Harley-k/tvos-super-app/actions/workflows/supertv-rc.yml) 打开与你下载版本相符的成功运行，在 Artifacts 下载并解压。核对 `SOURCE-COMMIT.txt` 和 `SHA256SUMS.txt`；在该目录可运行 `shasum -a 256 -c SHA256SUMS.txt`。

- **Mac**：解压名字含 `macOS-Apple-Silicon-adhoc` 的内层 ZIP，将 .app 放到「应用程序」，双击打开。开发测试版仅临时签名，未经 Developer ID 公证。系统可能提示，请仅在确认来源并信任后按系统提供的单项提示操作，不要关闭 Gatekeeper。
- **Apple TV 模拟器**：另一个 ZIP 仅适用于 Mac 的 Xcode tvOS 模拟器；不是电视盒子安装包。
- **你的 Apple TV 盒子**：下载本分支的源码，在 Mac 进入 `app` 执行 `bash scripts/prepare-open-film.sh`；Xcode 打开 `SuperTV.xcodeproj`。确保 Mac 与电视在同一可配对网络，在电视的「设置 → 遥控器与设备 → 遥控器 App 与设备」准备配对；在 Xcode 的设备窗口完成配对。选择 `SuperTV` 目标，Signing & Capabilities 选自己拥有权限的 Team 和可用唯一 Bundle ID，然后选电视按 Run。无需提供 Apple ID 密码或证书给本项目。TestFlight/商店发行需另外签名提交，并未包含在本版。参阅 [Apple 设备管理](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)。
- **从源码在 Mac 运行**：同样准备影片后，在 Xcode 选择 `SuperTV-macOS`、My Mac、Run。没准备离线影片的源码构建会从 Blender 官方地址播放，需联网。

## 第一次播放

1. 打开后选「开放影片 · WING IT!」，再选「正片」。CI 交付包含完整未改动的 3 分 58 秒公开动画，不需要添加链接。使用系统播放控件暂停、快进或返回。
2. 想体验分集续播：选「示例短剧 · 片段演练」第一集，播放几秒后退出。重开仍可继续第一集，第二集独立计时。两段合成测试片不是商业短剧。直播不存断点。
3. 想添加自己的视频：选「导入片源 → 单个视频」。可先按「试填一个可播放的示例地址」，再按「导入」，返回首页选刚加入的影片。之后同样可换成有权使用的 HTTPS MP4/HLS 地址。用「单个直播」添加一条直播流，或选择「M3U 直播清单」「JSON 短剧清单」批量导入。普通分享网页不等于视频地址。Apple TV 遥控器上下选择，点击选择键；可通过已配对的 iPhone 输入长链接。
4. 搜索支持剧名、分集和频道；移除用户导入的条目请在详情页选择「移除此片源」。有网络故障时可重试，或返回离线影片。tvOS 可能回收用户片库缓存，请保留自己的原始清单；两端不会自动同步。

## 平台边界

| 希望观看 | 本版的真实入口 |
| --- | --- |
| Bilibili | Mac 可输入 BV 号，在 App 内打开[官方站外播放器](https://player.bilibili.com/)。仅限站方允许嵌入且当前设备可播的公开视频；不提供账号、会员、直播或整站目录。tvOS 没有网页播放器。 |
| 红果短剧 | 没有已核实的原生授权接口或节目包，未内置。支持导入内容方提供的合法分集清单，不冒充红果。 |
| 抖音 | 未内置抖音目录或电视播放接口。分享链接不是自有媒体流。 |
| 大陆电视台 | 原生支持导入授权 HTTPS 直播/M3U，未内置未经频道方确认的 CCTV、卫视或地方台源。 |
| 开放授权片 | WING IT! · (CC) Blender Foundation / studio.blender.org · [原片](https://studio.blender.org/projects/wing-it/) · [作者授权](https://studio.blender.org/projects/wing-it/pages/licensing/) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)。23,049,214 字节，480p H.264/AAC，未改动。 |

片库只存在本机。导入和外部播放时会联系相应来源；不要将长期访问令牌或私人的订阅地址提交到公开仓库。单份远程清单限 256 KiB，最多 160 个条目、每条 400 集/频道。JSON 详情见 [清单与续播](README-catalog.md)。这些内容在一台设备播通不代表其它平台、地区、会员内容或真机也已通过验收。
