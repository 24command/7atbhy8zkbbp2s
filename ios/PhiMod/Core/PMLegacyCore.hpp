#pragma once
#include <algorithm>
#include <cmath>
namespace phimod::legacy {
constexpr float nightmare=86.15385f,dreamLength=112.9485f,facesStart=167.17943f,facesInterval=.512825f;
inline float clamp(float x){return std::max(0.f,std::min(1.f,x));}
inline float transition(float now){float t=1-clamp((now-nightmare)/.8f);return 1-t*t*t;}
inline float progress(float now,float energy){float amplitude=clamp(std::log10(1+9*std::sqrt(std::max(0.f,energy)))*16);float reactive=clamp(1.3f/(1+std::exp(2-6*amplitude))-.15f);float normal=now/dreamLength;return normal+(reactive-normal)*transition(now);}
inline int displayTotal(float now,int actual){return (int)std::nearbyint(305+(actual-305)*transition(now));}
inline int faceStep(float now){return (int)((now-facesStart)/facesInterval);}
}
