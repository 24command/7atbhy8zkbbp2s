# HP 加载修复与练习扩展 · 2026-10-18

当前源码为 PMGameplay-v2 / 57 hooks，framework 0.2.0 (57)。所有源码位于 G:\Phimod-ios\ios；audit、工具和备份留在父目录。

## HP 卡在 -3 秒的处理

用户日志已经显示 HP life=200/max=200，尚无证据表明本次卡住来自初始 HP=0。

本地 IDA 对原始 iOS UnityFramework 的核对结果：

- LevelControl.Awake (0x1580C78) 遍历 LevelStartInfo.levelMods，异步实例化每个资源，并在完成回调中增加 levelModCount。
- 完成回调 <Awake>b__45_0 (0x158330C) 将 LevelControl.levelModCount 增一。
- Start 等待条件 <Start>b__46_0 (0x158331C) 比较 levelModCount >= levelMods.Count；在该条件满足前不读谱。
- iOS Addressables catalog 的 base64 key data 确实包含 LevelMod/SecretChallengeLifeMod 与 LevelMod/HPDisplay。
- Android 新旧代码在 JudgeControl.Update 原函数前扩容 floorPositions；旧 iOS 版本缺少这一步。

本次 iOS 不再把 MOD 的 HP 特效添加到原游戏的 levelMods。先让游戏按原流程加载谱面，chartLoaded 后独立异步实例化相同的原生 HP 特效。通过真实完成状态读取结果，退出时释放句柄。资源加载失败会记录错误并允许歌曲继续，不伪造游戏的加载完成计数。保留顶部生命条、背景效果以及 HP 为零后的冻结、闪屏、退出流程。

补回 floorPositions 容量保护；独立记录 Progress/Judge 的进入与返回、音频时钟、pitch、chartLoaded、原生特效加载状态。常规 tick 改为时间每变化 1 秒记录，减少刷盘。

这是一项针对已确认等待条件的修复，尚未由新 IPA 实机证明是本次卡死的唯一原因。

## 练习扩展

参考新版 Android 的 practice.inc、segment_practice.inc、segment_render.inc、PracticeTransport.java：

- 区间起止、定位、暂停/继续、重播、整曲、循环及可选三秒倒数。
- 可拖动时间轴；拖动结束暂停并预览该位置，可将当前位置设为起点/终点。
- 暂停时创建并绘制可见音符与判定线；避免扫描/创建整张谱面的所有音符。
- 回退前恢复源音符数据，跨起点 Hold 保留剩余段；重播清空计分、Hold 缓存、HP 失败状态，并重建噪域块。
- 倍速设置请求范围 0–5×；实际 AudioSource pitch 会读取返回值，面板显示 effectiveRate。快捷按钮为 0.5、0.75、1、1.25、1.5、2×。不包含独立变速不变调引擎。
- 区间练习和非 1× 倍速触发成绩保护；HP/AP/FC 单独使用沿用此前指定的保护范围。

界面采用 UIKit 的平台实现；未移植 Android 的特定封面、斜切绘制和全部动画，不宣称像素一致。

## 构建与测试

1. 用当前源码覆盖 GitHub 仓库 ios/ 和根目录 .github/workflows/build-ios.yml，重新运行构建。
2. 下载新 framework，再使用当前 57-hook 打包工具生成新的 IPA；framework12 和旧 IPA 均不包含本次改动。
3. 第一轮只打开 HP：测试进入歌曲、顶部/背景特效、故意漏键耗尽 HP、返回选曲后再进一首。
4. 第二轮只打开区间练习：设置 10–20 秒，测试拖动、暂停预览、跨段 Hold、重播/循环、倒数及 0.75/1/1.5×。
5. 若仍卡住，强制结束后重新打开，先到悬浮窗设置复制日志再重新进歌。新进程不会清除旧日志；发送卡住会话起始到最后一条记录。

本机已运行源码、dump/ABI、真实游戏 ARM64 hook 模拟检查，并用本机 MSVC 重新编译运行四组便携 C++ 测试。另对 HP/练习/预览 C++ 部分用 Runtime shim 做语法检查。shim 检查不等于 UIKit/IL2CPP 实机执行或 Apple SDK 编译。Apple SDK 编译、实机音频同步与 UI 测试仍由下一次 GitHub 构建/设备测试确认。
