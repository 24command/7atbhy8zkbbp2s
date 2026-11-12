#pragma once
#include <algorithm>
#include <cmath>
namespace phimod {
struct RpePlanePose{double x=0,y=0,xx=1,xy=0,yx=0,yy=1;};
// Android rpeVisualNear: test the authored geometry AFTER the line transform.
// Long holds can cross the viewport even if both caps are outside it.
inline bool rpeVisualNear(const RpePlanePose&p,double x,double head,double tail,double size){
 double ax=p.x+x*p.xx+head*p.yx,ay=p.y+x*p.xy+head*p.yy;
 double bx=p.x+x*p.xx+tail*p.yx,by=p.y+x*p.xy+tail*p.yy;
 double margin=std::max(3.,3.*std::abs(size));
 if(!std::isfinite(ax)||!std::isfinite(ay)||!std::isfinite(bx)||!std::isfinite(by)||!std::isfinite(margin))return false;
 return std::min(ax,bx)<12+margin&&std::max(ax,bx)>-12-margin&&std::min(ay,by)<8+margin&&std::max(ay,by)>-8-margin;
}
}
