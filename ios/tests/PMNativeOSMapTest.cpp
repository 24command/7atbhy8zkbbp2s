#include "../PhiMod/Sources/PMNativeOSMap.hpp"
#include <cassert>
#include <cmath>
#include <cstring>
using namespace pmnativeosmap::layout;

// Run against the real VM so indices, normalized coordinates, and action types
// cannot silently diverge between declaration, presentation, and dispatch.
int main() {
    static PMOSPage page;
    const char script[] =
        "canvas(16,9); screen('west');"
        "frame{id='panel',x=.125,y=.25,w=.5,h=.5,hidden=true};"
        "image{parent='panel',src='map.png',x=-.25,y=.5,w=1.5,h=.25,fit='cover',start=2,duration=4,fade=3,open=1};"
        "hotspot{to='east'};screen('east');"
        "hotspot{onClick=function() return {to='west'} end};";
    PMOSSession *vm = PMOSStart(script, std::strlen(script), 1, &page);
    assert(vm && page.nodes == 4 && page.screens == 2);
    auto &frame = page.elements[0]; auto &image = page.elements[1];
    assert(frame.hidden && !actionable(frame) && image.parent == 0 && image.fill);
    auto parent = anchors(frame), child = anchors(image);
    assert(parent.low.x == .125f && parent.low.y == .25f && parent.high.x == .625f && parent.high.y == .75f);
    assert(child.low.x == -.25f && child.high.x == 1.25f && child.low.y == .25f && child.high.y == .5f);
    auto alpha = [&](double t){return opacity(t,image.start,image.duration,image.fade);};
    assert(alpha(1) < 0 && alpha(2) == 0 && alpha(3) == .5f && alpha(4) == 1);
    assert(alpha(5) == .5f && alpha(6) < 0);
    assert(opacity(4,3,0,2) == .5f && opacity(200,3,0,2) == 1 && opacity(0,0,0,0) == 1);
    // Parent fades compose once through CanvasGroup, while page/visibility gates
    // deactivate the subtree, including otherwise actionable image buttons.
    assert(!sample(.5f,true,true,false,1).active);
    assert(!sample(.5f,false,true,true,1).active);
    assert(!sample(.5f,true,false,true,1).active);
    assert(!sample(-1,true,true,true,1).active);
    auto nested = sample(.5f,true,true,true,.25f);
    assert(nested.active && nested.local == .5f && nested.inherited == .125f);
    PMOSAction action;
    for (int index = 1; index <= 3; ++index) {
        assert(actionable(page.elements[index]) && PMOSClick(vm,index,&action));
        if (index == 1) assert(action.song == 1);
        if (index == 2) assert(action.dest == 1);
        if (index == 3) assert(action.dest == 0);
    }
    PMOSStop(vm);
}
