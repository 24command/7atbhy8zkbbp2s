#include "../PhiMod/Core/PMSettingsTabRoute.hpp"
#include "../PhiMod/Core/PMBuildInfo.hpp"
#include <cassert>
#include <cstdio>
int main(){using namespace phimod;
 for(int index=0;index<4;++index){
  assert(settingsTabRoute(false,false,true,index)==SettingsTabRoute::Original);
  assert(settingsTabRoute(true,true,true,index)==SettingsTabRoute::Original);
 }
 assert(settingsTabRoute(true,false,false,3)==SettingsTabRoute::OpenMod);
 assert(settingsTabRoute(true,false,true,3)==SettingsTabRoute::KeepMod);
 for(int index=0;index<3;++index){
  assert(settingsTabRoute(true,false,true,index)==SettingsTabRoute::LeaveMod);
  assert(settingsTabRoute(true,false,false,index)==SettingsTabRoute::Original);
 }
 // Duplicate external requests must never restore 3 arrays then forward index 3.
 int arrays=4;bool forward=true;
 switch(settingsTabRoute(true,false,true,3)){
  case SettingsTabRoute::LeaveMod:arrays=3;break;
  case SettingsTabRoute::KeepMod:forward=false;break;
  default:break;
 }
 assert(arrays==4&&!forward);assert(buildRevision[0]&&settingsRevision[0]);
 // Separate private hosts for Gameplay/Audio/Misc: MOD belongs to host 1.
 int parents[10]={0,0,1,1,1,2,3,4,0,0};
 auto parent=[&](int node){return parents[node];};
 auto rect=[](int node){return node==1||node==2||node==8;};
 std::array<int,3>frames{5,6,7};assert(settingsFrameHost(frames,parent,rect)==1);
 parents[6]=parents[7]=2;assert(settingsFrameHost(frames,parent,rect)==2);
 parents[5]=3;parents[6]=3;parents[7]=1;frames={5,3,7};assert(settingsFrameHost(frames,parent,rect)==1);
 parents[1]=8;assert(settingsFrameHost(frames,parent,[](int n){return n==8;})==8);
 parents[7]=9;assert(settingsFrameHost(frames,parent,rect)==0);
 // Scene host can be a plain Transform: the caller provides canvas sizing.
 parents[7]=1;parents[1]=0;assert(settingsFrameHost(frames,parent,[](int){return true;})==1);
 // Separate managed wrappers for the same native ancestor must compare equal.
 auto aliases=[](int n){if(n==5)return 11;if(n==6)return 21;if(n==7)return 31;return 0;};
 assert(settingsFrameHost(std::array<int,3>{5,6,7},aliases,[](int){return true;},[](int a,int b){return a==b||(a>10&&b>10&&a%10==b%10);})==11);
 std::puts("PASS duplicate fourth-tab request, internal/foreign owner isolation and native tab exit");
}
