#include "../PhiMod/Core/PMUIInteraction.hpp"
#include <cassert>
#include <limits>
#include <cstdio>
int main(){using namespace phimod;
 UIParallelogram p{0,0,420,64,32};
 assert(p.contains(210,32));assert(p.contains(0,0));assert(p.contains(32,64));assert(p.contains(420,64));
 assert(!p.contains(0,64));assert(!p.contains(420,0));assert(!p.contains(210,65));assert(!p.contains(210,-1));
 assert(p.contains(16,32));assert(!p.contains(15,32));assert(p.contains(404,32));assert(!p.contains(405,32));
 UIParallelogram anchored{-210,-32,420,64,32};assert(anchored.contains(0,0));assert(!anchored.contains(-210,32));
 assert(!p.contains(std::numeric_limits<float>::quiet_NaN(),0));assert(!(UIParallelogram{0,0,0,0,0}.contains(0,0)));
 UITapGate gate;assert(!gate.finish(0,100,100,20,true));
 gate.begin(2,100,100);assert(gate.finish(2,110,105,20,true));assert(!gate.finish(2,110,105,20,true));
 gate.begin(2,100,100);gate.move(2,150,100,20);assert(!gate.finish(2,100,100,20,true)); // leave and return still a drag
 gate.begin(2,100,100);assert(!gate.finish(3,100,100,20,true));
 gate.begin(2,100,100);assert(!gate.finish(2,100,100,20,false));
 gate.begin(2,100,100);gate.reset();assert(!gate.finish(2,100,100,20,true)); // cancelled / multitouch / selection change
 for(int y=0;y<=64;++y)for(int x=0;x<=420;++x){bool expected=x>=y*.5f&&x<=388+y*.5f;assert(p.contains(float(x),float(y))==expected);}
 std::puts("PASS native parallelogram hit geometry, tap, drag-return, cancellation and duplicate release");
}
