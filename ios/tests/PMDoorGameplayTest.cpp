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
  assert(obj);
  if constexpr(std::is_same_v<T,P>){assert(std::string(key)=="levelInformation");return obj->info;}
  else return obj->flags.at(key);
 }
};
Runtime &R(){static Runtime runtime;return runtime;}
std::vector<std::string> diagnostics;
void diagf(const char *format,const char *detail){diagnostics.push_back(std::string(format)+detail);}
int clears=0,losses=0,abandons=0,cancels=0,presentationEnds=0;
bool media=false;
bool PMUnlockMediaBusy(){return media;}
void PMDoorCancelPending(){++cancels;}
void PMDoorAbandon(){++abandons;}
void PMDoorFinish(bool clear){++(clear?clears:losses);}
#include "../PhiMod/Sources/PMDoorGameplay.inc"
void endPresentation(){assert(!doorProgress);++presentationEnds;}
phimod::Session begin(phimod::Options options){
 phimod::Session session;session.setCoverage({true,true,true,true,true,true,true});
 session.request(options);assert(session.begin({}));return session;
}
}

int main(){
 phimod::Options options;
 assert(doorPlayEligible(options));
 options.autoplay=true;assert(!doorPlayEligible(options));options.autoplay=false;
 options.practiceMode=true;assert(!doorPlayEligible(options));options.practiceMode=false;
 options.playbackRate=.75f;assert(!doorPlayEligible(options));options.playbackRate=1;
 options.hpEnabled=true;options.hpMax=5;options.hpDelta={1,-1,-3,-5};
 auto replay=options;
 assert(applyChapterReplay(true,replay) && !replay.hpEnabled && options.hpEnabled);
 assert(replay.hpMax==options.hpMax && replay.hpDelta==options.hpDelta);
 auto next=options;assert(!applyChapterReplay(false,next) && next.hpEnabled);
 auto session=begin(options);
 // Native 4.0.4: info +0x68/+0x6A/+0x6B = loaded/over/canOver.
 // Device evidence has levelBegan=0 during real play. Progress.Update
 // 0x1593AE8 sets over=1; LevelOver factory 0x1593FF4 and MoveNext
 // 0x15949E4 leave these flags unchanged before loading the result scene.
 Object info{{{"chartLoaded",true},{"levelBegan",false},{"levelOver",true},{"canLevelOver",true}}};
 Object pc{{{"leave",false},{"levelBreak",false},{"_inChallengeMode",false},{"exit",false}},&info},other;
 auto settle=[&](const phimod::Session *attempt,bool ending,bool clear){
  const int c=clears,a=abandons,l=losses,e=presentationEnds;
  const auto d=diagnostics.size();
  doorProgress=&pc;endDoorPresentation=endPresentation;
  settleDoorEnd(&other,attempt,ending); // A foreign owner cannot read/consume it.
  assert(doorProgress==&pc && diagnostics.size()==d);
  settleDoorEnd(&pc,attempt,ending);
  assert(!doorProgress && !endDoorPresentation && presentationEnds==e+1);
  assert(clears==c+int(clear) && abandons==a+int(!clear) && losses==l);
  assert(diagnostics.size()==d+(attempt?1:0));
  settleDoorEnd(&pc,attempt,ending);abandonBoundDoor();finishBoundDoor(YES);
  assert(clears==c+int(clear) && abandons==a+int(!clear) && losses==l);
  assert(presentationEnds==e+1 && diagnostics.size()==d+(attempt?1:0));
 };
 finishBoundDoor(true);finishBoundDoor(false);assert(clears==0 && losses==0);
 // Actual production helper, not a test-side copy of its eligibility gate.
 settle(&session,false,true);
 assert(diagnostics.back().find("clear hp=5.000000")!=std::string::npos);
 assert(diagnostics.back().find("began=0 leave=0 over=1 canOver=1")!=std::string::npos);
 // Both entry/return snapshots of the native LevelOver factory accept the
 // completion. A focus callback may latch leave between them; it is not quit.
 for(bool began:{false,true})for(bool leave:{false,true}){
  info.flags["levelBegan"]=began;pc.flags["leave"]=leave;
  settle(&session,false,true);
 }
 info.flags["levelBegan"]=false;
 // Native quit/retry sets +0xA5 at 0x15940D4, even if leave is already clear.
 for(bool leave:{false,true}){
  pc.flags["leave"]=leave;pc.flags["levelBreak"]=true;
  settle(&session,false,false);pc.flags["levelBreak"]=false;
 }
 pc.flags["leave"]=false;
 // Pre-end, unloaded and canLevelOver-disabled terminal/failure paths fail closed.
 for(auto name:{"chartLoaded","levelOver","canLevelOver"}){
  info.flags[name]=false;settle(&session,false,false);info.flags[name]=true;
 }
 pc.flags["_inChallengeMode"]=true;settle(&session,false,false);pc.flags["_inChallengeMode"]=false;
 settle(&session,true,false);settle(nullptr,false,false);
 pc.info=nullptr;settle(&session,false,false);pc.info=&info;
 info.flags.erase("canLevelOver");settle(&session,false,false);info.flags["canLevelOver"]=true;
 assert(diagnostics.back().find("unavailable")!=std::string::npos);
 // Options are checked again at settlement; replay has no door binding and HP
 // is disabled on its per-attempt copy, which must not manufacture a clear.
 for(int mode=0;mode<4;++mode){
  auto assisted=options;
  if(mode==0)assisted.autoplay=true;
  if(mode==1)assisted.practiceMode=true;
  if(mode==2)assisted.playbackRate=.75f;
  if(mode==3)assisted=replay;
  auto ineligible=begin(assisted);settle(&ineligible,false,false);
 }
 auto replaySession=begin(replay);
 const int beforeReplay=clears;const auto beforeReplayLogs=diagnostics.size();
 settleDoorEnd(&pc,&replaySession,false);
 assert(clears==beforeReplay && diagnostics.size()==beforeReplayLogs);
 auto zeroHP=begin(options);zeroHP.seedTrackHP(0);settle(&zeroHP,false,false);
 // Drive actual HP samples including duplicate and foreign callbacks.
 doorProgress=&pc;session.registerNote({1,1,0,1});session.registerNote({2,2,0,1});
 auto judge=[&](int code,phimod::Rating rating){float before=session.hp();bool accepted=session.observe(float(code),0,rating);observeDoorLoss(&pc,session,accepted,before);};
 judge(1,phimod::Rating::Bad);judge(1,phimod::Rating::Miss);assert(session.hp()==2 && losses==0);
 observeDoorLoss(&other,session,true,2);assert(doorProgress==&pc);
 judge(2,phimod::Rating::Miss);assert(session.hp()==0 && losses==1 && lostDoorProgress==&pc);
 const int beforeLostClear=clears;
 judge(2,phimod::Rating::Miss);settleDoorEnd(&pc,&session,false);abandonBoundDoor();
 assert(clears==beforeLostClear && losses==1);
 settle(&session,false,false);
 session.seedTrackHP(2);assert(session.trackLost());settle(&session,false,false);
 // A late lethal callback after LevelBreak is an abandonment, including retry.
 const int beforeQuit=abandons;
 doorProgress=&pc;pc.flags["levelBreak"]=true;observeDoorLoss(&pc,session,true,2);
 assert(abandons==beforeQuit+1 && losses==1 && clears==beforeLostClear);
 watchingDoorLaunch=true;media=true;cancelIdleDoorLaunch(&pc);assert(cancels==0);
 media=false;pc.flags["exit"]=true;cancelIdleDoorLaunch(&pc);assert(cancels==0);
 pc.flags["exit"]=false;cancelIdleDoorLaunch(&pc);cancelIdleDoorLaunch(&pc);assert(cancels==1);
}
