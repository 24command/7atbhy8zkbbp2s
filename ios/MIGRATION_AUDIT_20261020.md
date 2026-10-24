# Android → iOS 功能与 UI 复核（2026-10-20）

## 范围与状态

- iOS 权威源码：`G:\Phimod-ios\ios`。本轮只改源码，不覆盖 framework14 或已有 IPA。
- 旧安卓：`G:\Phigros浮窗MOD源码`；新安卓：`G:\PhigrosPhi-source_0.1.5-v4\PhigrosPhi-source_0.1.5-v4`。
- 对照了两版 `Overlay.java`、`Bridge.java` 和相关 Java/native 模块；不能以“存在同名设置”代替运行效果验收。
- “已接入口”表示源码连接存在，不代表已在 iPad 验证。仍是 PMGameplay-v2 / 61 个 hook；本轮无需增加 hook 位点。

## framework14 启动错误（已修改源码，待新构建实测）

日志中的 `Missing overload: static:Copy|System.IntPtr|System.Single[]|System.Int32|System.Int32` 发生在 `pmcontent::validate`，先于 61 个 callback 发布。不是单独的音频导入按钮报错，而是让全部 hook 安装失败，连带导致选曲快捷按钮等不能工作。

`dump.cs` 中 Marshal 保留了 byte/char/int/IntPtr 数组的公开 Copy 重载，没有 float 数组的该重载。
保留的内部方法是：

```text
Marshal.copy_from_unmanaged(IntPtr source, int startIndex, Array destination, int length)
RVA 0x2F25960 → native helper sub_13DD6F8
```

已通过当前 IDA MCP 只读复核：辅助函数先取 `il2cpp_array_element_size`，复制 `element_size * length` 字节。**length 是元素数量；参数顺序是 source、startIndex、destination、length。**

修复：
1. `PMContentRuntime.mm` 的预检与实际 PCM 音频导入均改为以上精确重载，不写死数组结构偏移。
2. 安装 hook 前复制并读回 4 个 float；成功日志为 `Content PCM copy preflight passed (4 float elements)`。数组根在异常路径也释放。
3. 补验 `AudioClip.SetData(float[], int)`；改善分配/音频格式失败诊断。
4. Missing overload 诊断补充接收类名。
5. 原检查器只覆盖类名、字段及部分人工维护的方法表。本轮增加字面量 `r.resolve/r.stat` 的精确签名检查和回归夹具，避免“类存在但重载被裁剪”再漏检。动态 receiver/循环调用仍不是全量静态证明。

IDA 结果、dump 摘录、备份与清单：`G:\Phimod-ios\audit\20261020-startup-ui`。

## 已有功能及入口

| 模块 | iOS 源码状态 / 入口 | 与安卓的差距 |
|---|---|---|
| 判定 P/G | 浮窗→判定、设置→MOD→判定；保留读回及成绩保护 | 安卓滑条/判定分析图未全部还原 |
| AutoPlay、噪域、去噪域、统一键型、AP/FC、全屏、HP | 浮窗、MOD 模式页及已连接的选曲原生快捷标签 | 新安卓额外规则见下一表 |
| 选曲快捷标签 | 继续使用原版 Mirror prefab 克隆及原生按钮事件 | 新版头像抽屉/自定义排列未移植 |
| HP 参数及顶部/背景视觉 | 模式→HP→生命规则/视觉效果 | HP 进入动画的独立开关未移植；此前 Miss 修复仍需设备验收 |
| 区间练习 | 三手柄、暂停预览、起止、循环、倒数、整首/区间、倍速、流速 | 本轮补齐 MOD 页内白色 UI、定位位置、流速设置入口；不宣称像素一致 |
| 自制谱库 | 系统文件选择器、多文件导入 ZIP/PEZ/JSON/PEC/RPE、搜索、播放、编辑、移动、删除、单谱导出 | 安卓的批量选择/导出、当前官谱编辑等未全量实现 |
| 多难度分组 | 现有“分组 / 多难度合并”与 `chartSelections` | 目前仍有输入 group ID 的表单，不等同安卓图形化版本选择器 |
| 章节 | 新建、编辑、封面替换、删除保留谱面、排序、章节包导入导出 | 不含完整解锁规则系统；官方章节管理范围有限 |
| 原版章节管理 | 名称/副标题/banner 文本覆盖、隐藏/恢复 | 不是官方歌曲/章节全部资源的任意编辑、排序和导出 |
| RPE 基础视觉 | 转换、判定线父子层级/缓动、Hold 几何、纹理、文字、Fake 音符 | 不等于全部 RPE 扩展和旧谱特效，见下表 |
| 诊断与语言 | 浮窗日志、游戏中文/英文切换；本轮补 MOD 页复制日志 | 没有完整 MOD 多语言跟随、日语和全语言菜单 |

## 未移植 / 部分移植的功能（不是隐藏了一个开关）

| 功能 | 安卓参考 | 当前 iOS 状态 |
|---|---|---|
| 保留 Hold、仅练 Hold | 新版 `practice.inc`、`Bridge.practiceExtras`、`ShortcutDrawer.java` | 无相应设置/玩法链路 |
| Early / Late 提示 | 新版 `early_late.inc`、`earlyLateHints` | 未接 HUD / 提示逻辑 |
| 实时 ACC 与去连击分分别开关 | 新版 `live_accuracy.inc`、`practice.inc`、`noComboScore` | 当前 iOS `noCombo` 仍表示原先“Accuracy/去连击分”；没有新版独立实时 ACC 显示。不能直接复用新安卓同名 key |
| 噪域金色视觉选项 | 新版 `noise_gold.inc`、`noiseGoldFull/Lines/Info/Notes` | 未移植全屏、判定线、曲目信息、音符分项效果 |
| HP 开场效果独立控制 | 新版 `hpStartEffect`、`hp_life_bar.inc` | 无独立控制入口/选项；不意味着现有 HP 完全无原生效果 |
| 头像与皮肤/资源包 | 两版 `AvatarCropView`、`SkinStore`、`skin_runtime.inc` | 自定义头像、音符/Hold/点击音效皮肤未接入 |
| 本地 P3+B27 / RKS 成绩图 | 两版 `RksReport*`、`rks_report.inc` | 缺少报告计算/导出和页面 |
| 判定分析图 | 旧版 `JudgeAnalysisView`、`Overlay.analysis` | 没有对应完整图表 UI；不能把基本计分统计视为已移植 |
| 解锁规则/动画/视频 | 两版 `UnlockStore/Rules/Editor/Animation`、`unlocks.inc` 等 | 无完整规则执行与编辑。现有章节包导入会去除 chapter.unlock，不保留此玩法行为 |
| 主线全解锁 | 新版 `mainline_unlock.inc`、`mainStoryUnlock` | 未移植 |
| 自定义抽屉 / 模式排列 | 新版 `ShortcutDrawer/Surface/Guide`、`shortcutConfig` | 仍为固定的选曲快捷标签，没有头像下拉抽屉 |
| LAN 联机整套模块 | 新版 `Lan*`、`lan_*` | 房间、传谱、投票、比赛、排名/结算均未移植 |
| Dodge 模式 | 新版 `DodgePanel`、`dodge_mode.inc` | 未移植 |
| RPE 视频与 shader | 新版 `rpe_video.inc`、`rpe_shader*` | 没有视频时间轴播放、shader uniform 执行链路 |
| 动态/超大纹理、旧谱专属特效 | `AnimatedLineTextures`、`LargeLineTextures`、`LegacyChartEffects`、`legacy_*` | 当前通用静态纹理/基础 RPE 不覆盖这些全部效果 |
| 官方谱面/音乐导出 | 新版 `chart_export.inc`、`OriginalMusic`、`SourceAudioStore` 等 | 当前主要导出本地导入的自制谱/章节包，缺官方资源提取链路 |
| 大批量库管理、封面裁剪/旋转 | 新版 `ChartDuplicates/Cleanup`、`ChapterCoverEditor`、`SongCropView` 等 | 有基本导入删除和替换封面，但无完整去重、批选导出、手动裁剪编辑器 |
| 直接编辑当前官谱、原版歌曲资源覆盖 | 旧版 `editCurrent/editOfficial` 等 | 当前原版管理主要是章节信息覆盖，不能视为整块完成 |
| 安卓共享存储 / 外部导入 Activity / TapTap 专属 UI | Android 平台代码 | 不直接复制；iOS 已使用系统文件选择器与安全作用域文件访问；其余平台适配未实现 |

## 本轮 UI 实际改动

- 新增 `PMOfficialUI.h/.mm`：复用安卓 tan(15°) 斜切形状、96×36 开关视觉比例、白色滑块、180ms 动画；触摸高度至少 44pt，支持辅助功能与减少动态效果。
- MOD 页导航改为 **谱库 / 章节 / 判定 / 模式 / 设置**，默认进入模式；分类描述可收起，保留保存/取消和跨页草稿。
- 模式采用深色斜切卡片，宽屏两列；HP、噪域、AutoPlay、练习进入独立详情；统一键型/AP/FC 改为可选菜单而非填写数值枚举。
- 谱库/章节列表改为深色封面卡片及难度色块，保留搜索、实际管理动作和 iOS 原生文件选择器。
- 浮窗移除旧英文说明，主要操作汉化；诊断失败本身仍保留具体技术信息，不掩盖错误。
- 37 个当前 iOS 设置 key 均找到 UI 引用；本轮补充的是 MOD 页入口，而非声称这些设置以前完全没有浮窗入口。

**尚未做到像素级 1:1**：安卓专用字体、所有资源/封面、分组弹窗、裁剪器、滑条、全部转场与完整图库布局仍有差距。使用 UIKit 重建，不复制 Java 绘制代码就声称运行成功。

## 验证与下一步

本轮已通过：29 项源码回归测试；191 个 metadata / 61 hook 契约；481 个源码查找检查及 6 个反例；真实 UnityFramework 的 3 项 gameplay gate 测试与 2 项 judge trampoline 测试；5 组可移植 C++ 测试（包括 3019 项 RPE 检查）。

未完成：Apple SDK 的 Objective-C++ 编译、新版 framework 和 iPad 实机 UI/音频验证。Windows 静态检查不替代它们。

1. 将 `G:\Phimod-ios\ios` 的全部更新源码上传仓库的 `ios/`，尤其不要漏掉 `PMOfficialUI.h/.mm`，重新触发现有 GitHub 构建。
2. 取得新 framework 后再从干净 Payload 重打 IPA；**不要复用 framework14 声称错误已修复**。
3. 备份存档与自制谱；不要为了测试直接卸载唯一一份有数据的应用。
4. 启动日志应出现 `Content PCM copy preflight passed (4 float elements)` 和 `PMHookBackend.install success hooks=61`，没有重复 Missing overload。
5. 先关闭模式进入普通歌曲并结算；再测试 MOD 分类、开关、保存/取消、横屏布局；最后用短音频自制谱测试导入和播放。
6. 若仍失败，提供完整新 session 的初始化日志；若界面遮挡/无法点击，附截图和操作顺序。
