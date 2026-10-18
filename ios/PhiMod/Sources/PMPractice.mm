#include "PMPractice.hpp"
#include "PMPracticePreview.hpp"
#include "PMHPLife.hpp"
#include "PMChartModes.hpp"
#include "PMDiagnostics.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <sstream>

namespace pmpractice {
namespace {
phimod::Options options;
uint32_t progressRoot=0,sourceRoot=0,audioRoot=0;
float originalPitch=1,effectiveRate=1,anchorNative=0,anchorClip=0,lastNative=0;
bool active=false,segment=false,segmentPaused=false,entryPending=false,segmentEnded=false,restartPending=false,anchorReady=false,pitchCaptured=false,countdownActive=false,countdownAudio=false;
float segmentStart=0,segmentEnd=-1,segmentDuration=0,segmentCursor=0,countdownTarget=0,countdownFrom=0,countdownAt=0;
int rateDepth=0;
float savedWindows[3]{};
Runtime*rateRuntime=nullptr;
P rateJudge=nullptr;
P target(Runtime&r,uint32_t h){return h?r.gchandle_get_target(h):nullptr;}
void release(Runtime&r,uint32_t&h){if(h){r.gchandle_free(h);h=0;}}
P progressObject(Runtime&r){return target(r,progressRoot);}
P sourceObject(Runtime&r){return target(r,sourceRoot);}
P unityAudio(Runtime&r){return target(r,audioRoot);}
float clipOffset(Runtime&r,P progress){return r.get<float>(r.get<P>(progress,"levelInformation"),"offset");}
float setPitch(Runtime&r,float pitch){
 P audio=unityAudio(r);if(!r.alive(audio))return pitch;
 r.call(audio,"set_pitch",{"System.Single"},{&pitch});
 float actual=r.unbox<float>(r.call(audio,"get_pitch"));
 if(std::fabs(actual-pitch)>.03f){char message[160];snprintf(message,sizeof(message),"Practice pitch requested=%.3f actual=%.3f",pitch,actual);PMDiagnosticsWrite(message);}
 return actual;
}
void pauseAt(Runtime&r,P progress,float cursor,bool ended){
 P info=r.get<P>(progress,"levelInformation"),judge=r.get<P>(progress,"judgeControl"),source=sourceObject(r);
 segmentCursor=std::max(0.f,std::min(cursor,segmentDuration>0?segmentDuration:cursor));
 r.put(progress,"nowTime",segmentCursor);r.put(progress,"audioTime",std::max(0.f,segmentCursor+clipOffset(r,progress)));
 if(source)r.call(source,"Pause");
 r.put(progress,"isPlaying",false);r.put(info,"levelOver",false);r.put(info,"canLevelOver",false);
 r.put(judge,"stopJudge",true);
 P pauseBar=r.get<P>(progress,"pauseBar");bool yes=true;if(r.alive(pauseBar))r.call(pauseBar,"SetActive",{"System.Boolean"},{&yes});
 segmentPaused=true;segmentEnded=ended;countdownActive=false;countdownAudio=false;
 PMDiagnosticsWrite(ended?"Practice segment reached end; paused":"Practice segment paused");
}
void clearControllers(Runtime&r,P manager){
 pmpracticepreview::discardControls();
 for(const char*name:{"clickControls","dragControls","holdControls","flickControls"}){
  P list=r.get<P>(manager,name);int n=r.count(list);if(n<0||n>100000)throw std::runtime_error("Invalid practice controller count");
  for(int i=0;i<n;++i){P control=r.at(list,i);if(r.alive(control)){P go=r.call(control,"get_gameObject");if(r.alive(go))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});}}
  if(list)r.call(list,"Clear");
 }
}
void prepareRange(Runtime&r,P progress,float current){
 P info=r.get<P>(progress,"levelInformation"),judge=r.get<P>(progress,"judgeControl");
 P manager=r.get<P>(judge,"noteUpdateManager"),notes=r.get<P>(judge,"chartNoteSortByTime");
 if(!r.alive(info)||!r.get<bool>(info,"chartLoaded")||!notes)throw std::runtime_error("Practice chart is not ready");
 pmpracticepreview::reset(r,progress,current);
 clearControllers(r,manager);
 int noteCount=r.count(notes);if(noteCount<0||noteCount>200000)throw std::runtime_error("Practice chart note count invalid");
 // reset() restores source notes and preserves crossing Holds at the new start.
 r.put(judge,"startIndex",0);r.put(judge,"endIndex",0);
 P lines=r.get<P>(judge,"judgeLineControls");int lineCount=r.count(lines);if(lineCount<0||lineCount>10000)throw std::runtime_error("Practice judge-line count invalid");
 for(int i=0;i<lineCount;++i){P line=r.at(lines,i);for(const char*field:{"nowSpeedIndex","nowDisappearIndex","nowMoveIndex","nowRotateIndex","nowProductIndexAbove","nowProductIndexBelow"})r.put(line,field,0);r.put(line,"lastProductIndexAbove",-1);r.put(line,"lastProductIndexBelow",-1);r.put(line,"numOfFingers",0);}
 P score=r.get<P>(progress,"scoreControl");
 for(const char*field:{"perfect","good","bad","miss","early","late","_combo","maxcombo"})r.put(score,field,0);
 r.put(score,"_score",0.f);r.put(score,"_percent",0.f);r.put(score,"isAllPerfect",true);r.put(score,"isFullCombo",true);r.put(score,"scoreFrozen",false);
 r.call(score,"SetNoteCodeList");
 if(segmentEnd<=segmentStart)throw std::runtime_error("Practice range end must exceed start");
 segmentCursor=std::clamp(current,segmentStart,segmentEnd);segmentEnded=false;
 r.put(progress,"nowTime",segmentCursor);r.put(progress,"audioTime",std::max(0.f,segmentCursor+clipOffset(r,progress)));
 r.put(progress,"_playPrepared",false);r.put(progress,"_volumeSet",false);
}
void resumeAt(Runtime&r,P progress,float current,bool handoff=false){
 if(!handoff)prepareRange(r,progress,current);
 P info=r.get<P>(progress,"levelInformation"),judge=r.get<P>(progress,"judgeControl"),source=sourceObject(r);
 bool yes=true,no=false;bool restartAudio=!handoff||!countdownAudio;
 if(handoff){clearControllers(r,r.get<P>(judge,"noteUpdateManager"));P lines=r.get<P>(judge,"judgeLineControls");for(int i=0,n=r.count(lines);i<n;++i){P line=r.at(lines,i);for(const char*name:{"nowProductIndexAbove","nowProductIndexBelow"})r.put(line,name,0);r.put(line,"lastProductIndexAbove",-1);r.put(line,"lastProductIndexBelow",-1);}}
 r.call(progress,"Play",{"System.Boolean"},{&yes});
 float clipAt=std::max(0.f,current+clipOffset(r,progress));
 if(restartAudio&&source){r.call(source,"Seek",{"System.Single"},{&clipAt});r.call(source,"Play");float volume=r.get<float>(info,"musicVol");r.call(source,"set_Volume",{"System.Single"},{&volume});}
 r.put(progress,"nowTime",current);r.put(progress,"audioTime",clipAt);
 float timeSinceLoad=r.unbox<float>(r.stat(r.type("UnityEngine","Time"),"get_timeSinceLevelLoad"));
 r.put(progress,"_startTime",timeSinceLoad);r.put(progress,"_playPrepared",yes);r.put(progress,"_volumeSet",yes);r.put(progress,"isPlaying",yes);
 r.put(info,"levelOver",no);r.put(info,"canLevelOver",no);r.put(info,"canPause",yes);r.put(judge,"stopJudge",no);
 P pauseBar=r.get<P>(progress,"pauseBar");if(r.alive(pauseBar))r.call(pauseBar,"SetActive",{"System.Boolean"},{&no});
 segmentPaused=false;segmentEnded=false;segmentCursor=current;countdownActive=countdownAudio=false;
 if(restartAudio){anchorNative=clipAt;anchorClip=clipAt;lastNative=clipAt;anchorReady=true;}
 PMDiagnosticsWrite(handoff?"Practice countdown handed off to gameplay":"Practice segment playback resumed");
}
void startAt(Runtime&r,P progress,float current){
 current=std::clamp(current,segmentStart,std::max(segmentStart,segmentEnd-.01f));
 if(!options.practiceCountdown){restartPending=true;resumeAt(r,progress,current);return;}
 restartPending=true;
 prepareRange(r,progress,current);
 P info=r.get<P>(progress,"levelInformation"),judge=r.get<P>(progress,"judgeControl"),source=sourceObject(r);
 countdownTarget=current;countdownFrom=current-3.f;countdownAt=r.unbox<float>(r.stat(r.type("UnityEngine","Time"),"get_time"));countdownActive=true;countdownAudio=false;
 bool no=false;P pauseBar=r.get<P>(progress,"pauseBar");if(r.alive(pauseBar))r.call(pauseBar,"SetActive",{"System.Boolean"},{&no});
 r.put(progress,"nowTime",countdownFrom);r.put(progress,"audioTime",std::max(0.f,countdownFrom+clipOffset(r,progress)));r.put(progress,"isPlaying",false);r.put(progress,"_playPrepared",true);r.put(progress,"_volumeSet",true);
 r.put(info,"levelOver",false);r.put(info,"canLevelOver",false);r.put(info,"canPause",false);r.put(judge,"stopJudge",true);
 if(source)r.call(source,"Pause");segmentPaused=false;segmentEnded=false;segmentCursor=countdownFrom;
 PMDiagnosticsWrite("Practice three-second count-in started");
}
void countdownTick(Runtime&r,P progress){
 P source=sourceObject(r),info=r.get<P>(progress,"levelInformation");float offset=clipOffset(r,progress);
 float now=countdownFrom+(r.unbox<float>(r.stat(r.type("UnityEngine","Time"),"get_time"))-countdownAt)*effectiveRate;
 if(countdownAudio)now=std::max(segmentCursor,r.get<float>(source,"time")-offset);
 if(now>=countdownTarget){segmentCursor=countdownTarget;restartPending=true;resumeAt(r,progress,countdownTarget,true);return;}
 segmentCursor=now;r.put(progress,"nowTime",now);r.put(progress,"audioTime",std::max(0.f,now+offset));
 if(!countdownAudio&&now+offset>=0){float position=now+offset;r.call(source,"Seek",{"System.Single"},{&position});r.call(source,"Play");float volume=r.get<float>(info,"musicVol");r.call(source,"set_Volume",{"System.Single"},{&volume});countdownAudio=true;anchorNative=position;anchorClip=position;lastNative=position;anchorReady=true;PMDiagnosticsWrite("Practice count-in audio started");}
}
} // namespace
void prepare(Runtime&,const phimod::Options&o){options=o;effectiveRate=o.playbackRate;active=o.practiceMode||o.playbackRate<=.0001f||std::fabs(o.playbackRate-1.f)>.0001f;segment=o.practiceMode||o.playbackRate<=.0001f;segmentPaused=false;entryPending=false;segmentEnded=false;restartPending=false;anchorReady=false;countdownActive=countdownAudio=false;rateDepth=0;}
void begin(Runtime&r,P progress){
 if(!active)return;
 release(r,progressRoot);progressRoot=r.gchandle_new(progress,false);
 P source=r.get<P>(progress,"audioSource");if(!r.alive(source))throw std::runtime_error("Practice AddressableAudioSource missing");
 release(r,sourceRoot);sourceRoot=r.gchandle_new(source,false);
 P audio=r.get<P>(source,"audioSource");if(!r.alive(audio))throw std::runtime_error("Practice Unity AudioSource missing");
 if(!audioRoot){audioRoot=r.gchandle_new(audio,false);originalPitch=r.unbox<float>(r.call(audio,"get_pitch"));pitchCaptured=true;}
 segmentStart=options.practiceStart;segmentEnd=options.practiceEnd;segmentDuration=0;segmentCursor=0;segmentPaused=false;segmentEnded=false;
 entryPending=segment;anchorNative=r.get<float>(source,"startTime");anchorClip=anchorNative;lastNative=anchorNative;anchorReady=true;
 effectiveRate=setPitch(r,options.playbackRate);
 PMDiagnosticsWrite("Practice runtime armed; segment will pause after chart/audio preparation");
}
void clear(Runtime&r){
 if(pitchCaptured){try{setPitch(r,originalPitch);}catch(const std::exception&e){PMDiagnosticsWrite((std::string("Practice pitch restore failed: ")+e.what()).c_str());}}
 for(uint32_t*h:{&progressRoot,&sourceRoot,&audioRoot})release(r,*h);
 pmpracticepreview::clear();
 pitchCaptured=false;effectiveRate=1;active=segment=segmentPaused=entryPending=segmentEnded=restartPending=anchorReady=countdownActive=countdownAudio=false;rateDepth=0;
}
bool ownsAudio(Runtime&r,P self){return active&&target(r,sourceRoot)==self;}
void audioBefore(Runtime&r,P self){if(!ownsAudio(r,self))return;float targetPitch=options.playbackRate;P audio=unityAudio(r);if(r.alive(audio)){float current=r.unbox<float>(r.call(audio,"get_pitch"));if(std::fabs(current-effectiveRate)>.02f)effectiveRate=setPitch(r,targetPitch);}}
void audioAfter(Runtime&r,P self){
 if(!ownsAudio(r,self))return;
 float now=r.get<float>(self,"time");
 if(!anchorReady||now<lastNative-.05f||std::fabs(now-lastNative)>2.f){anchorNative=now;anchorClip=now;anchorReady=true;}
 float mapped=anchorClip+(now-anchorNative)*effectiveRate;r.put(self,"time",mapped);lastNative=now;
}
bool beforeProgress(Runtime&r,P progress){
 if(!segment)return false;
 if(r.get<bool>(progress,"leave")||r.get<bool>(progress,"levelBreak"))return false;
 P info=r.get<P>(progress,"levelInformation");if(info)r.put(info,"canLevelOver",false);
 if(countdownActive){countdownTick(r,progress);return true;}
 if(entryPending)return false;
 if(segmentPaused&&r.get<bool>(progress,"isPlaying")){startAt(r,progress,segmentEnded?segmentStart:segmentCursor);return countdownActive;}
 if(!segmentPaused&&!r.get<bool>(progress,"isPlaying")&&r.get<bool>(info,"chartLoaded")){pauseAt(r,progress,r.get<float>(progress,"nowTime"),false);return true;}
 if(!segmentPaused)return false;
 r.put(progress,"nowTime",segmentCursor);r.put(progress,"audioTime",std::max(0.f,segmentCursor+clipOffset(r,progress)));return true;
}
bool afterProgress(Runtime&r,P progress){
 if(!segment)return false;
 P info=r.get<P>(progress,"levelInformation");
 if(entryPending&&r.get<bool>(info,"chartLoaded")&&r.get<bool>(progress,"_playPrepared")&&r.get<bool>(progress,"_volumeSet")&&r.get<bool>(sourceObject(r),"loadOver")){
  P source=sourceObject(r);segmentDuration=std::max(0.f,r.unbox<float>(r.call(source,"get_ClipLength"))-clipOffset(r,progress));
  entryPending=false;
  segmentStart=std::clamp(options.practiceStart,0.f,std::max(0.f,segmentDuration-.01f));
  segmentEnd=options.practiceEnd<0?segmentDuration:std::clamp(options.practiceEnd,segmentStart+.01f,segmentDuration);
  if(segmentEnd<=segmentStart)throw std::runtime_error("Practice segment range is empty");
  prepareRange(r,progress,segmentStart);
  float clipAt=std::max(0.f,segmentStart+clipOffset(r,progress));
  r.call(source,"Seek",{"System.Single"},{&clipAt});r.call(source,"Pause");
  pauseAt(r,progress,segmentStart,false);
  r.put(progress,"_playPrepared",true);r.put(progress,"_volumeSet",true);
  PMDiagnosticsWrite("Practice entered paused range preview");
  return false;
 }
 if(segmentPaused)return false;
 float now=r.get<float>(progress,"nowTime");if(segmentEnd>0&&now>=segmentEnd){
  if(options.practiceLoop){startAt(r,progress,segmentStart);return true;}
  pauseAt(r,progress,segmentEnd,true);
 }
 return false;
}
bool paused(){return segmentPaused||countdownActive;}
bool allowNoteCreation(){return !paused()||pmpracticepreview::creating();}
bool previewFrame(Runtime&r,P manager){if(!paused())return false;pmpracticepreview::render(r,manager,segmentCursor,countdownActive,countdownTarget);return true;}
bool updateRange(Runtime&r,const phimod::Options&changed){
 if(!active||!segment||entryPending||segmentDuration<=0)return false;
 float start=std::clamp(changed.practiceStart,0.f,std::max(0.f,segmentDuration-.01f));
 float end=changed.practiceEnd<0?segmentDuration:std::min(changed.practiceEnd,segmentDuration);
 if(end<=start)return false;
 options.practiceStart=start;options.practiceEnd=end;options.practiceLoop=changed.practiceLoop;options.practiceCountdown=changed.practiceCountdown;
 segmentStart=start;segmentEnd=end;return true;
}
State state(Runtime&r){State s{};s.active=active;s.segment=segment;s.paused=segmentPaused;s.countdown=countdownActive;s.ended=segmentEnded;s.loop=options.practiceLoop;s.countIn=options.practiceCountdown;s.ready=active&&!entryPending&&segmentDuration>0;s.start=segmentStart;s.end=segmentEnd;s.duration=segmentDuration;s.cursor=segmentCursor;s.rate=options.playbackRate;s.effectiveRate=effectiveRate;P p=progressObject(r);if(p){s.cursor=r.get<float>(p,"nowTime");s.playing=r.get<bool>(p,"isPlaying");}return s;}
bool command(Runtime&r,int action,float requestedRate,float requestedPosition){
 P progress=progressObject(r);if(!progress||!active||entryPending||r.get<bool>(progress,"leave")||r.get<bool>(progress,"levelBreak"))return false;
 if(action==4){
  if(!std::isfinite(requestedRate)||requestedRate<0||requestedRate>5)return false;
  P source=sourceObject(r);float clipNow=source?r.get<float>(source,"time"):0;
  options.playbackRate=requestedRate;effectiveRate=setPitch(r,requestedRate);anchorNative=lastNative;anchorClip=clipNow;anchorReady=true;
  if(requestedRate<=.0001f){P info=r.get<P>(progress,"levelInformation");segment=true;float now=r.get<float>(progress,"nowTime");pauseAt(r,progress,now,false);if(info)r.put(info,"canLevelOver",false);return true;}
  if(countdownActive){countdownFrom=r.get<float>(progress,"nowTime");countdownAt=r.unbox<float>(r.stat(r.type("UnityEngine","Time"),"get_time"));}
  else if(segmentPaused){restartPending=true;startAt(r,progress,segmentEnded?segmentStart:segmentCursor);}
  return true;
 }
 if(!segment)return false;
 P info=r.get<P>(progress,"levelInformation");if(!r.get<bool>(info,"chartLoaded"))return false;
 P source=sourceObject(r);if(segmentDuration<=0)segmentDuration=std::max(0.f,r.unbox<float>(r.call(source,"get_ClipLength"))-clipOffset(r,progress));
 if(segmentEnd<0||segmentEnd>segmentDuration)segmentEnd=segmentDuration;
 if(action==0){startAt(r,progress,segmentStart);return true;}
 if(action==1){if(countdownActive){pauseAt(r,progress,r.get<float>(progress,"nowTime"),false);}else if(segmentPaused){startAt(r,progress,segmentEnded?segmentStart:segmentCursor);}else{float now=r.get<float>(progress,"nowTime");pauseAt(r,progress,now,false);}return true;}
 if(action==2){startAt(r,progress,segmentStart);return true;}
 if(action==3){segmentStart=0;segmentEnd=segmentDuration;segment=false;restartPending=true;resumeAt(r,progress,0);r.put(info,"canLevelOver",true);return true;}
 if(action==7){if(!std::isfinite(requestedPosition)||requestedPosition<0)return false;float cursor=std::clamp(requestedPosition,0.f,std::max(0.f,segmentDuration-.01f));prepareRange(r,progress,cursor);P audio=sourceObject(r);float clip=std::max(0.f,cursor+clipOffset(r,progress));r.call(audio,"Seek",{"System.Single"},{&clip});pauseAt(r,progress,cursor,false);restartPending=true;return true;}
 if(action==5){if(!std::isfinite(requestedPosition)||requestedPosition<0)return false;float target=std::clamp(requestedPosition,segmentStart,std::max(segmentStart,segmentEnd-.01f));restartPending=true;startAt(r,progress,target);return true;}
 return false;
}
bool consumeRestart(){bool value=restartPending;restartPending=false;return value;}
std::string status(Runtime&r){
 std::ostringstream out;out<<"practice="<<(segment?1:0)<<" paused="<<(segmentPaused?1:0)<<" countdown="<<(countdownActive?1:0)<<" ended="<<(segmentEnded?1:0)<<" rate="<<options.playbackRate<<" effectiveRate="<<effectiveRate<<" start="<<segmentStart<<" end="<<segmentEnd<<" current="<<segmentCursor<<" duration="<<segmentDuration;
 P progress=progressObject(r);if(progress){float now=r.get<float>(progress,"nowTime");out<<" now="<<now<<" playing="<<r.get<bool>(progress,"isPlaying");if(countdownActive)out<<" countdownLeft="<<std::max(0.f,countdownTarget-now);}return out.str();
}
void validate(Runtime&r){
 pmpracticepreview::validate(r);
 r.field(r.klass("AddressableAudioSource"),"audioSource","UnityEngine.AudioSource",false);
 r.field(r.klass("AddressableAudioSource"),"startTime","System.Single",false);
 r.field(r.klass("AddressableAudioSource"),"time","System.Single",false);
 r.field(r.klass("AddressableAudioSource"),"internalTime","System.Single",false);
 r.field(r.klass("AddressableAudioSource"),"playFlag","System.Boolean",false);
 r.field(r.klass("AddressableAudioSource"),"loadOver","System.Boolean",false);
 r.resolve(r.klass("AddressableAudioSource"),"get_ClipLength");r.resolve(r.klass("AddressableAudioSource"),"Seek",{"System.Single"});
 P audio=r.type("UnityEngine","AudioSource");r.resolve(audio,"get_pitch");r.resolve(audio,"set_pitch",{"System.Single"});r.resolve(audio,"get_time");r.resolve(audio,"set_time",{"System.Single"});
 r.field(r.klass("ProgressControl"),"audioTime","System.Single",false);r.field(r.klass("ProgressControl"),"_startTime","System.Single",false);
 r.field(r.klass("JudgeControl"),"startIndex","System.Int32",false);r.field(r.klass("JudgeControl"),"endIndex","System.Int32",false);
 r.field(r.klass("JudgeControl"),"chartNoteSortByTime","System.Collections.Generic.List<ChartNote>",false);r.field(r.klass("JudgeControl"),"noteUpdateManager","NoteUpdateManager",false);
 for(const char* field:{"nowSpeedIndex","nowDisappearIndex","nowMoveIndex","nowRotateIndex","nowProductIndexAbove","nowProductIndexBelow","lastProductIndexAbove","lastProductIndexBelow"})r.field(r.klass("JudgeLineControl"),field,"System.Int32",false);
 r.resolve(r.klass("ScoreControl"),"SetNoteCodeList");r.resolve(r.klass("ProgressControl"),"Play",{"System.Boolean"});
}
void judgeRateEnter(Runtime&r){
 if(!active||std::fabs(effectiveRate-1.f)<.0001f)return;
 if(rateDepth++>0)return;
 rateRuntime=&r;rateJudge=r.klass("JudgeControl");
 const char*names[]={"PerfectTimeRange","GoodTimeRange","BadTimeRange"};
 try{r.runtime_class_init(rateJudge);for(int i=0;i<3;++i)savedWindows[i]=r.staticValue<float>(rateJudge,names[i],"System.Single");for(int i=0;i<3;++i)r.setStaticValue<float>(rateJudge,names[i],"System.Single",savedWindows[i]*effectiveRate);}
 catch(const std::exception&e){for(int i=0;i<3;++i)try{r.setStaticValue<float>(rateJudge,names[i],"System.Single",savedWindows[i]);}catch(...){};rateDepth=0;rateRuntime=nullptr;rateJudge=nullptr;PMDiagnosticsWrite((std::string("Judge rate apply failed: ")+e.what()).c_str());}
}
void judgeRateLeave(){
 if(rateDepth<=0)return;if(--rateDepth>0)return;
 if(rateRuntime&&rateJudge){const char*names[]={"PerfectTimeRange","GoodTimeRange","BadTimeRange"};try{for(int i=0;i<3;++i)rateRuntime->setStaticValue<float>(rateJudge,names[i],"System.Single",savedWindows[i]);}catch(const std::exception&e){PMDiagnosticsWrite((std::string("Judge rate restore failed: ")+e.what()).c_str());}}
 rateRuntime=nullptr;rateJudge=nullptr;
}
}