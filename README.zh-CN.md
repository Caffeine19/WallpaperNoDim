# WallpaperNoDim

使用 macOS 原生 Fill / Maximize（填充／最大化）和平铺窗口时，让壁纸保持原亮度。

[English](README.md)

我在 GPT-6 / Codex 的帮助下做了这个小程序，用于绕开原生填充或平铺窗口后壁纸变暗的效果。桌面覆盖方案已在我的 **macOS 27.0，构建号 26A428** 上验证有效，其他版本尚未测试。

## 工作原理

程序读取各屏幕的壁纸图片，创建无边框窗口，把静态副本显示在桌面窗口层的上方。覆盖窗口忽略鼠标点击，并加入所有桌面空间。对于动态 HEIC，程序读取内嵌的浅色／深色帧映射，不再始终显示默认帧。自动模式跟随系统外观；能够识别的壁纸单独 Light/Dark 设置会优先采用。

在我的环境中，这些副本在使用原生 Fill / Maximize 时保持原亮度。系统底下的变暗逻辑仍然存在，这只是一个视觉绕过方案。程序不调整应用窗口、不修改系统文件，也不需要关闭 SIP（系统完整性保护）。

## 运行与退出

双击 `WallpaperNoDimTest.app`，或在项目目录运行：

```sh
open WallpaperNoDimTest.app
```

菜单栏会出现警示灯图标（`warninglight`）。**Launch at Login** 首次运行默认开启，取消勾选即可关闭登录启动。如果 macOS 要求批准，可选择 **Open Login Items Settings…**；后续启动会尊重系统设置中的修改。更换壁纸后，选择 **Refresh Wallpaper**，即可重新读取所有屏幕的壁纸；选择 **Quit and restore wallpaper**，即可立即撤掉覆盖层。系统浅色／深色外观和屏幕布局发生变化时，也会自动刷新。

## 编译

需要 Xcode 或包含 macOS SDK 的 Command Line Tools：

```sh
./build.sh
```

脚本生成应用并进行本地临时签名。应用源码：[`WallpaperNoDimTest.m`](WallpaperNoDimTest.m)；图片解码：[`WallpaperImage.m`](WallpaperImage.m)。

## 当前限制

- 覆盖层仍为静态图片，支持 HEIC 的浅色／深色版本；不播放视频，也不精确复现按太阳位置或一天中的时间变化的壁纸。
- 更换壁纸或其选项后，请使用 **Refresh Wallpaper**。系统外观和屏幕布局变化会自动刷新。
- 壁纸单独指定的外观会尽量从 macOS 配置中读取；无法识别配置格式时，程序跟随系统外观。
- 没有设置开机启动。
- 这是在一台 Mac 上验证有效的实验方案，尚未跨系统版本测试。

## 实验性替代方向：修改 WindowManager —— 尚未测试

排查时，我们定位了 Apple WindowManager 中的 `TiledWallpaperDimComponent`。在 **26A428** 这版二进制中，其更新路径选择硬编码的 `0.5` 或 `0` 作为变暗值。我们制作过将两份架构中的 `0.5` 指令改为 `0` 的副本，并通过本地签名校验，但**没有安装，也没有验证运行效果**。SIP 开启时，调试器连接系统进程的尝试被拒绝；具体由哪一项保护机制阻止，尚未确认。

候选指令位置和原文件哈希记录在 [`experimental/patch-details.json`](experimental/patch-details.json)。它们只对应本次检查的确切二进制；运行时地址还需要考虑 ASLR。这是研究记录，不是安装器或完整补丁流程。

### 供进一步研究的 SIP 操作说明

**我没有测试关闭 SIP 后的补丁方案。** 关闭 SIP 会削弱 macOS 的保护；当前有效的桌面覆盖程序不需要这一步。仅关闭 SIP，也不能证明调试、修改后的二进制或替代系统服务能够正常工作。

如果研究者自行决定继续探索，Apple 文档中的步骤是：

1. 进入 macOS 恢复模式。Apple 芯片机型关机后长按电源键，出现启动选项后选择“选项”→“继续”；Intel 机型启动时按住 Command-R。参见 [Apple 恢复模式说明](https://support.apple.com/en-us/102518)。
2. 打开“实用工具”→“终端”，执行 `csrutil disable`，按提示完成后重新启动。
3. 正常进入系统后，用 `csrutil status` 检查状态。
4. 研究结束后，重新进入恢复模式，执行 `csrutil enable` 并重启，恢复 SIP。

参见 [Apple SIP 文档](https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection)。这些是 SIP 的配置步骤，并不是替换 WindowManager 的操作流程。本项目没有提供修改系统卷或持久安装补丁的脚本。

期待好心人的反馈：如果你能验证补丁方向、找到真正的变暗开关，或改善桌面覆盖程序，欢迎分享 macOS 版本／构建号、硬件、相关保护设置，以及原生 Fill / Maximize 是否正常。

## 致谢

感谢 **GPT-6 / Codex** 帮助排查问题并实现这个小程序。

## 动态壁纸参考

[Apple 的 desktopImageURL(for:) 文档](https://developer.apple.com/documentation/appkit/nsworkspace/desktopimageurl(for:)) 返回壁纸文件 URL，并非当前外观的已渲染帧。HEIC 浅色／深色帧映射可参考[原始动态壁纸元数据研究](https://gist.github.com/leptos-null/c88e8c3c0f9f6860c7500826031c8551)。
