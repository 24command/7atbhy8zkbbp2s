#pragma once
namespace pmbridge { struct Runtime; }
namespace pmnativeswitch {
enum class Face { Hidden, List, OS };
enum class Press { Pass, Consumed, OpenOS, OpenList };
namespace detail {
// Lazy Unity checks keep unrelated, hidden and coordinator-gated presses cheap.
template<class CanPress> Press routePress(bool owned, Face face, bool input, CanPress canPress) {
    if (!owned) return Press::Pass;
    if (!input || face == Face::Hidden || !canPress()) return Press::Consumed;
    return face == Face::List ? Press::OpenOS : Press::OpenList;
}
}
// Unity main thread. Pass the installed custom chapter ID AFTER verifying it has
// a script. No discovery/ownership for retail chapters. Release on selector exit.
bool bind(pmbridge::Runtime&, void *songSelector, const char *customChapter);
// This is presentation state only. The coordinator owns mode and gating.
void show(pmbridge::Runtime&, Face, bool inputEnabled);
// Call once at native Button.Press BEFORE running the stock listener. Return
// anything but Pass => consume. Do not call a second time at Click/Submit.
Press press(pmbridge::Runtime&, void *button);
bool owns(pmbridge::Runtime&, void *button);
// Live Unity Button for the visible face, for coordinator raycast/input isolation.
void *visibleButton(pmbridge::Runtime&);
void release(pmbridge::Runtime&);
}
