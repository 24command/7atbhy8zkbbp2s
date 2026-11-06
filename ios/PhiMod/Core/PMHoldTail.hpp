#pragma once
#include <algorithm>
#include <cmath>
namespace phimod {
struct HoldTailPlan{float adjustedDuration,deadline;bool protectRelease;};
inline HoldTailPlan shortHoldTail(float start,float duration,float now,float perfect,bool head,bool missed,bool over){
 float grace=std::isfinite(perfect)?std::clamp(perfect,0.f,duration):0.f;
 float deadline=start+duration-grace;
 return {duration+.22f-grace,deadline,head&&!missed&&!over&&now>=deadline};
}
inline bool noteRenderFinished(int type,bool controllerJudged,float now,float start,float duration){
 return type==3?now>=start+duration:type==1&&controllerJudged;
}
}
