#include "../PhiMod/Core/PMCachedRPETrack.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <limits>
int main(){
 for(int easing=1;easing<=29;++easing)for(bool bezier:{false,true}){
  phimod::rpe::Track original;original.events={
   {-2,-1,-1,1,.1,.9,easing,bezier,{.42,0,.58,1}},
   {0,2,0,255,0,1,easing,bezier,{.25,.1,.25,1}},
   {2,2,255,0,0,1,1,false,{}},
   {2,4,0,-255,0,1,easing,bezier,{.42,0,.58,1}},
   {6,7,1,1,0,1,1,false,{}}};
  phimod::CachedRPETrack cached;cached.events=original.events;
  for(int direction:{1,-1})for(int i=0;i<=2400;++i){double now=direction>0?i/240.-3:7-i/240.;
   for(double fallback:{-9.,0.,1.,255.}){original.fallback=fallback;double expected=original.value(now);
    for(int repeat=0;repeat<5;++repeat)assert(cached.value(now,fallback)==expected);
   }
  }
  for(double boundary:{-2.,-1.,0.,2.,4.,6.,7.})for(double now:{std::nextafter(boundary,-INFINITY),boundary,std::nextafter(boundary,INFINITY)})assert(cached.value(now,original.fallback)==original.value(now));
  // A replacement chart cannot retain the old track's sample, even at the same time.
  cached={};cached.events={{0,1,99,99,0,1,1,false,{}}};assert(cached.value(.5,0)==99);
 }
 phimod::CachedRPETrack empty;assert(empty.value(0,1)==1);assert(empty.value(0,255)==255);
 puts("PASS exact RPE sampling: alpha/scale/position values, all easing curves, Bezier, gaps, equal-time events, seeks, 240 Hz and chart replacement");
}
