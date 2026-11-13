#pragma once
namespace phimod {
enum class SettingsTabRoute { Original, LeaveMod, OpenMod, KeepMod };
inline SettingsTabRoute settingsTabRoute(bool owns,bool internal,bool modActive,int index){
 if(!owns||internal)return SettingsTabRoute::Original;
 if(index==3)return modActive?SettingsTabRoute::KeepMod:SettingsTabRoute::OpenMod;
 return modActive?SettingsTabRoute::LeaveMod:SettingsTabRoute::Original;
}
}
