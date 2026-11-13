# Settings route / input diagnosis (2026-11-14)

## Finding
The previous onSettingTab hook unconditionally called settingsLeave before forwarding any ChangeTab request. An external duplicate request for tab 3 therefore restored the original three-entry arrays and then forwarded index 3 into native code. Requests from another Setting instance could also close the current MOD page. This is a code-level defect; without a new device log it is not proof that it caused every reported symptom.

## Changes
- Route requests by owner, internal transition guard, selected target and MOD state. Internal changes still call the original; an existing MOD page consumes repeated index-3 requests; switching to tabs 0..2 restores the original page normally. Foreign owners no longer tear down the active page.
- Add a single-touch fallback over the actual MOD tab RectTransform. Ignore drags/cancelled/multiple touches and native MsgBox overlays. Use the actual canvas/camera, with null checks. Native Button routing remains in place.
- Copy the native UI layer into the added hit target. Disable only Setting controllers copied inside the newly cloned MOD frame, not the real scene controller.
- Log page readiness after two frames, native navigation requests, precise leave reasons and per-update failures rather than silently retaining lastError.
- Embed the actual GitHub SHA in the framework at build time; log the runtime-loaded image path and compilation time. Warn when multiple PhiMod images are loaded. Settings marker: settings-route-v4-20261114.

## Previous camera error
The current ordinary MOD page path no longer calls projectTab; its remaining optional advanced-editor Canvas projection checks for null. The unlock/tab input hit tests also guard their canvases. Identical historical `Null call: get_worldCamera` text alone does not identify which build/session produced it. Diagnostics append sessions, so verify the new marker and build SHA in a fresh launch rather than assuming an older line is current.

## Verification
Local source regression tests, an executable fourth-tab routing test, the existing tap/geometry test, shell syntax checks, and 4.0.3 metadata verification pass (202 contracts, 72 hooks, 773 source lookups, 6 negative fixtures). Real Apple build status must be checked on Actions. No real-device success is claimed here.

Test: fully close/relaunch after installing the new framework; switch from each stock tab to MOD, tap MOD again, switch back, and use Back. Useful log lines: PhiMod runtime build=, MOD tab input ready, MOD tab touch fallback activation, MOD tab request, MOD page active/stable, MOD page leave reason=, MOD settings update failed.

No new hook and no chart/skin reimport. Rendering and unlock-button changes remain intact.
