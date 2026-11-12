#import "PMHookBackend.h"
#import "PMSettings.h"
#import "PMRuntime.h"
#import "PMDiagnostics.h"
#include "PMIL2CPP.hpp"
#include "PMOptions.hpp"
#include "PMSceneUI.hpp"
#include "PMHPLife.hpp"
#include "PMChartModes.hpp"
#include "PMPractice.hpp"
#include "PMPracticePreview.hpp"
#include "PMContentRuntime.hpp"
#include "PMRuntimeFeatures.hpp"
#include "PMUnlockRuntime.hpp"
#include "../Core/PMFlowCore.hpp"
#include "../Core/PMHoldTail.hpp"
#include "../Core/PMHookProtocol.hpp"
#include "../Core/PMHookManifest.hpp"
#include <atomic>
#include <memory>
#include <set>
#include <sstream>
#include <cstdio>
#include <cstdarg>
#include <chrono>
#include <cmath>
namespace {
using pmbridge::P;
using pmbridge::Runtime;
namespace h=phimod::hooks;
__attribute__((used)) static const char PMGameplayProtocol[16]="PMGameplay-v2";
__attribute__((used)) static const char PMGameplayBuild[]="PMGameplay-contract-v2-72-ios403";
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
uint64_t progressUpdateCalls=0,judgeUpdateCalls=0,levelCodesCalls=0,levelInfoCalls=0;
std::chrono::steady_clock::time_point lastProgressHeartbeat{},lastJudgeHeartbeat{};
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
// Capture the synchronous controller responsible for a native Miss; no rule changes.
P diagnosticJudgeControl=nullptr;unsigned missDiagnosticCount=0;
struct DiagnosticJudgeScope{P previous;explicit DiagnosticJudgeScope(P control):previous(diagnosticJudgeControl){diagnosticJudgeControl=control;}~DiagnosticJudgeScope(){diagnosticJudgeControl=previous;}};
void diagnoseNativeMiss(float code){
 if(missDiagnosticCount++>=32)return;
 try{auto&r=R();P control=diagnosticJudgeControl;
  if(!control){diagf("Native Miss code=%.3f source=outside-note-Judge",code);return;}
  P note=r.get<P>(control,"noteInfor"),progress=r.get<P>(control,"progressControl"),line=r.get<P>(control,"judgeLine");
  int type=r.get<int>(note,"type"),count=r.get<int>(line,"numOfFingers");float now=r.get<float>(progress,"nowTime"),start=r.get<float>(note,"realTime"),duration=r.get<float>(note,"holdTime"),x=r.get<float>(note,"positionX");
  float nearest=99999;P fingers=r.get<P>(line,"fingerPositionX");for(int i=0;fingers&&i<count&&uintptr_t(i)<r.array_length(fingers);++i){float position=r.unbox<float>(r.arrayAt(fingers,i));if(std::isfinite(position))nearest=std::min(nearest,std::fabs(position-x));}
  diagf("Native Miss code=%.3f type=%d line=%d time=%.6f now=%.6f deltaMs=%.2f duration=%.6f fingers=%d nearestX=%.5f lineAngle=%.3f",code,type,r.get<int>(note,"judgeLineIndex"),start,now,(now-start)*1000,duration,count,nearest,r.get<float>(line,"theta"));
  if(type==3)diagf("Hold Miss detail headJudged=%d missed=%d over=%d safeFrame=%d headOffsetMs=%.2f tailLeftMs=%.2f autoplay=%d noise=%d rate=%.3f",r.get<bool>(control,"judged"),r.get<bool>(control,"missed"),r.get<bool>(control,"judgeOver"),r.get<int>(control,"_safeFrame"),r.get<float>(control,"_judgeTime")*1000,(start+duration-now)*1000,attempt?attempt->options().autoplay:0,attempt?attempt->options().noise:0,attempt?attempt->options().playbackRate:1);
 }catch(const std::exception&e){diagf("Miss diagnostics failed: %s",e.what());}
}
uint32_t realtimeAccuracyRoot=0;P realtimeAccuracyOwner=nullptr,realtimeAccuracyText=nullptr;std::string realtimeAccuracyLast;
void clearRealtimeAccuracy(Runtime&r){if(realtimeAccuracyRoot){P go=r.gchandle_get_target(realtimeAccuracyRoot);if(r.alive(go))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});r.gchandle_free(realtimeAccuracyRoot);}realtimeAccuracyRoot=0;realtimeAccuracyOwner=realtimeAccuracyText=nullptr;realtimeAccuracyLast.clear();diagf("Live ACC display cleared");}
void updateRealtimeAccuracy(Runtime&r,P score,bool enabled){
 if(!enabled){if(realtimeAccuracyRoot)clearRealtimeAccuracy(r);return;}
 P official=r.get<P>(score,"score");if(!r.alive(official))return;
 if(realtimeAccuracyOwner!=score&&realtimeAccuracyRoot)clearRealtimeAccuracy(r);
 if(!realtimeAccuracyRoot){P sourceTransform=r.call(official,"get_transform"),parent=r.call(sourceTransform,"get_parent"),sourceGo=r.call(official,"get_gameObject");bool world=false;P clone=r.stat(r.type("UnityEngine","Object"),"Instantiate",{"UnityEngine.Object","UnityEngine.Transform","System.Boolean"},{sourceGo,parent,&world});if(!clone)throw std::runtime_error("Could not clone score label for live ACC");uint32_t root=r.gchandle_new(clone,false);try{
  r.call(clone,"set_name",{"System.String"},{r.string_new("PhiMod_LiveAccuracy")});P label=r.component(clone,r.type("UnityEngine.UI","Text"));if(!r.alive(label))throw std::runtime_error("Cloned score label has no Text component");
  P sourceRect=r.call(official,"get_rectTransform"),rect=r.call(label,"get_rectTransform");V2 middle{.5f,.5f};for(const char*name:{"set_anchorMin","set_anchorMax","set_pivot"})r.call(rect,name,{"UnityEngine.Vector2"},{&middle});
  V2 oldSize=r.unbox<V2>(r.call(sourceRect,"get_sizeDelta")),position=r.unbox<V2>(r.call(sourceRect,"get_anchoredPosition"));int oldFont=r.unbox<int>(r.call(official,"get_fontSize")),font=std::max(10,(int)std::lround(oldFont*.42));V2 size{oldSize.x,std::max(14.f,font*1.6f)};position.y-=oldSize.y*.72f+size.y*.48f;
  r.call(rect,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});r.call(rect,"set_anchoredPosition",{"UnityEngine.Vector2"},{&position});bool no=false;int align=4;
  r.call(label,"set_fontSize",{"System.Int32"},{&font});r.call(label,"set_resizeTextForBestFit",{"System.Boolean"},{&no});r.call(label,"set_raycastTarget",{"System.Boolean"},{&no});r.call(label,"set_alignment",{"UnityEngine.TextAnchor"},{&align});
  Color tint=r.unbox<Color>(r.call(official,"get_color"));r.call(label,"set_color",{"UnityEngine.Color"},{&tint});realtimeAccuracyText=label;realtimeAccuracyOwner=score;realtimeAccuracyRoot=root;diagf("Live ACC display attached to native score HUD");
 }catch(...){r.gchandle_free(root);throw;}}
 int p=r.get<int>(score,"perfect"),g=r.get<int>(score,"good"),b=r.get<int>(score,"bad"),m=r.get<int>(score,"miss"),judged=p+g+b+m;double accuracy=judged>0?100.0*(p+.65*g)/judged:100.0;char text[32];snprintf(text,sizeof(text),"%.2f%%",accuracy);bool visible=r.unbox<bool>(r.call(official,"get_isActiveAndEnabled"));r.call(realtimeAccuracyText,"set_enabled",{"System.Boolean"},{&visible});if(realtimeAccuracyLast!=text){r.text(realtimeAccuracyText,text);realtimeAccuracyLast=text;}
}
struct PlaybackJudgeScope{Runtime&r;explicit PlaybackJudgeScope(Runtime&value):r(value){pmpractice::judgeRateEnter(r);}~PlaybackJudgeScope(){pmpractice::judgeRateLeave();}};
void resetChartRegistration(){registered.clear();missDiagnosticCount=0;}
void restartPracticeSession(){
 if(attempt&&attempt->phase()==phimod::Phase::Playing){attempt->restartSegment();resetChartRegistration();try{pmmodes::restartSegment(R());if(attempt->options().hpEnabled)pmhp::beginAttempt(attempt->hp());diagf("Practice segment session reset hp=%.2f",attempt->hp());}catch(const std::exception&e){diagf("Practice session reset failed: %s",e.what());}}
}
bool heartbeatDue(std::chrono::steady_clock::time_point &last,uint64_t count){
 auto now=std::chrono::steady_clock::now();
 if(count==1||last.time_since_epoch().count()==0||now-last>=std::chrono::milliseconds(750)){last=now;return true;}
 return false;
}
void logProgressSnapshot(Runtime&r,P p,const char*source,uint64_t count){
 P info=r.get<P>(p,"levelInformation"),audio=r.get<P>(p,"audioSource"),judge=r.get<P>(p,"judgeControl");
 bool chartLoaded=info&&r.get<bool>(info,"chartLoaded"),levelBegan=info&&r.get<bool>(info,"levelBegan");
 P judgeLines=info?r.get<P>(info,"judgeLines"):nullptr,floors=info?r.get<P>(info,"floorPositions"):nullptr;
 int judgeLineCount=judgeLines?r.count(judgeLines):0;uintptr_t floorCount=floors?r.array_length(floors):0;
 bool playing=r.get<bool>(p,"isPlaying"),prepared=r.get<bool>(p,"_playPrepared"),volumeSet=r.get<bool>(p,"_volumeSet");
 float now=r.get<float>(p,"nowTime"),audioTime=r.get<float>(p,"audioTime"),length=r.get<float>(p,"_audioLength");
 bool stopJudge=judge&&r.get<bool>(judge,"stopJudge");float judgeNow=judge?r.get<float>(judge,"nowTime"):-999;
 float wrapperTime=audio?r.get<float>(audio,"time"):-1,internalTime=audio?r.get<float>(audio,"internalTime"):-1;
 bool loadOver=audio&&r.get<bool>(audio,"loadOver"),audioPlayFlag=audio&&r.get<bool>(audio,"playFlag");
 float pitch=-1,audioClipTime=-1;P unityAudio=audio?r.get<P>(audio,"audioSource"):nullptr;
 if(r.alive(unityAudio)){pitch=r.unbox<float>(r.call(unityAudio,"get_pitch"));audioClipTime=r.unbox<float>(r.call(unityAudio,"get_time"));}
 diagf("heartbeat %s n=%llu now=%.3f audioTime=%.3f len=%.3f playing=%d prepared=%d volume=%d load=%d wrapper=%.3f internal=%.3f audioPlay=%d pitch=%.2f clipTime=%.3f chart=%d began=%d floors=%d/%lu levelOver=%d canOver=%d leave=%d break=%d judgeStop=%d judgeNow=%.3f frame=%d",
       source,(unsigned long long)count,now,audioTime,length,playing,prepared,volumeSet,loadOver,wrapperTime,internalTime,audioPlayFlag,pitch,audioClipTime,chartLoaded,levelBegan,judgeLineCount,(unsigned long)floorCount,info?r.get<bool>(info,"levelOver"):false,info?r.get<bool>(info,"canLevelOver"):false,r.get<bool>(p,"leave"),r.get<bool>(p,"levelBreak"),stopJudge,judgeNow,r.get<int>(p,"_nowFrameIndex"));
 if(pmhp::active())diagf("HP loader %s",pmhp::loadingStatus(r).c_str());
}
void fault(const std::exception &e){diagf("fault: %s",e.what());NSLog(@"[PhiMod] Gameplay failure: %s",e.what());lastError=e.what();broken=true;guard.store(true);if(attempt)attempt->failClosed();}
bool applying(){return ready&&!broken&&attempt&&attempt->shouldApplyGameplay();}
P progress(){return progressRoot?R().gchandle_get_target(progressRoot):nullptr;}
P score(){return scoreRoot?R().gchandle_get_target(scoreRoot):nullptr;}
void release(uint32_t &root){if(root){R().gchandle_free(root);root=0;}}
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
  if(options.hpEnabled)pmhp::beginAttempt(attempt->hp());
 if(options.requiresSaveProtection())guard.store(true);
 lastError="Gameplay hooks armed (device verification pending)";
 diagf("ProgressControl.Start armed baseline P=%.4f G=%.4f B=%.4f",baseline.perfect,baseline.good,baseline.bad);
}
void onAwake(P self,P mi){
 diagf("LevelControl.Awake enter");
 try{pmcontent::levelBegin(R());pmfeatures::levelBegin(R(),self);pmunlock::clear(R());}catch(const std::exception&e){diagf("Content/feature begin: %s",e.what());}
 progressUpdateCalls=judgeUpdateCalls=0;lastProgressHeartbeat=lastJudgeHeartbeat={};diagHaveState=false;
 // A latch survives OnDestroy, disabled switches and the entire result screen.
 // Alternate assisted result never launches the reward/save coroutine.
 if(!broken){
  try{guard.store(PMReadOptions([[PMSettings shared] snapshot]).requiresSaveProtection());}catch(const std::exception &e){fault(e);}
 }
  try{release(progressRoot);release(scoreRoot);attempt.reset();resetChartRegistration();judgeUpdateSeen=false;pmscene::settingsLeave(R());pmscene::clearRecovery(R());pmhp::clear(R());pmmodes::clear(R());pmpractice::clear(R());}catch(const std::exception&e){fault(e);}
   inResult=false;resultPresented=false;levelOverStarted=false;loadingMaskCleared=false;
 try{frozenOptions=PMReadOptions([[PMSettings shared] snapshot]);diagf("LevelControl.Awake options assisted=%d hp=%d hpMax=%.1f hpD=[%.1f,%.1f,%.1f,%.1f]",frozenOptions.assisted(),frozenOptions.hpEnabled,frozenOptions.hpMax,frozenOptions.hpDelta[0],frozenOptions.hpDelta[1],frozenOptions.hpDelta[2],frozenOptions.hpDelta[3]);if(!broken){pmhp::prepare(R(),self,frozenOptions);diagf("HP prepare ok active=%d normalized=%.3f",pmhp::active(),pmhp::normalized());pmmodes::prepare(R(),self,frozenOptions);pmpractice::prepare(R(),frozenOptions);diagf("Chart modes and practice prepare ok");}}catch(const std::exception&e){diagf("LevelControl.Awake prepare failed: %s",e.what());fault(e);}
 diagf("LevelControl.Awake calling original hpActive=%d",pmhp::active());
 orig<VoidFn>(h::levelAwake)(self,mi);
 diagf("LevelControl.Awake returned");
}
void onDestroy(P self,P mi){
 diagf("LevelControl.OnDestroy enter");
 try{clearRealtimeAccuracy(R());}catch(const std::exception&e){diagf("Live ACC cleanup: %s",e.what());}
  if(attempt){attempt->result();if(attempt->excluded())guard.store(true);}
  resultPresented=false;levelOverStarted=false;loadingMaskCleared=false;judgeUpdateSeen=false;
  try{pmhp::clear(R());pmmodes::clear(R());pmpractice::clear(R());}catch(const std::exception&e){fault(e);}
  resetChartRegistration();
  try{pmfeatures::levelEnd(R());pmunlock::clear(R());pmcontent::levelEnd(R());}catch(const std::exception&e){diagf("Content/feature cleanup: %s",e.what());}
  orig<VoidFn>(h::levelDestroy)(self,mi);
  diagf("LevelControl.OnDestroy returned");
}
void onProgressStart(P self,P mi){
 diagf("ProgressControl.Start enter");
 try{pmpractice::begin(R(),self);diagf("Practice clock/pitch armed before ProgressControl.Start");}catch(const std::exception&e){diagf("Practice pre-start setup failed; original audio path retained: %s",e.what());try{pmpractice::clear(R());}catch(...){}}
 orig<VoidFn>(h::progressStart)(self,mi);
 diagf("ProgressControl.Start original returned");
 try{begin(self);}catch(const std::exception&e){fault(e);}
}
 void ensureFloorArray(Runtime&r,P info){
 if(!info)return;
 P lines=r.get<P>(info,"judgeLines"),floors=r.get<P>(info,"floorPositions");
 int count=lines?r.count(lines):0;
 if(count<0||count>2048)throw std::runtime_error("Judge line count outside floor buffer limit");
 uintptr_t oldCount=floors?r.array_length(floors):0;
 if(count==0||oldCount>=static_cast<uintptr_t>(count))return;
 P replacement=r.array_new(r.type("System","Single"),static_cast<uintptr_t>(count));
 if(!replacement)throw std::runtime_error("Could not allocate LevelInformation.floorPositions");
 uint32_t root=r.gchandle_new(replacement,false);
 try{for(uintptr_t i=0;i<oldCount;++i)r.arrayPutFloat(replacement,static_cast<int>(i),r.unbox<float>(r.arrayAt(floors,static_cast<int>(i))));r.put(info,"floorPositions",replacement);}
 catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);
 diagf("LevelInformation.floorPositions expanded %lu->%d",(unsigned long)oldCount,count);
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
 float before=attempt->hp();if(attempt->options().hpEnabled&&rating!=phimod::Rating::Perfect)diagf("HP judgement enter code=%.3f rating=%d hp=%.2f",code,(int)rating,before);bool accepted=attempt->observe(code,offset,rating);
 if(accepted&&attempt->options().hpEnabled&&before!=attempt->hp()){diagf("HP state changed code=%.3f hp=%.2f -> %.2f; visual update deferred",code,before,attempt->hp());}
}
void onPerfect(P self,float code,float offset,V3 pos,bool hold,P mi){
 if(applying()&&attempt->options().autoplay){
  try{auto &r=R();if(attempt->deferHold(code,offset,{pos.x,pos.y,pos.z},hold,r.get<float>(progress(),"nowTime")))return;
   if(!attempt->creditOnce(code))return;
  }catch(const std::exception&e){fault(e);return;}
 }
 observe(code,offset,phimod::Rating::Perfect);pmfeatures::observe(0);credit(self,code,offset,pos,hold,mi);
}
void onMiss(P self,float code,P mi){
 diagnoseNativeMiss(code);
 if(applying()&&attempt->options().autoplay){
  // Android only defers type-3 holds to their real tail. Ordinary Tap/Drag/
  // Flick misses are converted to an immediate Perfect and must not enter
  // the hold queue, otherwise the result coroutine sees unfinished notes.
  bool hold=attempt->noteType(code)==3;
  onPerfect(self,code,0,{0,0,0},hold,nullptr);return;
 }
 observe(code,0,phimod::Rating::Miss);pmfeatures::observe(3);if(pmhp::active())diagf("HP Miss original enter code=%.3f hp=%.2f",code,attempt?attempt->hp():-1);orig<void(*)(P,float,P)>(h::miss)(self,code,mi);if(pmhp::active())diagf("HP Miss original returned code=%.3f",code);
}
void onBad(P self,float code,float offset,P mi){observe(code,offset,phimod::Rating::Bad);pmfeatures::observe(2);orig<void(*)(P,float,float,P)>(h::bad)(self,code,offset,mi);}
void onGood(P self,float code,float offset,V3 pos,bool hold,P mi){observe(code,offset,phimod::Rating::Good);pmfeatures::observe(1);orig<PerfectFn>(h::good)(self,code,offset,pos,hold,mi);}
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
 bool timeDue=!std::isfinite(diagLastNow)||!std::isfinite(now)||std::fabs(now-diagLastNow)>=1.f;
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
   // Abort through the native exit path, never create a completed-chart result.
   diagf("HP failure ready; returning to SongSelector");
   guard.store(true);
   r.call(progressControl,"LevelBreak",{"System.String"},{r.string_new("SongSelector")});
   levelOverStarted=true;attempt->acknowledgeAction(action);
   r.put(info,"levelOver",true);r.put(info,"canPause",false);
   r.call(r.get<P>(progressControl,"audioSource"),"Stop");
   pmhp::finish(r);
   diagf("HP exit dispatched: SongSelector (no result)");
  }
  pmhp::frame(r,attempt->hp());
 }catch(const std::exception&e){lastError=std::string("Transition pending: ")+e.what();diagf("Transition pending: %s",e.what());NSLog(@"[PhiMod] %s",lastError.c_str());}
}
void onProgressUpdate(P self,P mi){
 uint64_t count=++progressUpdateCalls;bool heartbeat=heartbeatDue(lastProgressHeartbeat,count);
 if(heartbeat)diagf("ProgressControl.Update enter n=%llu",(unsigned long long)count);
 try{if(pmpractice::beforeProgress(R(),self)){if(pmpractice::consumeRestart())restartPracticeSession();if(heartbeat)logProgressSnapshot(R(),self,"ProgressControl.Update paused",count);return;}}
 catch(const std::exception&e){diagf("Practice pre-update failed: %s",e.what());}
 orig<VoidFn>(h::progressUpdate)(self,mi);
 if(heartbeat)diagf("ProgressControl.Update original returned n=%llu",(unsigned long long)count);
 try{pmhp::loadVisuals(R(),self);}catch(const std::exception&e){diagf("HP visual poll failed: %s",e.what());}
 if(heartbeat)try{logProgressSnapshot(R(),self,"ProgressControl.Update",count);}catch(const std::exception&e){diagf("ProgressControl.Update snapshot failed: %s",e.what());}
 try{pmpractice::afterProgress(R(),self);if(pmpractice::consumeRestart())restartPracticeSession();}
 catch(const std::exception&e){diagf("Practice post-update failed: %s",e.what());}
 try{diagnosticTick(R(),self,"ProgressControl.Update");}catch(const std::exception&e){diagf("ProgressControl.Update diagnostic failed: %s",e.what());}
}
void onJudgeUpdate(P self,P mi){
 judgeUpdateSeen=true;
 if(pmpractice::entryLoading(R(),R().get<P>(self,"progressControl"))){if(++judgeUpdateCalls==1)diagf("Practice entry: native judging held until range reset");return;}
 uint64_t count=++judgeUpdateCalls;bool heartbeat=heartbeatDue(lastJudgeHeartbeat,count);
 if(heartbeat)diagf("JudgeControl.Update enter n=%llu",(unsigned long long)count);
 if(pmpractice::paused()){if(heartbeat)diagf("JudgeControl.Update skipped practice-paused n=%llu",(unsigned long long)count);return;}
 try{auto&r=R();P pc=r.get<P>(self,"progressControl");ensureFloorArray(r,pc?r.get<P>(pc,"levelInformation"):nullptr);}catch(const std::exception&e){diagf("Judge floor buffer preparation failed: %s",e.what());}
 {
  auto &r=R();PlaybackJudgeScope rate(r);
  pmcontent::judgeWithHudPause(r,self,mi,orig<VoidFn>(h::judgeUpdate));
 }
 if(heartbeat)diagf("JudgeControl.Update original returned n=%llu",(unsigned long long)count);
 try{auto &r=R();P progressControl=r.get<P>(self,"progressControl");if(heartbeat)logProgressSnapshot(r,progressControl,"JudgeControl.Update",count);tickGameplay(r,progressControl,"JudgeControl.Update");}
 catch(const std::exception&e){lastError=std::string("JudgeControl.Update: ")+e.what();diagf("JudgeControl.Update failed: %s",e.what());}
 try{auto&r=R();pmfeatures::tick(r,r.get<P>(self,"progressControl"));}catch(const std::exception&e){static std::string previous;if(previous!=e.what()){previous=e.what();diagf("Visual feature tick failed: %s",e.what());}}
}
void onAddressableAudioUpdate(P self,P mi){
 try{if(pmpractice::ownsAudio(R(),self))pmpractice::audioBefore(R(),self);}catch(const std::exception&e){diagf("Practice audio pre-update failed: %s",e.what());}
 orig<VoidFn>(h::audioUpdate)(self,mi);
 try{if(pmpractice::ownsAudio(R(),self))pmpractice::audioAfter(R(),self);}catch(const std::exception&e){diagf("Practice audio post-update failed: %s",e.what());}
}
bool noteJudge(P self,P mi,h::Index index,bool hold){
 DiagnosticJudgeScope diagnosticScope(self);
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
  {PlaybackJudgeScope rate(r);called=true;result=orig<JudgeFn>(index)(self,mi);}
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
bool onHold(P s,P m){
 auto&r=R();P note=nullptr;float duration=0;bool adjusted=false,safeAdjusted=false;int oldSafe=0;
 PlaybackJudgeScope tailRate(r);
 try{
  note=r.get<P>(s,"noteInfor");
  if(pmcontent::shortSourceHold(r,note)){
   duration=r.get<float>(note,"holdTime");
   // Preserve native head quality, but allow the source Hold's final
   // Perfect window. Native Judge checks release BEFORE tail completion.
   registerOne(note);
   P progress=r.get<P>(s,"progressControl");float now=r.get<float>(progress,"nowTime");
   float perfect=r.staticValue<float>(r.klass("JudgeControl"),"PerfectTimeRange","System.Single");
   auto plan=phimod::shortHoldTail(r.get<float>(note,"realTime"),duration,now,perfect,r.get<bool>(s,"judged"),r.get<bool>(s,"missed"),r.get<bool>(s,"judgeOver"));
   r.put(note,"holdTime",plan.adjustedDuration);adjusted=true;
   if(plan.protectRelease){oldSafe=r.get<int>(s,"_safeFrame");if(oldSafe<1){r.put(s,"_safeFrame",1);safeAdjusted=true;}}

  }
 }catch(const std::exception&e){diagf("Short Hold scope setup: %s",e.what());}
 bool result=false;
 try{result=noteJudge(s,m,h::hold,true);}catch(...){if(adjusted)r.put(note,"holdTime",duration);if(safeAdjusted&&r.get<int>(s,"_safeFrame")<=1)r.put(s,"_safeFrame",oldSafe);throw;}
 if(adjusted)r.put(note,"holdTime",duration);
 if(safeAdjusted&&r.get<int>(s,"_safeFrame")<=1)r.put(s,"_safeFrame",oldSafe);
 return result;
}
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
  orig<VoidFn>(h::scoreUpdate)(self,mi);
  if(!applying()){if(realtimeAccuracyRoot)try{clearRealtimeAccuracy(R());}catch(...){}return;}
  try{auto &r=R();auto o=attempt->options();
   if(o.noComboScore){float accuracy=0;int total=0;if(readAccuracy(self,accuracy,total)){float value=accuracy*10000.f;r.put(self,"scoreOfNote",1000000.f/total);r.put(self,"_score",value);r.put(self,"_percent",value/1000000.f);char digits[32];snprintf(digits,sizeof(digits),"%07d",int(std::round(value)));r.text(r.get<P>(self,"score"),digits);r.text(r.get<P>(self,"comboText"),"NO COMBO");}}
   updateRealtimeAccuracy(r,self,o.accuracyDisplay);
   if(o.hpEnabled){pmhp::frame(r,attempt->hp());pmhp::scoreFrame(r,self);r.text(r.get<P>(self,"comboText"),"LIFE");r.text(r.get<P>(self,"combo"),std::to_string(int(std::ceil(attempt->hp()))).c_str());}
   else if(o.autoplay)r.text(r.get<P>(self,"comboText"),"AUTOPLAY");
  }catch(const std::exception&e){lastError=std::string("Score update: ")+e.what();NSLog(@"[PhiMod] %s",lastError.c_str());}
}
P onResultInfo(P self,P mi){
 P result=orig<P(*)(P,P)>(h::resultInfo)(self,mi);
 if(attempt&&attempt->options().noComboScore&&(applying()||inResult))try{float accuracy=0;int total=0;if(readAccuracy(self,accuracy,total)){float value=accuracy*10000.f;R().call(result,"set_Score",{"System.Single"},{&value});}}catch(const std::exception&e){lastError=std::string("No-combo result score: ")+e.what();}
 return result;
}
void onRecord(P self,P result,P mi){if(!guard.load())orig<void(*)(P,P,P)>(h::record)(self,result,mi);}
void onSetRecord(P self,P id,P level,P record,P mi){if(!guard.load())orig<void(*)(P,P,P,P,P)>(h::setRecord)(self,id,level,record,mi);}
void onRanking(P self,P mi){if(guard.load())return;try{pmcontent::ranking(R(),self,mi,orig<VoidFn>(h::ranking));}catch(const std::exception&e){diagf("Content ranking isolation: %s",e.what());}}
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
  try{pmunlock::resultStarted(R(),self);}catch(const std::exception&e){diagf("Unlock result owner: %s",e.what());}
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
  try{pmpractice::clear(R());}catch(const std::exception&e){diagf("Practice result cleanup failed: %s",e.what());}
  if(pmhp::active())try{pmhp::finish(R());}catch(const std::exception&e){lastError=std::string("HP result cleanup: ")+e.what();diagf("HP result cleanup failed: %s",e.what());}
  return orig<P(*)(P,P)>(h::progressLevelOver)(self,mi);
 }
void onLevelCodes(P self,P mi){
 uint64_t count=++levelCodesCalls;diagf("LevelControl.SetCodeForNote enter n=%llu",(unsigned long long)count);
 if(!broken)try{pmcontent::beforeChart(R(),self);pmmodes::beforeCodes(R(),self);}catch(const std::exception&e){fault(e);}
 orig<VoidFn>(h::levelCodes)(self,mi);
 diagf("LevelControl.SetCodeForNote returned n=%llu",(unsigned long long)count);
}
void onLevelInformation(P self,P mi){
 uint64_t count=++levelInfoCalls;diagf("LevelControl.SetInformation enter n=%llu",(unsigned long long)count);
 if(!broken)try{pmcontent::beforeInformation(R(),self);}catch(const std::exception&e){fault(e);}
 orig<VoidFn>(h::levelInfo)(self,mi);
 diagf("LevelControl.SetInformation original returned n=%llu",(unsigned long long)count);
 if(!broken)try{pmmodes::afterInformation(R(),self);pmcontent::afterChart(R(),self);pmfeatures::afterChart(R(),self);}catch(const std::exception&e){fault(e);}
 diagf("LevelControl.SetInformation finished n=%llu",(unsigned long long)count);
}
void onAssetCtor(P self,P key,P mi){try{if(pmcontent::assetConstructor(R(),self,key))return;}catch(const std::exception&e){diagf("Content ctor: %s",e.what());}orig<void(*)(P,P,P)>(h::assetCtor)(self,key,mi);}
void onAssetRelease(P self,P mi){try{if(pmcontent::assetRelease(R(),self))return;}catch(const std::exception&e){diagf("Content release: %s",e.what());return;}orig<VoidFn>(h::assetRelease)(self,mi);}
void onAssetReleaseResource(P self,P mi){try{if(pmcontent::assetRelease(R(),self,true))return;}catch(const std::exception&e){diagf("Content ReleaseResource: %s",e.what());return;}orig<VoidFn>(h::assetReleaseResource)(self,mi);}
void onChapterStart(P self,P mi){
 try{pmscene::settingsLeave(R());pmcontent::chapterPrepare(R(),self);}catch(const std::exception&e){diagf("Content chapter prepare failed: %s",e.what());}
 orig<VoidFn>(h::chapterStart)(self,mi);
 try{pmcontent::chapterReady(R(),self);pmunlock::chapterReady(R(),self);}catch(const std::exception&e){diagf("Content chapter layout failed: %s",e.what());}
}
P onSongInfo(P self,int slot,P mi){P value=orig<P(*)(P,int,P)>(h::songInfo)(self,slot,mi);try{pmcontent::levelInfo(R(),self,slot,value);pmunlock::songInfo(R(),self,slot,value);}catch(const std::exception&e){diagf("Content level info: %s",e.what());}return value;}
P onItemInfo(P self,int slot,P mi){P value=orig<P(*)(P,int,P)>(h::itemInfo)(self,slot,mi);try{pmcontent::levelInfo(R(),R().get<P>(self,"songInfo"),slot,value);pmunlock::itemInfo(R(),self,slot,value);}catch(const std::exception&e){diagf("Content item info: %s",e.what());}return value;}
void onCreateNote(P self,int index,bool above,P mi){
 if(!pmpractice::allowNoteCreation())return;
 if(!pmpracticepreview::creating()){
  auto&r=R();P notes=r.get<P>(self,above?"notesAbove":"notesBelow");
  if(index>=0&&index<r.count(notes)&&pmpracticepreview::settled(r.at(notes,index)))return;
 }
 if(pmcontent::hasNoteController(R(),self,index,above))return;
 orig<void(*)(P,int,bool,P)>(h::lineCreateNote)(self,index,above,mi);
}
void onNoteManager(P self,P mi){
 if(pmpractice::entryLoading(R(),self))return;
 if(pmpractice::paused()){try{auto&r=R();ensureFloorArray(r,r.get<P>(self,"levelInformation"));pmpractice::previewFrame(r,self);pmcontent::visuals(r,r.get<P>(self,"progressControl"));}catch(const std::exception&e){diagf("Practice preview failed: %s",e.what());}return;}
 if(applying())try{pmmodes::beginFrame(R(),self);}catch(const std::exception&e){fault(e);}
 orig<VoidFn>(h::noteManager)(self,mi);
   if(applying())try{pmmodes::frame(R(),self);}catch(const std::exception&e){fault(e);}
 // Native NoteUpdateManager.Update calls JudgeLineControl.UpdateInfo for all
 // lines. Apply custom visibility afterwards, never from a competing Update.
 try{pmcontent::recoverSourceNotes(R(),self);}catch(const std::exception&e){static std::string previous;if(previous!=e.what()){previous=e.what();diagf("Source note recovery failed: %s",e.what());}}
 try{auto&r=R();pmcontent::visuals(r,r.get<P>(self,"progressControl"));}catch(const std::exception&e){static std::string previous;if(previous!=e.what()){previous=e.what();diagf("Post-note-manager visuals failed: %s",e.what());}}
}
P onSkinInstantiate(P original,P mi){P clone=orig<P(*)(P,P)>(h::skinInstantiate)(original,mi);if(ready&&!broken&&[NSThread isMainThread])try{pmfeatures::skinEffectCreated(R(),original,clone,diagnosticJudgeControl);}catch(const std::exception&e){diagf("Skin hit effect: %s",e.what());}return clone;}
template<h::Index I>void onSkinSound(P self,int index,P mi){if(ready&&!broken&&[NSThread isMainThread])try{if(pmfeatures::playSkinSound(R(),self,index))return;}catch(const std::exception&e){diagf("Skin hitsound: %s",e.what());}orig<void(*)(P,int,P)>(I)(self,index,mi);}
bool onBlocking(P self,V2 point,P*out,P mi){
 if(applying())try{bool handled=false;bool value=pmmodes::blocking(R(),{point.x,point.y},out,handled);if(handled)return value;}catch(const std::exception&e){fault(e);}
 return orig<bool(*)(P,V2,P*,P)>(h::blocking)(self,point,out,mi);
}
void onBlockLate(P self,P mi){orig<VoidFn>(h::blockLate)(self,mi);if(applying())try{pmmodes::late(R(),self);}catch(const std::exception&e){fault(e);}}
void onHoldMove(P self,P mi){
 DiagnosticJudgeScope effectScope(self);
 // Native NoteMove reads missed/timeOfJudge to fade and emit Hold effects.
 // Set them BEFORE the original, as in Android; sample the hole afterwards.
 if(applying())try{pmmodes::holdMove(R(),self);}catch(const std::exception&e){fault(e);}
 pmfeatures::beforeNoteMove(R(),self,true);
 try{pmcontent::prepareHoldHitFX(R(),self);}catch(const std::exception&e){diagf("Hold hit FX sorting failed: %s",e.what());}
 orig<VoidFn>(h::holdMove)(self,mi);
 try{pmcontent::noteMoved(R(),self,true);}catch(const std::exception&e){diagf("Hold visual failed: %s",e.what());}
 pmfeatures::noteMoved(R(),self,true);
 if(applying())try{pmmodes::moved(R(),self,true);}catch(const std::exception&e){fault(e);}
}
template<h::Index i>void onNoteMove(P self,P mi){pmfeatures::beforeNoteMove(R(),self,false);orig<VoidFn>(i)(self,mi);pmfeatures::noteMoved(R(),self,false);try{pmcontent::noteMoved(R(),self,false);pmcontent::finishNoteGeometry(R(),self,false);}catch(const std::exception&e){diagf("RPE note visual/skin failed: %s",e.what());}if(applying())try{pmmodes::moved(R(),self);}catch(const std::exception&e){fault(e);}}
void onNormalStart(P self,P mi){
 try{if(pmunlock::beforeStart(R(),self,^{try{pmcontent::selectorLoadingEnd(R(),true);}catch(const std::exception&e){diagf("Selector loading resume: %s",e.what());}orig<VoidFn>(h::normalStart)(self,mi);}))return;}
 catch(const std::exception&e){diagf("Unlock start gate failed: %s",e.what());return;}
 try{pmcontent::selectorLoadingEnd(R(),true);}catch(const std::exception&e){diagf("Selector loading start: %s",e.what());}
 orig<VoidFn>(h::normalStart)(self,mi);
}
using MainlineCheckFn=void(*)(P,P,int*,P*,bool*,P*,P);
void onMainlineCheckSongUnlock(P self,P songID,int*unlockType,P*chartUnlocked,bool*appeared,P*unlockInfo,P mi){
 orig<MainlineCheckFn>(h::mainlineCheckUnlock)(self,songID,unlockType,chartUnlocked,appeared,unlockInfo,mi);
 if(!PMSettingBool("mainlineUnlock"))return;
 try{
  auto&r=R();NSString*identifier=r.string(songID);
  if(!pmcontent::isMainlineSong(identifier))return;
  if(unlockType)*unlockType=-1;
  if(appeared)*appeared=true;
  if(chartUnlocked&&*chartUnlocked){
   P song=r.call(self,"GetSongInformation",{"System.String"},{songID});
   P difficulty=song?r.get<P>(song,"difficulty"):nullptr;
   uintptr_t count=r.array_length(*chartUnlocked);
   for(uintptr_t i=0;i<count;++i){
    bool unlocked=false;
    if(difficulty&&i<r.array_length(difficulty)){
     float rating=r.unbox<float>(r.arrayAt(difficulty,(int)i));
     unlocked=std::isfinite(rating)&&rating>0;
    }
    r.arrayPutBool(*chartUnlocked,(int)i,unlocked);
   }
  }
  if(unlockInfo)*unlockInfo=r.managedString(@"");
 }catch(const std::exception&e){diagf("Mainline CheckSongUnlock failed: %s",e.what());}
}
void onMainlinePhase1Start(P self,P mi){
 orig<VoidFn>(h::mainlinePhase1Start)(self,mi);
 if(!PMSettingBool("mainlineUnlock"))return;
 try{pmunlock::mainlinePhase1Start(R(),self);}catch(const std::exception&e){diagf("Mainline Chapter9 phase1 entry failed: %s",e.what());}
}
void onMainlinePhase1ToPhase2(P self,P mi){
 try{if(pmunlock::mainlinePhase1ToPhase2(R(),self))return;}catch(const std::exception&e){diagf("Mainline Chapter9 phase transition failed: %s",e.what());}
 orig<VoidFn>(h::mainlinePhase1ToPhase2)(self,mi);
}
void onMainlineApplyMapCover(P self,P mi){
 orig<VoidFn>(h::mainlineApplyMapCover)(self,mi);
 try{pmunlock::mainlineApplyMapCover(R(),self);}catch(const std::exception&e){diagf("Mainline Chapter9 map cover failed: %s",e.what());}
}

void onSelector(P self,P mi){try{if(!pmunlock::selectorAccess(R(),self))return;}catch(const std::exception&e){diagf("Selector chapter access: %s",e.what());return;}try{pmcontent::prepareSelectorItems(R(),self);pmcontent::selectorLoadingBegin(R(),self);}catch(const std::exception&e){diagf("Selector loading begin: %s",e.what());}orig<VoidFn>(h::selector)(self,mi);try{pmscene::selectorFrame(R(),self);pmcontent::selectorFrame(R(),self);pmunlock::tick(R(),self);pmcontent::selectorLoadingFrame(R(),self);}catch(const std::exception&e){lastError=e.what();}}
void onSelectorOff(P self,P mi){try{pmcontent::selectorLoadingEnd(R(),false);pmscene::selectorOff(R());pmunlock::clear(R());}catch(const std::exception&e){lastError=e.what();}orig<VoidFn>(h::selectorOff)(self,mi);}
void onSetting(P self,P mi){orig<VoidFn>(h::setting)(self,mi);try{pmunlock::clear(R());pmscene::settingsFrame(R(),self);}catch(const std::exception&e){lastError=e.what();}}
void onSettingTab(P self,int index,P mi){try{pmscene::settingsLeave(R());}catch(const std::exception&e){lastError=e.what();}orig<void(*)(P,int,P)>(h::settingTab)(self,index,mi);}
void onSettingBack(P self,P mi){try{pmscene::settingsLeave(R());}catch(const std::exception&e){lastError=e.what();}orig<VoidFn>(h::settingBack)(self,mi);}
bool dispatchModButton(P self){
 try{if(pmunlock::beforeResultContinue(R(),self))return true;}catch(const std::exception&e){diagf("Unlock result Continue: %s",e.what());}
 try{if(pmunlock::pressRequirement(R(),self))return true;}catch(const std::exception&e){diagf("Unlock details button: %s",e.what());return true;}
 try{if(pmunlock::blockChallengeButton(R(),self))return true;}catch(const std::exception&e){diagf("Challenge access guard: %s",e.what());return true;}
 if(!pmscene::ownsButton(self))return false;
 try{auto&r=R();if(!r.unbox<bool>(r.call(self,"IsActive"))||!r.unbox<bool>(r.call(self,"IsInteractable")))return true;pmscene::press(r,self);}
 catch(const std::exception&e){lastError=std::string("MOD button: ")+e.what();NSLog(@"[PhiMod] %s",lastError.c_str());}
 return true; // Only an owned clone is consumed. All game buttons pass through.
}
void onPress(P self,P mi){if(!dispatchModButton(self))orig<VoidFn>(h::button)(self,mi);}
void onPointerClick(P self,P event,P mi){
 if(pmunlock::ownsRequirementButton(self)){try{if(R().enumValue(R().call(event,"get_button"),"UnityEngine.EventSystems.PointerEventData.InputButton")==0)pmunlock::pressRequirement(R(),self);}catch(const std::exception&e){diagf("Unlock details click: %s",e.what());}return;}
 try{if(pmunlock::blockChallengeButton(R(),self))return;}catch(const std::exception&e){diagf("Challenge click guard: %s",e.what());return;}
 if(pmscene::ownsButton(self)){
  try{P value=R().call(event,"get_button");int button=0;P raw=R().object_unbox(value);if(!raw)throw std::runtime_error("Invalid pointer button");memcpy(&button,raw,sizeof(button));if(button==0)dispatchModButton(self);}
  catch(const std::exception&e){lastError=e.what();}return;
 }
 orig<void(*)(P,P,P)>(h::buttonClick)(self,event,mi);
}
void onSubmit(P self,P event,P mi){if(!dispatchModButton(self))orig<void(*)(P,P,P)>(h::buttonSubmit)(self,event,mi);}
void onCheck(P self,int finger,P mi,h::Index i){
 // Fullscreen positional scope for initial Tap/Flick candidate collection.
 auto fn=orig<void(*)(P,int,P)>(i);if(!applying()||!attempt->options().fullscreen){PlaybackJudgeScope rate(R());fn(self,finger,mi);return;}
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
  {PlaybackJudgeScope rate(r);called=true;fn(self,finger,mi);}
 }catch(const std::exception&e){fault(e);}
 try{for(auto p:restore)r.put(p.first,"positionX",p.second);}catch(const std::exception&e){fault(e);}
 if(!called){PlaybackJudgeScope rate(r);fn(self,finger,mi);}
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
  r.field(r.klass("LevelInformation"),"chartLoaded","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"levelBegan","System.Boolean",false);
  r.field(r.klass("LevelInformation"),"judgeLines","System.Collections.Generic.List<UnityEngine.GameObject>",false);
  r.field(r.klass("LevelInformation"),"floorPositions","System.Single[]",false);
  r.field(r.klass("AddressableAudioSource"),"audioSource","UnityEngine.AudioSource",false);
  r.field(r.klass("AddressableAudioSource"),"startTime","System.Single",false);
  r.field(r.klass("AddressableAudioSource"),"time","System.Single",false);
  r.field(r.klass("AddressableAudioSource"),"internalTime","System.Single",false);
  r.field(r.klass("AddressableAudioSource"),"playFlag","System.Boolean",false);
  r.field(r.klass("AddressableAudioSource"),"loadOver","System.Boolean",false);
  r.field(r.klass("JudgeControl"),"nowTime","System.Single",false);
   r.resolve(r.klass("GameInformation"),"GetSongInformation",{"System.String"});
   r.field(r.klass("SongsItem"),"difficulty","System.Single[]",false);
   pmunlock::validate(r);
   r.field(r.klass("GameInformation"),"levelResultInfo","LevelResultInfo",false);
   r.field(r.klass("GameInformation"),"noteCodes","System.Collections.Generic.List<System.Single>",false);
   r.field(r.klass("GameInformation"),"nowChallengeIndex","System.Int32",false);
   r.field(r.klass("GameInformation"),"challengeSongItems","System.Collections.Generic.List<Phigros2.SongSelector.Scripts.ChallengeSongItem>",false);
   r.field(r.type("Phigros2.SongSelector.Scripts","ChallengeSongItem"),"result","LevelResultInfo",false);
   r.field(r.type("Phigros2.SongSelector.Scripts","ChallengeSongItem"),"noteCodes","System.Collections.Generic.List<System.Single>",false);
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
  pmpractice::validate(r);
  r.resolve(r.klass("AddressableAudioSource"),"Update");
  P ctx=r.nested(r.klass("LevelOverControl"),"<>c__DisplayClass43_0");
  for(auto name:{"<Start>g__SetResultAudio|1","<Start>g__SetResultInfo|2","<Start>g__SetScreenRatio|23","<Start>g__EnableResultCanvas|21","<Start>g__PlayResultBGM|22"})r.resolve(ctx,name);
  r.resolve(ctx,"<Start>g__SetRatingWithScore|3",{"System.Int32","System.Boolean"});
  P resultIterator=r.nested(r.klass("LevelOverControl"),"<Start>d__43");
  r.field(resultIterator,"<>1__state","System.Int32",false);
  r.field(resultIterator,"<>2__current","System.Object",false);
  r.field(resultIterator,"<>4__this","LevelOverControl",false);
  r.resolve(r.klass("AddressableAudioSource"),"set_Volume",{"System.Single"});
  pmhp::validate(r);pmmodes::validate(r);pmcontent::validate(r);
  rt=std::move(candidate);pmcontent::attach(*rt);pmfeatures::attach(*rt);pmunlock::attach(*rt);
  P callbacks[h::Count]={reinterpret_cast<P>(onAwake),reinterpret_cast<P>(onDestroy),reinterpret_cast<P>(onProgressStart),reinterpret_cast<P>(onProgressUpdate),reinterpret_cast<P>(onMiss),reinterpret_cast<P>(onBad),reinterpret_cast<P>(onGood),reinterpret_cast<P>(onPerfect),reinterpret_cast<P>(onScoreUpdate),reinterpret_cast<P>(onResultInfo),reinterpret_cast<P>(onClick),reinterpret_cast<P>(onDrag),reinterpret_cast<P>(onHold),reinterpret_cast<P>(onFlick),reinterpret_cast<P>(onRecord),reinterpret_cast<P>(onSetRecord),reinterpret_cast<P>(onRanking),reinterpret_cast<P>(onResultStart),reinterpret_cast<P>(onResultMove),reinterpret_cast<P>(onSelector),reinterpret_cast<P>(onSelectorOff),reinterpret_cast<P>(onSetting),reinterpret_cast<P>(onSettingTab),reinterpret_cast<P>(onSettingBack),reinterpret_cast<P>(onPress),reinterpret_cast<P>(onCheckNote),reinterpret_cast<P>(onCheckFlick),reinterpret_cast<P>(onDelete),reinterpret_cast<P>(saveBool<h::SaveBool>),reinterpret_cast<P>(saveInt<h::SaveInt>),reinterpret_cast<P>(saveFloat<h::SaveFloat>),reinterpret_cast<P>(onSaveDate),reinterpret_cast<P>(saveString<h::SaveString>),reinterpret_cast<P>(saveBool<h::LegacySaveBool>),reinterpret_cast<P>(saveInt<h::LegacySaveInt>),reinterpret_cast<P>(saveFloat<h::LegacySaveFloat>),reinterpret_cast<P>(saveString<h::LegacySaveString>),reinterpret_cast<P>(onPointerClick),reinterpret_cast<P>(onSubmit),reinterpret_cast<P>(onLifeStart),reinterpret_cast<P>(onLifeNormalized),reinterpret_cast<P>(onLifeModStart),reinterpret_cast<P>(onHPBackgroundStart),reinterpret_cast<P>(onProgressLevelOver),reinterpret_cast<P>(onLifeUpdate),reinterpret_cast<P>(onLevelCodes),reinterpret_cast<P>(onLevelInformation),reinterpret_cast<P>(onNoteManager),reinterpret_cast<P>(onBlocking),reinterpret_cast<P>(onBlockLate),reinterpret_cast<P>(onHoldMove),reinterpret_cast<P>(onNoteMove<h::clickMove>),reinterpret_cast<P>(onNoteMove<h::dragMove>),reinterpret_cast<P>(onNoteMove<h::flickMove>),reinterpret_cast<P>(onJudgeUpdate),reinterpret_cast<P>(onAddressableAudioUpdate),reinterpret_cast<P>(onCreateNote),reinterpret_cast<P>(onAssetCtor),reinterpret_cast<P>(onAssetRelease),reinterpret_cast<P>(onSongInfo),reinterpret_cast<P>(onItemInfo),reinterpret_cast<P>(onAssetReleaseResource),reinterpret_cast<P>(onChapterStart),reinterpret_cast<P>(onNormalStart),reinterpret_cast<P>(onMainlineCheckSongUnlock),reinterpret_cast<P>(onMainlinePhase1Start),reinterpret_cast<P>(onMainlinePhase1ToPhase2),reinterpret_cast<P>(onMainlineApplyMapCover),reinterpret_cast<P>(onSkinInstantiate),reinterpret_cast<P>(onSkinSound<h::skinSoundHit>),reinterpret_cast<P>(onSkinSound<h::skinSoundNA>),reinterpret_cast<P>(onSkinSound<h::skinSoundUnity>)};
  auto slots=reinterpret_cast<h::Slot*>(const_cast<uint8_t*>(base)+state);
  for(uint32_t i=0;i<h::Count;++i)__atomic_store_n(&slots[i].callback,reinterpret_cast<uint64_t>(callbacks[i]),__ATOMIC_RELEASE);
  ready=true;lastError="72 offline entry hooks v2 installed; verify on device";diagf("PMHookBackend.install success hooks=%u judgeUpdate=1 audioUpdate=1",h::Count);return [self status];
 }catch(const std::exception&e){lastError=e.what();if(installAttempts<=3||installAttempts%10==0)diagf("PMHookBackend.install failed: %s",e.what());return [self status];}
}
+ (BOOL)protectJudgeChange {
 if(!ready||broken)return NO;
 guard.store(true); // Also covers toggles between LevelControl.Awake/Start.
 return YES;
}
+ (NSDictionary *)practiceCommand:(NSInteger)action {
 if(!ready||broken||!rt)return @{ @"ok":@NO,@"message":@"Gameplay backend unavailable" };
 try{auto&r=R();auto options=PMReadOptions([[PMSettings shared] snapshot]);float position=[[[PMSettings shared] value:@"practicePosition"] floatValue];
  bool ok=action==6?pmpractice::updateRange(r,options):pmpractice::command(r,(int)action,options.playbackRate,position);
  if(ok&&action==4&&attempt&&attempt->phase()==phimod::Phase::Playing){auto changed=attempt->options();changed.playbackRate=options.playbackRate;attempt->request(changed);if(!attempt->sync())throw std::runtime_error("Could not apply live practice rate");frozenOptions.playbackRate=options.playbackRate;if(changed.requiresSaveProtection())guard.store(true);}
  if(ok&&pmpractice::consumeRestart())restartPracticeSession();
  std::string message=ok?pmpractice::status(r):"Practice command unavailable: enable range practice before entering a song, wait for chart loading, and check the range";
  return @{ @"ok":@(ok),@"message":[NSString stringWithUTF8String:message.c_str()] ?: @"Practice command failed" };
 }catch(const std::exception&e){diagf("Practice command failed: %s",e.what());return @{ @"ok":@NO,@"message":[NSString stringWithUTF8String:e.what()] ?: @"Practice command failed" };}
}
+ (NSDictionary *)practiceStatus {
 if(!ready||broken||!rt)return @{ @"ok":@NO,@"message":@"Gameplay backend unavailable" };
 try{auto&r=R();auto s=pmpractice::state(r);return @{ @"ok":@YES,@"message":[NSString stringWithUTF8String:pmpractice::status(r).c_str()] ?: @"Practice status unavailable",@"state":@{ @"active":@(s.active),@"segment":@(s.segment),@"paused":@(s.paused),@"countdown":@(s.countdown),@"ended":@(s.ended),@"loop":@(s.loop),@"countIn":@(s.countIn),@"ready":@(s.ready),@"playing":@(s.playing),@"start":@(s.start),@"end":@(s.end),@"duration":@(s.duration),@"cursor":@(s.cursor),@"rate":@(s.rate),@"effectiveRate":@(s.effectiveRate) } };}
 catch(const std::exception&e){return @{ @"ok":@NO,@"message":[NSString stringWithUTF8String:e.what()] ?: @"Practice status failed" };}
}
+ (NSDictionary*)contentSnapshot {return pmcontent::officialSnapshot();}
+ (NSDictionary*)contentCommand:(NSString*)action identifier:(NSString*)identifier slot:(NSInteger)slot {return pmcontent::command(action,identifier,(int)slot);}
+ (void)contentPulse {pmcontent::pulse();}
+ (NSDictionary *)status {
 NSString*practice=@"unavailable";if(ready&&rt&&[NSThread isMainThread])try{practice=[NSString stringWithUTF8String:pmpractice::status(R()).c_str()] ?: @"unavailable";}catch(...){}
 return @{ @"ok":@(ready&&!broken),@"ready":@(ready),@"failedClosed":@(broken),@"saveGuard":@(guard.load()),@"hookCount":@(ready?h::Count:0),@"judgeUpdateHook":@(judgeUpdateSeen),@"judgeUpdateCalls":@(judgeUpdateCalls),@"progressUpdateCalls":@(progressUpdateCalls),@"practice":practice,@"autoplay":@(applying()&&attempt->options().autoplay),@"hp":@(attempt?attempt->hp():0),@"noiseReady":@(ready&&!broken),@"unifiedReady":@(ready&&!broken),@"diagnosticPath":PMDiagnosticsPath(),@"diagnosticTail":PMDiagnosticsTail(80),@"message":[NSString stringWithUTF8String:lastError.c_str()] ?: @"Backend error" };
}
@end
