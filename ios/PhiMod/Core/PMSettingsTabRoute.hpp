#pragma once
#include <array>
namespace phimod {
enum class SettingsTabRoute { Original, LeaveMod, OpenMod, KeepMod };
inline SettingsTabRoute settingsTabRoute(bool owns,bool internal,bool modActive,int index){
 if(!owns||internal)return SettingsTabRoute::Original;
 if(index==3)return modActive?SettingsTabRoute::KeepMod:SettingsTabRoute::OpenMod;
 return modActive?SettingsTabRoute::LeaveMod:SettingsTabRoute::Original;
}
// Use a STRICT common ancestor, never an individual tab or its private host.
// This keeps the MOD frame alive when any of the three original tabs hides.
template<class Node,class Parent,class IsRect>
Node settingsFrameHost(const std::array<Node,3>&frames,Parent parent,IsRect isRect){
 Node candidate=parent(frames[0]);
 for(int depth=0;candidate!=Node{}&&depth<32;++depth,candidate=parent(candidate)){
  bool common=true;
  for(Node frame:frames){
   if(frame==candidate){common=false;break;}
   Node node=parent(frame);int steps=0;
   while(node!=Node{}&&node!=candidate&&steps++<32)node=parent(node);
   if(node!=candidate){common=false;break;}
  }
  if(common&&isRect(candidate))return candidate;
 }
 return Node{};
}
}
