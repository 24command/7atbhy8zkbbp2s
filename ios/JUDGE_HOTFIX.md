# Custom judge fix - 2026-10-16

> Historical framework6 judge-hotfix notes. The newer source also requires
> the offline gameplay backend before enabling Custom judge, so the new build
> must be repackaged with the updated tools. See GAMEPLAY_UI_PORT.md.

## Cause

`ProgressControl.Update` resets JudgeControl.PerfectTimeRange / GoodTimeRange /
BadTimeRange every frame. In the supplied UUID-gated iOS 4.0.1 binary:

- 0x1592808: normal P/G store (`stur d0, [x8, #4]`)
- 0x159287C: challenge P/G store (`stur d1, [x8, #4]`)
- 0x1592890: B store (`str s0, [x8, #12]`)

The old UI wrote only once and reported success without comparing readback.
It was overwritten by the next game frame. A timer cannot reliably solve this.

## Fix

- `patch_judge_windows.py` redirects exactly these three stores in a staging copy
  of UnityFramework to conditional RX trampolines. This is an offline patch,
  before signing, not an on-device writable-code hook.
- Adds a 40-byte zero-fill state in unused __DATA VM tail (outside all existing
  fields, BSS and common symbols). New section ordinals in nlist are corrected.
- Original engine values are always recorded. Override ON substitutes requested
  windows; OFF executes the original instructions, including challenge changes.
- Main-thread runtime explicitly initializes the judge class, validates metadata,
  verifies the offline patch protocol, writes P/G/B, compares readback and only
  then enables interception. Failed verification disables interception and
  attempts baseline restoration; game-state readback remains the truth.
- Editing while disabled does not capture or mutate game baseline. B is recomputed
  as max(220 ms, G + 40 ms) each edit; expansions do not accumulate.
- Stored enable/config resumes after game readiness (bounded startup retry).
- Preview does NOT apply anything. It shows draft values and separately read
  actual values/status. Other gameplay switches were drafts in framework6;
  the current v2 / 55-hook source connects them (see GAMEPLAY_UI_PORT.md).

## Build and package

1. Upload the updated `ios/` and root `.github/workflows/build-ios.yml` to your
   existing build repository. Run the workflow and download the NEW framework.
   framework5 is the old binary and does not contain this runtime fix.
2. Use the updated packaging tool with the ORIGINAL extracted Payload and new
   framework. The tool detects `PMJudgeHook-v1` in the new framework and applies
   the offline patch automatically. Merely replacing PhiMod.framework in the old
   IPA is insufficient. Re-running the patch on an already patched binary is
   rejected intentionally.
3. Re-sign/install as before (TrollStore test first). Ordinary certificate signing
   needs separate testing; this fix has not proven non-jailbroken compatibility.

Example (substitute the new extracted framework path):

```powershell
python ios/tools/package_unsigned_ipa.py --source G:/games.Pigeon.Phigros_4.0.1_und3fined --framework NEW/PhiMod.framework --output Phigros-PhiMod-judge-hotfix.ipa
```

## Device regression test

Back up saves first. Save/ranking/result protection is NOT installed. Avoid cloud
sync and official score submission; use a separate local test save if possible.

1. At the normal song selection screen: Custom judge OFF. Read game state and
   check normal P80/G180/B220 ms (challenge mode can have different originals).
2. Set P40 / G90, enable Custom judge. Read state immediately, enter a song,
   wait several seconds and read again: P40/G90/B220 + Custom judge verified.
3. Retry, then enter another song. Read again: values must remain P40/G90/B220.
   Compare a consistently early/late Tap: it should not retain the original
   80 ms Perfect window. Repeat enough to distinguish input timing variance.
4. While playing set G300: B should become 340. Change G90 again: B must shrink
   back to 220, not remain 340.
5. Turn Custom judge OFF during play; actual readback should return to the most
   recent engine baseline. In normal mode: P80/G180/B220. Check retry/next song
   and challenge mode OFF-path behavior too.
6. Restart with the switch saved ON, then test foreground/background and pause.
   If it reports hook missing, you used an old framework or an old packaging tool.

## Validation boundaries

Local: rebuilt C++17 gameplay tests (10,124 checks), judge-controller tests,
8 dump contracts / 3 negative fixtures, and actual generated ARM64 execution via
Unicorn (normal/challenge paths, enabled/disabled, 90 repeated frames and two
ASLR slides per binary, register/flags/FP preservation). Both synthetic and real
binary fixtures pass. Injection + patching were also checked on a temporary copy.

Pending: Apple SDK build of this revision, real iPad timing/scene regression,
TrollStore installation of the rebuilt revision, and ordinary signing. No new
working IPA is claimed until a newly compiled framework is provided.
