#pragma once
#include <cmath>
namespace pmnativeenterscene {
struct Clock {
    bool running=false, committing=false, finished=false;
    double began=0;
    void reset(){*this={};}
    void shown(double now){if(!running && !committing && !finished && std::isfinite(now)){running=true;began=now;}}
    bool due(double now,double duration) const {return running && !committing && !finished && std::isfinite(now) && now>=began && now-began>=duration;}
    bool claim(double now,double duration){if(!due(now,duration))return false;committing=true;return true;}
    void complete(){running=false;committing=false;finished=true;}
};
}
