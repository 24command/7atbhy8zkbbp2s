// Compile the production Gameplay<> controller, not a second state-machine model.
#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#define PM_SONG_INTERRUPTION_GAMEPLAY_TEST
#include "../PhiMod/Sources/PMSongInterruptionGameplay.inc"
using songinterruption::Entry;

struct FakeHost {
 using Object=int;
 struct Owner {int level=0,pc=0,scene=0;};
 struct Snapshot {bool canPause=true,canOver=true,stopJudge=false,playing=true;float now=159,audio=159.1f,wrapper=159.2f;};
 Snapshot state;
 int currentLevel=1,currentScene=7,roots=0,pauses=0,resumes=0,quits=0,protects=0,triggers=0,captures=0,ends=0;
 bool sound=true,playFlag=true,pendingValue=false,uiPlaying=false,uiBlocking=false,ready=true,denyTrigger=false,failPresentation=false;
 bool failAcquire=false,failCapture=false,failPause=false,failHold=false;
 int resumeFailures=0;
 int matchReads=0,liveReads=0,eligibilityReads=0,timeReads=0,dueReads=0;
 std::array<int,5> probes()const{return {matchReads,liveReads,eligibilityReads,timeReads,dueReads};}
 std::string pendingID;int pendingSlot=-1;double at=159;
 std::function<bool()> configuredGuard,playingGuard,freezeCallback;
 std::function<void()> configuredInvalidation,playingInvalidation,quitCallback;
 std::vector<std::string> calls;
 void arm(std::string id="installed-OS",int slot=3){pendingValue=true;pendingID=id;pendingSlot=slot;}
 void cancel(){pendingValue=false;}
 void configure(std::function<bool()>guard,std::function<void()>invalidated){configuredGuard=guard;configuredInvalidation=invalidated;}
 bool pending(){return pendingValue;}
 bool begin(std::string id,int slot){
  auto previous=playingInvalidation;
  bool ok=pendingValue&&id==pendingID&&slot==pendingSlot;pendingValue=false;
  uiPlaying=ok;uiBlocking=false;playingGuard=ok?configuredGuard:std::function<bool()>{};
  playingInvalidation=ok?configuredInvalidation:std::function<void()>{};
  if(previous)previous();return ok;
 }
 void invalidate(){auto old=playingInvalidation;playingInvalidation={};uiPlaying=uiBlocking=false;if(old)old();}
 void end(){++ends;pendingValue=false;invalidate();}
 void acquire(Owner&o,int level,int pc){o={level,pc,currentScene};roots+=2;if(failAcquire)throw std::runtime_error("acquire");}
 void release(Owner&o){if(o.level)roots-=2;o={};}
 bool live(const Owner&o){++liveReads;return o.level&&o.level==currentLevel&&o.scene==currentScene;}
 bool inScene(const Owner&o,int scene){return o.scene==scene;}
 bool matches(const Owner&o,Entry entry,int object){
  ++matchReads;
  int offset=entry==Entry::Progress?0:entry==Entry::Judge?1:entry==Entry::Audio?2:3;
  return object==o.pc+offset;
 }
 bool eligible(const Owner&){++eligibilityReads;return ready&&state.playing;}
 double time(const Owner&){++timeReads;return state.now;}
 bool due(double value){++dueReads;return uiPlaying&&playingGuard&&playingGuard()&&std::isfinite(value)&&value>=at;}
 void capture(Owner&,Snapshot&s){++captures;calls.push_back("capture");if(failCapture)throw std::runtime_error("capture");s=state;}
 void protect(){++protects;calls.push_back("protect");}
 void hold(const Owner&,const Snapshot&s){
  calls.push_back("hold");state.now=s.now;state.audio=s.audio;state.wrapper=s.wrapper;
  state.canPause=false;state.canOver=false;state.stopJudge=true;state.playing=false;
  if(failHold){failHold=false;throw std::runtime_error("partial hold");}
 }
 void pause(const Owner&){++pauses;calls.push_back("Pause");sound=false;playFlag=false;state.wrapper=-999;if(failPause){failPause=false;throw std::runtime_error("partial pause");}}
 void repauseIfPlaying(const Owner&o){if(playFlag)pause(o);}
 void resume(const Owner&,const Snapshot&s){
  ++resumes;calls.push_back("Seek");calls.push_back("PlayScheduled");sound=true;playFlag=true;
  if(resumeFailures){--resumeFailures;throw std::runtime_error("partial resume");}
  calls.push_back("restore flags");state=s;
 }
 bool blocking(){if(uiBlocking&&(!playingGuard||!playingGuard()))invalidate();return uiBlocking;}
 bool trigger(std::function<bool()>freeze,std::function<void()>quit){
  ++triggers;if(denyTrigger)return false;
  freezeCallback=freeze;quitCallback=quit;
  if(!freeze()){invalidate();return false;}
  if(failPresentation){invalidate();return false;}
  uiBlocking=true;return true;
 }
 void quit(){++quits;}
 void error(const char*,const char*){}
};
struct Run {
 FakeHost h;songinterruption::Gameplay<FakeHost> g{h};
 void bind(){h.arm();assert(g.begin(1,11,std::string("installed-OS"),3));}
 bool frame(Entry e=Entry::Progress,int self=11){return g.tick(e,self);}
};

int main(){int groups=0;
 {Run r;assert(!r.g.begin(1,11,std::string("ordinary"),3));assert(!r.frame());assert(r.h.roots==0);++groups;}
 {Run r;r.h.arm();assert(!r.g.begin(1,11,std::string("wrong-installed-chart"),3));assert(!r.h.pending());assert(!r.frame());++groups;}
 {Run r;r.h.arm();assert(!r.g.begin(1,11,std::string("installed-OS"),2));assert(!r.h.pending());++groups;}
 {Run r;r.h.arm();r.h.cancel();assert(!r.g.begin(1,11,std::string("installed-OS"),3));assert(!r.frame());++groups;}
 {Run r;r.bind();r.h.state.now=158.99f;assert(!r.frame());assert(r.h.pauses==0);r.h.state.now=NAN;assert(!r.frame());++groups;}
 {Run r;r.bind();r.h.state.now=159;assert(r.frame());assert(r.h.pauses==1&&r.h.protects==1);assert(!r.h.sound);assert(!r.h.state.canPause&&!r.h.state.canOver&&r.h.state.stopJudge&&!r.h.state.playing);
  assert(r.h.state.now==159&&r.h.state.audio==159.1f&&r.h.state.wrapper==159.2f);assert(r.h.calls[0]=="capture"&&r.h.calls[1]=="protect");
  for(int n=0;n<6;++n){assert(r.frame());assert(r.frame(Entry::Judge,12));assert(r.frame(Entry::Audio,13));assert(r.frame(Entry::Notes,14));}
  assert(r.h.pauses==1&&r.h.triggers==1);++groups;}
 {Run r;r.bind();assert(!r.frame(Entry::Progress,21));assert(!r.frame(Entry::Judge,22));assert(!r.frame(Entry::Audio,23));assert(!r.frame(Entry::Notes,24));assert(r.h.triggers==0);++groups;}
 {Run r;r.bind();r.h.ready=false;assert(!r.frame());r.h.ready=true;r.h.state.playing=false;assert(!r.frame());assert(r.h.pauses==0);++groups;}
 {Run r;r.bind();assert(!r.frame(Entry::Judge,12));assert(r.h.triggers==0);assert(r.frame(Entry::Progress,11));assert(r.frame(Entry::Judge,12));assert(r.h.triggers==1);++groups;}
 {Run r;r.bind();assert(!r.frame(Entry::Audio,13));assert(!r.frame(Entry::Notes,14));assert(r.h.triggers==0);assert(r.frame());assert(r.frame(Entry::Audio,13));assert(r.frame(Entry::Notes,14));assert(r.h.triggers==1);++groups;}
 {Run r;r.bind();assert(r.frame());r.h.state.canPause=true;r.g.fence();assert(!r.h.state.canPause);++groups;}
 {Run r;r.bind();r.h.denyTrigger=true;assert(!r.frame());assert(r.h.pauses==0&&r.h.roots==2);r.h.denyTrigger=false;assert(r.frame());assert(r.h.pauses==1);++groups;}
 {Run r;r.bind();r.h.failCapture=true;assert(!r.frame());assert(r.h.pauses==0&&r.h.resumes==0&&r.h.roots==0);assert(r.h.sound);++groups;}
 {Run r;r.bind();r.h.failHold=true;assert(!r.frame());assert(r.h.resumes==1&&r.h.sound&&r.h.state.playing);assert(r.h.roots==0);++groups;}
 {Run r;r.bind();r.h.failPause=true;assert(!r.frame());assert(r.h.resumes==1&&r.h.sound&&r.h.state.playing);assert(r.h.protects==1&&r.h.roots==0);++groups;}
 {Run r;r.bind();r.h.failPresentation=true;assert(!r.frame());assert(r.h.resumes==1&&r.h.sound&&r.h.state.playing&&r.h.state.canPause);assert(r.h.calls[r.h.calls.size()-3]=="Seek"&&r.h.calls[r.h.calls.size()-2]=="PlayScheduled");assert(r.h.roots==0);++groups;}
 {Run r;r.bind();r.h.failPresentation=true;r.h.resumeFailures=2;assert(r.frame());assert(!r.h.sound&&r.g.holding());assert(r.frame(Entry::Judge,12));assert(!r.h.sound&&r.g.holding());assert(!r.frame());assert(r.h.sound&&r.h.state.playing&&!r.g.holding()&&r.h.roots==0);++groups;}
 {Run r;r.bind();assert(r.frame());auto lateQuit=r.h.quitCallback,lateInvalidated=r.h.playingInvalidation;auto lateFreeze=r.h.freezeCallback;
  r.g.end();assert(r.h.roots==0&&!r.g.holding());lateQuit();lateInvalidated();assert(!lateFreeze());assert(r.h.quits==0&&r.h.resumes==0);++groups;}
 {Run r;r.bind();assert(r.frame());auto oldQuit=r.h.quitCallback,oldInvalidated=r.h.playingInvalidation;auto oldGuard=r.h.playingGuard;
  r.h.arm();r.g.awake();assert(r.h.pending());r.h.currentLevel=2;r.h.currentScene=8;r.h.state=FakeHost::Snapshot{};
  assert(r.g.begin(2,21,std::string("installed-OS"),3));oldQuit();oldInvalidated();assert(!oldGuard());assert(r.h.resumes==0&&r.h.roots==2);
  assert(r.frame(Entry::Progress,21));assert(r.h.quits==0&&r.h.pauses==2);++groups;}
 {Run r;r.bind();assert(r.frame());r.h.currentLevel=2;assert(!r.frame());assert(r.h.resumes==0&&r.h.quits==0&&r.h.roots==0);++groups;}
 {Run r;r.bind();assert(r.frame());r.g.unloaded(999);assert(r.g.holding());r.g.unloaded(7);assert(!r.g.holding()&&r.h.roots==0&&r.h.resumes==0);++groups;}
 {Run r;r.bind();assert(r.frame());auto quit=r.h.quitCallback;quit();quit();assert(r.h.quits==1);assert(r.frame());++groups;}
 {Run r;r.bind();assert(r.frame());auto invalidated=r.h.playingInvalidation;r.h.invalidate();invalidated();assert(r.h.resumes==1&&r.h.roots==0);++groups;}
 {Run r;r.h.failAcquire=true;r.h.arm();assert(!r.g.begin(1,11,std::string("installed-OS"),3));assert(r.h.roots==0&&!r.h.uiPlaying);++groups;}
 {Run r;r.bind();assert(r.frame());assert(r.h.pauses==1);
  r.h.playFlag=true;r.h.sound=true;r.h.state.playing=true;r.h.state.canPause=true;r.h.state.canOver=true;r.h.state.stopJudge=false;
  r.h.state.now=170;r.h.state.wrapper=170;
  assert(r.frame(Entry::Audio,13));assert(r.h.pauses==2&&!r.h.playFlag&&!r.h.sound);
  assert(!r.h.state.playing&&!r.h.state.canPause&&!r.h.state.canOver&&r.h.state.stopJudge);
  assert(r.h.state.now==159&&r.h.state.wrapper==159.2f);
  for(int n=0;n<10;++n)assert(r.frame(Entry::Audio,13));assert(r.h.pauses==2);++groups;}
 // Pre-threshold hot hooks: not even identity field reads or scene queries.
 {Run r;r.bind();r.h.state.now=158.99f;const auto before=r.h.probes();
  for(int n=0;n<1000;++n){assert(!r.frame(Entry::Judge,12));assert(!r.frame(Entry::Audio,13));assert(!r.frame(Entry::Notes,14));}
  assert(r.h.probes()==before&&r.h.triggers==0&&r.h.captures==0);
  // Progress remains the sole trigger discovery point even at the threshold.
  r.h.state.now=159;assert(!r.frame(Entry::Judge,12));assert(r.h.probes()==before);assert(r.frame());++groups;}
 // Emulate the existing pre/original/post Progress hook ordering, not a frame cache.
 {for(float crossing:{159.f,159.125f}){
   Run r;r.bind();r.h.state.now=158.99f;int nativeProgress=0,futureJudgments=0,futureAudio=0,futureNotes=0;
   assert(!r.frame(Entry::Progress,11)); // Before native: threshold not reached.
   ++nativeProgress;r.h.state.now=crossing; // Native clock's FIRST >=159 sample.
   assert(r.frame(Entry::Progress,11)); // After native: freeze synchronously.
   assert(nativeProgress==1&&r.h.pauses==1&&r.h.state.now==crossing);
   if(!r.frame(Entry::Judge,12))++futureJudgments;
   if(!r.frame(Entry::Audio,13))++futureAudio;
   if(!r.frame(Entry::Notes,14))++futureNotes;
   assert(futureJudgments==0&&futureAudio==0&&futureNotes==0);
   assert(r.h.triggers==1&&r.h.state.now==crossing);
  }++groups;}
 // Fast path must NOT weaken exact identity or scene validation once held.
 {Run r;r.bind();assert(r.frame());auto before=r.h.probes();
  assert(!r.frame(Entry::Judge,22));assert(!r.frame(Entry::Audio,23));assert(!r.frame(Entry::Notes,24));
  assert(r.h.matchReads==before[0]+3&&r.h.liveReads==before[1]&&r.g.holding());
  before=r.h.probes();assert(r.frame(Entry::Judge,12));assert(r.frame(Entry::Audio,13));assert(r.frame(Entry::Notes,14));
  assert(r.h.matchReads==before[0]+3&&r.h.liveReads>before[1]);
  r.h.currentScene=8;assert(!r.frame(Entry::Judge,12));assert(!r.g.holding()&&r.h.roots==0&&r.h.resumes==0);++groups;}
 std::cout<<groups<<" native gameplay groups passed\n";
}
