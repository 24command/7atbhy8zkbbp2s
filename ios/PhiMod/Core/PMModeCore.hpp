#pragma once
#include "PMGameplayCore.hpp"
#include <limits>
#include <utility>
namespace phimod {
struct UnifiedNote {int type;float speed,holdTicks;};
inline UnifiedNote unifiedNote(int old,int target,float speed,float hold,float lineSpeed,float bpm) {
 convertedNoteType(old,target);
 if(!std::isfinite(speed)||!std::isfinite(hold)||!std::isfinite(lineSpeed)||!std::isfinite(bpm)||bpm<=0)
  throw std::invalid_argument("Invalid chart conversion input");
 if(!target||old==target)return {old,speed,hold};
 if(old==3&&std::fabs(lineSpeed)>.00001f)speed/=lineSpeed;
 if(target==3){speed*=lineSpeed;if(hold<=0)hold=std::max(1.f,bpm*.1f*32.f/60.f);}else hold=0;
 if(!std::isfinite(speed)||!std::isfinite(hold))throw std::invalid_argument("Chart conversion overflow");
 return {target,speed,hold};
}
struct Hole {float x,y,w,h;};
inline bool inside(Hole h,float x,float y){return std::fabs(x-h.x)<=h.w&&std::fabs(y-h.y)<=h.h;}
class NoiseHoles {
 struct Entry {Hole hole{};std::vector<std::pair<Hole,float>> history;float expiry=-std::numeric_limits<float>::infinity();std::uint64_t frame=0;};
 std::map<float,Entry> entries_;
 std::vector<Hole> active_;
 std::vector<Hole> published_;
 std::uint64_t frame_=0;
 std::uint64_t geometryRevision_=0;
 float now_=0;
 static bool sameGeometry(const std::vector<Hole>&a,const std::vector<Hole>&b){
  if(a.size()!=b.size())return false;
  for(std::size_t i=0;i<a.size();++i){
   if(a[i].x!=b[i].x||a[i].y!=b[i].y||a[i].w!=b[i].w||a[i].h!=b[i].h)return false;
  }
  return true;
 }
 public:
 void clear(){entries_.clear();active_.clear();published_.clear();frame_=0;geometryRevision_=0;now_=0;}
 void begin(float now){if(!std::isfinite(now))throw std::invalid_argument("Invalid noise clock");if(now<now_)clear();now_=now;++frame_;active_.clear();}
 void visible(float code,Hole hole,bool hold,float grace){
  if(!std::isfinite(code)||!std::isfinite(hole.x)||!std::isfinite(hole.y)||!std::isfinite(hole.w)||!std::isfinite(hole.h)||hole.w<=0||hole.h<=0||!std::isfinite(grace)||grace<0||grace>.5f)
   throw std::invalid_argument("Invalid noise hole");
  auto found=entries_.find(code);
  if(found==entries_.end()&&entries_.size()>=200000)throw std::runtime_error("Noise note limit");
  auto &e=entries_[code];
  if(hold&&grace>0&&e.frame&&(std::fabs(e.hole.x-hole.x)>std::max(.5f,hole.w*.35f)||std::fabs(e.hole.y-hole.y)>std::max(.5f,hole.h*.35f))){
   e.history.push_back({e.hole,now_+grace});if(e.history.size()>2)e.history.erase(e.history.begin());
  }
  e.hole=hole;e.frame=frame_;
 }
 void completed(float code,float now,float grace){
  if(!std::isfinite(now)||!std::isfinite(grace)||grace<0||grace>1.5f)throw std::invalid_argument("Invalid noise grace");
  auto it=entries_.find(code);if(it!=entries_.end())it->second.expiry=now+grace;
 }
 void end(){
  std::vector<Hole> next;
  for(auto it=entries_.begin();it!=entries_.end();){auto&e=it->second;
   e.history.erase(std::remove_if(e.history.begin(),e.history.end(),[&](const auto&h){return h.second<now_;}),e.history.end());
   bool current=e.frame==frame_||e.expiry>=now_;
   if(current)next.push_back(e.hole);
   for(auto h:e.history)next.push_back(h.first);
   if(!current&&e.history.empty())it=entries_.erase(it);else ++it;
  }
  active_=std::move(next);
  if(!sameGeometry(active_,published_)){published_=active_;++geometryRevision_;}
 }
 bool allows(float x,float y)const{for(auto h:active_)if(inside(h,x,y))return true;return false;}
 const std::vector<Hole>&active()const{return active_;}
 std::uint64_t geometryRevision()const{return geometryRevision_;}
 std::vector<Rect> masks(float width,float height)const{
  if(!std::isfinite(width)||!std::isfinite(height)||width<=0||height<=0)throw std::invalid_argument("Invalid noise viewport");
  std::vector<Rect> rectangles;rectangles.reserve(active_.size());
  for(auto h:active_){Rect r{std::max(-width/2,h.x-h.w),std::max(-height/2,h.y-h.h),std::min(width/2,h.x+h.w),std::min(height/2,h.y+h.h)};if(r.right>r.left&&r.top>r.bottom)rectangles.push_back(r);}
  return noiseUnion(rectangles);
 }
};
class HoldFxClock {
 std::map<float,float> times_;
 public:
 void clear(){times_.clear();}
 void retire(float code){times_.erase(code);}
 bool pulse(float code,float now,float start,float interval){
  if(!std::isfinite(code)||!std::isfinite(now)||!std::isfinite(start)||!std::isfinite(interval)||interval<.1f||interval>2)
   throw std::invalid_argument("Invalid Hold FX clock");
  auto inserted=times_.emplace(code,start);auto&last=inserted.first->second;
  if(now<last){last=now;return false;}
  if(now-last>=interval){last=now;return true;}return false;
 }
};
}
