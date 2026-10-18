# HP 调试日志 · 2026-10-18 / 61 hooks

日志保存在应用 Documents 的 PhiMod-diagnostics.log，悬浮窗“设置”页提供 Copy diagnostics 和 Clear diagnostics。每次启动带有独立 session 标记，重启不会自动清除上一会话。

本次日志已经证明初始生命是 200，而不是 0。IDA 确认原生 LevelControl.Start 会等 levelMods 列表内每个资源的完成回调；本次不再向该列表塞入 MOD 的 HP 特效，而在 chartLoaded 后独立异步加载相同原生资源。另补齐 Android 的 floorPositions 扩容逻辑。

复测顺序：

1. 重新构建并打包当前 57-hook 源码，先只开 HP，开始前清一次日志。
2. 测试进谱、顶部血条/背景效果、耗尽 HP 后退出、返回选曲后再进一首。
3. 如果卡住且浮窗不能操作，强制结束并重启，立即到设置复制日志；不要先清空日志或重新进歌。
4. 把出问题 session 的 LevelControl.Awake 起始到最后一条记录发回。

新日志包括 ProgressControl.Update、JudgeControl.Update 的独立进入与原函数返回；音频包装器时钟、AudioSource pitch/time、prepared/volume/load、chartLoaded/levelBegan、floorPositions 容量、HP 资源 pending/settled/failed 状态。更新心跳约 0.75 秒一轮，普通 tick 约每个游戏秒一条。HP 特效失败会明确记录并允许谱面继续加载。Miss 扣血后的 HP 视觉更新已移出 ScoreControl.Miss 回调，改由 ScoreControl.Update 主循环应用。

源码验证不等于实机修复成功。优先在 iPad 第六代 / iPadOS 15.4.1 测试；练习功能另开第二轮测试，避免混淆 HP 日志。
