#pragma once
#include "PMRPECore.hpp"
namespace phimod {
// The parsed track is immutable for one chart. No rounding, horizon, skipped
// frame or visibility decision is introduced; backward seeks are new samples.
struct CachedRPETrack {
 std::vector<rpe::Event> events;
 bool sampled=false;double sampleTime=0,sampleValue=0;
 double value(double now,double fallback){
  // Fallback belongs to the caller, not the track: never cache it.
  if(events.empty()||now<events.front().s)return fallback;
  if(sampled&&now==sampleTime)return sampleValue;
  auto event=std::upper_bound(events.begin(),events.end(),now,[](double time,const auto&e){return time<e.s;});
  if(event==events.begin())return fallback;
  sampleValue=(event-1)->value(now);sampleTime=now;sampled=true;return sampleValue;
 }
};
}
