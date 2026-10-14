# iOS 源码迁移状态（2026-10-15，本次续作）

## 本次新增：已接入源码，未完成 Apple 编译和真机测试
- PMRuntime：限定供给的 iOS 4.0.1 UnityFramework UUID，按 Assembly-CSharp.dll 查类。
- 动态解析 23 个 IL2CPP API；检查字段类型/静态性、方法参数和返回类型；不读取 MethodInfo 的私有布局。
- 游戏语言切换：对应 Android Bridge.setLanguage -> MultiLanguageManager.SetLanguage；先核验 getter/setter，切换后读回。支持 6/10/22/40/41，UI 先提供中文(6)和英文(10)。游戏自身可能持久化语言偏好。
- 实时状态快照：当前语言、Perfect/Good/Bad 毫秒、挑战状态和当前 RKS。RKS 是现有值，不是完整 B30 报告，也不主动重新计算。
- 所有入口限定主线程；仅在需要时附加 IL2CPP 线程；只释放自己拥有的附加。托管调用异常停止后续调用；语言切换异常不假称回滚。
- 设置页接入语言按钮和读取按钮；判定/模式开关仍为草案，不会改成绩或开启 AutoPlay。
- 未初始化的 GameInformation 拒绝操作。未做后台轮询或自动应用。

## 本次验证
- PhiMod-framework2.zip 内嵌 PhiMod.framework.zip；arm64、最低 iOS 15.0。这是修改前的产物，不包含本次新功能。
- 目标 UnityFramework UUID：6e181f31750a3044a73a1498dc2d56d4；23 个需要的导出均存在。
- verify_runtime_contracts.py 对 dump 校验 8 个声明，以及 3 个不兼容反例。此静态检查不证明 ABI/线程执行/真机加载一定正确。
- MCP 已实际连接 127.0.0.1:13337，server_health 确认打开的是目标 UnityFramework。查询时自动分析未完成；本次没有把未完成的反编译当证据，没有修改 IDB。
- 未在 Windows 上声称完成 Apple 编译；需要 GitHub macOS 构建和设备测试。

## 已有实现
UIKit 浮窗、拖动/穿透、配置持久化及范围校验、源代码构建脚本和 IPA 暂存打包工具。
Android 73/73 引用类型找到，34 个 Bridge 入口未全部迁移；类型匹配不等同于功能完成。

## 尚未完成
- 判定/AutoPlay/噪域/HP/统一键型等逻辑，以及练习局成绩隔离。
- 游戏帧执行点和 Hook 后端。当前主线程用户操作不替代完整 Unity Update 调度。
- 谱库/章节导航、自制谱导入、音频、皮肤、解锁、完整报告。
- 正常签名的非越狱设备加载验证；TrollStore 成功不能替代该验证。

## 验证流程
1. 上传新版源代码到 GitHub，运行 macOS 构建。不要上传 audit、dump、IPA、IDA 数据库。
2. 用新生成的 framework 打包（原始游戏和 framework2.zip 保持不动）。
3. 设备返回后先到游戏主界面：探测 -> 读取状态 -> 切英文 -> 切中文 -> 再读取；核对原生游戏 UI 是否实际更新。
4. 对照游戏原设置检查语言持久化、重启、前后台、横竖屏、打歌暂停菜单；如异常，记录场景和崩溃日志。
5. 判定/模式仍只保存草案；不要据开关状态认为生效。

当前无需购买额外工具。审计文件只留本地。
