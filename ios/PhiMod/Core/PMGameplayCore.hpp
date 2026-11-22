#pragma once
// Ported from native/mod.cpp, practice.inc, auto_hold_score.inc and noise_union.h.
// Pure C++17: no JNI, Android addresses, Unity pointers or executable-memory writes.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

namespace phimod {
enum class Rating : int { Perfect=0, Good=1, Bad=2, Miss=3 };
enum class Phase { Idle, Playing, Result };
enum class Action { None, Retry, TrackLost };
struct Windows { float perfect=.08f, good=.18f, bad=.22f; };
struct Options {
 bool judge=false, autoplay=false, noise=false, clearNoise=false;
 bool fullscreen=false, accuracyDisplay=false, noComboScore=false, hpEnabled=false;
 bool noiseVisual=true, hpTop=true, hpBackground=true;
 bool practiceMode=false,practiceLoop=true,practiceCountdown=false;
 int unified=0, challenge=0;
 float perfectMs=80,goodMs=180,radius=1,holdGraceMs=100,holdFxMs=150,noiseGraceMs=250;
 float playbackRate=1,practiceStart=0,practiceEnd=-1,practicePosition=0;
 float hpMax=200; std::array<float,4> hpDelta{1,-4,-16,-25};
 float hpRed=.3f,hpBlue=.6f;
 bool allowsDoorChallenge() const { return !autoplay && !practiceMode && std::fabs(playbackRate-1.f)<=.0001f; }
 bool assisted() const { return judge||autoplay||noise||clearNoise||fullscreen||accuracyDisplay||noComboScore||unified!=0||hpEnabled||challenge!=0||practiceMode||std::fabs(playbackRate-1.f)>.0001f; }
 bool requiresSaveProtection() const { return judge||autoplay||clearNoise||fullscreen||noComboScore||unified!=0||practiceMode||std::fabs(playbackRate-1.f)>.0001f; }
 void validate() const {
  auto range=[](float n,float a,float b){return std::isfinite(n)&&n>=a&&n<=b;};
  if(!range(perfectMs,1,1000)||!range(goodMs,perfectMs,2000)||!range(radius,.3f,3)||
     !range(holdGraceMs,0,500)||!range(holdFxMs,100,2000)||!range(noiseGraceMs,0,1500)||
     unified<0||unified>4||challenge<0||challenge>2||!range(playbackRate,0,5)||
     !range(practiceStart,0,100000)||!range(practicePosition,0,100000)||(!range(practiceEnd,0,100000)&&practiceEnd!=-1)||
     (practiceEnd>=0&&practiceEnd<=practiceStart)||!range(hpMax,1,10000)||
     !range(hpRed,0,1)||!range(hpBlue,hpRed,1))throw std::invalid_argument("Invalid gameplay options");
  for(float d:hpDelta)if(!range(d,-10000,10000))throw std::invalid_argument("Invalid HP delta");
 }
};
// Backend supplies verified coverage. A UI setting is never evidence of hook readiness.
struct Coverage {
 bool frame=false, lifecycle=false, recordUpdate=false, recordSet=false;
 bool ranking=false, persistence=false, result=false;
 bool safe() const {return frame&&lifecycle&&recordUpdate&&recordSet&&ranking&&persistence&&result;}
};
struct Sample {float time,offsetMs;int type;Rating rating;};
struct Note {float code,time,duration;int type;bool fake=false;};
struct DeferredHold {float end,offset;std::array<float,3> position;bool hold;};
struct HoldCredit {float code,offset;std::array<float,3> position;bool hold;};

class Session {
 Phase phase_=Phase::Idle;
 Coverage coverage_{};
 Options requested_{},active_{};
 Windows baseline_{};
 bool excluded_=false,lost_=false,retry_=false,failed_=false,lostDispatched_=false;
 float hp_=200;
 std::uint64_t serial_=0;
 std::map<float,Note> notes_;
 std::set<float> sampled_,credited_;
 std::map<float,DeferredHold> pending_;
 std::vector<Sample> samples_;
 std::size_t dropped_=0;
 static constexpr std::size_t sampleLimit=200000;
 static bool finiteWindows(Windows w){return std::isfinite(w.perfect)&&std::isfinite(w.good)&&std::isfinite(w.bad)&&w.perfect>0&&w.good>=w.perfect&&w.bad>=w.good;}
 public:
 void setCoverage(Coverage coverage) {
  if(phase_!=Phase::Idle)throw std::logic_error("Cannot change backend coverage during an attempt/result");
  coverage_=coverage;
 }
 void request(const Options &o) {o.validate();requested_=o;}
 bool begin(Windows baseline) {
  if(phase_!=Phase::Idle)throw std::logic_error("Finish previous attempt and result first");
  if(!finiteWindows(baseline))throw std::invalid_argument("Invalid engine baseline");
  if(requested_.assisted()&&!coverage_.safe())return false;
  baseline_=baseline;active_=requested_;phase_=Phase::Playing;serial_++;
  excluded_=active_.requiresSaveProtection();lost_=retry_=failed_=lostDispatched_=false;hp_=active_.hpMax;
  notes_.clear();sampled_.clear();credited_.clear();pending_.clear();samples_.clear();dropped_=0;
  return true;
 }
 bool sync() {
  if(phase_!=Phase::Playing||failed_)return false;
  if(requested_.assisted()&&!coverage_.safe())return false;
  if(requested_.requiresSaveProtection())excluded_=true; // cannot unlatch protection during an active attempt
  if(requested_.hpEnabled&&!active_.hpEnabled){hp_=requested_.hpMax;lost_=lostDispatched_=false;}
  else if(requested_.hpMax!=active_.hpMax)hp_=std::clamp(hp_/active_.hpMax*requested_.hpMax,0.f,requested_.hpMax);
  active_=requested_;return true;
 }
 Windows windows() const {
  if(!active_.judge||phase_!=Phase::Playing||failed_)return baseline_;
  float g=active_.goodMs/1000.f;
  return {active_.perfectMs/1000.f,g,std::max(baseline_.bad,g+.04f)};
 }
 void registerNote(Note n) {
  if(phase_!=Phase::Playing)throw std::logic_error("No active attempt");
  if(!std::isfinite(n.code)||!std::isfinite(n.time)||!std::isfinite(n.duration)||n.duration<0||n.type<1||n.type>4)
   throw std::invalid_argument("Invalid note");
  if(!notes_.emplace(n.code,n).second)throw std::invalid_argument("Duplicate note code");
 }
 int noteType(float code) const {
  if(!std::isfinite(code))return 0;
  auto it=notes_.find(code);
  return it==notes_.end()?0:it->second.type;
 }
 bool observe(float code,float offsetSeconds,Rating rating) {
  int index=static_cast<int>(rating);
  if(phase_!=Phase::Playing||failed_||!std::isfinite(code)||(!std::isfinite(offsetSeconds)||!std::isfinite(offsetSeconds*1000.f))||index<0||index>3)return false;
  auto found=notes_.find(code);
  if(found==notes_.end()||found->second.fake||!sampled_.insert(code).second)return false;
  if(samples_.size()<sampleLimit)samples_.push_back({found->second.time,offsetSeconds*1000,found->second.type,rating});else ++dropped_;
  if(active_.hpEnabled&&!lost_){hp_=std::clamp(hp_+active_.hpDelta[index],0.f,active_.hpMax);if(hp_<=0)lost_=true;}
  if((active_.challenge==1&&rating!=Rating::Perfect)||(active_.challenge==2&&index>=2))retry_=true;
  return true;
 }
 // Peek does not consume a failure/retry before Unity accepts the coroutine.
 Action pendingAction(bool playing,bool leaving,bool breaking) const {
  if(phase_!=Phase::Playing||failed_||leaving||breaking)return Action::None;
  if(lost_)return playing&&!lostDispatched_?Action::TrackLost:Action::None;
  return retry_?Action::Retry:Action::None;
 }
 void acknowledgeAction(Action action) {
  if(action==Action::TrackLost)lostDispatched_=true;
  if(action==Action::Retry){retry_=false;if(active_.requiresSaveProtection())excluded_=true;}
 }
 Action takeAction(bool playing,bool leaving,bool breaking) {
  Action action=pendingAction(playing,leaving,breaking);acknowledgeAction(action);return action;
 }
 // Only queues score credit, not note animation or synthetic Unity touches.
 bool deferHold(float code,float offset,std::array<float,3> position,bool hold,float now) {
  if(phase_!=Phase::Playing||failed_||!std::isfinite(code)||!std::isfinite(now)||!std::isfinite(offset))return false;
  for(float v:position)if(!std::isfinite(v))return false;
  if(credited_.count(code)||pending_.count(code))return true;
  if(!active_.autoplay)return false;
  auto it=notes_.find(code);
  if(it==notes_.end()||it->second.fake||it->second.type!=3)return false;
  float end=it->second.time+it->second.duration;
  if(!std::isfinite(end)||now>=end)return false;
  pending_[code]={end,offset,position,hold};return true;
 }
 std::vector<HoldCredit> dueHolds(float now,bool playing) {
  std::vector<HoldCredit> out;
  (void)playing;
  if(phase_!=Phase::Playing||failed_||!std::isfinite(now))return out;
  for(auto it=pending_.begin();it!=pending_.end();) {
   if(now<it->second.end){++it;continue;}
   if(credited_.insert(it->first).second)out.push_back({it->first,it->second.offset,it->second.position,it->second.hold});
   it=pending_.erase(it);
  }
  return out; // backend must dispatch each once on game frame and root managed targets
 }
  // Result can start after ProgressControl stops advancing time.  Android's
  // score path has already reached the real hold tail by then, so the iOS
  // result hook must drain the remaining queue without waiting on nowTime.
  std::vector<HoldCredit> flushPendingHolds() {
   std::vector<HoldCredit> out;
   if(phase_!=Phase::Playing||failed_)return out;
   for(auto it=pending_.begin();it!=pending_.end();) {
    if(credited_.insert(it->first).second)out.push_back({it->first,it->second.offset,it->second.position,it->second.hold});
    it=pending_.erase(it);
   }
   return out;
  }
 bool creditOnce(float code) {
  if(phase_!=Phase::Playing||failed_||!std::isfinite(code))return false;
  auto note=notes_.find(code);if(note==notes_.end()||note->second.fake)return false;
  if(pending_.count(code))return false;
  return credited_.insert(code).second;
 }
 void result() {if(phase_==Phase::Playing)phase_=Phase::Result;}
 void failClosed() {if(phase_!=Phase::Idle){excluded_=true;failed_=true;}}
 void restartSegment() {
  if(phase_!=Phase::Playing||failed_)throw std::logic_error("No active practice segment");
  lost_=retry_=lostDispatched_=false;hp_=active_.hpMax;
  notes_.clear();sampled_.clear();credited_.clear();pending_.clear();samples_.clear();dropped_=0;
 }
 // Called only after all result coroutines/record writes complete, not LevelControl.OnDestroy.
 void finishResult() {
  if(phase_!=Phase::Result)throw std::logic_error("Result completion required before releasing save guard");
  phase_=Phase::Idle;excluded_=false;failed_=false;pending_.clear();
 }
 bool allowRecordWrite() const {return !excluded_&&!failed_;}
 bool shouldApplyGameplay() const {return phase_==Phase::Playing&&coverage_.safe()&&!failed_;}
 Phase phase() const {return phase_;}
 bool excluded() const {return excluded_;}
 void seedTrackHP(float value){hp_=std::clamp(value,0.f,active_.hpMax);}
 float hp() const {return hp_;}
 bool trackLost() const {return lost_;}
 std::uint64_t serial() const {return serial_;}
 const Options &options() const {return active_;}
 const std::vector<Sample> &samples() const {return samples_;}
 std::size_t droppedSamples() const {return dropped_;}
};
inline float accuracyScore(int perfect,int good,int total) {
 if(total<=0||perfect<0||good<0||static_cast<std::int64_t>(perfect)+good>total)throw std::invalid_argument("Invalid accuracy counts");
 return 1000000.f*(perfect+.65f*good)/total;
}
inline int convertedNoteType(int original,int unified) {
 if(original<1||original>4||unified<0||unified>4)throw std::invalid_argument("Invalid note type");
 return unified?unified:original;
}
struct Rect {float left,bottom,right,top;};
inline std::vector<Rect> noiseUnion(const std::vector<Rect> &input) {
 std::vector<Rect> valid;std::vector<float> edges;
 for(auto r:input){
  if(!std::isfinite(r.left)||!std::isfinite(r.bottom)||!std::isfinite(r.right)||!std::isfinite(r.top))throw std::invalid_argument("Nonfinite noise geometry");
  if(r.right<=r.left||r.top<=r.bottom)continue;
  valid.push_back(r);edges.push_back(r.left);edges.push_back(r.right);
 }
 std::sort(edges.begin(),edges.end());edges.erase(std::unique(edges.begin(),edges.end()),edges.end());
 std::vector<Rect> result;
 for(std::size_t i=1;i<edges.size();++i){
  float l=edges[i-1],r=edges[i];std::vector<std::pair<float,float>> intervals,merged;
  for(auto h:valid)if(h.left<r&&h.right>l)intervals.push_back({h.bottom,h.top});
  std::sort(intervals.begin(),intervals.end());
  for(auto y:intervals){if(!merged.empty()&&y.first<=merged.back().second)merged.back().second=std::max(merged.back().second,y.second);else merged.push_back(y);}
  for(auto y:merged){bool extended=false;for(auto it=result.rbegin();it!=result.rend();++it){if(it->right==l&&it->bottom==y.first&&it->top==y.second){it->right=r;extended=true;break;}}if(!extended)result.push_back({l,y.first,r,y.second});}
 }
 return result;
}

struct AutoPlan {
 enum class Kind { Original, Wait, Assisted };
 Kind kind=Kind::Original;
 bool markJudged=false,markFlick=false,holdPerfect=false;
 bool replaceClock=false;
 float temporaryClock=0;
 int safeFrames=0;
};
inline AutoPlan autoPlan(bool enabled,bool fake,bool playing,bool hold,bool headJudged,float now,float time) {
 if(!std::isfinite(now)||!std::isfinite(time))throw std::invalid_argument("Invalid note timing");
 AutoPlan plan;
 if(!enabled||fake||!playing)return plan;
 if(now<time){plan.kind=AutoPlan::Kind::Wait;return plan;}
 plan.kind=AutoPlan::Kind::Assisted;plan.markJudged=plan.markFlick=true;
 plan.holdPerfect=hold;plan.safeFrames=hold?2:0;
 plan.replaceClock=!(hold&&headJudged);plan.temporaryClock=time+.0001f;
 return plan;
}
class HoldGrace {
 std::map<float,float> lastTouch_;
 public:
 void clear(){lastTouch_.clear();}
 void retire(float code){lastTouch_.erase(code);}
 bool inject(float code,float now,float noteX,const std::vector<float> &fingers,float graceSeconds,bool fullscreen) {
  if(!std::isfinite(code)||!std::isfinite(now)||!std::isfinite(noteX)||!std::isfinite(graceSeconds)||graceSeconds<0||graceSeconds>.5f)
   throw std::invalid_argument("Invalid Hold grace input");
  bool touching=false;
  for(float x:fingers){if(!std::isfinite(x))continue;if(fullscreen||std::fabs(x-noteX)<=1.5f){touching=true;break;}}
  if(touching){lastTouch_[code]=now;return false;}
  auto it=lastTouch_.find(code);
  if(it==lastTouch_.end())return false;
  if(now<it->second){lastTouch_.erase(it);return false;} // rewind cannot inherit an old touch
  return !fingers.empty()&&graceSeconds>0&&now-it->second<=graceSeconds;
 }
};
struct SpatialOverride {float code,originalX,replacementX;};
inline std::vector<SpatialOverride> fullScreenOverrides(const std::vector<Note> &notes,const std::map<float,float> &positions,
                                                       float now,float fingerX,bool enabled) {
 if(!std::isfinite(now)||!std::isfinite(fingerX))throw std::invalid_argument("Invalid full-screen touch");
 std::vector<SpatialOverride> result;if(!enabled)return result;
 for(auto note:notes){if(note.fake||!std::isfinite(note.time)||std::fabs(note.time-now)>.5f)continue;
  auto old=positions.find(note.code);if(old!=positions.end()&&std::isfinite(old->second))result.push_back({note.code,old->second,fingerX});}
 return result; // backend must scope restoration to the single original CheckNote/CheckFlick call
}
struct Color {float r,g,b,a;};
inline Color practiceColor(const Options &o) {
 if(o.autoplay)return {.25f,.9f,1,1};
 if(o.unified)return {.72f,.4f,1,1};
 if(o.noise||o.clearNoise)return {1,.12f,.16f,1};
 return {1,.48f,.12f,1};
}
} // namespace phimod
