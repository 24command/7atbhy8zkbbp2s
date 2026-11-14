#include "../PhiMod/Core/PMUIInteraction.hpp"
#include <cassert>
#include <cmath>
#include <limits>
#include <cstdio>
int main(){using namespace phimod;
 UIRegion parent{-960,-540,960,540};
 for(float x:{-5000.f,0.f,5000.f})for(float y:{-5000.f,0.f,5000.f}){
  auto body=settingsBody({x-960,y-450,x+960,y+450},parent);
  assert(body.left==0&&body.right==1);assert(body.bottom>=0&&body.top<=1&&body.top>body.bottom);
 }
 auto wide=settingsViewport({-900,-400,900,400},parent);assert(wide.right-wide.left>.9f);
 auto invalid=settingsViewport({0,0,std::numeric_limits<float>::quiet_NaN(),1},parent);assert(std::isfinite(invalid.right));
 for(auto size:{UIPopupSize{1920,1080},UIPopupSize{1440,1080},UIPopupSize{640,360}}){auto popup=readablePopupSize(size.width,size.height);assert(popup.width<size.width&&popup.height<size.height&&popup.width>0&&popup.height>0);}
 auto ipad=readablePopupSize(1440,1080);assert(ipad.width>1000&&ipad.height>660);
 auto inactive=selectorModalFrame(false,false,false);assert(!inactive.block&&!inactive.release);
 auto shown=selectorModalFrame(true,true,false);assert(shown.block&&!shown.release);
 auto closeHeld=selectorModalFrame(true,false,true);assert(closeHeld.block&&!closeHeld.release);
 auto closeReleased=selectorModalFrame(true,false,false);assert(closeReleased.block&&closeReleased.release);
 auto resumed=selectorModalFrame(false,false,false);assert(!resumed.block);
 std::puts("PASS full-width hidden-frame normalization, adaptive dialog size and modal release handoff");
}
