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
 std::puts("PASS duplicate fourth-tab request, internal/foreign owner isolation and native tab exit");
}
