#include "../PhiMod/Core/PMRPEVisibility.hpp"
#include <cassert>
#include <cstdio>
#include <vector>
int main(){using namespace phimod;
 // Offscreen line cancels a large local distance. Old abs(localY)>30 rejected it.
 RpePlanePose stopped{0,-60,1,0,0,1};assert(rpeVisualNear(stopped,0,60,60,1));
 assert(rpeVisualNear(stopped,0,68,68,1));assert(!rpeVisualNear(stopped,0,0,0,1));
 // Rotated/below notes must be transformed before testing viewport bounds.
 RpePlanePose rotated{-60,0,0,1,-1,0};assert(rpeVisualNear(rotated,0,-60,-60,1));
 assert(!rpeVisualNear(rotated,0,60,60,1));
 // A hold crossing the viewport is visible even when neither cap is inside.
 assert(rpeVisualNear({},0,-50,50,1));
 assert(!rpeVisualNear({},100,0,0,1));
 // Time is intentionally absent: a note 20 seconds away may be on screen.
 for(int secondsAhead:{2,8,20,100}){(void)secondsAhead;assert(rpeVisualNear(stopped,0,60,60,1));}
 RpeVisualValues n{0,0,0,0,1,1,999999};
 assert(rpeVisibleAt(n,0,100,false));n.visible=-1;
 assert(!rpeVisibleAt(n,9,10,false));assert(!rpeVisibleAt(n,10,10,false));
 assert(rpeVisibleAt(n,11,10,false));n.visible=999999;n.alpha=0;
 assert(!rpeVisibleAt(n,0,100,false));n.alpha=1;assert(!rpeVisibleAt(n,100,100,true));
 struct Candidate{double end;};std::vector<Candidate>notes;
 for(int i=0;i<100000;++i)notes.push_back({double(i)});
 assert(rpeFirstUnexpired(notes,99990)-notes.begin()==99990);
 assert(rpeFirstUnexpired(notes,10)-notes.begin()==10); // backwards practice seek
 assert(rpeFirstUnexpired(notes,100000)==notes.end());
 assert(rpeFirstUnexpired(notes,-3)==notes.begin());
 puts("PASS stopped-scroll, offscreen/rotated lines, hold crossings and no time horizon");}
