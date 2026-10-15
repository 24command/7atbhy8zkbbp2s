#pragma once
// Platform-independent algorithms ported from native helpers. No Unity calls.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

namespace phimod {

// Android source: chart_utf16.h
// Most converted chart JSON is ASCII, with occasional captions in UTF-8.
// Avoid the locale codecvt path for each byte of a large event array.
static std::u16string chartUtf16(const std::string& bytes){
    std::u16string out(bytes.size(),0);size_t i=0,n=0;
    while(i<bytes.size()){
        if(i+4<=bytes.size()){uint32_t block;memcpy(&block,bytes.data()+i,4);if(!(block&0x80808080u)){for(int k=0;k<4;k++)out[n++]=(unsigned char)bytes[i++];continue;}}
        uint32_t c=(unsigned char)bytes[i++];if(c<128){out[n++]=c;continue;}
        int count=c>=0xF0&&c<=0xF4?3:c>=0xE0&&c<=0xEF?2:c>=0xC2&&c<=0xDF?1:0;
        if(!count||i+count>bytes.size())throw std::runtime_error("谱面文本不是有效 UTF-8");
        uint32_t code=c&((1u<<(6-count))-1);for(int k=0;k<count;k++){unsigned char next=bytes[i++];if((next&0xC0)!=0x80)throw std::runtime_error("谱面文本不是有效 UTF-8");code=(code<<6)|(next&63);}
        if(code<(count==1?0x80u:count==2?0x800u:0x10000u)||code>0x10FFFF||(code>=0xD800&&code<=0xDFFF))throw std::runtime_error("谱面文本包含无效字符");
        if(code>=0x10000){code-=0x10000;out[n++]=0xD800+(code>>10);out[n++]=0xDC00+(code&1023);}else out[n++]=code;
    }
    out.resize(n);return out;
}


// Android source: rpe_floor.h
struct RpeFloorSegment {double start,end,speed,floor;};
inline double rpeFloor(const std::vector<RpeFloorSegment>& segments,double now,double fallback){
 if(segments.empty())return fallback;
 auto it=std::upper_bound(segments.begin(),segments.end(),now,[](double t,const RpeFloorSegment& segment){return t<segment.start;});
 if(it==segments.begin())return it->floor+(now-it->start)*it->speed;
 --it;return it->floor+(now-it->start)*it->speed;
}


// Android source: rpe_geometry.h

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


// Android source: rpe_hud_geometry.h
struct RpeHudOffset {float x,y;};
inline RpeHudOffset rpeHudOffset(float ox,float oy,float dx,float dy,float sx,float sy,float degrees){
    float radians=degrees*.01745329252f,c=std::cos(radians),s=std::sin(radians);
    // Native UI scripts keep writing the child's original parent coordinates.
    // Keep an identity wrapper, then transform around the original HUD anchor.
    return {dx+ox-(ox*sx*c-oy*sy*s),dy+oy-(ox*sx*s+oy*sy*c)};
}


} // namespace phimod
