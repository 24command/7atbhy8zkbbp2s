#pragma once
#include <cmath>
#include <stdexcept>
namespace phimod {
// Unity scaled time: failure visuals and fade pause together with the game.
class FailureDelay {
 float began_=-1;
 public:
 void reset(){began_=-1;}
 bool started()const{return began_>=0;}
 void begin(float now){if(!std::isfinite(now)||now<0)throw std::invalid_argument("Invalid Unity time");if(!started())began_=now;}
 bool ready(float now)const{return started()&&std::isfinite(now)&&now-began_>=1.5f;}
};
// Guarded result iterator always yields once, then presents; never invokes
// the stock reward/unlock MoveNext. A stopped iterator cannot replay helpers.
inline int resultStep(int state){return state==0?1:state==1?2:0;}
}
