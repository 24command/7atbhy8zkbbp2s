# PhiMod iOS - device fixes + native gameplay modes

Source revision: **2026-10-18**, protocol **PMGameplay-v2 / 61 hooks**,
framework version **0.2.0 (61)**. This revision is newer than framework13.
**It must be rebuilt with the Apple iOS SDK before creating a new test IPA.**

Start with [HP_PRACTICE_20261018.md](HP_PRACTICE_20261018.md) for this revision, [DEVICE_FIX_20261017.md](DEVICE_FIX_20261017.md) for the Chinese
build/test checklist, and [GAMEPLAY_UI_PORT.md](GAMEPLAY_UI_PORT.md) for scope
and safety boundaries. Portable C++ cores were rebuilt and run with local MSVC. Source-contract, metadata, judge-patch, and real-image hook-gate checks have passed on Windows. This revision still needs the macOS Apple SDK build and real-device verification.

## MOD full-width page / unlock modal input (2026-11-14)

See [UI_MODAL_LAYOUT_20261114.md](UI_MODAL_LAYOUT_20261114.md): shared native page host, full-width settings rows, larger left-aligned unlock dialog and exclusive selector input until the closing touch is released. Current runtime marker: `settings-layout-v5-20261114`. No new hooks (72) or reimport; device verification remains required.

## MOD fourth-tab routing / loaded-build diagnosis (2026-11-14)

See [SETTINGS_ROUTE_20261114.md](SETTINGS_ROUTE_20261114.md): owner-aware tab routing, duplicate fourth-tab protection, native tab touch fallback and page-exit tracing. Builds now embed the GitHub SHA; runtime marker `settings-route-v4-20261114` identifies the actually loaded framework. No new hooks or reimport. Device switching still requires verification.

## Unlock-details button input / native slanted style (2026-11-14)

See [UNLOCK_BUTTON_INPUT_20261114.md](UNLOCK_BUTTON_INPUT_20261114.md): native LeanPolygon parallelogram, precise single-touch fallback with drag/duplicate guards, and a retained original message box even if optional scrolling fails. No new hooks or reimport. Device click/scroll validation remains required.

## MOD tab / unlock details / CPU follow-up (2026-11-14)

See [TAB_UNLOCK_CPU_20261114.md](TAB_UNLOCK_CPU_20261114.md): independent clickable unlock-details button and native scrollable MsgBox, native tab readback/interaction safeguards, and reductions in measured custom CPU work. The supplied small log repeats the previously fixed null-Canvas session; check the new `20261114-b` marker in the latest build. No chart reimport or new hooks (72). Actual iPad FPS/UI validation is still required.

## MOD tab / hit effects / iPad runtime (2026-11-14)

See [IPAD_RUNTIME_FIXES_20261114.md](IPAD_RUNTIME_FIXES_20261114.md) for the log-confirmed null-Canvas rollback fix, post-native hit-effect placement/scale, and CPU/GPU/video overhead reductions. No chart reimport, no reduced shader resolution, and no new hooks (72). Device validation remains required.

## MOD tab input / RPE performance (2026-11-13)

See [TAB_RENDER_OPTIMIZATION_20261113.md](TAB_RENDER_OPTIMIZATION_20261113.md) for the independent native tab hit target, cached note/line visibility, lifetime cursors, and pooled shader buffers. Current hook count remains **72**; no chart reimport is needed. Device click/FPS validation is still required.

## Chapter management update (2026-11-13)

See [CHAPTER_MANAGEMENT_20261113.md](CHAPTER_MANAGEMENT_20261113.md) for bulk moves, official-song references and cover edits, expanded chapter-cover fitting, compact Android-format exports, and dense-chart render caching. Existing native save identities and72-hook protocol are preserved.

## Changes

- Practice result coroutine presentation and navigation-only recovery.
- HP startup no longer adds optional visual assets to the native chart-loading gate. Native SecretChallengeLifeBar and HPDisplay are instantiated asynchronously after chart readiness, with independent resource diagnostics.
- HP failure delay/transition and native floor-buffer capacity repair.
- Real Button.OnPointerClick / OnSubmit paths for the MOD tab and song shortcuts.
- Noise masks and touch blocking; No Noise; unified Tap/Drag/Hold/Flick conversion.
- Noise Hold grace and AutoPlay Hold effect interval, following Android logic.
- Range practice: draggable timeline, paused live note preview, range markers, pause/resume/repeat, looping, three-second count-in, and live rate controls. Crossing Holds are trimmed from restored source data on each rewind.
- The in-game MOD editor now has categorized mode/practice/judgment/noise/UI pages, with a separate HP rules/visuals page.
- Practice controls now mirror Android’s industrial and white panels: three draggable handles, editable timestamps, countdown toggle, rate/flow controls and paused preview.
- Added local library/chapter management with the iOS document picker, ZIP/PEZ safety checks, native v3/PEC/RPE conversion, cover replacement, chapter ordering, multi difficulty groups and original chapter browsing.
- Added Android-style RPE line/note visuals: easing, parent lines, floor integration, custom sizes/alpha, line textures, extended text and fake notes.
- AddressableAudioSource.Update rate mapping and nested judge-window scaling follow the Android playback-rate path.
- Android's JudgeControl.Update floor-buffer capacity guard is restored before the native judge update.
- Save/RKS/reward/unlock protection covers custom judge, AutoPlay, No Noise, full-screen judgment, Accuracy, Unified, range practice, and changed playback rate. HP/AP/FC alone follow the previously requested save policy.

Video playback, shader uniform execution, custom skins and exact pixel-for-pixel Android settings presentation still require additional device-specific work. Library import/export and RPE conversion are implemented in source and require Apple SDK/device validation. The MOD tab
uses a native Unity navigation button with a UIKit editor. Do not call this a
fully verified Android port or a verified normal-signing release.

## Build on GitHub Actions (no local Mac required)

Upload the contents of the clean source package into the repository root, with
both `ios/` and `.github/workflows/build-ios.yml` present. Do not upload game
binaries, dump.cs, metadata, IDA databases or the extracted IPA.

Run the existing `Build PhiMod iOS framework` workflow. The workflow tests the
portable cores, generated ARM64 gateways and source contracts, then builds the
arm64 framework on macOS and checks its protocol markers. Download the artifact
and unpack until `PhiMod.framework/PhiMod` is present.

Equivalent on a Mac:

```bash
bash ios/build_unsigned.sh
```

## Package locally on Windows

Use the NEW framework with the NEW packaging tools and the ORIGINAL extracted
Payload. Merely replacing PhiMod.framework inside an older patched IPA is not
sufficient: the Unity entry gates changed from 37 to 61 and from v1 to v2.
The helper rejects stale frameworks before copying the game. The current source revision requires the 61-hook framework.

```powershell
python ios\tools\package_unsigned_ipa.py `
  --source "G:\games.Pigeon.Phigros_4.0.1_und3fined" `
  --framework "C:\path\to\PhiMod.framework" `
  --output "G:\Phigros_4.0.1_PhiMod_devicefix_unsigned.ipa"
```

The source app is not modified. In a temporary copy, the helper embeds
PhiMod.framework, adds the load dependency to UnityFramework, installs the
UUID/prologue-gated judge patch and 61 gameplay gateways, and removes old
signature data. No runtime executable-page writes or external hook library are
used. Final output is deliberately unsigned.

Signing and installation on an ordinary non-jailbroken device are separate
acceptance steps. A TrollStore test alone is not evidence of normal-signing
compatibility. Keep signing credentials and provisioning files out of the repo.

## Local verification

```bash
bash ios/tests/run_core_tests.sh
python ios/tests/test_source_contracts.py
python ios/tests/test_judge_patch.py
python ios/tests/test_gameplay_hooks.py
python ios/tools/verify_runtime_contracts.py /path/to/dump.cs
python ios/tools/verify_gameplay_contracts.py /path/to/dump.cs
```

The emulator tests require `unicorn==2.1.4`. They also accept `--unity` to audit
the local original UnityFramework without altering it. Dump verification checks
metadata/ABI and source lookup contracts, not in-game execution.

## 2026-11-12：合并难度与解锁详情

- 列表初始化时为所有自制歌曲补齐难度数量、AT 槽位及每格宽度，不再要求先选中过歌曲才能显示 AT。
- 切换全局难度后，刷新列表中各首合并歌曲的锁标记和曲绘锁定遮罩；锁定 AT 不应残留到已解锁 IN。
- 简短解锁条件继续单行显示；按现有框体测量后若需缩小到 20 号以下，则改为“查看解锁要求”按钮。
- 详情复用游戏原生 PhigrosUI / MsgBox，内容使用 28 号字、支持纵向滑动；保留原生确认关闭按钮，不调用云存档同步逻辑。
- 不改存档 ID、成绩记录或解锁规则。已有谱面无需重新导入。

测试重点：未访问歌曲直接切 AT；锁定 AT → 切其他歌曲 → 切 IN 返回；超长条件点击、滚动、关闭后再次打开；章节锁与课题限制仍有效。
本次源码检查已通过，实际设备布局和触摸仍需验证。iOS 源码的当前本地位置为 G:\phimod项目\Phimod-ios\ios。
## 2026-11-12：资源管理与原版 MOD 设置页（72 Hooks）

**打包要求变更：新增四个资源包 Hook，需使用本版本 tools/ 重新打包原版 iOS 4.0.3 IPA。旧 68-Hook IPA 仅替换 framework 不兼容。** 构建标记为 `PMGameplay-contract-v2-72-ios403`，打包脚本会拒绝旧标记。

- 导出 ZIP 是临时分享副本：系统导出成功、取消或分享完成后清理；上次进程遗留的 ZIP 在下一次启动谱库时清理。用户已经保存到其他目录的文件不删除。
- 谱库左上新增“回收站”：恢复谱面、原章节（章节已不存在则回默认收藏）、未被新操作替代的难度版本选择；永久删除必须再次确认。删除提交失败回滚文件移动，恢复不覆盖已有同 ID 谱面。
- 新删除记录保存完整元数据。旧回收目录会尝试从 library.backup.json 找回对应歌曲；找不到时标注“缺少元数据”，不能自动恢复原分组和条件，可保留目录后另行导入，或确认永久删除。
- 解锁条件搜索选曲后关闭的是完整搜索导航窗口，再显示 ACC/分数等数值输入，不再只关闭搜索栏。
- 皮肤管理支持“编辑”或左滑删除；删除当前皮肤会关闭皮肤开关，下次进曲回到原版。已有曲目播放期间的已载入素材在退出后清理。
- 资源包 `hit_fx.png` 按 `info.yml` 的 `hitFx` 行列播放，支持 hitFxDuration/hitFxScale/hitFxRotate/hitFxTinted/colorPerfect/colorGood；按原生特效生成时机替换，不额外记分。单次会话最多64个并发自定义特效，超出回退原版。
- `click / drag / flick` 的 WAV/OGG/MP3/FLAC 音效导入为 M4A，通过游戏 PlayHit/PlayNA/PlayUnityFx 入口按原打击音量替换；找不到或无法加载的项目回退原音效。直接 M4A 也接受。旧已导入皮肤会在加载时尝试转换保存过的音效文件。
- `line.png`（导入也接受 judgeline.png）替换普通判定线样式；带专用贴图/文字的故事板线仍使用谱面自己的资源。旧版导入时被忽略的 line.png 需要重新导入皮肤包。
- 悬浮按钮透明度范围为0到1，0在本次进程中有效；下次启动自动恢复默认0.96，其余数值保持。
- MOD 常用页复用原版 SettingItemsManager 的 AddButton/AddToggle/AddSlider/RefreshItems/RefreshPosition。常用开关即时保存；判定、HP数值、练习等复杂配置通过“高级参数”进入原有详情页，保留保存/取消事务。

测试覆盖：回收移动失败回滚、恢复/永久删除、路径边界和导出清理；透明度重启恢复；72-Hook 协议及元数据；原生设置函数、皮肤绑定与特效/音效调用接线。实际视觉样式、音量和触摸仍需实机验证。