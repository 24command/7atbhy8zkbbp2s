#include "../PhiMod/Core/PMSelectorSort.hpp"
#include <cassert>
#include <limits>
#include <cstdio>
int main(){
 phimod::DeferredSelectorSort sort;
 assert(!sort.ready(1,2,false,0));sort.request(1);
 for(int i=0;i<2000;++i){sort.request(1);assert(!sort.ready(1,2,true,0));assert(!sort.ready(1,2,false,.2f));}
 assert(sort.ready(1,2,false,0));assert(sort.ready(1,3,false,-.01f));
 assert(!sort.ready(1,0,false,0)&&!sort.ready(1,1,false,0));
 assert(!sort.ready(2,2,false,0));assert(!sort.ready(1,2,false,std::numeric_limits<float>::quiet_NaN()));
 sort.clear();assert(!sort.pending(1));sort.request(2);assert(!sort.pending(1)&&sort.ready(2,2,false,0));
 sort.clear();assert(!sort.pending(2));
 puts("PASS selector shared-slot sorting: coalesced gestures, stable release, correct modes and scene reset");
}
