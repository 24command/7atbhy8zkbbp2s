#include "../PhiMod/Core/PMJudgeCore.hpp"
#include <cassert>
#include <cstdio>
#include <limits>
using namespace phimod::judge;
int main() {
    PatchState s{}; Controller controller; Windows game{.08f,.18f,.22f}; int writes=0;
    auto read=[&] { return game; };
    auto write=[&](Windows w) { ++writes;game=w; };
    controller.apply(s,false,50,100,read,write);assert(writes==0 && !s.enabled);
    auto actual=controller.apply(s,true,40,90,read,write);
    assert(s.enabled && matches(actual,{.04f,.09f,.22f}));
    // An engine frame/scene reset must see the configuration via the patch.
    s.pairSeen=s.badSeen=1;s.enginePerfect=.065f;s.engineGood=.115f;s.engineBad=.135f;
    game=configured(s);assert(matches(game,{.04f,.09f,.22f}));
    controller.apply(s,true,60,300,read,write);assert(matches(game,{.06f,.30f,.34f}));
    controller.apply(s,true,40,90,read,write);assert(matches(game,{.04f,.09f,.22f})); // B must shrink, not accumulate
    controller.apply(s,false,40,90,read,write);
    assert(!s.enabled && matches(game,{.065f,.115f,.135f})); // latest engine baseline, not stale menu baseline
    int previous=writes;controller.apply(s,false,80,180,read,write);assert(writes==previous);
    // A setter that silently ignores the requested values must not return success.
    bool failed=false;
    try {controller.apply(s,true,30,60,read,[](Windows){});}catch(const std::runtime_error&){failed=true;}
    assert(failed && !s.enabled);
    // Partial write failure restores all fields and disables interception.
    failed=false;bool first=true;
    try {controller.apply(s,true,20,50,read,[&](Windows w){game.perfect=w.perfect;if(first){first=false;return;} game=w;});}
    catch(const std::runtime_error&){failed=true;}
    assert(failed && !s.enabled && matches(game,{.065f,.115f,.135f}));
    for (auto p : {0.0,1001.0,std::numeric_limits<double>::quiet_NaN()}) {
        failed=false;try {controller.apply(s,true,p,180,read,write);}catch(const std::invalid_argument&){failed=true;}
        assert(failed && !s.enabled);
    }
    // Before the first ProgressControl frame restore the class-initialized baseline.
    PatchState early{};Controller c2;game={.08f,.18f,.22f};
    c2.apply(early,true,10,20,read,write);c2.apply(early,false,10,20,read,write);
    assert(matches(game,{.08f,.18f,.22f}) && !early.enabled);
    game={0,0,0};failed=false;
    try {c2.apply(early,true,10,20,read,write);}catch(const std::runtime_error&){failed=true;}
    assert(failed && !early.enabled);
    std::puts("PASS judge controller: readback, reset baseline, enable/disable, invalid input, rollback");
}
