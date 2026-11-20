#pragma once
#include "PMIL2CPP.hpp"
#import "PMSettings.h"
#include <algorithm>
namespace pmchallenge {
using pmbridge::P;
using pmbridge::Runtime;
inline uint32_t runRoot=0, hpRoot=0;
inline int cursor=-1, hpIndex=-1;
inline float initialLife=0;
inline float life=0, damage=0, startLife=0, startDamage=0;
inline bool atResult=false;
inline void drop(Runtime&r,uint32_t&root){if(root)r.gchandle_free(root);root=0;}
inline bool variable(){return runRoot!=0;}
inline P list(Runtime&r){return runRoot?r.gchandle_get_target(runRoot):nullptr;}
inline void clearHP(Runtime&r){drop(r,hpRoot);hpIndex=-1;initialLife=life=damage=0;}
inline void cancelVariable(Runtime&r){drop(r,runRoot);cursor=-1;atResult=false;clearHP(r);}
inline void startVariable(Runtime&r,P items){cancelVariable(r);if(!r.count(items))throw std::runtime_error("Empty challenge");runRoot=r.gchandle_new(items,false);}
inline bool hpVisible(Runtime&r){return hpRoot && (variable() || r.get<P>(r.mainGame(),"challengeSongItems")==r.gchandle_get_target(hpRoot));}
inline float beginTrack(Runtime&r,P progress,float maximum){
 if(!PMSettingBool("challengeCarryHP")||!r.get<bool>(progress,"_inChallengeMode")){clearHP(r);return maximum;}
 P gi=r.mainGame();if(r.get<bool>(gi,"secretChallengeLifeEnabled")){clearHP(r);return maximum;}
 P items=variable()?list(r):r.get<P>(gi,"challengeSongItems");
 int index=variable()?cursor:r.get<int>(gi,"nowChallengeIndex")-1;
 if(!items||index<0){clearHP(r);return maximum;}
 if(!hpRoot||r.gchandle_get_target(hpRoot)!=items||index<hpIndex||index>hpIndex+1){clearHP(r);hpRoot=r.gchandle_new(items,false);initialLife=maximum;life=initialLife;}
 if(index!=hpIndex){startLife=life;startDamage=damage;hpIndex=index;}
 life=std::clamp(startLife,0.f,maximum);damage=startDamage;return life;
}
inline void observe(float before,float after){if(hpRoot){damage+=std::max(0.f,before-after);life=after;}}
inline void restoreList(Runtime&r,int played){P gi=r.mainGame();r.put(gi,"challengeSongItems",list(r));r.put(gi,"nowChallengeIndex",played);}
inline bool advance(Runtime&r){
 P gi=r.mainGame(),items=list(r);int count=r.count(items);
 if(cursor>=0 && cursor<count){P prev=r.at(items,cursor);r.put(prev,"result",r.get<P>(gi,"levelResultInfo"));r.put(prev,"noteCodes",r.get<P>(gi,"noteCodes"));}
 int next=cursor+1;
 if(next>=count){restoreList(r,count);atResult=true;r.stat(r.type("UnityEngine.SceneManagement","SceneManager"),"LoadScene",{"System.String"},{r.string_new("ChallengeModeOver")});return false;}
 P window=r.object_new(r.object_get_class(items));r.call(window,".ctor");
 r.call(window,"Add",{"Phigros2.SongSelector.Scripts.ChallengeSongItem"},{r.at(items,next)});
 r.put(gi,"challengeSongItems",window);r.put(gi,"nowChallengeIndex",0);cursor=next;return true;
}
}
