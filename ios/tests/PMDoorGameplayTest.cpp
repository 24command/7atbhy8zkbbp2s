#include "../PhiMod/Core/PMGameplayCore.hpp"
#include <cassert>
#include <map>
#include <string>
#include <type_traits>

namespace {
using BOOL=bool;
constexpr bool YES=true,NO=false;
struct Object { std::map<std::string,bool> flags; Object *info=nullptr; };
using P=Object*;
struct Runtime {
 template<class T>T get(P obj,const char *key){
  if constexpr(std::is_same_v<T,P>){assert(std::string(key)=="levelInformation");return obj->info;}
  else return obj->flags.at(key);
 }
};
Runtime &R(){static Runtime runtime;return runtime;}
void diagf(const char*,const char*){}
int clears=0,losses=0,abandons=0,cancels=0;
bool media=false;
bool PMUnlockMediaBusy(){return media;}
void PMDoorCancelPending(){++cancels;}
void PMDoorAbandon(){++abandons;}
void PMDoorFinish(bool clear){++(clear?clears:losses);}
#include "../PhiMod/Sources/PMDoorGameplay.inc"
}

int main(){
 phimod::Options options;
 assert(doorPlayEligible(options));
 options.autoplay=true;assert(!doorPlayEligible(options));options.autoplay=false;
 options.practiceMode=true;assert(!doorPlayEligible(options));options.practiceMode=false;
 options.playbackRate=.75f;assert(!doorPlayEligible(options));options.playbackRate=1;
 Object info{{{"chartLoaded",true},{"levelBegan",true},{"levelOver",true},{"canLevelOver",true}}};
 Object pc{{{"leave",false},{"levelBreak",false},{"_inChallengeMode",false},{"exit",false}},&info},other;
 options.hpEnabled=true;options.hpMax=5;options.hpDelta={1,-1,-3,-5};
 auto replay=options;
 assert(applyChapterReplay(true,replay) && !replay.hpEnabled && options.hpEnabled);
 assert(replay.hpMax==options.hpMax && replay.hpDelta==options.hpDelta);
 auto next=options;assert(!applyChapterReplay(false,next) && next.hpEnabled);
 finishBoundDoor(true);finishBoundDoor(false);assert(clears==0 && losses==0);
 phimod::Session session;session.setCoverage({true,true,true,true,true,true,true});session.request(options);assert(session.begin({}));
 // An unfinished chart, manual transition, or course produces no door result.
 for(auto &field:info.flags){doorProgress=&pc;field.second=false;settleDoorEnd(&pc,&session,false);field.second=true;assert(!doorProgress);}
 for(auto name:{"leave","levelBreak","_inChallengeMode"}){doorProgress=&pc;pc.flags[name]=true;settleDoorEnd(&pc,&session,false);pc.flags[name]=false;}
 doorProgress=&pc;settleDoorEnd(&pc,&session,true);
 doorProgress=&pc;settleDoorEnd(&pc,nullptr,false);
 assert(abandons==9 && clears==0 && losses==0);
 doorProgress=&pc;settleDoorEnd(&other,&session,false);assert(doorProgress==&pc);
 settleDoorEnd(&pc,&session,false);settleDoorEnd(&pc,&session,false);abandonBoundDoor();assert(clears==1 && abandons==9);
 // Drive an actual native-style HP sample sequence, including a duplicate.
 doorProgress=&pc;session.registerNote({1,1,0,1});session.registerNote({2,2,0,1});
 auto judge=[&](int code,phimod::Rating rating){float before=session.hp();bool accepted=session.observe(float(code),0,rating);observeDoorLoss(&pc,session,accepted,before);};
 judge(1,phimod::Rating::Bad);judge(1,phimod::Rating::Miss);assert(session.hp()==2 && losses==0);
 judge(2,phimod::Rating::Miss);assert(session.hp()==0 && losses==1 && lostDoorProgress==&pc);
 judge(2,phimod::Rating::Miss);settleDoorEnd(&pc,&session,false);abandonBoundDoor();assert(clears==1 && losses==1);
 // A late lethal callback after LevelBreak is an abandonment, including retry.
 doorProgress=&pc;pc.flags["levelBreak"]=true;observeDoorLoss(&pc,session,true,2);assert(abandons==10 && losses==1);
 watchingDoorLaunch=true;media=true;cancelIdleDoorLaunch(&pc);assert(cancels==0);
 media=false;pc.flags["exit"]=true;cancelIdleDoorLaunch(&pc);assert(cancels==0);
 pc.flags["exit"]=false;cancelIdleDoorLaunch(&pc);cancelIdleDoorLaunch(&pc);assert(cancels==1);
}
