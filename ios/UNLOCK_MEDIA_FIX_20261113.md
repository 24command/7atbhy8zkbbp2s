# Unlock animation fixes (2026-11-13)

- In the library, open a song difficulty or chapter -> unlock conditions -> unlock animation. Import MP4/GIF, remove assigned media, or choose unlock/start/both playback timing; save and apply to game.
- Imported media is staged until Save, validated with the same importer rules (up to 4096px / 600 seconds, GIF up to 32 MB), then copied to the individual entity asset directory. Failed saves remove the new copy; Cancel leaves the existing library untouched.
- Unity game audio is paused and muted while native unlock media plays, including between consecutive queued reveals. Previous listener pause/volume are restored on finish, skip, cancellation and failed presentation.
- Specific custom-chart requirements resolve their exact chart ID before merged-group fallback. The reference picker shows and preselects difficulty. Empty merged slots do not evaluate the base difficulty's rule. No assigned animation means a silent unlock.
- Result Continue interception uses the existing Button hook and a persistent Back callback targeting the current LevelOverControl. It waits for pending reveals, then invokes the original onClick event so the game's transition remains intact. Scores still come from existing saved records. Chained unlocks or unrecognized button layouts keep the menu route. No new hooks: 72 total.
- Backgrounding cancels a held Continue without consuming its reveal; tap Continue after returning to retry. Native GIF/video errors retain the existing short fallback + Skip behavior.

Validation: local 4.0.3 metadata check and relevant source tests passed. Added Foundation regressions for exact merged-chart references and separate seen/open states with identical rules. Full Apple SDK build is checked in Actions. Device verification is still required.

Retest: use two merged difficulties, assign media to only one, fulfill an ACC condition with normal scoring, and tap result Continue. Expect media before the transition, no preview overlap, correct Skip behavior, and no animation from the unassigned sibling. No chart reimport is needed for this change. Earlier Algebra visibility fixes still require original-chart reimport as documented separately.
