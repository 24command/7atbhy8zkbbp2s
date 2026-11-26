#include "../PhiMod/Sources/PMNativeOSMapMediaTiming.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
using namespace pmnativeosmap::playback;
static void zeroOriginAndReveal() {
 SequenceClock clock;clock.start(500,true);
 assert(clock.sample(500,2026,1./30.,false).frame==0 && !clock.needsFrame());
 assert(clock.sample(500.02,2026,1./30.,false).frame==0);
 assert(clock.sample(500+1./30.,2026,1./30.,false).frame==1);
 assert(clock.sample(501,2026,1./30.,false).frame==30);
 auto wrap=clock.sample(500+2026./30.,2026,1./30.,true);assert(wrap.frame==0 && wrap.cycle==1);
 clock.start(900,true);assert(clock.sample(900,2026,1./30.,false).frame==0);
 clock.start(1200,false);assert(clock.sample(1200,2026,1./30.,false).frame==0 && clock.needsFrame());
}
static void longSourceDoesNotDrift() {
 SequenceClock clock;clock.start(0,true);
 // Sparse ticks/slow decodes must not turn 67.533333 seconds into 2026 decode intervals.
 for(double now=0;now<67.5;now+=.137) {
  const auto slot=clock.sample(now,2026,1./30.,false);
  assert(slot.frame==std::size_t(std::floor(now*30.)));
  clock.displayed(slot);
 }
 assert(clock.sample(67.5,2026,1./30.,false).frame==2025);
 assert(clock.sample(2026./30.,2026,1./30.,false).frame==2025);
 assert(clock.sample(1000,2026,1./30.,false).frame==2025);
}
static void loopsAndBoundaries() {
 const double dt=1./30.,duration=2026./30.;
 assert(sequenceSlot(duration-1e-7,2026,dt,true).frame==2025);
 auto s=sequenceSlot(duration,2026,dt,true);assert(s.frame==0 && s.cycle==1);
 s=sequenceSlot(duration*3+dt*5,2026,dt,true);assert(s.frame==5 && s.cycle==3);
 assert(sequenceSlot(dt-1e-8,2026,dt,true).frame==0);
 assert(sequenceSlot(dt,2026,dt,true).frame==1);
 assert(sequenceSlot(0,2026,dt,true).frame==0);
 assert(sequenceSlot(-1,2026,dt,true).frame==0);
 for(int n=1;n<=4096;n+=17)for(double fps: {1.,23.976,30.,60.}){
  s=sequenceSlot(n/fps,std::size_t(n),1./fps,true);assert(s.frame==0 && s.cycle==1);
 }
}
static void staleAndFutureResults() {
 SequenceClock clock;clock.start(0,true);
 auto old=clock.sample(.1,100,.1,true);
 clock.sample(.4,100,.1,true);assert(!clock.accepts(old));
 auto next=clock.next(100,true);assert(clock.accepts(next));assert(next!=clock.wanted);
 clock.sample(.5,100,.1,true);assert(next==clock.wanted);
 clock.displayed(next);assert(!clock.needsFrame());
 // Same modulo frame, wrong lap, must be rejected (including ready data).
 old=clock.wanted;clock.sample(10.5,100,.1,true);
 assert(old.frame==clock.wanted.frame && old.before(clock.wanted) && !clock.accepts(old));
}
static void finalFrameIsRequired() {
 SequenceClock clock;clock.start(0,true);clock.sample(40,4,.1,false);
 assert(clock.wanted.frame==3 && clock.needsFrame());
 auto last=clock.wanted;assert(clock.accepts(last));
 clock.sample(100,4,.1,false);assert(clock.wanted==last && clock.needsFrame());
 clock.displayed(last);assert(!clock.needsFrame());assert(clock.next(4,false)==last);
 SequenceClock one;one.start(0,true);one.sample(200,1,1,false);
 assert(!one.needsFrame() && one.next(1,false)==one.wanted);
}
static void boundedPrefetchAt60fps() {
 SequenceClock clock;clock.start(0,true);
 auto ticket=clock.next(100,true);bool pending=true;bool ready=false;int maxRetained=1;
 for(int tick=1;tick<=200;++tick){
  // Decode completes before the next display tick, one image ahead, no preload.
  assert(pending);pending=false;ready=clock.accepts(ticket);maxRetained=2;
  clock.sample(tick/60.,100,1./60.,true);
  assert(ready && ticket==clock.wanted);clock.displayed(ticket);ready=false;
  ticket=clock.next(100,true);pending=true;
 }
 assert(maxRetained==2 && !ready && pending);
}
static void gifAndBadInput() {
 assert(frameDelay(.02,.1)==.02 && frameDelay(0,.1)==.1);
 assert(nextFrame(3,4,false)==4 && nextFrame(3,4,true)==0);
 assert(sequenceSlot(1,0,.1,false).frame==0);
 assert(sequenceSlot(1,5,0,false).frame==0);
 assert(sequenceSlot(NAN,5,.1,false).frame==0);
}
int main(){zeroOriginAndReveal();longSourceDoesNotDrift();loopsAndBoundaries();staleAndFutureResults();finalFrameIsRequired();boundedPrefetchAt60fps();gifAndBadInput();std::cout<<"PMA map clock: 7 groups passed\n";}
