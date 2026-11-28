#include "../PhiMod/Sources/PMNativeOSMap.hpp"
#include <cassert>
#include <cstdio>
#include <memory>
using namespace pmnativeosmap;
int main() {
    preload::Plan plan;
    assert(plan.next() == -1 && !plan.matches(0,1));
    plan.source=0; plan.target=1; plan.nodes={3,7,11};
    // A pending decoder cannot starve later uploads; repeat calls are fair.
    for (int lap=0;lap<20;++lap) for(int node:{3,7,11}) assert(plan.next()==node);
    assert(plan.matches(0,1));
    assert(!plan.matches(1,1) && !plan.matches(0,2));
    plan={}; assert(plan.next()==-1 && !plan.matches(0,1));

    // Use the production visibility sampler: zero-alpha entry fades preload,
    // hidden ancestors, future/expired nodes and reserved placeholders do not.
    assert(preload::eligible(true,1,1,true,true,layout::opacity(0,0,4,1)));
    assert(!preload::eligible(true,1,1,true,true,layout::opacity(0,1,4,1)));
    assert(!preload::eligible(true,1,1,false,true,1));
    assert(!preload::eligible(true,1,1,true,false,1));
    assert(!preload::eligible(false,1,1,true,true,1));
    assert(!preload::eligible(true,0,1,true,true,1));

    // Prepared media survive ordinary intro refresh and the frozen real switch.
    // Only the actual running target releases frame zero. Later hides stop it.
    readiness::FirstFrame frame;
    assert(frame.begin(true)==readiness::Action::Prepare);
    assert(frame.poll(true,false,false)==readiness::Action::Play);
    assert(frame.poll(false,true,false)==readiness::Action::Hold);
    assert(preload::retainMedia(true,1,0,false,true,true));
    assert(preload::retainMedia(true,1,1,true,true,false));
    assert(preload::retainMedia(true,1,1,true,false,false));
    assert(frame.held());
    assert(!preload::retainMedia(true,1,1,true,true,true));
    assert(frame.release() && !frame.release());
    assert(!preload::retainMedia(false,1,1,true,false,false));
    assert(!preload::retainMedia(true,1,1,false,true,false));
    std::puts("entry target plan, visibility, fairness and frozen handoff passed");
}
