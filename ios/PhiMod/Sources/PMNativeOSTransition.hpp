#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
namespace pmnativeostran {
// Times verified against 4.0.4 sharedassets1 CutOut/CutInFromBlack clips.
// Coverage is earlier than the native coroutine's 0.67-second switch gate.
constexpr double coveredAt = .5, switchAt = .67, revealDuration = .733333349;
enum class Phase { Closing, Covered, Loading, Ready, Revealing, Finished };
struct Gate {
    Phase phase = Phase::Closing;
    double elapsed = 0;
    bool external = false;
    explicit Gate(bool covered=false,bool authored=false):phase(covered?Phase::Covered:Phase::Closing),external(authored){}
    bool advance(double dt) {
        if (!std::isfinite(dt) || dt < 0) return false;
        elapsed += dt;
        if (phase==Phase::Closing && elapsed>=switchAt) {phase=Phase::Covered;elapsed=0;}
        return phase==Phase::Covered && !external;
    }
    bool request() {if(phase!=Phase::Covered)return false;phase=Phase::Loading;elapsed=0;return true;}
    bool ready() {if(phase!=Phase::Loading)return false;phase=Phase::Ready;elapsed=0;return true;}
    bool reveal() {if(phase!=Phase::Ready)return false;phase=Phase::Revealing;elapsed=0;return true;}
    bool finish() {if(phase==Phase::Finished)return false;phase=Phase::Finished;return true;}
};
}
#ifdef __OBJC__
#import <Foundation/Foundation.h>
namespace pmbridge { struct Runtime; }
namespace pmnativeostran {
using Ticket=uint64_t;
using Load=void (^)(Ticket);
using Done=void (^)(Ticket,bool);
// Acquire the actual stock CutIn clip while Loading.instance still owns it.
void rememberReveal(pmbridge::Runtime&);
// A short-lived persistent native cut, not a replacement OS scene. sourcePrefab
// is the source controller's verified cutOut. 'covered' starts at its opaque end.
Ticket begin(pmbridge::Runtime&,void *sourcePrefab,bool covered,bool authored,Load,Done);
bool request(Ticket); // Author video/timeline has reached its hold marker.
bool ready(Ticket,bool deferReveal=false);   // Destination scene AND presentation resources are ready.
bool reveal(Ticket,bool animate=true); // Authored continuation ended.
void cancel(Ticket=0);
bool active();
bool loading();
}
#endif
