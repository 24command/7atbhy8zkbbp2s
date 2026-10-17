# HP 调试日志

本次修复把 HP/gameplay tick 移到 `JudgeControl.Update`，与 Android `practiceTick()` 的调用位置一致。日志文件保存在应用 Documents 下的 `PhiMod-diagnostics.log`，悬浮窗“设置”页可复制最近 400 行或清空日志。

若仍在加载遮罩消失后卡住：

1. 启动新版 IPA，在悬浮窗“设置”页先点 **Clear diagnostics**。
2. 只开启 HP 生存，进入一首曲目并复现卡住。
3. 返回悬浮窗“设置”页点 **Copy diagnostics**，把剪贴板内容发回。

日志重点包括 hook 安装状态、`LevelControl.Awake` / `ProgressControl.Start`、HP 原生组件初始化、`JudgeControl.Update` 与 `ProgressControl.Update` 的时间/播放状态，以及 HP 失败延迟和 `LevelOver()` 调用阶段。正常等待时按状态变化及约 0.1 秒间隔记录，不会逐帧写盘。

仅依靠源码测试还不能证明实机修复成功；需要在 iPad 第六代 / iPadOS 15.4.1 上复测。
