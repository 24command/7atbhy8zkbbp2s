#import "PMHookBackend.h"
#import "PMSettings.h"
#import "PMRuntime.h"
#include "PMIL2CPP.hpp"
#include "PMOptions.hpp"
#include "PMSceneUI.hpp"
#include "../Core/PMHookProtocol.hpp"
#include "../Core/PMHookManifest.hpp"
#include <atomic>
#include <memory>
#include <set>
#include <sstream>
#include <cstdio>
namespace {
using pmbridge::P;
using pmbridge::Runtime;
namespace h=phimod::hooks;
__attribute__((used)) static const char PMGameplayProtocol[16]="PMGameplay-v1";
struct V3{float x,y,z;};
struct V2{float x,y;};
struct Color{float r,g,b,a;};
std::unique_ptr<Runtime> rt;
P gateways[h::Count]{};
std::unique_ptr<phimod::Session> attempt;
std::atomic<bool> guard{false};
bool ready=false,broken=false,inResult=false;
uint32_t progressRoot=0,scoreRoot=0;
std::set<float> registered;
std::string lastError="Backend not installed";
// All runtime reflection and gameplay callbacks are Unity main-thread only.
// Persistence callbacks only load the atomic guard and invoke their gateway.
Runtime &R(){if(!rt||![NSThread isMainThread])throw std::runtime_error("Unity main thread required");return *rt;}
template<class T>T orig(h::Index i){return reinterpret_cast<T>(gateways[i]);}
using VoidFn=void(*)(P,P);
using JudgeFn=bool(*)(P,P);
using PerfectFn=void(*)(P,float,float,V3,bool,P);
void fault(const std::exception &e){lastError=e.what();broken=true;guard.store(true);if(attempt)attempt->failClosed();}
bool applying(){return ready&&!broken&&attempt&&attempt->shouldApplyGameplay();}
P progress(){return progressRoot?R().gchandle_get_target(progressRoot):nullptr;}
P score(){return scoreRoot?R().gchandle_get_target(scoreRoot):nullptr;}
void release(uint32_t &root){if(root){R().gchandle_free(root);root=0;}}
void registerOne(P note){
 auto &r=R();float code=r.get<float>(note,"noteCode");
 if(registered.count(code))return;
 attempt->registerNote({code,r.get<float>(note,"realTime"),r.get<float>(note,"holdTime"),r.get<int>(note,"type"),false});registered.insert(code);
}
void registerChart(P info){
 auto &r=R();P list=r.get<P>(info,"chartNoteSortByTime");int count=r.count(list);
 if(count<0||count>200000)throw std::runtime_error("Invalid chart count");
 for(int i=0;i<count;++i)registerOne(r.at(list,i));
}
void begin(P p){
 auto &r=R();auto options=PMReadOptions([[PMSettings shared] snapshot]);
 // These two pipelines need independent chart/block coverage; never simulate
 // them by turning AutoPlay on or merely changing a label.
 if(options.noise||options.unified||options.clearNoise)throw std::runtime_error("Noise/Unified pipelines not yet verified; disable before playing");
 release(progressRoot);release(scoreRoot);attempt.reset();registered.clear();
 if(!options.assisted()){lastError="Original gameplay: assistance off";return;}
 progressRoot=r.gchandle_new(p,false);scoreRoot=r.gchandle_new(r.get<P>(p,"scoreControl"),false);
 attempt=std::make_unique<phimod::Session>();
 attempt->setCoverage({true,true,true,true,true,true,true});
 attempt->request(options);
 auto jc=r.klass("JudgeControl");r.runtime_class_init(jc);
 phimod::Windows baseline{r.staticValue<float>(jc,"PerfectTimeRange","System.Single"),r.staticValue<float>(jc,"GoodTimeRange","System.Single"),r.staticValue<float>(jc,"BadTimeRange","System.Single")};
 if(!attempt->begin(baseline))throw std::runtime_error("Incomplete hook coverage");
 if(options.assisted())guard.store(true);
 registered.clear();registerChart(r.get<P>(p,"levelInformation"));
 lastError="Gameplay hooks armed (device verification pending)";
}
void onAwake(P self,P mi){
 // A latch survives OnDestroy, disabled switches and the entire result screen.
 // Alternate assisted result never launches the reward/save coroutine.
 if(!broken){
  try{guard.store(PMReadOptions([[PMSettings shared] snapshot]).assisted());}catch(const std::exception &e){fault(e);}
 }
 try{release(progressRoot);release(scoreRoot);attempt.reset();registered.clear();pmscene::settingsLeave(R());}catch(const std::exception&e){fault(e);}
 inResult=false;
 orig<VoidFn>(h::levelAwake)(self,mi);
}
void onDestroy(P self,P mi){
 if(attempt){attempt->result();if(attempt->excluded())guard.store(true);}
 try{pmscene::hpFrame(0,1,false);}catch(const std::exception&e){fault(e);}
 orig<VoidFn>(h::levelDestroy)(self,mi);
}
void onProgressStart(P self,P mi){
 orig<VoidFn>(h::progressStart)(self,mi);
 try{begin(self);}catch(const std::exception&e){fault(e);}
}
void credit(P self,float code,float offset,V3 pos,bool hold,P mi){
 orig<PerfectFn>(h::perfect)(self,code,offset,pos,hold,mi);
}
void observe(float code,float offset,phimod::Rating rating){if(applying())attempt->observe(code,offset,rating);}
void onPerfect(P self,float code,float offset,V3 pos,bool hold,P mi){
 if(applying()&&attempt->options().autoplay){
  try{auto &r=R();if(attempt->deferHold(code,offset,{pos.x,pos.y,pos.z},hold,r.get<float>(progress(),"nowTime")))return;
   if(!attempt->creditOnce(code))return;
  }catch(const std::exception&e){fault(e);return;}
 }
 observe(code,offset,phimod::Rating::Perfect);credit(self,code,offset,pos,hold,mi);
}
void onMiss(P self,float code,P mi){
 if(applying()&&attempt->options().autoplay){onPerfect(self,code,0,{0,0,0},true,nullptr);return;}
 observe(code,0,phimod::Rating::Miss);orig<void(*)(P,float,P)>(h::miss)(self,code,mi);
}
void onBad(P self,float code,float offset,P mi){observe(code,offset,phimod::Rating::Bad);orig<void(*)(P,float,float,P)>(h::bad)(self,code,offset,mi);}
void onGood(P self,float code,float offset,V3 pos,bool hold,P mi){observe(code,offset,phimod::Rating::Good);orig<PerfectFn>(h::good)(self,code,offset,pos,hold,mi);}
void onProgressUpdate(P self,P mi){
 orig<VoidFn>(h::progressUpdate)(self,mi);
 if(!applying())return;
 try{
  auto &r=R();bool playing=r.get<bool>(self,"isPlaying");float now=r.get<float>(self,"nowTime");
  // Pending holds only credit at their real tail, not the engine's -220ms
  // completion point. Exactly one sample/HP award and one original Perfect.
  for(auto c:attempt->dueHolds(now,playing)){
   observe(c.code,c.offset,phimod::Rating::Perfect);
   credit(score(),c.code,c.offset,{c.position[0],c.position[1],c.position[2]},c.hold,nullptr);
  }
  auto action=attempt->takeAction(playing,r.get<bool>(self,"leave"),r.get<bool>(self,"levelBreak"));
  P info=r.get<P>(self,"levelInformation");
  if(action==phimod::Action::Retry){
   guard.store(true);r.call(self,"LevelBreak",{"System.String"},{r.string_new("Level")});
   r.put(info,"levelOver",true);r.put(info,"canPause",false);r.call(r.get<P>(self,"audioSource"),"Stop");
  }else if(action==phimod::Action::TrackLost){
   r.call(score(),"FreezeScore");r.put(self,"isPlaying",false);r.put(info,"levelOver",true);r.put(info,"canLevelOver",true);
   P routine=r.call(self,"LevelOver");r.call(self,"StartCoroutine",{"System.Collections.IEnumerator"},{routine});
  }
  pmscene::hpFrame(attempt->hp(),attempt->options().hpMax,attempt->options().hpEnabled&&!r.get<bool>(self,"leave"));
 }catch(const std::exception&e){fault(e);}
}
bool noteJudge(P self,P mi,h::Index index,bool hold){
 if(!applying())return orig<JudgeFn>(index)(self,mi);
 auto &r=R();P clock=nullptr,note=nullptr;bool restoreClock=false,restoreX=false;float now=0,oldX=0;
 bool called=false,result=false;
 try{
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
 }catch(const std::exception&e){fault(e);}
 // Restore temporary game clock and note position even if a managed operation
 // failed. No 'retry original' after an original call has already happened.
 try{if(restoreClock)r.put(clock,"nowTime",now);if(restoreX)r.put(note,"positionX",oldX);}catch(const std::exception&e){fault(e);}
 return called?result:orig<JudgeFn>(index)(self,mi);
}
bool onClick(P s,P m){return noteJudge(s,m,h::click,false);}
bool onDrag(P s,P m){return noteJudge(s,m,h::drag,false);}
bool onHold(P s,P m){return noteJudge(s,m,h::hold,true);}
bool onFlick(P s,P m){return noteJudge(s,m,h::flick,false);}
float accuracy(P self){auto &r=R();return phimod::accuracyScore(r.get<int>(self,"perfect"),r.get<int>(self,"good"),r.get<int>(r.get<P>(self,"levelInformation"),"numOfNotes"));}
void onScoreUpdate(P self,P mi){
 if(applying()&&attempt->options().accuracyOnly){try{R().put(self,"_score",accuracy(self));}catch(const std::exception&e){fault(e);}}
 orig<VoidFn>(h::scoreUpdate)(self,mi);
 if(!applying())return;
 try{auto &r=R();auto o=attempt->options();
  if(o.accuracyOnly){float value=accuracy(self);r.put(self,"_score",value);char digits[32];snprintf(digits,sizeof(digits),"%07d",int(std::round(value)));r.text(r.get<P>(self,"score"),digits);}
  if(o.hpEnabled){r.text(r.get<P>(self,"comboText"),"LIFE");r.text(r.get<P>(self,"combo"),std::to_string(int(std::ceil(attempt->hp()))).c_str());}
  else if(o.autoplay)r.text(r.get<P>(self,"comboText"),"AUTOPLAY");
 }catch(const std::exception&e){fault(e);}
}
P onResultInfo(P self,P mi){
 P result=orig<P(*)(P,P)>(h::resultInfo)(self,mi);
 if(applying()&&attempt->options().accuracyOnly)try{float value=accuracy(self);R().call(result,"set_Score",{"System.Single"},{&value});}catch(const std::exception&e){fault(e);}
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
 r.put(self,"_gameInformation",gi);r.put(self,"_levelStartInfo",info);r.put(self,"levelResultInfo",result);
 P mask=r.get<P>(gi,"sceneSwitchMask");r.call(mask,"set_texture",{"UnityEngine.Texture"},{nullptr});Color clear{0,0,0,0};r.call(mask,"set_color",{"UnityEngine.Color"},{&clear});
 float volume=1;r.stat(r.klass("GameInformation"),"set_ListenerVolume",{"System.Single"},{&volume});
 // Whitelist only presentation helpers. Never run the stock iterator or its
 // first-run/tutorial/unlock/reward/record helpers on an assisted result.
 P ctx=r.object_new(r.nested(r.klass("LevelOverControl"),"<>c__DisplayClass43_0"));uint32_t root=r.gchandle_new(ctx,false);
 try{
  r.call(ctx,".ctor");r.put(ctx,"<>4__this",self);P record=r.object_new(r.klass("LevelRecord"));uint32_t rr=r.gchandle_new(record,false);
  try{r.call(record,".ctor");r.put(ctx,"record",record);}catch(...){r.gchandle_free(rr);throw;}r.gchandle_free(rr);
  r.call(ctx,"<Start>g__SetResultAudio|1");r.call(ctx,"<Start>g__SetResultInfo|2");
  int value=r.get<int>(result,"<IntScore>k__BackingField");bool fc=r.unbox<bool>(r.call(result,"get_FullCombo"));
  r.call(ctx,"<Start>g__SetRatingWithScore|3",{"System.Int32","System.Boolean"},{&value,&fc});
  r.text(r.get<P>(self,"best"),"PHIMOD PRACTICE - Scores / RKS / unlocks not saved");
  r.call(r.get<P>(self,"cover"),"set_Code",{"System.String"},{r.get<P>(info,"illustrationKey")});
  r.call(ctx,"<Start>g__SetScreenRatio|23");r.call(ctx,"<Start>g__EnableResultCanvas|21");r.call(ctx,"<Start>g__PlayResultBGM|22");
 }catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);
}
P onResultStart(P self,P mi){
 if(!guard.load())return orig<P(*)(P,P)>(h::resultStart)(self,mi);
 inResult=true;if(attempt)attempt->result();
 try{renderPracticeResult(self);}catch(const std::exception&e){fault(e);}
 inResult=false;return nullptr; // NEVER fall back to saving/unlocking coroutine
}
bool onResultMove(P self,P mi){if(guard.load())return false;return orig<JudgeFn>(h::resultMove)(self,mi);}
void onSelector(P self,P mi){orig<VoidFn>(h::selector)(self,mi);try{pmscene::selectorFrame(R(),self);}catch(const std::exception&e){lastError=e.what();}}
void onSelectorOff(P self,P mi){try{pmscene::selectorOff(R());}catch(const std::exception&e){lastError=e.what();}orig<VoidFn>(h::selectorOff)(self,mi);}
void onSetting(P self,P mi){orig<VoidFn>(h::setting)(self,mi);try{pmscene::settingsFrame(R(),self);}catch(const std::exception&e){lastError=e.what();}}
void onSettingTab(P self,int index,P mi){try{pmscene::settingsLeave(R());}catch(const std::exception&e){lastError=e.what();}orig<void(*)(P,int,P)>(h::settingTab)(self,index,mi);}
void onSettingBack(P self,P mi){try{pmscene::settingsLeave(R());}catch(const std::exception&e){lastError=e.what();}orig<VoidFn>(h::settingBack)(self,mi);}
void onPress(P self,P mi){try{if(pmscene::press(R(),self))return;}catch(const std::exception&e){lastError=e.what();return;}orig<VoidFn>(h::button)(self,mi);}
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
  if(memcmp(desc,PMGameplayProtocol,16)||ver!=1||count!=h::Count||state!=data->addr)throw std::runtime_error("Gameplay protocol mismatch");
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
  rt=std::move(candidate);
  P callbacks[h::Count]={reinterpret_cast<P>(onAwake),reinterpret_cast<P>(onDestroy),reinterpret_cast<P>(onProgressStart),reinterpret_cast<P>(onProgressUpdate),reinterpret_cast<P>(onMiss),reinterpret_cast<P>(onBad),reinterpret_cast<P>(onGood),reinterpret_cast<P>(onPerfect),reinterpret_cast<P>(onScoreUpdate),reinterpret_cast<P>(onResultInfo),reinterpret_cast<P>(onClick),reinterpret_cast<P>(onDrag),reinterpret_cast<P>(onHold),reinterpret_cast<P>(onFlick),reinterpret_cast<P>(onRecord),reinterpret_cast<P>(onSetRecord),reinterpret_cast<P>(onRanking),reinterpret_cast<P>(onResultStart),reinterpret_cast<P>(onResultMove),reinterpret_cast<P>(onSelector),reinterpret_cast<P>(onSelectorOff),reinterpret_cast<P>(onSetting),reinterpret_cast<P>(onSettingTab),reinterpret_cast<P>(onSettingBack),reinterpret_cast<P>(onPress),reinterpret_cast<P>(onCheckNote),reinterpret_cast<P>(onCheckFlick),reinterpret_cast<P>(onDelete),reinterpret_cast<P>(saveBool<h::SaveBool>),reinterpret_cast<P>(saveInt<h::SaveInt>),reinterpret_cast<P>(saveFloat<h::SaveFloat>),reinterpret_cast<P>(onSaveDate),reinterpret_cast<P>(saveString<h::SaveString>),reinterpret_cast<P>(saveBool<h::LegacySaveBool>),reinterpret_cast<P>(saveInt<h::LegacySaveInt>),reinterpret_cast<P>(saveFloat<h::LegacySaveFloat>),reinterpret_cast<P>(saveString<h::LegacySaveString>)};
  auto slots=reinterpret_cast<h::Slot*>(const_cast<uint8_t*>(base)+state);
  for(uint32_t i=0;i<h::Count;++i)__atomic_store_n(&slots[i].callback,reinterpret_cast<uint64_t>(callbacks[i]),__ATOMIC_RELEASE);
  ready=true;lastError="37 offline entry hooks installed; verify on device";return [self status];
 }catch(const std::exception&e){lastError=e.what();return [self status];}
}
+ (BOOL)protectJudgeChange {
 if(!ready||broken)return NO;
 guard.store(true); // Also covers toggles between LevelControl.Awake/Start.
 return YES;
}
+ (NSDictionary *)status {
 return @{ @"ok":@(ready&&!broken),@"ready":@(ready),@"failedClosed":@(broken),@"saveGuard":@(guard.load()),@"hookCount":@(ready?h::Count:0),@"autoplay":@(applying()&&attempt->options().autoplay),@"hp":@(attempt?attempt->hp():0),@"noiseReady":@NO,@"unifiedReady":@NO,@"message":[NSString stringWithUTF8String:lastError.c_str()] ?: @"Backend error" };
}
@end
