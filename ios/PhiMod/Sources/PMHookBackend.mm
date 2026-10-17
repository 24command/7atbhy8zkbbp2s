#import "PMHookBackend.h"
#import "PMSettings.h"
#import "PMRuntime.h"
#import "PMDiagnostics.h"
#include "PMIL2CPP.hpp"
#include "PMOptions.hpp"
#include "PMSceneUI.hpp"
#include "PMHPLife.hpp"
#include "PMChartModes.hpp"
#include "../Core/PMFlowCore.hpp"
#include "../Core/PMHookProtocol.hpp"
#include "../Core/PMHookManifest.hpp"
#include <atomic>
#include <memory>
#include <set>
#include <sstream>
#include <cstdio>
#include <cstdarg>
namespace {
using pmbridge::P;
using pmbridge::Runtime;
namespace h=phimod::hooks;
__attribute__((used)) static const char PMGameplayProtocol[16]="PMGameplay-v2";
__attribute__((used)) static const char PMGameplayBuild[]="PMGameplay-contract-v2-55";
struct V3{float x,y,z;};
struct V2{float x,y;};
struct Color{float r,g,b,a;};
std::unique_ptr<Runtime> rt;
P gateways[h::Count]{};
std::unique_ptr<phimod::Session> attempt;
std::atomic<bool> guard{false};
 bool ready=false,broken=false,inResult=false,resultPresented=false,levelOverStarted=false,loadingMaskCleared=false;
phimod::Options frozenOptions;
uint32_t progressRoot=0,scoreRoot=0;
  std::set<float> registered;
std::string lastError="Backend not installed";
bool judgeUpdateSeen=false;
bool diagHaveState=false,diagLastPlaying=false,diagLastLeave=false,diagLastLevelBreak=false,diagLastLevelOver=false,diagLastCanLevelOver=false;
float diagLastNow=0;
int diagLastFrame=-1;
unsigned installAttempts=0;
// All runtime reflection and gameplay callbacks are Unity main-thread only.
// Persistence callbacks only load the atomic guard and invoke their gateway.
Runtime &R(){if(!rt||![NSThread isMainThread])throw std::runtime_error("Unity main thread required");return *rt;}
template<class T>T orig(h::Index i){return reinterpret_cast<T>(gateways[i]);}
using VoidFn=void(*)(P,P);
using JudgeFn=bool(*)(P,P);
using PerfectFn=void(*)(P,float,float,V3,bool,P);
void diagf(const char *format,...){
 char buffer[768];va_list args;va_start(args,format);vsnprintf(buffer,sizeof(buffer),format,args);va_end(args);PMDiagnosticsWrite(buffer);
}
void fault(const std::exception &e){diagf("fault: %s",e.what());NSLog(@"[PhiMod] Gameplay failure: %s",e.what());lastError=e.what();broken=true;guard.store(true);if(attempt)attempt->failClosed();}
bool applying(){return ready&&!broken&&attempt&&attempt->shouldApplyGameplay();}
P progress(){return progressRoot?R().gchandle_get_target(progressRoot):nullptr;}
P score(){return scoreRoot?R().gchandle_get_target(scoreRoot):nullptr;}
void release(uint32_t &root){if(root){R().gchandle_free(root);root=0;}}
  void resetChartRegistration(){registered.clear();}
 bool registerOne(P note){
  if(!attempt||!note)return false;
  try{
   auto &r=R();float code=r.get<float>(note,"noteCode");
   if(registered.count(code))return true;
   attempt->registerNote({code,r.get<float>(note,"realTime"),r.get<float>(note,"holdTime"),r.get<int>(note,"type"),false});registered.insert(code);
   return true;
  }catch(const std::exception&e){
   lastError=std::string("Chart registration deferred: ")+e.what();
   return false;
  }catch(...){
   lastError="Chart registration deferred: unknown error";
   return false;
  }
 }
void begin(P p){
 auto &r=R();auto options=frozenOptions;
    release(progressRoot);release(scoreRoot);attempt.reset();resetChartRegistration();resultPresented=false;levelOverStarted=false;loadingMaskCleared=false;
 diagf("ProgressControl.Start begin assisted=%d judge=%d autoplay=%d hp=%d challenge=%d",options.assisted(),options.judge,options.autoplay,options.hpEnabled,options.challenge);
 if(!options.assisted()){lastError="Original gameplay: assistance off";diagf("ProgressControl.Start original gameplay");return;}
 progressRoot=r.gchandle_new(p,false);scoreRoot=r.gchandle_new(r.get<P>(p,"scoreControl"),false);
 attempt=std::make_unique<phimod::Session>();
 attempt->setCoverage({true,true,true,true,true,true,true});
 attempt->request(options);
 auto jc=r.klass("JudgeControl");r.runtime_class_init(jc);
 phimod::Windows baseline{r.staticValue<float>(jc,"PerfectTimeRange","System.Single"),r.staticValue<float>(jc,"GoodTimeRange","System.Single"),r.staticValue<float>(jc,"BadTimeRange","System.Single")};
 if(!attempt->begin(baseline))throw std::runtime_error("Incomplete hook coverage");
 if(options.requiresSaveProtection())guard.store(true);
 lastError="Gameplay hooks armed (device verification pending)";
 diagf("ProgressControl.Start armed baseline P=%.4f G=%.4f B=%.4f",baseline.perfect,baseline.good,baseline.bad);
}
void onAwake(P self,P mi){
 diagf("LevelControl.Awake enter hp=%d",frozenOptions.hpEnabled);
 // A latch survives OnDestroy, disabled switches and the entire result screen.
 // Alternate assisted result never launches the reward/save coroutine.
 if(!broken){
  try{guard.store(PMReadOptions([[PMSettings shared] snapshot]).requiresSaveProtection());}catch(const std::exception &e){fault(e);}
 }
  try{release(progressRoot);release(scoreRoot);attempt.reset();resetChartRegistration();judgeUpdateSeen=false;pmscene::settingsLeave(R());pmscene::clearRecovery(R());pmhp::clear(R());pmmodes::clear(R());}catch(const std::exception&e){fault(e);}
   inResult=false;resultPresented=false;levelOverStarted=false;loadingMaskCleared=false;
 try{frozenOptions=PMReadOptions([[PMSettings shared] snapshot]);diagf("LevelControl.Awake options assisted=%d hp=%d hpMax=%.1f",frozenOptions.assisted(),frozenOptions.hpEnabled,frozenOptions.hpMax);if(!broken){pmhp::prepare(R(),self,frozenOptions);diagf("HP prepare ok");pmmodes::prepare(R(),self,frozenOptions);}}catch(const std::exception&e){diagf("LevelControl.Awake prepare failed: %s",e.what());fault(e);}
 orig<VoidFn>(h::levelAwake)(self,mi);
 diagf("LevelControl.Awake returned");
}
void onDestroy(P self,P mi){
 diagf("LevelControl.OnDestroy enter");
  if(attempt){attempt->result();if(attempt->excluded())guard.store(true);}
  resultPresented=false;levelOverStarted=false;loadingMaskCleared=false;judgeUpdateSeen=false;
  try{pmhp::clear(R());pmmodes::clear(R());}catch(const std::exception&e){fault(e);}
  resetChartRegistration();
  orig<VoidFn>(h::levelDestroy)(self,mi);
  diagf("LevelControl.OnDestroy returned");
}
void onProgressStart(P self,P mi){
 diagf("ProgressControl.Start enter");
 orig<VoidFn>(h::progressStart)(self,mi);
 diagf("ProgressControl.Start original returned");
 try{begin(self);}catch(const std::exception&e){fault(e);}
}
 void clearGameplayMask(Runtime&r,P progressControl){
  if(loadingMaskCleared||r.get<float>(progressControl,"nowTime")<0||!r.get<bool>(progressControl,"isPlaying"))return;
  P mask=r.get<P>(r.mainGame(),"sceneSwitchMask");
  if(!mask)return;
  r.call(mask,"set_texture",{"UnityEngine.Texture"},{nullptr});
  Color clear{0,0,0,0};
  r.call(mask,"set_color",{"UnityEngine.Color"},{&clear});
  loadingMaskCleared=true;
 }
void credit(P self,float code,float offset,V3 pos,bool hold,P mi){
 orig<PerfectFn>(h::perfect)(self,code,offset,pos,hold,mi);
}
void observe(float code,float offset,phimod::Rating rating){
 if(!applying())return;
 float before=attempt->hp();bool accepted=attempt->observe(code,offset,rating);
 if(accepted&&attempt->options().hpEnabled){try{pmhp::frame(R(),attempt->hp());if(before!=attempt->hp())pmhp::flash(R());}catch(const std::exception&e){lastError=std::string("HP visuals: ")+e.what();}}
}
void onPerfect(P self,float code,float offset,V3 pos,bool hold,P mi){
 if(applying()&&attempt->options().autoplay){
  try{auto &r=R();if(attempt->deferHold(code,offset,{pos.x,pos.y,pos.z},hold,r.get<float>(progress(),"nowTime")))return;
   if(!attempt->creditOnce(code))return;
  }catch(const std::exception&e){fault(e);return;}
 }
 observe(code,offset,phimod::Rating::Perfect);credit(self,code,offset,pos,hold,mi);
}
void onMiss(P self,float code,P mi){
 if(applying()&&attempt->options().autoplay){
  // Android only defers type-3 holds to their real tail. Ordinary Tap/Drag/
  // Flick misses are converted to an immediate Perfect and must not enter
  // the hold queue, otherwise the result coroutine sees unfinished notes.
  bool hold=attempt->noteType(code)==3;
  onPerfect(self,code,0,{0,0,0},hold,nullptr);return;
 }
 observe(code,0,phimod::Rating::Miss);orig<void(*)(P,float,P)>(h::miss)(self,code,mi);
}
void onBad(P self,float code,float offset,P mi){observe(code,offset,phimod::Rating::Bad);orig<void(*)(P,float,float,P)>(h::bad)(self,code,offset,mi);}
void onGood(P self,float code,float offset,V3 pos,bool hold,P mi){observe(code,offset,phimod::Rating::Good);orig<PerfectFn>(h::good)(self,code,offset,pos,hold,mi);}
void diagnosticTick(Runtime&r,P progressControl,const char *source){
 if(!progressControl)return;
 bool playing=r.get<bool>(progressControl,"isPlaying");
 float now=r.get<float>(progressControl,"nowTime");
 int frame=r.get<int>(progressControl,"_nowFrameIndex");
 bool leave=r.get<bool>(progressControl,"leave");
 bool breaking=r.get<bool>(progressControl,"levelBreak");
 bool over=false,canOver=false;
 P info=r.get<P>(progressControl,"levelInformation");
 if(info){over=r.get<bool>(info,"levelOver");canOver=r.get<bool>(info,"canLevelOver");}
 bool stateChanged=!diagHaveState||playing!=diagLastPlaying||leave!=diagLastLeave||breaking!=diagLastLevelBreak||over!=diagLastLevelOver||canOver!=diagLastCanLevelOver||frame<diagLastFrame;
 bool timeDue=!std::isfinite(diagLastNow)||!std::isfinite(now)||std::fabs(now-diagLastNow)>=.1f;
 if(stateChanged||timeDue){
  int phase=attempt?static_cast<int>(attempt->phase()):-1;
  float hp=attempt?attempt->hp():-1;
  diagf("tick source=%s frame=%d now=%.3f playing=%d leave=%d break=%d over=%d canOver=%d phase=%d hp=%.2f",source,frame,now,playing,leave,breaking,over,canOver,phase,hp);
  diagHaveState=true;diagLastPlaying=playing;diagLastLeave=leave;diagLastLevelBreak=breaking;diagLastLevelOver=over;diagLastCanLevelOver=canOver;diagLastNow=now;diagLastFrame=frame;
 }
}
void tickGameplay(Runtime&r,P progressControl,const char *source){
 if(!progressControl)return;
 diagnosticTick(r,progressControl,source);
 float now=r.get<float>(progressControl,"nowTime");
 if(!attempt||!attempt->shouldApplyGameplay())return;
 try{
  clearGameplayMask(r,progressControl);bool playing=r.get<bool>(progressControl,"isPlaying");
  // Pending holds only credit at their real tail, not the engine's -220ms
  // completion point. Exactly one sample/HP award and one original Perfect.
  for(auto c:attempt->dueHolds(now,playing)){
   observe(c.code,c.offset,phimod::Rating::Perfect);
   credit(score(),c.code,c.offset,{c.position[0],c.position[1],c.position[2]},c.hold,nullptr);
  }
  bool hpLost=attempt->options().hpEnabled&&attempt->trackLost();
  auto action=attempt->pendingAction(playing||pmhp::failing()||hpLost,r.get<bool>(progressControl,"leave"),r.get<bool>(progressControl,"levelBreak"));
  P info=r.get<P>(progressControl,"levelInformation");
  if(action==phimod::Action::Retry){
   if(attempt->options().requiresSaveProtection())guard.store(true);r.call(progressControl,"LevelBreak",{"System.String"},{r.string_new("Level")});
   r.put(info,"levelOver",true);r.put(info,"canPause",false);r.call(r.get<P>(progressControl,"audioSource"),"Stop");attempt->acknowledgeAction(action);diagf("gameplay retry dispatched");
  }else if(action==phimod::Action::TrackLost&&!levelOverStarted&&pmhp::failureReady(r,progressControl)){
   diagf("HP failure ready; starting LevelOver");
   r.call(score(),"FreezeScore");r.put(progressControl,"isPlaying",false);r.put(info,"levelOver",true);r.put(info,"canLevelOver",true);
   P routine=r.call(progressControl,"LevelOver");r.call(progressControl,"StartCoroutine",{"System.Collections.IEnumerator"},{routine});levelOverStarted=true;attempt->acknowledgeAction(action);r.call(r.get<P>(progressControl,"audioSource"),"Stop");
   diagf("HP LevelOver coroutine started");
  }
  pmhp::frame(r,attempt->hp());
 }catch(const std::exception&e){lastError=std::string("Transition pending: ")+e.what();diagf("Transition pending: %s",e.what());NSLog(@"[PhiMod] %s",lastError.c_str());}
}
void onProgressUpdate(P self,P mi){
 orig<VoidFn>(h::progressUpdate)(self,mi);
 try{diagnosticTick(R(),self,"ProgressControl.Update");}catch(const std::exception&e){diagf("ProgressControl.Update diagnostic failed: %s",e.what());}
}
void onJudgeUpdate(P self,P mi){
 judgeUpdateSeen=true;
 orig<VoidFn>(h::judgeUpdate)(self,mi);
 try{
  auto &r=R();P progressControl=r.get<P>(self,"progressControl");tickGameplay(r,progressControl,"JudgeControl.Update");
 }catch(const std::exception&e){lastError=std::string("JudgeControl.Update: ")+e.what();diagf("JudgeControl.Update failed: %s",e.what());}
}
bool noteJudge(P self,P mi,h::Index index,bool hold){
 if(!applying())return orig<JudgeFn>(index)(self,mi);
 auto &r=R();P clock=nullptr,note=nullptr;bool restoreClock=false,restoreX=false;float now=0,oldX=0;
 bool called=false,result=false;
 std::unique_ptr<pmmodes::HoldScope> holdScope;
 try{
  if(hold)holdScope=std::make_unique<pmmodes::HoldScope>(r,self);
  note=r.get<P>(self,"noteInfor");clock=r.get<P>(self,"progressControl");registerOne(note);
  if(attempt->options().autoplay){
   bool playing=r.get<bool>(clock,"isPlaying");now=r.get<float>(clock,"nowTime");float time=r.get<float>(note,"realTime");
   bool head=hold&&r.get<bool>(self,"judged");
   auto plan=phimod::autoPlan(true,false,playing,hold,head,now,time);
   if(plan.kind==phimod::AutoPlan::Kind::Wait){r.put(note,"isJudged",false);return false;}
   if(plan.kind==phimod::AutoPlan::Kind::Assisted){
    r.put(note,"isJudged",true);r.put(note,"isJudgedForFlick",true);r.put(self,"isJudged",true);
    if(hold){r.put(self,"missed",false);r.put(self,"isPerfect",true);r.put(self,"_safeFrame",plan.safeFrames);}
    if(plan.replaceClock){restoreClock=true;r.put(clock,"nowTime",plan.temporaryClock);}
   }
  }else if(attempt->options().fullscreen){
   P line=r.get<P>(self,"judgeLine");int n=r.get<int>(line,"numOfFingers");P fingers=r.get<P>(line,"fingerPositionX");
   if(n>0&&fingers&&r.array_length(fingers)>0){oldX=r.get<float>(note,"positionX");float x=r.unbox<float>(r.arrayAt(fingers,0));restoreX=true;r.put(note,"positionX",x);}
  }
  called=true;result=orig<JudgeFn>(index)(self,mi);
  if(result)pmmodes::completed(r,self);
 }catch(const std::exception&e){fault(e);}
 try{if(holdScope)holdScope->finish();}catch(const std::exception&e){fault(e);}
 holdScope.reset();
 // Restore temporary game clock and note position even if a managed operation
 // failed. No 'retry original' after an original call has already happened.
 try{if(restoreClock)r.put(clock,"nowTime",now);if(restoreX)r.put(note,"positionX",oldX);}catch(const std::exception&e){fault(e);}
 return called?result:orig<JudgeFn>(index)(self,mi);
}
bool onClick(P s,P m){return noteJudge(s,m,h::click,false);}
bool onDrag(P s,P m){return noteJudge(s,m,h::drag,false);}
bool onHold(P s,P m){return noteJudge(s,m,h::hold,true);}
bool onFlick(P s,P m){return noteJudge(s,m,h::flick,false);}
bool readAccuracy(P self,float &outScore,int &outTotal){
 try{
  auto &r=R();P info=r.get<P>(self,"levelInformation");if(!info)return false;
  int perfect=r.get<int>(self,"perfect"),good=r.get<int>(self,"good");
  int total=r.get<int>(info,"numOfNotes");
  // Accuracy only depends on Perfect/Good and the note total. Bad/Miss are
  // deliberately not read: during result handoff they can be transient or
  // represented differently for holds, while Android uses the same formula.
  if(perfect<0||good<0||total<=0)return false;
  if(static_cast<std::int64_t>(perfect)+good>total)return false;
  float value=phimod::accuracyScore(perfect,good,total);
  if(!std::isfinite(value))return false;
  outScore=value;outTotal=total;return true;
 }catch(...){return false;}
}
void onScoreUpdate(P self,P mi){
  // ScoreControl must update its native counters first. During level setup the
  // note count is transiently zero, so invalid reads are ignored rather than
  // fail-closing the entire gameplay backend.
  orig<VoidFn>(h::scoreUpdate)(self,mi);
  if(!applying())return;
  try{auto &r=R();auto o=attempt->options();
   if(o.accuracyOnly){float value=0;int total=0;if(readAccuracy(self,value,total)){
    r.put(self,"scoreOfNote",1000000.f/total);r.put(self,"_score",value);r.put(self,"_percent",value/1000000.f);
    char digits[32];snprintf(digits,sizeof(digits),"%07d",int(std::round(value)));r.text(r.get<P>(self,"score"),digits);
   }}
   if(o.hpEnabled){pmhp::scoreFrame(r,self);r.text(r.get<P>(self,"comboText"),"LIFE");r.text(r.get<P>(self,"combo"),std::to_string(int(std::ceil(attempt->hp()))).c_str());}
   else if(o.autoplay)r.text(r.get<P>(self,"comboText"),"AUTOPLAY");
  }catch(const std::exception&e){lastError=std::string("Score update: ")+e.what();NSLog(@"[PhiMod] %s",lastError.c_str());}
 }
 P onResultInfo(P self,P mi){
  P result=orig<P(*)(P,P)>(h::resultInfo)(self,mi);
  if(attempt&&attempt->options().accuracyOnly&&(applying()||inResult))try{float value=0;int total=0;if(readAccuracy(self,value,total))R().call(result,"set_Score",{"System.Single"},{&value});}catch(const std::exception&e){lastError=std::string("Accuracy result: ")+e.what();}
  return result;
}
void onRecord(P self,P result,P mi){if(!guard.load())orig<void(*)(P,P,P)>(h::record)(self,result,mi);}
void onSetRecord(P self,P id,P level,P record,P mi){if(!guard.load())orig<void(*)(P,P,P,P,P)>(h::setRecord)(self,id,level,record,mi);}
void onRanking(P self,P mi){if(!guard.load())orig<VoidFn>(h::ranking)(self,mi);}
void onDelete(P key,P mi){if(!guard.load())orig<VoidFn>(h::DeleteKey)(key,mi);}
template<h::Index I>void saveInt(P key,int value,P mi){if(!guard.load())orig<void(*)(P,int,P)>(I)(key,value,mi);}
template<h::Index I>void saveBool(P key,bool value,P mi){if(!guard.load())orig<void(*)(P,bool,P)>(I)(key,value,mi);}
template<h::Index I>void saveFloat(P key,float value,P mi){if(!guard.load())orig<void(*)(P,float,P)>(I)(key,value,mi);}
template<h::Index I>void saveString(P key,P value,P mi){if(!guard.load())orig<void(*)(P,P,P)>(I)(key,value,mi);}
void onSaveDate(P key,uint64_t value,P mi){if(!guard.load())orig<void(*)(P,uint64_t,P)>(h::SaveDate)(key,value,mi);}
void renderPracticeResult(P self){
 auto &r=R();P gi=r.mainGame(),info=r.get<P>(gi,"levelStartInfo"),result=r.get<P>(gi,"levelResultInfo");
 if(!info||!result)throw std::runtime_error("Result data missing after LevelOver");
 r.put(self,"_gameInformation",gi);r.put(self,"_levelStartInfo",info);r.put(self,"levelResultInfo",result);
 P mask=r.get<P>(gi,"sceneSwitchMask");r.call(mask,"set_texture",{"UnityEngine.Texture"},{nullptr});Color clear{0,0,0,0};r.call(mask,"set_color",{"UnityEngine.Color"},{&clear});
 std::string warnings;
 auto present=[&](const char*stage,auto fn){try{fn();}catch(const std::exception&e){warnings+=std::string(stage)+": "+e.what()+"; ";NSLog(@"[PhiMod] Result %s: %s",stage,e.what());}};
 // Optional audio/cover/name replacements must never prevent the canvas from
 // becoming visible. Each presentation helper has its own failure boundary.
 present("listener",[&]{float volume=1;r.stat(r.klass("GameInformation"),"set_ListenerVolume",{"System.Single"},{&volume});});
 P ctx=r.object_new(r.nested(r.klass("LevelOverControl"),"<>c__DisplayClass43_0"));uint32_t root=r.gchandle_new(ctx,false);
 try{
  r.call(ctx,".ctor");r.put(ctx,"<>4__this",self);P record=r.object_new(r.klass("LevelRecord"));uint32_t rr=r.gchandle_new(record,false);
  try{r.call(record,".ctor");r.put(ctx,"record",record);}catch(...){r.gchandle_free(rr);throw;}r.gchandle_free(rr);
  present("audio prepare",[&]{float zero=0;r.call(r.get<P>(self,"audioSource"),"set_Volume",{"System.Single"},{&zero});});
  present("audio key",[&]{r.call(ctx,"<Start>g__SetResultAudio|1");});
  present("result info",[&]{r.call(ctx,"<Start>g__SetResultInfo|2");});
  present("rating",[&]{int value=r.get<int>(result,"<IntScore>k__BackingField");bool fc=r.unbox<bool>(r.call(result,"get_FullCombo"));r.call(ctx,"<Start>g__SetRatingWithScore|3",{"System.Int32","System.Boolean"},{&value,&fc});});
  present("cover",[&]{r.call(r.get<P>(self,"cover"),"set_Code",{"System.String"},{r.get<P>(info,"illustrationKey")});});
  present("screen ratio",[&]{r.call(ctx,"<Start>g__SetScreenRatio|23");});
  // Critical: independently enable the game canvas even if audio or an
  // optional song-name helper failed. No null Start or silent black screen.
  r.call(ctx,"<Start>g__EnableResultCanvas|21");
  present("BGM",[&]{r.call(ctx,"<Start>g__PlayResultBGM|22");});
  present("practice label",[&]{
    bool lost=attempt&&attempt->options().hpEnabled&&attempt->hp()<=0;
    r.text(r.get<P>(self,"best"),lost?"PHIMOD PRACTICE / TRACK LOST - Not saved":warnings.empty()?"PHIMOD PRACTICE - Scores / RKS / unlocks not saved":"PHIMOD PRACTICE - presentation warning (see status)");
   });
 }catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);
 lastError=warnings.empty()?"Practice result displayed; saves remain blocked":warnings;
}
P onResultStart(P self,P mi){
  // Keep Unity's real <Start>d__43 coroutine. It owns result-canvas setup,
  // result audio and the save/unlock ordering; only the protected data path is
  // intercepted by the persistence hooks below.
  if(!guard.load())return orig<P(*)(P,P)>(h::resultStart)(self,mi);
  inResult=true;resultPresented=false;
  try{
   if(attempt){
    for(auto c:attempt->flushPendingHolds()){
     observe(c.code,c.offset,phimod::Rating::Perfect);
     credit(score(),c.code,c.offset,{c.position[0],c.position[1],c.position[2]},c.hold,nullptr);
    }
    attempt->result();
   }
  }catch(const std::exception&e){
   lastError=std::string("Result preparation: ")+e.what();
   NSLog(@"[PhiMod] %s",lastError.c_str());
  }
  return orig<P(*)(P,P)>(h::resultStart)(self,mi);
 }
 bool onResultMove(P iterator,P mi){
  if(!guard.load())return orig<JudgeFn>(h::resultMove)(iterator,mi);
  bool more=orig<JudgeFn>(h::resultMove)(iterator,mi);
  if(!more){
   resultPresented=true;inResult=false;
   try{if(attempt&&attempt->phase()==phimod::Phase::Result)attempt->finishResult();}
   catch(const std::exception&e){lastError=std::string("Result completion: ")+e.what();}
  }
  return more;
 }
void onLifeStart(P self,P mi){
 diagf("SecretChallengeLifeBar.Start active=%d",pmhp::active());
 if(!pmhp::active()){orig<VoidFn>(h::lifeStart)(self,mi);return;}
 try{pmhp::barStart(R(),self);}catch(const std::exception&e){
  lastError=std::string("Native HP bar: ")+e.what();
  diagf("Native HP bar failed: %s",e.what());
  orig<VoidFn>(h::lifeStart)(self,mi);
 }
}
float onLifeNormalized(P self,P game,P mi){
 try{if(pmhp::ownsBar(R(),self))return pmhp::normalized();}
 catch(const std::exception&e){lastError=std::string("Native HP normalized: ")+e.what();diagf("Native HP normalized failed: %s",e.what());}
 return orig<float(*)(P,P,P)>(h::lifeNormalized)(self,game,mi);
}
void onLifeModStart(P self,P mi){
 diagf("SecretChallengeLifeMod.Start active=%d",pmhp::active());
 if(!pmhp::active()){orig<VoidFn>(h::lifeModStart)(self,mi);return;}
 try{pmhp::modStart(R(),self);}catch(const std::exception&e){
  lastError=std::string("Native HP mod: ")+e.what();
  diagf("Native HP mod failed: %s",e.what());
  orig<VoidFn>(h::lifeModStart)(self,mi);
 }
}
void onHPBackgroundStart(P self,P mi){diagf("HPDisplayControl.Start active=%d",pmhp::active());try{pmhp::backgroundBefore(R());}catch(const std::exception&e){lastError=e.what();diagf("HP background capture failed: %s",e.what());}orig<VoidFn>(h::hpBackgroundStart)(self,mi);try{if(pmhp::active())pmhp::frame(R(),attempt?attempt->hp():frozenOptions.hpMax);}catch(const std::exception&e){lastError=e.what();diagf("HP background update failed: %s",e.what());}}
void onLifeUpdate(P self,P mi){
 try{if(pmhp::ownsBar(R(),self)){pmhp::barUpdate(R(),self);return;}}
 catch(const std::exception&e){lastError=std::string("Native HP update: ")+e.what();diagf("Native HP update failed: %s",e.what());orig<VoidFn>(h::lifeUpdate)(self,mi);return;}
 orig<VoidFn>(h::lifeUpdate)(self,mi);
}
 P onProgressLevelOver(P self,P mi){
  diagf("ProgressControl.LevelOver enter hpActive=%d",pmhp::active());
  if(pmhp::active())try{pmhp::finish(R());}catch(const std::exception&e){lastError=std::string("HP result cleanup: ")+e.what();diagf("HP result cleanup failed: %s",e.what());}
  return orig<P(*)(P,P)>(h::progressLevelOver)(self,mi);
 }
void onLevelCodes(P self,P mi){
 if(!broken)try{pmmodes::beforeCodes(R(),self);}catch(const std::exception&e){fault(e);}
 orig<VoidFn>(h::levelCodes)(self,mi);
}
void onLevelInformation(P self,P mi){
 orig<VoidFn>(h::levelInfo)(self,mi);
 if(!broken)try{pmmodes::afterInformation(R(),self);}catch(const std::exception&e){fault(e);}
}
void onNoteManager(P self,P mi){
 if(applying())try{pmmodes::beginFrame(R(),self);}catch(const std::exception&e){fault(e);}
 orig<VoidFn>(h::noteManager)(self,mi);
   if(applying())try{pmmodes::frame(R(),self);}catch(const std::exception&e){fault(e);}
}
bool onBlocking(P self,V2 point,P*out,P mi){
 if(applying())try{bool handled=false;bool value=pmmodes::blocking(R(),{point.x,point.y},out,handled);if(handled)return value;}catch(const std::exception&e){fault(e);}
 return orig<bool(*)(P,V2,P*,P)>(h::blocking)(self,point,out,mi);
}
void onBlockLate(P self,P mi){orig<VoidFn>(h::blockLate)(self,mi);if(applying())try{pmmodes::late(R(),self);}catch(const std::exception&e){fault(e);}}
void onHoldMove(P self,P mi){
 // Native NoteMove reads missed/timeOfJudge to fade and emit Hold effects.
 // Set them BEFORE the original, as in Android; sample the hole afterwards.
 if(applying())try{pmmodes::holdMove(R(),self);}catch(const std::exception&e){fault(e);}
 orig<VoidFn>(h::holdMove)(self,mi);
 if(applying())try{pmmodes::moved(R(),self,true);}catch(const std::exception&e){fault(e);}
}
template<h::Index i>void onNoteMove(P self,P mi){orig<VoidFn>(i)(self,mi);if(applying())try{pmmodes::moved(R(),self);}catch(const std::exception&e){fault(e);}}
void onSelector(P self,P mi){orig<VoidFn>(h::selector)(self,mi);try{pmscene::selectorFrame(R(),self);}catch(const std::exception&e){lastError=e.what();}}
void onSelectorOff(P self,P mi){try{pmscene::selectorOff(R());}catch(const std::exception&e){lastError=e.what();}orig<VoidFn>(h::selectorOff)(self,mi);}
void onSetting(P self,P mi){orig<VoidFn>(h::setting)(self,mi);try{pmscene::settingsFrame(R(),self);}catch(const std::exception&e){lastError=e.what();}}
void onSettingTab(P self,int index,P mi){try{pmscene::settingsLeave(R());}catch(const std::exception&e){lastError=e.what();}orig<void(*)(P,int,P)>(h::settingTab)(self,index,mi);}
void onSettingBack(P self,P mi){try{pmscene::settingsLeave(R());}catch(const std::exception&e){lastError=e.what();}orig<VoidFn>(h::settingBack)(self,mi);}
bool dispatchModButton(P self){
 if(!pmscene::ownsButton(self))return false;
 try{auto&r=R();if(!r.unbox<bool>(r.call(self,"IsActive"))||!r.unbox<bool>(r.call(self,"IsInteractable")))return true;pmscene::press(r,self);}
 catch(const std::exception&e){lastError=std::string("MOD button: ")+e.what();NSLog(@"[PhiMod] %s",lastError.c_str());}
 return true; // Only an owned clone is consumed. All game buttons pass through.
}
void onPress(P self,P mi){if(!dispatchModButton(self))orig<VoidFn>(h::button)(self,mi);}
void onPointerClick(P self,P event,P mi){
 if(pmscene::ownsButton(self)){
  try{P value=R().call(event,"get_button");int button=0;P raw=R().object_unbox(value);if(!raw)throw std::runtime_error("Invalid pointer button");memcpy(&button,raw,sizeof(button));if(button==0)dispatchModButton(self);}
  catch(const std::exception&e){lastError=e.what();}return;
 }
 orig<void(*)(P,P,P)>(h::buttonClick)(self,event,mi);
}
void onSubmit(P self,P event,P mi){if(!dispatchModButton(self))orig<void(*)(P,P,P)>(h::buttonSubmit)(self,event,mi);}
void onCheck(P self,int finger,P mi,h::Index i){
 // Fullscreen positional scope for initial Tap/Flick candidate collection.
 auto fn=orig<void(*)(P,int,P)>(i);if(!applying()||!attempt->options().fullscreen){fn(self,finger,mi);return;}
 auto &r=R();std::vector<std::pair<P,float>> restore;bool called=false;
 try{
  P lines=r.get<P>(self,"judgeLineControls");P notes=r.get<P>(self,"chartNoteSortByTime");float now=r.get<float>(self,"nowTime");
  int total=r.count(notes),low=0,high=total;
  while(low<high){int mid=low+(high-low)/2;if(r.get<float>(r.at(notes,mid),"realTime")<now-.5f)low=mid+1;else high=mid;}
  for(int n=low;n<total;++n){P note=r.at(notes,n);if(r.get<float>(note,"realTime")>now+.5f)break;
   int li=r.get<int>(note,"judgeLineIndex")/2;if(li<0||li>=r.count(lines))continue;
   P line=r.at(lines,li);P xs=r.get<P>(line,"fingerPositionX");
   if(finger<0||!xs||uintptr_t(finger)>=r.array_length(xs))continue;
   float localX=r.unbox<float>(r.arrayAt(xs,finger));
   float old=r.get<float>(note,"positionX");restore.push_back({note,old});r.put(note,"positionX",localX);
  }
  called=true;fn(self,finger,mi);
 }catch(const std::exception&e){fault(e);}
 try{for(auto p:restore)r.put(p.first,"positionX",p.second);}catch(const std::exception&e){fault(e);}
 if(!called)fn(self,finger,mi);
}
void onCheckNote(P s,int f,P m){onCheck(s,f,m,h::checkNote);}
void onCheckFlick(P s,int f,P m){onCheck(s,f,m,h::checkFlick);}
}
@implementation PMHookBackend
+ (NSDictionary *)install {
 if(ready)return [self status];
 ++installAttempts;
 if(installAttempts<=3||installAttempts%10==0)diagf("PMHookBackend.install attempt=%u",installAttempts);
 try{
  auto candidate=std::make_unique<Runtime>();candidate->open();candidate->mainGame();auto &r=*candidate;
  const section_64 *code=nullptr,*data=nullptr;auto cursor=reinterpret_cast<const uint8_t*>(r.imageHeader+1);auto end=cursor+r.imageHeader->sizeofcmds;
  for(uint32_t i=0;i<r.imageHeader->ncmds;++i){if(cursor+8>end)throw std::runtime_error("Invalid hook load commands");auto cmd=reinterpret_cast<const load_command*>(cursor);
   if(cmd->cmdsize<8||cmd->cmdsize>size_t(end-cursor))throw std::runtime_error("Invalid hook command size");
   if(cmd->cmd==LC_SEGMENT_64){auto seg=reinterpret_cast<const segment_command_64*>(cmd);if(cmd->cmdsize<sizeof(*seg)||seg->nsects>(cmd->cmdsize-sizeof(*seg))/sizeof(section_64))throw std::runtime_error("Invalid hook section count");auto secs=reinterpret_cast<const section_64*>(seg+1);
    for(uint32_t k=0;k<seg->nsects;++k){auto sec=secs+k;bool c=!strncmp(seg->segname,"__TEXT",16)&&!strncmp(sec->sectname,"__pmghook",16);bool d=!strncmp(seg->segname,"__DATA",16)&&!strncmp(sec->sectname,"__pmgame",16);
     if(c||d){if((c&&seg->initprot!=5)||(d&&seg->initprot!=3))throw std::runtime_error("Expected RX hook/RW state");if(sec->addr<seg->vmaddr||sec->size>seg->vmsize||sec->addr-seg->vmaddr>seg->vmsize-sec->size)throw std::runtime_error("Hook section outside segment");if(c)code=sec;else data=sec;}
    }}cursor+=cmd->cmdsize;
  }
  if(!code||!data||code->size!=32+(sizeof(h::Entry)+48)*h::Count||data->size!=sizeof(h::Slot)*h::Count)throw std::runtime_error("Gameplay hooks absent: compile and repackage with NEW tools");
  auto base=reinterpret_cast<const uint8_t*>(r.imageHeader);auto desc=base+code->addr;uint32_t ver,count;uint64_t state;
  memcpy(&ver,desc+16,4);memcpy(&count,desc+20,4);memcpy(&state,desc+24,8);
  if(memcmp(desc,PMGameplayProtocol,16)||ver!=h::version||count!=h::Count||state!=data->addr)throw std::runtime_error("Gameplay protocol mismatch");
  auto entries=reinterpret_cast<const h::Entry*>(desc+32);
  for(uint32_t i=0;i<h::Count;++i){
   auto e=entries[i];uint64_t gate=code->addr+32+sizeof(h::Entry)*h::Count+48*i;
   if(e.site!=h::expected[i].site||e.original!=h::expected[i].original||e.gateway!=gate+40||gate+48>code->addr+code->size)throw std::runtime_error("Gateway manifest mismatch");
   uint32_t siteWord,first,back;memcpy(&siteWord,base+e.site,4);memcpy(&first,base+e.gateway,4);memcpy(&back,base+e.gateway+4,4);
   auto branch=[](uint64_t a,uint64_t b){return 0x14000000u|(uint32_t((int64_t(b)-int64_t(a))/4)&0x03ffffffu);};
   if(siteWord!=branch(e.site,gate)||first!=e.original||back!=branch(e.gateway+4,e.site+4))throw std::runtime_error("Gateway instructions mismatch");
   uint64_t pc=gate,slot=state+i*8;int64_t delta=(int64_t(slot&~4095ULL)-int64_t((pc+4)&~4095ULL))/4096;
   uint32_t adrp=0x90000010u|((uint32_t(delta)&3)<<29)|(((uint32_t(delta)>>2)&0x7ffff)<<5);
   uint32_t words[12]={0xa9bf47f0,adrp,uint32_t(0x91000210u|((slot&4095)<<10)),0xf9400210,0xb40000b0,0xaa1003f1,0xf94003f0,0x910043ff,0xd61f0220,0xa8c147f0,e.original,branch(pc+44,e.site+4)};
   if(memcmp(base+gate,words,sizeof(words)))throw std::runtime_error("Entry gate instruction mismatch");
   gateways[i]=const_cast<uint8_t*>(base)+e.gateway;
  }
  // Scalar fields are size/type checked before publishing any callback.
  r.field(r.klass("JudgeControl"),"progressControl","ProgressControl",false);
  r.field(r.klass("JudgeControl"),"stopJudge","System.Boolean",false);
  r.field(r.klass("ProgressControl"),"_isFirstTimeLaunch","System.Boolean",false);
  r.field(r.klass("ProgressControl"),"_isFirstTimeLaunchInGuide","System.Boolean",false);
  r.field(r.klass("ProgressControl"),"isPlaying","System.Boolean",false);
  r.field(r.klass("ProgressControl"),"_playPrepared","System.Boolean",false);
  r.field(r.klass("ProgressControl"),"_volumeSet","System.Boolean",false);
  r.field(r.klass("ProgressControl"),"nowTime","System.Single",false);
  r.field(r.klass("ProgressControl"),"_audioLength","System.Single",false);
  r.field(r.klass("ProgressControl"),"_offset","System.Single",false);
  r.field(r.klass("ProgressControl"),"_startTime","System.Single",false);
  r.field(r.klass("ProgressControl"),"_overTime","System.Single",false);
  r.field(r.klass("ProgressControl"),"leave","System.Boolean",false);
  r.field(r.klass("ProgressControl"),"levelBreak","System.Boolean",false);
  r.field(r.klass("ProgressControl"),"_inChallengeMode","System.Boolean",false);
  r.field(r.klass("ProgressControl"),"_nowFrameIndex","System.Int32",false);
  r.field(r.klass("ProgressControl"),"_timeSum","System.Single",false);
  r.field(r.klass("ProgressControl"),"audioTime","System.Single",false);
  r.field(r.klass("ProgressControl"),"lowPassFilterLerpDuration","System.Single",false);
  r.field(r.klass("ProgressControl"),"lowPassCutoffFrequency","System.Single",false);
  r.field(r.klass("ProgressControl"),"difficultyIndex","System.Int32",false);
  r.field(r.klass("ProgressControl"),"_leaveTime","System.Single",false);
  r.field(r.klass("ScoreControl"),"_score","System.Single",false);
  r.field(r.klass("ScoreControl"),"_percent","System.Single",false);
  r.field(r.klass("ScoreControl"),"scoreOfNote","System.Single",false);
  r.field(r.klass("ScoreControl"),"_combo","System.Int32",false);
  r.field(r.klass("ScoreControl"),"isAllPerfect","System.Boolean",false);
  r.field(r.klass("ScoreControl"),"isFullCombo","System.Boolean",false);
  r.field(r.klass("ScoreControl"),"maxcombo","System.Int32",false);
  r.field(r.klass("ScoreControl"),"perfect","System.Int32",false);
  r.field(r.klass("ScoreControl"),"good","System.Int32",false);
  r.field(r.klass("ScoreControl"),"bad","System.Int32",false);
  r.field(r.klass("ScoreControl"),"miss","System.Int32",false);
  r.field(r.klass("ScoreControl"),"early","System.Int32",false);
  r.field(r.klass("ScoreControl"),"late","System.Int32",false);
  r.field(r.klass("ScoreControl"),"noteScale","System.Single",false);
  r.field(r.klass("ScoreControl"),"scoreFrozen","System.Boolean",false);
  r.field(r.klass("ScoreControl"),"comboBlocked","System.Boolean",false);
  r.field(r.klass("ClickControl"),"isVisible","System.Boolean",false);
  r.field(r.klass("ClickControl"),"isJudged","System.Boolean",false);
  r.field(r.klass("DragControl"),"isVisible","System.Boolean",false);
  r.field(r.klass("DragControl"),"isJudged","System.Boolean",false);
  r.field(r.klass("HoldControl"),"isVisible","System.Boolean",false);
  r.field(r.klass("HoldControl"),"scale","System.Single",false);
  r.field(r.klass("HoldControl"),"timeOfJudge","System.Single",false);
  r.field(r.klass("HoldControl"),"isJudged","System.Boolean",false);
  r.field(r.klass("HoldControl"),"missed","System.Boolean",false);
  r.field(r.klass("HoldControl"),"judged","System.Boolean",false);
  r.field(r.klass("HoldControl"),"judgeOver","System.Boolean",false);
  r.field(r.klass("HoldControl"),"isPerfect","System.Boolean",false);
  r.field(r.klass("HoldControl"),"_holdHeadIsDestroyed","System.Boolean",false);
  r.field(r.klass("HoldControl"),"_safeFrame","System.Int32",false);
  r.field(r.klass("HoldControl"),"_judgeTime","System.Single",false);
  r.field(r.klass("FlickControl"),"isVisible","System.Boolean",false);
  r.field(r.klass("FlickControl"),"isJudged","System.Boolean",false);
  r.field(r.klass("ChartNote"),"type","System.Int32",false);
  r.field(r.klass("ChartNote"),"time","System.Int32",false);
  r.field(r.klass("ChartNote"),"positionX","System.Single",false);
  r.field(r.klass("ChartNote"),"holdTime","System.Single",false);
  r.field(r.klass("ChartNote"),"speed","System.Single",false);
  r.field(r.klass("ChartNote"),"floorPosition","System.Single",false);
  r.field(r.klass("ChartNote"),"isJudged","System.Boolean",false);
  r.field(r.klass("ChartNote"),"isJudgedForFlick","System.Boolean",false);
  r.field(r.klass("ChartNote"),"realTime","System.Single",false);
  r.field(r.klass("ChartNote"),"judgeLineIndex","System.Int32",false);
  r.field(r.klass("ChartNote"),"noteIndex","System.Int32",false);
  r.field(r.klass("ChartNote"),"noteCode","System.Single",false);
  r.field(r.klass("LevelInformation"),"offset","System.Single",false);
  r.field(r.klass("LevelInformation"),"noteScale","System.Single",false);
  r.field(r.klass("LevelInformation"),"scale","System.Single",false);
  r.field(r.klass("LevelInformation"),"numOfNotes","System.Int32",false);
  r.field(r.klass("LevelInformation"),"stopBeforeBegan","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"ApFcIsOn","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"chartLoaded","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"levelBegan","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"levelOver","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"canLevelOver","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"canPause","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"hitFxIsOn","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"musicVol","System.Single",false);
  r.field(r.klass("LevelInformation"),"judgeLineColorSetOver","System.Boolean",false);
  r.field(r.klass("JudgeLineControl"),"index","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"theta","System.Single",false);
  r.field(r.klass("JudgeLineControl"),"isShowingPic","System.Boolean",false);
  r.field(r.klass("JudgeLineControl"),"numOfFingers","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"nowSpeedIndex","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"nowDisappearIndex","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"nowMoveIndex","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"nowRotateIndex","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"nowProductIndexAbove","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"nowProductIndexBelow","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"lastProductIndexAbove","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"lastProductIndexBelow","System.Int32",false);
  r.field(r.klass("JudgeLineControl"),"nowTime","System.Single",false);
  r.field(r.klass("JudgeLineControl"),"noteScale","System.Single",false);
  r.field(r.klass("JudgeLineControl"),"chordSupport","System.Boolean",false);
  r.field(r.klass("JudgeLineControl"),"moveScale","System.Single",false);
  // Resolve critical result contracts BEFORE publishing any callback pointer.
  P ctx=r.nested(r.klass("LevelOverControl"),"<>c__DisplayClass43_0");
  for(auto name:{"<Start>g__SetResultAudio|1","<Start>g__SetResultInfo|2","<Start>g__SetScreenRatio|23","<Start>g__EnableResultCanvas|21","<Start>g__PlayResultBGM|22"})r.resolve(ctx,name);
  r.resolve(ctx,"<Start>g__SetRatingWithScore|3",{"System.Int32","System.Boolean"});
  P resultIterator=r.nested(r.klass("LevelOverControl"),"<Start>d__43");
  r.field(resultIterator,"<>1__state","System.Int32",false);
  r.field(resultIterator,"<>2__current","System.Object",false);
  r.field(resultIterator,"<>4__this","LevelOverControl",false);
  r.resolve(r.klass("AddressableAudioSource"),"set_Volume",{"System.Single"});
  pmhp::validate(r);pmmodes::validate(r);
  rt=std::move(candidate);
  P callbacks[h::Count]={reinterpret_cast<P>(onAwake),reinterpret_cast<P>(onDestroy),reinterpret_cast<P>(onProgressStart),reinterpret_cast<P>(onProgressUpdate),reinterpret_cast<P>(onMiss),reinterpret_cast<P>(onBad),reinterpret_cast<P>(onGood),reinterpret_cast<P>(onPerfect),reinterpret_cast<P>(onScoreUpdate),reinterpret_cast<P>(onResultInfo),reinterpret_cast<P>(onClick),reinterpret_cast<P>(onDrag),reinterpret_cast<P>(onHold),reinterpret_cast<P>(onFlick),reinterpret_cast<P>(onRecord),reinterpret_cast<P>(onSetRecord),reinterpret_cast<P>(onRanking),reinterpret_cast<P>(onResultStart),reinterpret_cast<P>(onResultMove),reinterpret_cast<P>(onSelector),reinterpret_cast<P>(onSelectorOff),reinterpret_cast<P>(onSetting),reinterpret_cast<P>(onSettingTab),reinterpret_cast<P>(onSettingBack),reinterpret_cast<P>(onPress),reinterpret_cast<P>(onCheckNote),reinterpret_cast<P>(onCheckFlick),reinterpret_cast<P>(onDelete),reinterpret_cast<P>(saveBool<h::SaveBool>),reinterpret_cast<P>(saveInt<h::SaveInt>),reinterpret_cast<P>(saveFloat<h::SaveFloat>),reinterpret_cast<P>(onSaveDate),reinterpret_cast<P>(saveString<h::SaveString>),reinterpret_cast<P>(saveBool<h::LegacySaveBool>),reinterpret_cast<P>(saveInt<h::LegacySaveInt>),reinterpret_cast<P>(saveFloat<h::LegacySaveFloat>),reinterpret_cast<P>(saveString<h::LegacySaveString>),reinterpret_cast<P>(onPointerClick),reinterpret_cast<P>(onSubmit),reinterpret_cast<P>(onLifeStart),reinterpret_cast<P>(onLifeNormalized),reinterpret_cast<P>(onLifeModStart),reinterpret_cast<P>(onHPBackgroundStart),reinterpret_cast<P>(onProgressLevelOver),reinterpret_cast<P>(onLifeUpdate),reinterpret_cast<P>(onLevelCodes),reinterpret_cast<P>(onLevelInformation),reinterpret_cast<P>(onNoteManager),reinterpret_cast<P>(onBlocking),reinterpret_cast<P>(onBlockLate),reinterpret_cast<P>(onHoldMove),reinterpret_cast<P>(onNoteMove<h::clickMove>),reinterpret_cast<P>(onNoteMove<h::dragMove>),reinterpret_cast<P>(onNoteMove<h::flickMove>),reinterpret_cast<P>(onJudgeUpdate)};
  auto slots=reinterpret_cast<h::Slot*>(const_cast<uint8_t*>(base)+state);
  for(uint32_t i=0;i<h::Count;++i)__atomic_store_n(&slots[i].callback,reinterpret_cast<uint64_t>(callbacks[i]),__ATOMIC_RELEASE);
  ready=true;lastError="55 offline entry hooks v2 installed; verify on device";diagf("PMHookBackend.install success hooks=%u judgeUpdate=1",h::Count);return [self status];
 }catch(const std::exception&e){lastError=e.what();if(installAttempts<=3||installAttempts%10==0)diagf("PMHookBackend.install failed: %s",e.what());return [self status];}
}
+ (BOOL)protectJudgeChange {
 if(!ready||broken)return NO;
 guard.store(true); // Also covers toggles between LevelControl.Awake/Start.
 return YES;
}
+ (NSDictionary *)status {
 return @{ @"ok":@(ready&&!broken),@"ready":@(ready),@"failedClosed":@(broken),@"saveGuard":@(guard.load()),@"hookCount":@(ready?h::Count:0),@"judgeUpdateHook":@(judgeUpdateSeen),@"autoplay":@(applying()&&attempt->options().autoplay),@"hp":@(attempt?attempt->hp():0),@"noiseReady":@(ready&&!broken),@"unifiedReady":@(ready&&!broken),@"diagnosticPath":PMDiagnosticsPath(),@"diagnosticTail":PMDiagnosticsTail(80),@"message":[NSString stringWithUTF8String:lastError.c_str()] ?: @"Backend error" };
}
@end
