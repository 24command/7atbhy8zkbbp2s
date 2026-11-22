#include "../PhiMod/Sources/PMNativeOSMapPuzzle.hpp"
#include "../PhiMod/Sources/PMNativeOSMapMediaTiming.hpp"
#include <cassert>
#include <limits>
using namespace pmnativeosmap;
int main() {
    static PMOSPage page;
    const char script[] = "screen('a');frame{id='source',x=.125,w=.25,h=.5};"
        "image{src='piece.png',parent='source',w=.5,h=.5,fit='cover',dropTarget='slot',alphaHit=true,"
        "onClick=function() return {to='b'} end};"
        "frame{id='board',x=.5,y=.25,w=.5,h=.5};frame{id='slot',parent='board',x=-.5,w=1};"
        "screen('b');image{src='movie.mp4',loop=true};image{src='intro.gif'}";
    PMOSSession *vm=PMOSStart(script,sizeof(script)-1,1,&page);
    assert(vm && page.elements[1].dropIndex==3 && page.elements[1].alphaHit);
    assert(page.elements[4].loop && !page.elements[5].loop);
    auto source=layout::anchors(page.elements[0]);
    auto piece=puzzle::compose(source,layout::anchors(page.elements[1]));
    auto board=layout::anchors(page.elements[2]);
    auto slot=puzzle::compose(board,layout::anchors(page.elements[3]));
    layout::Point clipped{.375f,.5f};
    assert(puzzle::contains(slot,clipped) && !puzzle::contains(board,clipped));
    auto placed=puzzle::centered(puzzle::center(slot),puzzle::size(piece));
    auto restored=puzzle::compose(board,puzzle::relative(board,placed));
    assert(restored.low.x==placed.low.x && restored.high.y==placed.high.y);
    assert(puzzle::size(restored).x==.125f && puzzle::size(restored).y==.25f);
    assert(!puzzle::contains(slot,slot.high));
    PMOSAction result;
    assert(PMOSClick(vm,1,&result) && result.dest==1);
    PMOSStop(vm);
    using namespace playback;
    assert(nextFrame(0,1,true)==1 && nextFrame(0,3,false)==1);
    assert(nextFrame(2,3,true)==0 && nextFrame(2,3,false)==3);
    assert(frameDelay(.02,.1)==.02 && frameDelay(0,.04)==.04);
    assert(frameDelay(std::numeric_limits<double>::infinity(),-1)==.1);
}
