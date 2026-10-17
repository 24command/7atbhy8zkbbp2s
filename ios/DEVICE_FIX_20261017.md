# 真机问题修复与玩法补齐（2026-10-17）

## 当前交付是什么

这是 **framework10 之后的新版源码**：协议 `PMGameplay-v2 / 55 hooks`，
框架版本 `0.2.0 (55)`。旧 framework10 ZIP 和 IPA 均不包含这次修改。

本次尚未生成新版 framework 或 IPA。必须先在 GitHub Actions 使用 Apple SDK
重新编译，再从原始 Payload 打包。不要把旧 framework7 塞回安装包当作修复版。
请勿把游戏文件、dump、metadata、IDA 数据库、签名凭据或存档上传至 GitHub。

## 已加入源码的修复

1. **结算卡住**：保留原版 Start 创建的有效迭代器，接管其 MoveNext，
   仅调用结算展示方法；可选封面/音频失败不会阻止启用结算 Canvas。
   严重错误提供 Retry / Back 恢复，不回退执行原版奖励、解锁或写存档流程。
2. **HP 归零卡住**：冻结判定和分数，播放原生闪屏/音频淡出，约 1.5 秒后
   启动 LevelOver 转场，显示受保护的练习结算。转场未被接受时保留重试请求。
3. **原生 HP UI**：复用游戏 LevelMod、顶部血条、材质和背景效果，
   适配 iOS 内联的生命值更新，不再用悬浮窗上的假血条代替。
4. **MOD 标签和歌曲下方按钮**：接入实际 OnPointerClick / OnSubmit 点击路径，
   修复 CanvasGroup 点击状态；Mirror 旁各按钮直接修改配置，其他原版按钮透传。
5. **玩法补齐**：噪域、清除原噪域、统一音符类型、噪域 Hold 容错、
   AutoPlay Hold 特效间隔均已接入；谱面先克隆，结束后恢复原引用。
   Hold 特效参数在原版 NoteMove 之前设置，避免调用顺序导致参数不生效。

既有 Custom judge、AutoPlay、全屏判定、Accuracy、AP / FC、HP 和存档保护保留。
除 Custom judge 外，玩法参数在下一首开始时冻结；修改后请重开乐曲验证。
Accuracy 对应 Android 的去除连击分，不是隐藏 Combo 文字。

## 构建与安装

1. 将干净源码包内的 `ios`、`.github` 等文件上传并覆盖到 GitHub 仓库根目录。
   不要再套一层压缩包目录，也不要只上传 README；检查隐藏的 .github 没有漏掉。
2. 在 Actions 选择 `Build PhiMod iOS framework`，针对包含新代码的分支手动
   Run workflow。重跑旧提交的失败任务不会取得这次新代码。
3. 下载新的 `PhiMod-framework` 构建产物。解压后应包含
   `PhiMod.framework/PhiMod`。把下载路径发给我，再用本版工具和原始 Payload
    打包新版 IPA。55-hook v2 工具会拒绝旧版 framework。
4. 先备份游戏存档，再使用测试账号安装到 TrollStore 设备验证。

## 建议测试顺序

- **全关基线**：关闭全部玩法修改，确保至少一首能自然结束并正常结算，
   Retry / Back 都能使用。点击 Validate gameplay config，应报告 **55 hooks v2**。
- **按钮**：直接点 Mirror 旁的 AutoPlay 等按钮；进入设置点 MOD，保存/取消后
  回到选曲页应正常。Unified 循环关闭/Tap/Drag/Hold/Flick，AP / FC 循环三态。
- **AutoPlay**：选择含四种音符的谱面，验证长 Hold 尾部、暂停/继续、
  自然结算；尾部计分不能提前或重复。
- **HP**：先只开 HP，将最大 HP 设为 1、Miss 设为 -1，故意漏一个音符。
  检查原生顶部血条与背景效果，约 1.5 秒后应进入 TRACK LOST 练习结算，
  再测试 Retry / Back。分别关闭顶部/背景效果，确认开关真的控制原生效果。
  若仍卡在加载后空白页，进入悬浮窗“设置”点击 **Copy diagnostics**，把剪贴板日志发回；日志会标明 JudgeControl.Update 是否触发以及 HP 生命周期停在哪一步。
- **噪域/统一**：分别测试遮罩、孔洞重叠、实际触摸阻挡、关闭视觉但保留阻挡；
  测试统一四种音符和清除原噪域，退出后重开原曲不得被永久修改。
  同时启用时噪域优先于清除原噪域。检查 Hold 短暂离手的容错边界。
- **判定/AP/FC**：修改 P/G 并启用 Custom judge，读取实际游戏状态而非 Preview；
  再测 AP 遇 Good、FC 遇 Bad/Miss 的重开，以及关闭 Custom judge 后恢复。
- **存档**：对比修改前后的最高分、RKS、解锁和奖励。辅助局不得写入；
  全部关闭并开始新一首后，普通局才恢复保存。故障锁定则需重启。

出现异常时请提供操作顺序、录屏、Validate 状态文字；闪退另提供系统崩溃日志。
请先单独开一个功能，确认后再做组合测试，不要一上来全部开启。

## 验证边界与仍未完成的部分

本地已通过玩法核心、ARM64 网关模拟、原始二进制及 dump 合同检查。
部分 Objective-C++ 文件只做了临时声明桩的宿主编译，**不等于 Apple SDK 编译**。
这份新源码还没有经过 iPad 实测；UIKit 界面文件也不能靠这些测试证明正确。

自制谱导入/管理/章节导航、完整 RPE 变换/装饰/视频/Shader、皮肤/头像/音效资源
生态尚未全部移植。MOD 导航按钮使用 Unity，编辑器主体仍为 UIKit，
尚未与 Android 设置页面逐像素一致。不能将这版描述为全部功能已完成的正式版。

普通签名、未越狱设备安装仍待单独验证，TrollStore 测试不代表该路径已经验证通过。
