#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

namespace phimod::judge {
// Shared with tools/patch_judge_windows.py. Only the Unity/UIKit main thread
// accesses this state. No writable executable pages, pointer rebinding or timer.
struct PatchState {
    uint32_t enabled;
    uint8_t pairSeen, badSeen, reserved[2];
    float perfect, good, bad;
    uint32_t padding;
    float enginePerfect, engineGood, engineBad;
    uint32_t tail;
};
static_assert(sizeof(PatchState)==40);
static_assert(offsetof(PatchState, perfect)==8 && offsetof(PatchState, bad)==16);
static_assert(offsetof(PatchState, enginePerfect)==24 && offsetof(PatchState, engineBad)==32);
struct Windows { float perfect, good, bad; };
inline bool valid(Windows w) {
    return std::isfinite(w.perfect) && std::isfinite(w.good) && std::isfinite(w.bad)
        && w.perfect>0 && w.good>=w.perfect && w.bad>=w.good && w.bad<=10;
}
inline bool matches(Windows a, Windows b) {
    return valid(a) && valid(b) && std::fabs(a.perfect-b.perfect)<0.000001f
        && std::fabs(a.good-b.good)<0.000001f && std::fabs(a.bad-b.bad)<0.000001f;
}
inline Windows target(double p, double g) {
    if (!std::isfinite(p) || !std::isfinite(g) || p<1 || p>1000 || g<p || g>2000)
        throw std::invalid_argument("Judge window range invalid");
    return {float(p/1000),float(g/1000),std::max(.22f,float(g/1000)+.04f)};
}
inline Windows configured(const PatchState &s) { return {s.perfect,s.good,s.bad}; }
inline Windows engine(const PatchState &s, Windows fallback) {
    Windows w=s.pairSeen && s.badSeen ? Windows{s.enginePerfect,s.engineGood,s.engineBad} : fallback;
    if (!valid(w)) throw std::runtime_error("Engine judge baseline not ready");
    return w;
}
class Controller {
    bool captured=false;
    Windows baseline{};
public:
    // Reader/writer are the same production IL2CPP functions used by PMRuntime.
    // A failed readback disables interception and attempts restoration; never
    // report success merely because the managed setter returned normally.
    template<class Read, class Write>
    Windows apply(PatchState &s, bool enabled, double p, double g, Read read, Write write) {
        Windows requested=enabled ? target(p,g) : Windows{};
        Windows before=read();
        if (!valid(before)) throw std::runtime_error("Judge class not initialized");
        if (!enabled && !s.enabled && !captured) return before; // editing disabled config is read-only
        if (!captured) { baseline=before; captured=true; }
        Windows restore=engine(s,baseline);
        Windows desired=enabled ? requested : restore;
        s.enabled=0;
        s.perfect=desired.perfect; s.good=desired.good; s.bad=desired.bad;
        Windows actual{};
        try {
            write(desired);
            actual=read();
            if (!matches(actual,desired))
                throw std::runtime_error("Judge readback mismatch; override disabled (read game state)");
        } catch (...) {
            try { write(restore); } catch (...) { /* preserve original failure, override remains OFF */ }
            throw;
        }
        s.enabled=enabled ? 1u : 0u;
        if (!enabled) captured=false;
        return actual;
    }
};
} // namespace phimod::judge
