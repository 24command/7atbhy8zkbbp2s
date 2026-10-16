# Gameplay / Android reference port - 2026-10-17

## Current revision

`PMGameplay-v2`, version 2, **54 hooks**, marker
`PMGameplay-contract-v2-54`; framework Info.plist version 0.2.0, build 54.
This is source only. framework7 is an older 37-hook v1 build.

## Implemented source paths

| Area | Implementation / boundary |
| --- | --- |
| Custom judge | Existing three-store offline judge patch, live P/G/B readback and transactional rollback. Preview remains explicitly non-applying. |
| AutoPlay | Original note Judge routines own effects/removal; managed note state is injected at note time. Hold score credits are deferred to the real tail. |
| Full Screen | Scoped positions in initial Tap/Flick collection and note Judge paths; restores originals afterwards. |
| Accuracy | Android noCombo means removing combo score contribution, not hiding the combo label. |
| AP / FC | Pending retry is acknowledged only after the transition is accepted. |
| HP | Adds `LevelMod/SecretChallengeLifeMod` + `LevelMod/HPDisplay` before original LevelControl.Awake. Reuses native Canvas/RawImage/material, TrueShadow, SmoothDamp and ApplyShaderParameters. |
| HP zero | Stops judging/freezes score, native failure flash/audio fade, 1.5-second delay, then the normal LevelOver transition into a protected practice result. |
| Practice result | Original Start allocates a real iterator; intercepted MoveNext yields a frame then invokes presentation-only helpers. Optional cover/audio failures cannot block canvas activation. Catastrophic failure offers Retry/Back; never falls back to reward/save MoveNext. |
| Scene buttons | Clones the existing Mirror-style song controls and settings tab. Hooks Button.Press + OnPointerClick + OnSubmit; original non-MOD buttons pass through. |
| Noise | Clones chart; supplies full native block and subtract masks; captures holes from real NoteMove calls; rectangle union prevents subtract-XOR overlaps; hooks real touch blocking. |
| No Noise | Clears blockAreaList on the cloned chart, not the cached original. Noise takes precedence if both switches are enabled. |
| Unified | Converts chart note types before SetCodeForNote, preserving speed semantics and synthesizing Hold length as in Android. 0=off, 1=Tap, 2=Drag, 3=Hold, 4=Flick. |
| Hold tuning | Noise-only temporary finger injection with managed Array.SetValue and guaranteed restoration. AutoPlay Hold FX is prepared BEFORE native NoteMove. |

Options other than Custom judge freeze at the next chart's Awake. HP parameter
changes mid-song do not silently rewrite the active session. The MOD editor
uses Save/Cancel and nested HP configuration pages; Unity supplies navigation,
UIKit supplies editor content. Exact Android pixel matching is not complete.

## Android code consulted

- `native/mod.cpp` levelAwake / SetCode / SetInformation for frozen modes,
  native HP mod loading, Unified and Noise chart construction.
- note movement / update / block-render / blocking paths for visible holes,
  grace history, native masks and material properties.
- holdJudge / holdMove / autoNote for temporary touch scope, delayed completion
  and effect ordering; Android raw managed-array layout was NOT copied.
- `native/hp_life_bar.inc`, `native/hp_selector.inc`, `native/practice.inc` and
  settings UI sources for HP presentation, mode semantics and persistence rules.

IDA was used on the original iOS binary to confirm entry instructions, real
calls to note-movement routines, inlined button/HP behavior and presentation-only
result helpers. `verify_gameplay_contracts.py` checks exact namespaces too:
PreviewBlockControl is under `ProjectEditor.PreviewScripts`, and
PreviewElementUpdateControl under `Phigros2.Level.Scripts`.

## Protection

The assisted-session latch survives chart destruction, switches being disabled,
and the result screen. It clears only on the next wholly unassisted chart's
Awake; a backend fault keeps it until relaunch. SaveManagement setters,
LevelRecord.UpdateRecord, SetSongRecord and UpdateRankingScore are guarded.
The original reward/unlock result iterator is never used as an error fallback.

This is intentionally broad: while protection is latched, unrelated saves can
also be suppressed. Do not use a valuable online profile for initial tests.
Host tests do not prove the absence of every inlined persistence path.

## Verification actually performed

- 10,124 gameplay/chart core checks; judge controller readback/rollback tests.
- 36 flow/transition checks; 57,696 Unified/Noise/Hold geometry and timing checks.
- 16 source/protocol regression tests, including real click paths, original
  button passthrough, scoped Hold buffers, native HP and stale-build rejection.
- Judge and all 54 gameplay gates: synthetic fixtures AND local original
  UnityFramework, two ASLR slides, dormant/callback/gateway paths, FP/register/
  stack invariants, combined injection and fail-closed mismatches.
- 8 existing runtime dump contracts + 3 negative fixtures.
- 169 gameplay metadata/hook contracts, 250 literal source lookup checks and
  5 negative fixtures for changed types/namespaces.
- PMChartModes, PMHPLife, PMHookBackend and PMGameplay compile to host objects
  against temporary declaration stubs. These are NOT Apple SDK builds or links;
  UIKit-heavy UI files were not validated this way. Stubs are excluded from delivery.
- Original UnityFramework SHA-256 unchanged:
  `29b761de72ed4c2d7613294892fd23aa693dac0383bfab1646cfe5dbeffdf9a7`.

No local Apple SDK, new device test, new compiled framework or new IPA exists
for this revision. Rebuild in Actions, repackage from the original Payload, then
follow [DEVICE_FIX_20261017.md](DEVICE_FIX_20261017.md).

## Not completed

Custom song import/storage/library/chapters/navigation; extended RPE resource
rendering, decoration/video/shaders; custom skins/avatars/hitsounds and the rest
of Android's resource pipeline. Non-jailbroken normal signing/install testing.
This is not a claim that every Android feature is finished.
