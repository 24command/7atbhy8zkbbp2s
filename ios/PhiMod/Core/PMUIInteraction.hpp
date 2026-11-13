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
}
