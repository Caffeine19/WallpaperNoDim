# WallpaperNoDim

使用 macOS 原生 Fill / Maximize（填充／最大化）和平铺窗口时，让壁纸保持原亮度。

[English](README.md)

我在 GPT-6 / Codex 的帮助下做了这个小程序，用于绕开原生填充或平铺窗口后壁纸变暗的效果。桌面覆盖方案已在我的 **macOS 27.0，构建号 26A428** 上验证有效，其他版本尚未测试。

## 工作原理

程序读取各屏幕的壁纸图片，创建无边框窗口，把静态副本显示在桌面窗口层的上方。覆盖窗口忽略鼠标点击，并加入所有桌面空间。

在我的环境中，这些副本在使用原生 Fill / Maximize 时保持原亮度。系统底下的变暗逻辑仍然存在，这只是一个视觉绕过方案。程序不调整应用窗口、不修改系统文件，也不需要关闭 SIP（系统完整性保护）。

## 运行与退出

双击 `WallpaperNoDimTest.app`，或在项目目录运行：

```sh
open WallpaperNoDimTest.app
```

菜单栏会出现“壁纸实验”。选择“退出并恢复原壁纸显示”，即可立即撤掉覆盖层。

## 编译

需要 Xcode 或包含 macOS SDK 的 Command Line Tools：

```sh
./build.sh
```

脚本生成应用并进行本地临时签名。源码：[`WallpaperNoDimTest.m`](WallpaperNoDimTest.m)。

## 当前限制

- 显示静态副本，运行期间看不到动态或动画壁纸效果。
- 启动时读取壁纸和屏幕布局；更换后请退出并重新启动。
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
