# framework15 device fixes - 2026-10-21

Source of truth: `G:\Phimod-ios\ios`. Rebuild the framework before packaging.
Existing framework15 ZIP and IPA are unchanged. Hook protocol stays v2 / 61.

## Evidence

- `G:\loghp.txt`: failure delay completes, then the old implementation starts
  ProgressControl.LevelOver and destroys LevelControl. No successful result or
  selector transition is recorded. A subsequent process session is not by itself
  a crash stack trace.
- `G:\logchart.txt`: both operations stop after Content applied, before a new
  process session. There is no import callback log in the supplied recording.
- Android native/mod.cpp has a distinct put<P> specialization: reference values
  are passed directly to field_set_value, not by address.
- The original iOS UnityFramework confirms the same ABI. Export 0x13c9754 jumps
  to 0x1425a00 (instance setter); static export 0x13c9760 jumps to 0x1425ac8.
  Both call 0x14251b4 with dereference flag zero. Reference types pass the source
  pointer straight to the GC write barrier at 0x232c34. Scalars dereference it.
- The old iOS bridge passed &value for both categories. This stores a temporary
  stack address as GameInformation.song/chapters and navigation strings.
  Four Unicorn tests execute the actual iOS setters and reproduce this error,
  including static fields, null references and scalar writes.
- IDA health initially reported the correct image and completed analysis. The
  service disconnected on the next decompile request, then refused connections.
  No claim is made of a fresh successful Hex-Rays decompilation this session.
  The local original binary and archived devicefix_decomp.json LevelBreak
  decompilation were used instead; no binary/database modifications were made.

## Changes

1. PMIL2CPP.hpp: pass reference values directly; retain address-based scalar and
   value-type writes. Read back instance and static references immediately.
   The existing image UUID gate still applies; not a universal IL2CPP ABI rule.
2. PMContentRuntime.mm: exercise the setter on a disposable Chapter at startup.
   Add command/application/navigation stage logs, validate chapter existence and
   reject empty chapters before opening SongSelector. Report managed/Objective-C
   failures instead of silently returning no useful diagnostic. No library data
   is deleted or reset by this change.
3. PMHookBackend.mm: after the HP failure animation delay, call native
   LevelBreak("SongSelector"), acknowledge once, stop audio and finish HP visuals.
   Do not run LevelOver/result completion for this aborted attempt. Protect this
   failed attempt from score writes. AP/FC retry behavior is unchanged.
4. PMContentUI.mm: import as local copies; explicitly dismiss the document picker
   before background conversion. Log picker selection/cancellation and each
   import result. Keep busy UI visible and report failures after dismissal.

## Verification

- 32 source-contract tests passed.
- 4 actual-binary reference setter tests passed (instance/static/null/scalars).
- 191 metadata / 61 hook contracts, 480 source lookups and six negative fixtures.
- Runtime contracts and real-image judge/gameplay gateway emulation passed.
- All five portable C++ suites rebuilt and passed, including 3019 RPE checks.
- Apple SDK build, UIKit presentation and device scene transitions remain untested.
  No claim that the import cause is conclusively proven without callback logs.

## Device checklist

Back up saves and imported charts. Upload the complete updated ios directory and
rebuild using the existing GitHub workflow. Do not use framework15 for this test.

1. Launch: expect `Content reference write preflight passed`, PCM preflight and
   `PMHookBackend.install success hooks=61`.
2. With HP enabled, miss until zero. After the effect, expect
   `HP exit dispatched: SongSelector (no result)` and return to song selection.
   Test a second song to confirm audio and judgment resume normally.
3. Apply the unchanged library, then open an official nonempty chapter. Expect
   `Content references published and read back`, `Content LoadScene begin` and
   `Content LoadScene returned`, without a process restart.
4. Import one small local ZIP/PEZ. The picker should close and show importing,
   followed by a completion/error dialog. Expect `Content picker selected`,
   `Content import begin` and `Content import ok` or `failed`.
5. Test cancel, malformed ZIP, multi-file import and image replacement separately.
   If the picker stays open, capture a screenshot and the new session log: the
   presence/absence of `Content picker selected` separates File Provider issues
   from conversion failures. For a crash, also provide the iOS .ips crash report.
