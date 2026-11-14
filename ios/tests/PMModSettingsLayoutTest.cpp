#include "../PhiMod/Core/PMModSettingsLayout.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>
int main(){
 const std::vector<float> heights{76,76,76,76,90,90,90,90,90,90,90,90,90,140};
 for(float width:{520.f,820.f,1024.f,1366.f,1920.f})for(float height:{360.f,640.f,900.f}){
  auto page=phimod::modSettingsLayout(width,height,heights);assert(page.rows.size()==14);
  float previousBottom=0;
  for(auto row:page.rows){assert(row.x==24);assert(row.x>=0&&row.x+row.width<=width);assert(row.y>=previousBottom);assert(row.height>0);previousBottom=row.y+row.height;}
  assert(page.contentHeight>=previousBottom+24);assert(page.contentHeight>=height);
  float bottomScroll=page.contentHeight-height;auto last=page.rows.back();assert(last.y+last.height-bottomScroll<=height);
  assert(last.y+last.height-bottomScroll>0);
  auto resized=phimod::modSettingsLayout(width+100,height,heights);for(size_t i=0;i<heights.size();++i){assert(resized.rows[i].y==page.rows[i].y);assert(resized.rows[i].x==page.rows[i].x);assert(std::fabs(resized.rows[i].width-page.rows[i].width-100)<.001f);}
 }
 assert(phimod::modSettingsLayout(800,600,{}).contentHeight==600);
 puts("PASS settings row bounds: phone/tablet widths, no diagonal drift, complete last-row scroll, rotation reflow");
}
