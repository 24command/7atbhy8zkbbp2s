# Gameplay hooks and Android-style scene UI (2026-10-16)

## Deliverables: do not confuse these two builds

1. `Phigros-PhiMod-framework6-judge-hotfix-unsigned.ipa` at the project root
   embeds the downloaded framework6 unchanged. It contains the judge hotfix,
   NOT the subsequent gameplay/UI changes in this source tree.
2. This source revision adds the gameplay entry backend and scene UI. It must
   be built on the macOS GitHub runner, downloaded, and repackaged from the
   ORIGINAL extracted Payload using the updated packaging helper. Replacing
   the framework in an old IPA does not install the new Unity entry gates.

## Implemented in source; Apple build and iPad validation still pending

- 37 UUID/prologue-gated offline arm64 entry hooks, plus the three judge stores.
- Actual Tap/Drag/Hold/Flick judgement interception for AutoPlay, with deferred
  Hold tail score credit and duplicate credit prevention.
- Score observation, configurable HP deltas / Track Lost, AP/FC retry,
  Accuracy scoring and fullscreen spatial checks.
- In-memory record/ranking interception and SaveManagement write interception.
- Assisted result presentation through a restricted set of original helpers;
  the stock reward/unlock/save iterator is not executed for an assisted result.
- Custom judge enablement requires the new protection backend to be installed.
- Original Mirror root is cloned for song shortcuts. Mirror is not replaced.
  First row: Mirror, AutoPlay, Noise, Unified. Second row: AP/FC, HP,
  Full Screen, Accuracy. Original cover/profile/difficulty/score UI stays intact.
- Original third Settings tab prefab is cloned for MOD. MOD content is UIKit,
  anchored below the real Unity tab; it is not a permanent screen overlay.
  HP rule/visual subpages include the LIFE hexagon, Save/Cancel and all HP
  parameters. This is a native adaptation, NOT a verified pixel-perfect port.
- Editor Save validates the full settings dictionary and commits once; Cancel
  discards the draft. Original content/animator/audio states are restored on
  tab changes and exit. Gameplay options are sampled at the next chart.

## Explicitly unavailable

Noise, Unified, No Noise, Hold grace/FX tuning, chart import/RPE resource/render
integration, chapter navigation and unlock/skin/audio replacement are NOT
complete. Noise and Unified song buttons are visible but disabled. Their draft
switches in the floating panel are disabled too; validation rejects enabling
unimplemented modes. The MOD editor clears old unsupported draft flags when
opening; they are persisted as off only when Save is selected.

## Protection boundaries

Protection is not a guarantee that every possible game/cloud persistence path
has been identified. Use a disposable/offline profile and back up saves.
The broad SaveManagement latch intentionally blocks OTHER game settings saves
while an assisted chart/result is latched. It is not cleared by turning switches
 off, OnDestroy, returning to song selection or a result animation. A new clean
LevelControl.Awake clears it after assistance has been disabled. Runtime faults
keep it latched until app restart. PhiMod's own NSUserDefaults settings are
separate. The special assisted result bypasses stock progression/rewards;
missing result contracts fail closed instead of falling back to stock saves.
Normal unassisted charts do not create a practice Session or scan chart notes.

No executable page is modified at runtime. Offline RX gateways load callbacks
from a separate RW zero-fill table; empty callbacks execute original prologues.
At startup the framework checks UUID, metadata, protocol, every site/prologue,
slot, gateway and all 12 words in each stub before publishing callbacks.

## What was actually tested on Windows

- 10,124 portable gameplay/chart rules; judge controller rollback/readback tests.
- Judge generated arm64 execution on a synthetic fixture and the local real
  UnityFramework with two ASLR slides.
- All 37 gameplay gates: dormant path, callback ABI/register/FP/flags/SP/stack
  arguments, callable original gateway, two ASLR slides.
- Combined dependency + judge + gameplay patches, repeat/wrong UUID/prologue
  rejection, and source/protocol consistency checks.
- Existing runtime dump contracts plus negative fixtures.
- Original UnityFramework SHA-256 remains
  `29b761de72ed4c2d7613294892fd23aa693dac0383bfab1646cfe5dbeffdf9a7`.

These tests do NOT compile UIKit/Objective-C++, verify Unity scene layout,
prove AutoPlay works in-game, or prove persistence isolation on-device.
Normal signing on a non-jailbroken device remains unverified; TrollStore success
must not be presented as proof of it.

## Build and repackage

Upload the `ios` directory AND root `.github` directory from the clean source
ZIP. Run the existing Build PhiMod iOS framework workflow. It now tests the
entry gates and protocol in addition to the core and judge trampolines.
Download and unpack the artifact until `PhiMod.framework/PhiMod` is present.
Use `ios/tools/package_unsigned_ipa.py` with the original extracted app, that
new framework, and a NEW output IPA filename. No new paid tool is required.
Keep the game binaries and IDA database local; do not upload them to Actions.

## Short device checklist (new build, not framework6)

1. Back up saves. Install using the established TrollStore test procedure.
   Use an offline disposable profile. Enter the game; floating panel > Validate
   gameplay config should report 37 installed entry hooks, not missing hooks.
   That button also retries installation if startup was too slow.
2. Check song shortcuts below difficulties and MOD tab in Settings. Open HP:
   edit a delta > Cancel > reopen (unchanged); edit > Save > reopen (retained).
   Change normal settings tabs / rotate / exit and check no hidden content or
   leftover editor. Noise/Unified must remain unavailable.
3. One mode at a time: AutoPlay on a mixed Tap/Drag/Hold/Flick chart; pause,
   resume, retry, and inspect long Hold tail credits. HP at 1 with a Miss;
   AP with a Good; FC with a Bad/Miss. Accuracy and Full Screen separately.
4. Custom judge: choose obviously small P/G, enable and read actual P/G/B during
   gameplay (not Preview), test early/late notes, disable and check restoration.
5. For EVERY assisted result: verify practice label, no best/RKS/reward/unlock
   change, also after turning switches off before exit and after restarting.
   Then disable ALL assistance, start a NEW chart and verify original gameplay
   and normal saves. Check backups/diffs, not just the result-screen wording.
6. If anything fails, provide the mode/options, song+difficulty, exact actions,
   screenshot of Validate/Read game state, and iPad crash log when applicable.
