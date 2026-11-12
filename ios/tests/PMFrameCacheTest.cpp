#include "../PhiMod/Core/PMFrameCache.hpp"
#include "../PhiMod/Core/PMCoverGeometry.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>
int main(){phimod::FrameCache<int,double>cache;int evaluated=0;for(int frame=0;frame<60;++frame){double t=frame/60.;for(int note=0;note<10000;++note){int line=note%32;double v=cache.get(line,t,[&]{++evaluated;return line+t*2;});assert(v==line+t*2);}}assert(evaluated==60*32);auto calculate=[&]{++evaluated;return 12.;};assert(cache.get(0,-1,calculate)==12);assert(cache.get(0,-1,calculate)==12);assert(evaluated==60*32+1);cache.clear();cache.get(0,-1,calculate);assert(evaluated==60*32+2);
 for(auto source:{pmcover::Rect{0,0,1920,1080},pmcover::Rect{0,0,800,1085},pmcover::Rect{0,0,1085,800}}){auto fit=pmcover::fit(source.w,source.h,1085,800,true);assert(fit.w>=1085-1e-6&&fit.h>=800-1e-6);assert(std::fabs(fit.w/fit.h-source.w/source.h)<1e-9);}
 puts("PASS frame-cache reuse, backward seek, chart replacement and expanded chapter aspect");}
