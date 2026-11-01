#pragma once
#include <algorithm>
#include <cmath>
#include <vector>

struct RpeControlSegment {float from,to,start,end;};
inline float rpeControl(const std::vector<RpeControlSegment>& segments,float distance){
    if(segments.empty())return 1;
    auto next=std::upper_bound(segments.begin(),segments.end(),distance,[](float x,const RpeControlSegment& s){return x<s.from;});
    if(next==segments.begin())return next->start;
    const auto& s=*--next;
    float t=s.to>s.from?std::clamp((distance-s.from)/(s.to-s.from),0.f,1.f):1;
    return s.start+(s.end-s.start)*t;
}
// The converter uses RPE speed / 4.5 for native floor units. Phira uses
// the same integrated speed divided by HEIGHT_RATIO (0.83175).
constexpr float rpeFloorToDistance=450.f/.83175f;
constexpr float rpeOffsetToFloor=.83175f/450.f;
struct RpeGeometry {float head,tail,distance;};
inline RpeGeometry rpeGeometry(float start,float end,float floor,float rawSpeed,float yOffset,float yControl,float worldSpeed,bool started){
    float offset=yOffset*rpeOffsetToFloor*rawSpeed;
    float head=((started?floor:start)-floor)*rawSpeed*yControl+offset;
    float tail=(end-floor)*rawSpeed*yControl+offset;
    return {head*worldSpeed,tail*worldSpeed,(start-floor)*rpeFloorToDistance+yOffset};
}
struct RpeHoldLayout {float origin,scale;};
inline RpeHoldLayout rpeHoldLayout(const RpeGeometry& g,float spriteHeight,float spriteBottom,bool below){
    float side=below?-1.f:1.f;
    // Mirror the complete Hold, including its body and child positions.
    // Negative integrated lengths have no body in Phira's renderer.
    float scale=side*std::max(.00001f,g.tail-g.head)/spriteHeight;
    return {side*g.head-spriteBottom*scale,scale};
}

// Android rpe_floor.h: source floor units must not be mixed with native
// floorPositions, which the game may rebuild/quantize when loading a chart.
struct RpeFloorSegment { double start,end,speed,floor; };
inline double rpeFloor(const std::vector<RpeFloorSegment>& segments,double now,double fallback){
 if(segments.empty())return fallback;
 auto it=std::upper_bound(segments.begin(),segments.end(),now,
  [](double t,const RpeFloorSegment& s){return t<s.start;});
 if(it!=segments.begin())--it;
 return it->floor+(now-it->start)*it->speed;
}

// Align cap edges with the body instead of covering a short body's interior.
// Compact resource packs deliberately keep cap centers at the endpoints.
inline float rpeHoldCapPosition(float edge,float capCenter,float capExtent,float capScale,bool tail,bool compact){
 return edge+(compact?0.f:((tail?capExtent:-capExtent)-capCenter)*capScale);
}

// Android applyRpeGeometry / Phira now_transform: Hold does not use
// posControl or incline perspective. Distances here are native world units.
inline float rpeHorizontalPosition(float x,bool hold,float posControl,float inclineDegrees,float head,float worldWidth){
 if(hold)return x;
 if(!std::isfinite(worldWidth)||worldWidth<=0)return x*posControl;
 float perspective=1-std::sin(inclineDegrees*0.017453292519943295f)*head*(2*(16.f/9.f)/worldWidth)*1.25f;
 return x*posControl*perspective;
}
