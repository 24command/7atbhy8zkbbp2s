#pragma once
#include <algorithm>
#include <cmath>
namespace phimod {
// Same quad for LeanPolygon vertices and touch hit testing: no atlas cropping.
struct UIParallelogram {
 float x,y,width,height,cut;
 bool contains(float px,float py)const {
  if(!std::isfinite(px)||!std::isfinite(py)||!std::isfinite(width)||!std::isfinite(height)||!std::isfinite(cut)||cut<0||cut>=width||!(width>0)||!(height>0)||py<y||py>y+height)return false;
  float left=x+cut*(py-y)/height;
  return px>=left&&px<=left+width-cut;
 }
};
struct UITapGate {
 int finger=-1;float startX=0,startY=0;bool dragged=false;
 void reset(){finger=-1;dragged=false;}
 void begin(int id,float x,float y){finger=id;startX=x;startY=y;dragged=false;}
 void move(int id,float x,float y,float slop){if(id!=finger)return;float dx=x-startX,dy=y-startY;dragged=dragged||dx*dx+dy*dy>slop*slop;}
 bool finish(int id,float x,float y,float slop,bool inside){move(id,x,y,slop);bool result=id==finger&&finger>=0&&!dragged&&inside;reset();return result;}
};
struct UIRegion {float left,bottom,right,top;};
inline UIRegion settingsViewport(UIRegion area,UIRegion frame){
 float w=frame.right-frame.left,h=frame.top-frame.bottom;
 if(!(w>0&&h>0))return {.035f,.075f,.965f,.90f};
 UIRegion n{(area.left-frame.left)/w,(area.bottom-frame.bottom)/h,(area.right-frame.left)/w,(area.top-frame.bottom)/h};
 if(!std::isfinite(n.left)||!std::isfinite(n.bottom)||!std::isfinite(n.right)||!std::isfinite(n.top))return {.035f,.075f,.965f,.90f};
 n.left=std::clamp(n.left,0.f,1.f);n.right=std::clamp(n.right,0.f,1.f);n.bottom=std::clamp(n.bottom,0.f,1.f);n.top=std::clamp(n.top,0.f,1.f);
 return n.right-n.left>.3f&&n.top-n.bottom>.3f?n:UIRegion{.035f,.075f,.965f,.90f};
}
inline UIRegion settingsBody(UIRegion visible,UIRegion parent){
 float h=parent.top-parent.bottom;if(!(h>0))return {0,0,1,1};
 float height=std::clamp(visible.top-visible.bottom,0.f,h);
 if(!std::isfinite(height)||height<h*.3f)return {0,0,1,1};
 float center=(visible.top+visible.bottom)*.5f;if(!std::isfinite(center))center=(parent.top+parent.bottom)*.5f;
 center=std::clamp(center,parent.bottom+height*.5f,parent.top-height*.5f);
 return {0,(center-height*.5f-parent.bottom)/h,1,(center+height*.5f-parent.bottom)/h};
}
struct UIPopupSize{float width,height;};
inline UIPopupSize readablePopupSize(float width,float height){
 if(!std::isfinite(width)||!std::isfinite(height)||width<=0||height<=0)return {1000,660};
 return {width*.86f,height*.82f};
}
struct UIModalFrame{bool block,release;};
inline UIModalFrame selectorModalFrame(bool owned,bool visible,bool pointerDown){
 return {owned,owned&&!visible&&!pointerDown};
}
}
