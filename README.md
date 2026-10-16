# PhiMod iOS gameplay/UI source revision - 2026-10-16

Upload this directory's CONTENTS (including hidden `.github`) to the repository
root, replacing its existing `ios` and root workflow files. Run the Build PhiMod
iOS framework workflow in GitHub Actions. Download its framework artifact and
return it for IPA repackaging; the game itself must never be uploaded to CI.
No new paid tool is required.

IMPORTANT: This source revision is NOT included in the already packaged
`Phigros-PhiMod-framework6-judge-hotfix-unsigned.ipa`. That IPA embeds downloaded
framework6 unchanged and includes only the preceding judge hotfix.

The new Objective-C++/UIKit source still needs an Apple SDK build and device
tests. Passing C++/ARM64 emulator/static tests is not evidence of an Apple build.
Noise/Unified/No Noise and several other Android subsystems remain disabled.
The Settings MOD content is a native adaptation, not a pixel-perfect Unity UI.
Use an offline disposable profile and back up saves before testing assistance.

Read `ios/GAMEPLAY_UI_PORT.md` for scope, protection limits and the short device
checklist. Read `ios/README.md` for the build/package/signing procedure.
