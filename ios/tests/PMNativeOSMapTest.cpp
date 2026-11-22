#include "../PhiMod/Sources/PMNativeOSMap.hpp"
#include <cassert>
#include <cmath>
#include <cstring>
using namespace pmnativeosmap::layout;

static void doorMotion() {
    static PMOSPage page;
    const char script[] =
        "local d={id='red',song=1,tiers={{after=0,hp=1,perfect=0,good=0,bad=-1,miss=-1}}};"
        "challenge(d); d.id='blue'; d.unlocked=false; challenge(d);"
        "frame{id='door',enter=.5,bob=.02,bobPeriod=4,tapTime=.25,tapScale=1.2,tapFlash=.8,tapFace='face'};"
        "frame{parent='door',color='#351214ff'}; image{id='face',parent='door',src='red.png'};"
        "frame{parent='door',label='Red Door'}; hotspot{parent='door',challenge='red'};"
        "hotspot{parent='door',challenge='blue',tapTime=.5}; frame{open=1}";
    PMOSSession *vm = PMOSStart(script, sizeof(script)-1, 1, &page);
    assert(vm && page.nodes == 7);
    auto &door = page.elements[0];
    assert(door.tapFaceIndex == 2 && door.motion.bob == .02);
    assert(door.motion.tapTime == .25 && door.motion.tapScale == 1.2 && door.motion.tapFlash == .8);
    for (int i = 1; i <= 5; ++i) assert(page.elements[i].parent == 0);
    int owner = feedbackOwner(door, 0, -1);
    assert(owner == 0 && feedbackOwner(page.elements[4], 4, owner) == 0);
    assert(feedbackOwner(page.elements[5], 5, owner) == 5);
    auto &plain = page.elements[6];
    assert(feedbackOwner(plain, 6, -1) == -1 && motion(plain.motion, 0, 0).scale == 1);
    assert(actionable(page.elements[4]) && !actionable(page.elements[5]));
    assert(motion(door.motion, 0, 0).scale < 1 && motion(door.motion, .3, 0).scale > 1);
    assert(motion(door.motion, .5, 0).scale == 1);
    assert(motion(door.motion, 1, 0).lift == .02f && motion(door.motion, 3, 0).lift == -.02f);
    assert(motion(door.motion, 5, 0).lift == motion(door.motion, 1, 0).lift);
    auto rect = lifted({{0,.25f},{1,.75f}}, .125f);
    assert(rect.low.y == .3125f && rect.high.y == .8125f);

    PendingTap tap;
    assert(tap.begin(4, owner, 10, door.motion.tapTime));
    assert(!tap.begin(5, 5, 10.1, .5) && tap.owner == 0);
    auto peak = motion(door.motion, 10, tap.pulse(10.125));
    assert(peak.scale == 1.2f && peak.white == .8f);
    assert(tap.take(10.249, true) == -1 && tap.busy());
    int node = tap.take(10.25, true);
    PMOSAction action;
    assert(node == 4 && PMOSClick(vm, node, &action) && action.challenge == 1);
    assert(tap.take(11, true) == -1 && !tap.busy());
    assert(PMOSClick(vm, 5, &action) && !action.challenge && !action.song);
    assert(tap.begin(4, owner, 12, .25) && tap.take(12.25, false) == -1 && !tap.busy());
    assert(tap.begin(4, owner, 13, .25));
    tap.cancel();
    assert(tap.take(14, true) == -1 && tap.pulse(14) == 0);
    PMOSStop(vm);

    const char *invalid[] = {"frame{enter=-1}", "frame{bob=0/0}", "frame{bobPeriod=0}",
        "frame{tapTime=1/0}", "frame{tapScale='1.2'}", "frame{tapFlash=1.01}",
        "frame{tapFace='typo'}", "frame{tapFace='face'};frame{id='face'}"};
    for (auto bad : invalid) assert(!PMBuildOSPage(bad, std::strlen(bad), 1, &page));
}

static void challengeOnTransparentParent() {
    static PMOSPage page;
    const char script[] = R"lua(
        local function door(d)
            challenge(d)
            frame{id=d.id, challenge=d.id, tapTime=.22, tapScale=1.08,
                  tapFlash=.82, tapFace=d.id..'_face'}
            image{id=d.id..'_face', parent=d.id, src='face.png'}
        end
        local tiers={{after=0,hp=1,perfect=0,good=0,bad=-1,miss=-1}}
        door{id='red', song=1, tiers=tiers}
        door{id='blue', song=1, tiers=tiers, unlocked=false}
    )lua";
    PMOSSession *vm = PMOSStart(script, sizeof(script)-1, 1, &page);
    assert(vm && page.nodes == 4 && page.challengeCount == 2);
    for (int i : {0, 2}) {
        const auto &door = page.elements[i];
        const auto &face = page.elements[i + 1];
        assert(door.kind == PMOSFrame && door.rgba == 0 && door.parent == -1);
        assert(door.tapFaceIndex == i + 1 && face.parent == i);
        assert(!face.alphaHit && !actionable(face));
        assert(door.motion.tapTime == .22 && door.motion.tapScale == 1.08 && door.motion.tapFlash == .82);
        assert(feedbackOwner(door, i, -1) == i);
    }
    PMOSAction action;
    const auto &red = page.elements[0];
    assert(actionable(red) && red.challenge == 1);
    PendingTap tap;
    assert(tap.begin(0, 0, 0, red.motion.tapTime));
    assert(tap.take(.219, true) == -1);
    int node = tap.take(.22, true);
    assert(node == 0 && PMOSClick(vm, node, &action) && action.challenge == red.challenge);
    assert(tap.take(.23, true) == -1);
    const auto &blue = page.elements[2];
    assert(blue.challenge == 2 && !blue.handler && !actionable(blue));
    assert(PMOSClick(vm, 2, &action) && !action.challenge && !action.song && action.dest == -1);
    PMOSStop(vm);
}

// Run against the real VM so indices, normalized coordinates, and action types
// cannot silently diverge between declaration, presentation, and dispatch.
int main() {
    doorMotion();
    challengeOnTransparentParent();
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
