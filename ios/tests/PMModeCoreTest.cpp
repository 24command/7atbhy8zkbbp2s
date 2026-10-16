#include "../PhiMod/Core/PMModeCore.hpp"
#include <iostream>
#include <random>
using namespace phimod;
static int checks=0;
#define CHECK(x) do{++checks;if(!(x))throw std::runtime_error("Failed: " #x);}while(0)
template<class F>void rejects(F f){bool rejected=false;try{f();}catch(const std::invalid_argument&){rejected=true;}CHECK(rejected);}
int main(){try{
 for(int old=1;old<=4;++old)for(int target=0;target<=4;++target){auto n=unifiedNote(old,target,2,old==3?32.f:0.f,3,120);CHECK(n.type==(target?target:old));
  if(!target||old==target){CHECK(n.speed==2);CHECK(n.holdTicks==(old==3?32.f:0.f));}
  else if(target==3){CHECK(n.speed==6);CHECK(n.holdTicks==6.4f);}
  else{CHECK(std::fabs(n.speed-(old==3?2.f/3:2.f))<.00001f);CHECK(n.holdTicks==0);}
 }
 CHECK(unifiedNote(1,3,1,0,0,1).holdTicks==1);CHECK(unifiedNote(3,1,2,32,0,120).speed==2);
 CHECK(unifiedNote(1,3,2,0,-3,120).speed==-6);CHECK(unifiedNote(3,1,-6,32,-3,120).speed==2);
 rejects([]{unifiedNote(0,1,1,0,1,120);});rejects([]{unifiedNote(1,5,1,0,1,120);});rejects([]{unifiedNote(1,2,1,0,1,0);});
 NoiseHoles h;h.begin(0);h.visible(1,{0,0,2,2},false,0);h.end();CHECK(h.allows(2,2));CHECK(!h.allows(2.01f,0));CHECK(h.active().size()==1);
 h.completed(1,0,.25f);h.begin(.2f);h.end();CHECK(h.allows(0,0));h.begin(.25f);h.end();CHECK(h.allows(0,0));h.begin(.251f);h.end();CHECK(!h.allows(0,0));
 h.clear();h.begin(1);h.visible(1,{0,0,1,1},true,.1f);h.end();h.begin(1.01f);h.visible(1,{3,0,1,1},true,.1f);h.end();CHECK(h.allows(0,0));CHECK(h.allows(3,0));
 h.begin(1.02f);h.visible(1,{6,0,1,1},true,.1f);h.end();h.begin(1.03f);h.visible(1,{9,0,1,1},true,.1f);h.end();CHECK(!h.allows(0,0));CHECK(h.active().size()==3);
 h.begin(1.14f);h.visible(1,{9,0,1,1},true,.1f);h.end();CHECK(h.active().size()==1);h.begin(.5f);h.end();CHECK(h.active().empty());
 rejects([&]{h.begin(std::numeric_limits<float>::infinity());});rejects([&]{h.masks(0,1);});
 std::mt19937 random(40151);std::uniform_real_distribution<float> coord(-8,8);
 for(int trial=0;trial<50;++trial){h.clear();h.begin(0);for(int i=0;i<12;++i)h.visible(float(i),{coord(random),coord(random),.3f+std::fabs(coord(random))*.3f,.3f+std::fabs(coord(random))*.3f},i%4==0,.1f);h.end();auto masks=h.masks(16,9);
  for(float x=-7.75f;x<8;x+=.5f)for(float y=-4.25f;y<4.5f;y+=.5f){bool mask=false;int overlap=0;for(auto rect:masks)if(x>rect.left&&x<rect.right&&y>rect.bottom&&y<rect.top){mask=true;++overlap;}CHECK(mask==h.allows(x,y));CHECK(overlap<=1);}
 }
 HoldGrace grace;float nan=std::numeric_limits<float>::quiet_NaN();CHECK(!grace.inject(1,0,0,{0},.1f,false));CHECK(grace.inject(1,.05f,0,{nan},.1f,false));CHECK(!grace.inject(1,.11f,0,{nan},.1f,false));CHECK(!grace.inject(1,.05f,0,{},.1f,false));
 CHECK(!grace.inject(2,1,4,{0},.1f,true));CHECK(grace.inject(2,1.05f,4,{nan},.1f,true));CHECK(!grace.inject(2,.5f,4,{nan},.1f,true));
 HoldFxClock fx;CHECK(!fx.pulse(1,0,0,.15f));CHECK(!fx.pulse(1,.14f,0,.15f));CHECK(fx.pulse(1,.16f,0,.15f));CHECK(!fx.pulse(1,.17f,0,.15f));CHECK(fx.pulse(1,.32f,0,.15f));CHECK(!fx.pulse(1,.1f,0,.15f));fx.retire(1);CHECK(fx.pulse(1,1,0,.15f));rejects([&]{fx.pulse(1,1,0,0);});
 std::cout<<"PASS: "<<checks<<" chart / noise / Hold checks\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
