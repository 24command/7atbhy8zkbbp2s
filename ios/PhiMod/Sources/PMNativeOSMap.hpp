#pragma once
#include "../Core/PMChapterVM.h"
#include "PMNativeOSMapReadiness.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace pmnativeosmap {
namespace layout {
inline int reservedScreen(const PMOSPage &page) {
    return page.entryTransition.declared && page.entryTransition.kind == PMOSEntryTransitionTimeline
        ? page.entryTransition.screen : -1;
}
inline bool reserved(const PMOSPage &page, int screen) {
    int index = reservedScreen(page);
    return index >= 0 && screen == index;
}
inline bool suppressed(const PMOSPage &page, const PMOSNode &node) {
    return node.songSuppressed || reserved(page,node.screen);
}
inline bool canDisplay(int screens, int transitionScreen, int screen) {
    return screen >= 0 && screen < screens && screen != transitionScreen;
}
struct Point { float x, y; };
struct Anchors { Point low, high; };
inline Anchors anchors(const PMOSNode &n) {
    return {{float(n.x), float(1 - n.y - n.h)}, {float(n.x + n.w), float(1 - n.y)}};
}
// Tracks use age after the most recent own/manual/parent visibility start.
inline double nodeAge(double now, double ownStart, double manualSince = 0, double parentShown = 0) {
    return std::max(0., now - std::max({ownStart, manualSince, parentShown}));
}
struct Numeric {
    double x, y, w, h, rotation, scaleX, scaleY, opacity, red, green, blue, alpha;
};
inline Anchors anchors(const Numeric &n) {
    return {{float(n.x), float(1 - n.y - n.h)}, {float(n.x + n.w), float(1 - n.y)}};
}
inline double boundedNumeric(int property, double value) {
    switch (property) {
        case PMOSTrackX: case PMOSTrackY: return std::clamp(value, -8., 8.);
        case PMOSTrackW: case PMOSTrackH: return std::clamp(value, 0., 8.);
        case PMOSTrackRotation: return std::clamp(value, -1e6, 1e6);
        case PMOSTrackScaleX: case PMOSTrackScaleY: return std::clamp(value, -16., 16.);
        default: return std::clamp(value, 0., 1.);
    }
}
// Upper-bound search: exact key times select that key (also for step segments).
// Callers may omit the pool entirely for static/legacy aggregate-zero nodes.
inline double trackValue(const PMOSTrack &track, const PMOSTrackKey *pool,
                         int poolCount, double age, double fallback) {
    if (!pool || track.count <= 0 || track.offset < 0 || track.offset > poolCount ||
        track.count > poolCount - track.offset) return fallback;
    const PMOSTrackKey *keys = pool + track.offset;
    if (!(age > keys[0].time)) return keys[0].value;
    if (age >= keys[track.count - 1].time) return keys[track.count - 1].value;
    int low = 1, high = track.count - 1;
    while (low < high) {
        int mid = low + (high - low) / 2;
        if (keys[mid].time <= age) low = mid + 1;
        else high = mid;
    }
    const auto &left = keys[low - 1], &right = keys[low];
    if (left.ease == PMOSTrackStep) return left.value;
    double dt = right.time - left.time, u = (age - left.time) / dt;
    if (left.ease != PMOSTrackCubic) return left.value + (right.value - left.value) * u;
    double u2 = u * u, u3 = u2 * u;
    return (2*u3 - 3*u2 + 1)*left.value + (u3 - 2*u2 + u)*(dt*left.outTangent)
         + (-2*u3 + 3*u2)*right.value + (u3 - u2)*(dt*right.inTangent);
}
inline Numeric numeric(const PMOSNode &n, double age,
                       const PMOSTrackKey *pool = nullptr, int poolCount = 0) {
    unsigned color = n.rgba;
    if (n.kind == PMOSImage && !(n.numericFlags & PMOSHasColor) && !color) color = 0xffffffffu;
    Numeric result {n.x, n.y, n.w, n.h, n.rotation,
        n.numericFlags & PMOSHasScaleX ? n.scaleX : 1.,
        n.numericFlags & PMOSHasScaleY ? n.scaleY : 1.,
        n.numericFlags & PMOSHasOpacity ? n.opacity : 1.,
        double((color >> 24) & 255)/255., double((color >> 16) & 255)/255.,
        double((color >> 8) & 255)/255., double(color & 255)/255.};
    age = std::max(0., age);
    if (n.trackLoop > 0 && std::isfinite(age)) age = std::fmod(age, n.trackLoop);
    double *values[] = {&result.x, &result.y, &result.w, &result.h, &result.rotation,
        &result.scaleX, &result.scaleY, &result.opacity, &result.red, &result.green, &result.blue};
    for (int i = 0; i < PMOSTrackPropertyCount; ++i) {
        if (n.tracks[i].count > 0)
            *values[i] = boundedNumeric(i, trackValue(n.tracks[i], pool, poolCount, age, *values[i]));
    }
    return result;
}
inline Numeric numeric(const PMOSPage &page, const PMOSNode &node, double age) {
    return numeric(node, age, page.trackKeys, page.trackKeyCount);
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
// Screen-clock samples are absolute. Repeated ticks never accumulate offsets.
struct Pose { float scale = 1, lift = 0, white = 0; };
inline Pose motion(const PMOSMotion &m, double age, float pulse) {
    Pose p;
    age = std::max(0., age);
    if (age < m.enter) {
        double u = age / m.enter - 1;
        // Ease-out back, starting at 0.68 and settling exactly at authored size.
        p.scale = float(1 + .32 * u * u * (3.5 * u + 2.5));
    }
    if (m.bob > 0 && m.bobPeriod > 0)
        p.lift = float(m.bob * std::sin(6.283185307179586 * (std::fmod(age, m.bobPeriod) / m.bobPeriod)));
    p.scale *= 1 + pulse * float(m.tapScale - 1);
    p.white = pulse * float(m.tapFlash);
    return p;
}
inline Anchors lifted(Anchors a, float lift) {
    float dy = (a.high.y - a.low.y) * lift;
    a.low.y += dy;
    a.high.y += dy;
    return a;
}
// One outstanding activation per visit. The clicked node keeps its original
// action index even when an ancestor supplies the visual feedback.
struct PendingTap {
    int node = -1, owner = -1;
    double start = 0, duration = 0;
    bool busy() const { return node >= 0; }
    void cancel() { *this = {}; }
    bool begin(int index, int group, double now, double seconds) {
        if (busy() || seconds <= 0) return false;
        node = index; owner = group; start = now; duration = seconds;
        return true;
    }
    float pulse(double now) const {
        if (!busy()) return 0;
        double u = std::clamp((now - start) / duration, 0., 1.);
        return float(std::min(1., std::min(.25 + 3.75*u, (1-u)*3)));
    }
    int take(double now, bool eligible) {
        if (!busy()) return -1;
        if (!eligible) { cancel(); return -1; }
        if (now - start < duration) return -1;
        int result = node;
        cancel();
        return result;
    }
};
inline int feedbackOwner(const PMOSNode &n, int index, int inherited) {
    return n.motion.tapTime > 0 ? index : inherited;
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
// open builds hidden at page.initialScreen; -1 leaves the map empty for the
// caller-owned card sheet. Reserved timeline nodes retain indices as empty items
// and never acquire map resources. Zero signals an acquisition error in reason.
// GIF and silent MP4 use the scene canvas. Drag releases dispatch the same node
// callback as buttons, after the piece has been placed on its declared target.
Visit open(Runtime &, void *parent, const PMOSPage &page, NSArray<NSDictionary *> *models,
           void *font, Activate activate, NSString **reason = nullptr);
bool displayPage(Runtime &, Visit, int screen); // reset time, retain overrides; reject reserved timeline screen
bool setElement(Runtime &, Visit, int nodeIndex, bool visible);
// Optional covered-transition staging. Call after open/displayPage, before any
// authored time has run, with visible=false and a nonzero transition token.
// prepare keeps the hierarchy active but alpha=0, clock=0 and input disabled.
// Only t=0 active media (including zero-alpha fades) participate. The caller must
// keep the private scene/canvas alive and active. Same-token prepare is idempotent;
// a new token replaces ownership without restarting already warmed media.
// pollPrepared uploads/holds first frames; it never runs input or advances time.
// A 3s monotonic deadline produces revealable Fallback (with counts), not a hang.
// Slow media retain their decoder work and continue warming behind the poster
// after reveal; only actual missing/decode errors become terminal failures.
// Invalid means wrong visit/token/page or consumed/cancelled staging; never reveal
// based on Invalid. Ready/Fallback are revealable; total==0 is immediately Ready.
// present(visible=true, runClock=true, ...) consumes the ticket and resumes held
// media without Stop/Prepare. Early reveal defers pending media behind the poster.
// present(..., visible, false, false) retains staging/held frames, including while
// shown frozen under the cover. Failure is sticky for that media for this Visit;
// its acquired frame/authored background is retained, not a synthesized poster.
// displayPage and close invalidate the ticket; ordinary show/hide semantics are
// unchanged after reveal. No ownership of caller's transition/token is retained.
bool prepare(Runtime &, Visit, uint64_t transitionToken);
ReadinessResult pollPrepared(Runtime &, Visit, uint64_t transitionToken);

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
