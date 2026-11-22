#pragma once
#include "../Core/PMChapterVM.h"
#include <algorithm>
#include <cstdint>

namespace pmnativeosmap {
namespace layout {
struct Point { float x, y; };
struct Anchors { Point low, high; };
inline Anchors anchors(const PMOSNode &n) {
    return {{float(n.x), float(1 - n.y - n.h)}, {float(n.x + n.w), float(1 - n.y)}};
}
// A negative value means outside the half-open interval. Zero is the first fade sample.
inline float opacity(double t, double start, double duration, double fade) {
    if (t < start || (duration > 0 && t >= start + duration)) return -1;
    double age = t - start;
    if (duration > 0) fade = std::min(fade, duration / 2);
    if (fade == 0) return 1;
    double alpha = std::min(1., age / fade);
    if (duration > 0) alpha = std::min(alpha, (start + duration - t) / fade);
    return float(alpha);
}
struct Sample { bool active; float local, inherited; };
inline Sample sample(float opacity, bool onScreen, bool manual, bool parentActive, float parentAlpha) {
    if (opacity < 0 || !onScreen || !manual || !parentActive) return {false, 0, 0};
    return {true, opacity, opacity * parentAlpha};
}
inline bool actionable(const PMOSNode &n) { return n.handler || n.open || n.dest >= 0; }
}
}

#ifdef __OBJC__
#import <Foundation/Foundation.h>
namespace pmbridge { struct Runtime; }
namespace pmnativeosmap {
using pmbridge::Runtime;
using Visit = uint64_t;
using Activate = void (^)(Visit, int nodeIndex);
// Unity main thread throughout. parent is a private RectTransform under the custom
// map scene Canvas (with GraphicRaycaster/EventSystem). The caller owns routing.
// font is a borrowed UnityEngine.Font used for visible authored labels. models
// are indexed exactly like page.elements and supply the already resolved paths.
// open builds hidden. Zero signals an acquisition error, with details in reason.
// GIF and silent MP4 use the scene canvas. Drag releases dispatch the same node
// callback as buttons, after the piece has been placed on its declared target.
Visit open(Runtime &, void *parent, const PMOSPage &page, NSArray<NSDictionary *> *models,
           void *font, Activate activate, NSString **reason = nullptr);
bool displayPage(Runtime &, Visit, int screen); // reset page time, retain visibility overrides
bool setElement(Runtime &, Visit, int nodeIndex, bool visible);
// Pause for background/detail/reveal. A frozen map may remain visible underneath
// a reveal. While awaiting a Lua action, pass input=false to prevent repeat input.
bool present(Runtime &, Visit, bool visible, bool runClock, bool input);
bool tick(Runtime &, Visit); // call on the scene update while presented
void *anchor(Runtime &, Visit, int nodeIndex); // borrowed RectTransform on current screen
bool owns(Runtime &, void *button);
bool press(Runtime &, void *button); // true consumes only an owned Button, including disabled ones
void close(Runtime &, Visit); // before unloading the private scene or destroying Runtime
}
#endif
