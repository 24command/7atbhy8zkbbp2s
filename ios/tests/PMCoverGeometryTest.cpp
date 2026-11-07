#include "../PhiMod/Core/PMCoverGeometry.hpp"
#include <cassert>
#include <initializer_list>
int main(){
 for(auto source:{pmcover::Rect{0,0,600,1200},pmcover::Rect{0,0,2400,400},pmcover::Rect{0,0,1000,1000},pmcover::Rect{0,0,1920,1080}}){
  for(double aspect:{16./9.,1.35625}){double w=1600,h=w/aspect;
   auto fg=pmcover::fit(source.w,source.h,w,h,false),bg=pmcover::fit(source.w,source.h,w,h,true);
   assert(fg.x>=-1e-8&&fg.y>=-1e-8&&fg.x+fg.w<=w+1e-8&&fg.y+fg.h<=h+1e-8);
   assert(bg.x<=1e-8&&bg.y<=1e-8&&bg.x+bg.w>=w-1e-8&&bg.y+bg.h>=h-1e-8);
   assert(std::fabs(fg.w/fg.h-source.w/source.h)<1e-8);assert(std::fabs(bg.w/bg.h-source.w/source.h)<1e-8);
  }
 }
 bool rejected=false;try{pmcover::fit(0,1,10,10,false);}catch(const std::invalid_argument&){rejected=true;}assert(rejected);
}
