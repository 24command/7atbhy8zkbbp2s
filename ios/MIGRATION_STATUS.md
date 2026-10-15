# iOS 迁移状态（2026-10-15）

## 本轮交付
- 新增 PhiMod/Core/PMGameplayCore.hpp：C++17 玩法规则，无 Android 地址/JNI/Unity 指针。
- 移植判定窗口计算与基线恢复、AutoPlay 判定计划、Hold 尾端延迟计分与去重、Hold 容错、全屏空间覆盖计划、ACC-only 公式、统一键型、HP、AP/FC 重开规则、噪域矩形并集及练习配色。
- 新增 PMChartCore.hpp：Android 谱面 UTF-8→UTF-16 验证转换、RPE floor/control/Hold 几何和 HUD 偏移算法。这里只移植算法，不代表自制谱导入或 RPE 渲染接通。
- PMGameplay.h/.mm 将 UI 配置转换到核心并校验；新增“玩法核心配置校验（不应用）”和“玩法核心预览（不应用）”。明确返回 backendReady=false，不触碰游戏字段。
- 练习局隔离状态机：七项挂接覆盖缺一不可，辅助模式拒绝启动；隔离标记贯穿结果阶段，关闭开关不会解除；后端失败停止辅助且继续隔离。当前它只是核心规则，还没有拦截游戏实际写入。
- 核心补充假音符计分拒绝、HP 失败一次性派发及非有限判定样本拒绝。

## 实际验证结果
- Windows 本地使用 Zig 0.16.0 单任务编译最新 C++17 核心测试，启用 -Wall -Wextra -Werror -pedantic；通过 **10,124 项检查**。包含 100 轮随机噪域几何覆盖/不重叠检查、UTF-8 非法序列、生命周期、隔离、HP/挑战、Hold 计分和 RPE 计算。
- dump 静态合约：8 项声明 + 3 个反例 + 源码保护检查通过。PMRuntime 没有 field_static_set_value。
- IDA MCP 已重新确认目标 UnityFramework 和 auto_analysis_ready=true，auto_wait 返回 true；没有修改 IDB 或原始游戏。
- 本地 IDA 审计确认：LevelRecord.UpdateRecord 修改内存成绩；SetSongRecord 序列化并持久化；LevelOverControl.Start 是协程工厂，不能只拦工厂就宣称结算保护完整。
- framework4.zip：嵌套 PhiMod.framework.zip，Mach-O arm64 dylib，iOS 平台、最低 15.0，依赖系统框架；包含上一版运行时桥接，不含本轮 PMGameplay，需要重新构建。未在 Windows 验证 Apple 签名有效性。
- 已添加 macOS 主机核心测试步骤到两份构建工作流；Apple SDK 编译/设备测试还未执行。

## 功能分层
| 功能 | 源码状态 | 游戏内状态 |
|---|---|---|
| UIKit 浮窗、配置存储 | 已有实现 | 等待设备验证 |
| 语言切换、判定/RKS快照 | 运行时桥接已实现 | 等待设备验证 |
| 判定/AutoPlay/Hold/HP/AP-FC/ACC/统一键型/全屏 | 核心规则已移植并测试 | 未挂接，未启用 |
| 噪域 | 并集算法已移植 | 生成、触摸和视觉未挂接 |
| 练习局成绩隔离 | 状态机已移植并测试 | 保存、排行和结算拦截未安装 |
| RPE 与自制谱 | 部分编码/几何算法已移植 | 导入、资源和渲染未接通 |
| 章节导航、音频、皮肤、解锁、完整报告 | 尚未完成 | 未启用 |

## 后续关键工作
1. 对 iOS ARM64 的实际 ABI、生命周期及结算迭代器 MoveNext 验证，补齐完整游戏接入。
2. 选择并验证能服务普通签名非越狱目标的挂接方式；不能以越狱/Dobby 运行时改代码成功替代。当前没有离线 trampoline 或完整 hook 后端，不伪造 Coverage。
3. 先完整安装并验证成绩/排行/存档/结算保护，再开放玩法修改，避免污染存档。
4. macOS CI 重新构建；真机回到手边后做原生游戏、重启、前后台、暂停/退出、结果和存档对照测试。
5. TrollStore 和普通证书签名分别验证，当前未声称非越狱安装成功。

## 使用与交付
源代码上传包只包含 ios 和根目录工作流；audit、dump、IPA、IDA 数据库、编译器及测试 exe/pdb 都不上传。
本轮无需新购工具。Windows 的主机 C++ 测试不能代替 Apple Objective-C++/UIKit 编译。
