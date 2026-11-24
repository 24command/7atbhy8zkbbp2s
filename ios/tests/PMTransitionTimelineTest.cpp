// The Python runner extracts the actual private core from PMUnlockMedia.mm.
#include <cmath>
#include <cstdio>
#include <limits>
#include <cstdlib>
#include "PMTransitionTimelineUnderTest.hpp"
using namespace PMHeldTransition;
static unsigned checks=0;
#define CHECK(x) do { ++checks; if(!(x)){std::fprintf(stderr,"line %d: %s\n",__LINE__,#x);std::exit(1);} } while(0)
static bool near(double a,double b){return std::fabs(a-b)<0.000001;}
static Timeline code(double end=2,double gate=-1){Timeline t(false,end,gate);t.advance(0,true,0);return t;}
static Timeline video(double duration=0,double gate=-1,double natural=3){
 Timeline t(true,duration,gate);t.naturalEnd(natural);t.advance(0,true,0);return t;
}
int main(){
 { // Code final-frame hold: no time or completion while loading.
  auto t=code();CHECK(t.advance(.25,true,0)==Event::None);CHECK(near(t.time,.25));
  CHECK(t.advance(4,true,0)==Event::Load);CHECK(near(t.time,2));CHECK(t.atEnd);
  CHECK(t.advance(30,true,0)==Event::None);CHECK(near(t.time,2));
  CHECK(t.resume(true)==Event::Complete);CHECK(t.succeeded);
  CHECK(t.resume(false)==Event::None);CHECK(t.finish(false)==Event::None);CHECK(t.succeeded);
 }
 { // Code midpoint clamps the sample, then plays only the remainder.
  auto t=code(2,.5);CHECK(t.advance(.75,true,0)==Event::Load);CHECK(near(t.time,.5));
  CHECK(!t.atEnd);CHECK(t.resume(true)==Event::None);CHECK(t.phase==Phase::Playing);
  CHECK(t.resume(false)==Event::None);CHECK(t.advance(.75,true,0)==Event::None);
  CHECK(near(t.time,1.25));CHECK(t.advance(.75,true,0)==Event::Complete);CHECK(t.succeeded);
 }
 { // Zero and past-end load boundaries are deterministic.
  auto t=code(2,0);CHECK(t.phase==Phase::Holding);CHECK(!t.atEnd);CHECK(near(t.time,0));
  CHECK(t.resume(true)==Event::None);CHECK(t.advance(2,true,0)==Event::Complete);
  auto past=code(2,99);CHECK(past.advance(5,true,0)==Event::Load);
  CHECK(near(past.time,2));CHECK(past.atEnd);CHECK(past.resume(true)==Event::Complete);
  auto empty=code(0,-1);CHECK(empty.phase==Phase::Holding);CHECK(empty.atEnd);
  CHECK(empty.resume(true)==Event::Complete);
 }
 { // Natural duration, optional cutoff, and videos shorter than the cutoff.
  auto t=video();CHECK(near(t.end,3));CHECK(t.advance(1,true,1)==Event::None);
  CHECK(t.advance(2,true,3,true)==Event::Load);CHECK(near(t.time,3));CHECK(t.atEnd);
  CHECK(t.resume(true)==Event::Complete);CHECK(t.succeeded);
  auto cutoff=video(1.5,-1,10);CHECK(near(cutoff.stop(),1.5));
  CHECK(cutoff.advance(2,true,1.5,true)==Event::Load);CHECK(near(cutoff.time,1.5));
  CHECK(cutoff.resume(true)==Event::Complete);
  auto shortVideo=video(10,-1,2);CHECK(near(shortVideo.end,2));
  CHECK(shortVideo.advance(2,true,2,true)==Event::Load);CHECK(shortVideo.atEnd);
 }
 { // AVPlayer is stopped at loadAt, not treated as a natural video end.
  auto t=video(0,1,3);CHECK(near(t.stop(),1));
  CHECK(t.advance(1,true,1,false)==Event::Load);CHECK(!t.atEnd);
  CHECK(t.resume(true)==Event::None);CHECK(near(t.stop(),3));
  CHECK(t.advance(1,true,2)==Event::None);CHECK(t.advance(1,true,3,true)==Event::Complete);
  CHECK(t.succeeded);
 }
 { // Unknown duration can finish by notification, including after a midpoint.
  auto t=video(0,-1,-1);CHECK(t.end<0);CHECK(t.advance(7,true,7,true)==Event::Load);
  CHECK(near(t.end,7));CHECK(t.atEnd);CHECK(t.resume(true)==Event::Complete);
  auto mid=video(0,.5,-1);CHECK(mid.advance(.5,true,.5)==Event::Load);
  CHECK(mid.resume(true)==Event::None);CHECK(mid.stop()<0);
  CHECK(mid.advance(4,true,4.5,true)==Event::Complete);CHECK(mid.succeeded);
 }
 { // Missing/failed decode still requests load once, but can never succeed.
  Timeline t(true,0,-1);CHECK(t.fail()==Event::Load);CHECK(t.failed);
  CHECK(t.fail()==Event::None);CHECK(t.advance(12,false,0)==Event::None);
  CHECK(t.fail()==Event::None);CHECK(near(t.waiting,12));
  CHECK(t.resume(true)==Event::Complete);CHECK(!t.succeeded);
  CHECK(t.resume(true)==Event::None);CHECK(t.fail()==Event::None);
 }
 { // A failure during an existing load preserves its deadline and single request.
  auto t=video(0,1,3);CHECK(t.advance(1,true,1)==Event::Load);
  CHECK(t.advance(40,true,1)==Event::None);CHECK(t.fail()==Event::None);
  CHECK(near(t.waiting,40));CHECK(t.advance(20,true,1)==Event::Complete);
  CHECK(!t.succeeded);CHECK(t.resume(true)==Event::None);
  auto no=code(2,1);no.advance(1,true,0);CHECK(no.resume(false)==Event::Complete);
  CHECK(!no.succeeded);CHECK(no.advance(2,true,0)==Event::None);
 }
 { // Decoder timeout, including first-frame-not-ready, is bounded.
  Timeline t(true,0,-1);CHECK(t.advance(DecodeTimeout-.1,false,0)==Event::None);
  CHECK(t.advance(.2,false,0)==Event::Load);CHECK(t.failed);
  CHECK(t.resume(false)==Event::Complete);CHECK(!t.succeeded);
 }
 { // Stalls before and after load are failures, without a second load.
  auto t=video();CHECK(t.advance(StallTimeout,true,0)==Event::Load);CHECK(t.failed);
  CHECK(t.resume(true)==Event::Complete);CHECK(!t.succeeded);
  auto mid=video(0,1,3);CHECK(mid.advance(1,true,1)==Event::Load);
  CHECK(mid.resume(true)==Event::None);CHECK(mid.advance(StallTimeout,true,1)==Event::Complete);
  CHECK(mid.failed);CHECK(!mid.succeeded);
 }
 { // Progress resets stall age, but does not bypass the overall play bound.
  auto t=video(0,-1,2000);CHECK(t.advance(19,true,.5)==Event::None);
  CHECK(t.advance(19,true,.5)==Event::None);CHECK(t.advance(1,true,1)==Event::None);
  CHECK(near(t.stalled,0));CHECK(t.advance(PlayTimeout,true,2)==Event::Load);CHECK(t.failed);
  auto c=code(2000);CHECK(c.advance(PlayTimeout,true,0)==Event::Load);CHECK(c.failed);
 }
 { // A loader that never resumes is bounded and releases with NO.
  auto t=code(1);CHECK(t.advance(1,true,0)==Event::Load);
  CHECK(t.advance(LoadTimeout-.1,false,0)==Event::None);
  CHECK(t.advance(.2,false,0)==Event::Complete);CHECK(!t.succeeded);
  CHECK(t.resume(true)==Event::None);
 }
 { // Decoder, animation, and load deadlines freeze in background.
  Timeline preparing(true,0,-1);preparing.advance(10,false,0);preparing.suspended=true;
  CHECK(preparing.advance(10000,false,0)==Event::None);CHECK(near(preparing.waiting,10));
  preparing.suspended=false;CHECK(preparing.advance(10,false,0)==Event::Load);
  auto playing=code(2);playing.suspended=true;playing.advance(10000,true,0);
  CHECK(near(playing.time,0));CHECK(near(playing.playing,0));playing.suspended=false;
  CHECK(playing.advance(1,true,0)==Event::None);CHECK(near(playing.time,1));
  CHECK(playing.advance(1,true,0)==Event::Load);playing.suspended=true;
  CHECK(playing.advance(10000,true,0)==Event::None);CHECK(near(playing.waiting,0));
  CHECK(playing.resume(true)==Event::None);CHECK(playing.phase==Phase::Holding);
  CHECK(playing.resume(false)==Event::None);playing.suspended=false;
  CHECK(playing.advance(0,true,0)==Event::Complete);CHECK(playing.succeeded);
 }
 { // Both successful and rejected async resumes defer until foreground.
  auto mid=code(2,1);mid.advance(1,true,0);mid.suspended=true;
  CHECK(mid.resume(true)==Event::None);CHECK(mid.phase==Phase::Holding);
  mid.suspended=false;CHECK(mid.advance(0,true,0)==Event::None);CHECK(mid.phase==Phase::Playing);
  CHECK(mid.advance(1,true,0)==Event::Complete);
  auto no=code(0);no.suspended=true;CHECK(no.resume(false)==Event::None);
  no.suspended=false;CHECK(no.advance(0,true,0)==Event::Complete);CHECK(!no.succeeded);
 }
 { // Cancellation in every phase is terminal; stale replies cannot complete again.
  for(int phase=0;phase<4;++phase){
   Timeline t(true,0,-1);
   if(phase>=1)t.advance(0,true,0);
   if(phase>=2)t.fail();
   if(phase==3)t.resume(true);
   CHECK(t.finish(false)==(phase==3?Event::None:Event::Complete));
   CHECK(t.resume(true)==Event::None);CHECK(t.advance(1000,true,1000,true)==Event::None);
   CHECK(t.fail()==Event::None);CHECK(!t.succeeded);
  }
 }
 { // Invalid/unbounded numeric inputs cannot poison the clock.
  const double nan=std::numeric_limits<double>::quiet_NaN(), inf=std::numeric_limits<double>::infinity();
  CHECK(Timeline::valid(0,-1));CHECK(Timeline::valid(2,99));CHECK(!Timeline::valid(-1,0));
  CHECK(!Timeline::valid(nan,0));CHECK(!Timeline::valid(1,nan));CHECK(!Timeline::valid(inf,0));
  CHECK(!Timeline::valid(1,inf));auto t=video();t.naturalEnd(nan);CHECK(near(t.end,3));
  CHECK(t.advance(nan,true,nan)==Event::None);CHECK(near(t.time,0));
  CHECK(t.advance(-1,true,-1)==Event::None);CHECK(near(t.time,0));
 }
 std::printf("held transition: %u checks passed\n",checks);
}
