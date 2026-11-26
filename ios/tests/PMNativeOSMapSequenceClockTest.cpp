#include "../PhiMod/Sources/PMNativeOSMapMediaTiming.hpp"
#include <cassert>
#include <cmath>
#include <iostream>
#include <memory>
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
 clock.sample(.4,100,.1,true);assert(clock.accepts(old) && clock.canDisplay(old));
 assert(!clock.acceptsFailure(old)); // Late success advances, late failure is obsolete.
 clock.displayed(old);assert(!clock.accepts(old));
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

// Models the actual adapter ordering: sample on tick; a completion can publish
// one result; resample/recheck before upload; request newest wanted or next only.
struct SlowDecoder {
 SequenceClock clock;
 SequenceSlot request{},readySlot{};
 std::size_t count;
 bool loop,pending=false,ready=false,failed=false,stopped=false,finished=false;
 int due=0,uploads=0,dropped=0;
 explicit SlowDecoder(std::size_t n,bool looping):count(n),loop(looping) {
  clock.start(0,true);clock.sample(0,count,1./30.,loop);
  request=clock.next(count,loop);pending=true;due=6; // 100ms at a 60Hz display clock.
 }
 void complete(bool ok) {
  assert(pending);pending=false;
  if(!(ok ? clock.accepts(request) : clock.acceptsFailure(request))){++dropped;return;}
  readySlot=request;ready=ok;failed=!ok;
 }
 void tick(int tick,bool failDecode=false) {
  const auto wanted=clock.sample(tick/60.,count,1./30.,loop);
  if(pending && tick>=due)complete(!failDecode);
  if(ready && !clock.accepts(readySlot)){ready=false;++dropped;}
  if(failed && !clock.acceptsFailure(readySlot))failed=false;
  if(failed && readySlot==wanted){stopped=true;return;}
  if(ready && clock.canDisplay(readySlot)){
   assert(!clock.hasShown || clock.shown.before(readySlot));
   assert(readySlot.cycle==wanted.cycle && readySlot.frame<=wanted.frame);
   clock.displayed(readySlot);ready=false;++uploads;
   finished=!loop && readySlot.frame==count-1;
  }
  if(!pending && !ready && !failed){
   auto ticket=clock.needsFrame() ? wanted : clock.next(count,loop);
   if(clock.needsFrame() || ticket!=wanted){request=ticket;pending=true;due=tick+6;}
  }
 }
};
static void repeated100msAt30fpsMakesProgress() {
 SlowDecoder d(2026,false);
 d.tick(6);assert(d.uploads==1 && d.clock.shown.frame==1 && d.clock.wanted.frame==3);
 d.tick(12);assert(d.uploads==2 && d.clock.shown.frame==3 && d.clock.wanted.frame==6);
 for(int tick=13;tick<=4200;++tick){
  d.tick(tick);assert(!d.stopped && d.clock.origin==0);
  const auto expected=sequenceSlot(tick/60.,2026,1./30.,false);
  assert(d.clock.wanted==expected); // Decode latency must not move authored time.
 }
 assert(d.uploads>600 && d.finished && d.clock.shown.frame==2025);
 assert(!d.pending && !d.ready); // Final nonloop image uploaded, not just elapsed.
}
static void slowDecodeAcrossLoopBoundary() {
 SlowDecoder d(12,true);
 for(int tick=1;tick<=18;++tick)d.tick(tick);
 assert(d.clock.shown.frame==6 && d.clock.shown.cycle==0);
 const auto before=d.clock.shown;
 for(int tick=19;tick<=24;++tick)d.tick(tick);
 assert(d.clock.wanted.frame==0 && d.clock.wanted.cycle==1);
 assert(d.clock.shown==before && d.dropped==1); // Old lap completion rejected.
 for(int tick=25;tick<=120;++tick)d.tick(tick);
 assert(d.uploads>=15 && d.dropped>=5 && d.clock.shown.cycle==4);
 assert(d.clock.wanted.cycle==5 && !d.stopped); // Clock advances even during drop.
}
static void failedLateFrameDoesNotStopNewerFrames() {
 SlowDecoder d(30,false);
 d.tick(6,true);assert(!d.stopped && d.uploads==0 && d.dropped==1);
 assert(d.pending && d.request.frame==3); // Skip failed obsolete frame 1.
 d.tick(12);assert(d.uploads==1 && d.clock.shown.frame==3 && !d.stopped);
 // Conversely, the current terminal frame cannot silently fail or finish.
 SlowDecoder last(4,false);
 last.tick(6);assert(last.pending && last.request.frame==3);
 last.tick(12,true);assert(last.stopped && !last.finished);
 SequenceClock clock;clock.start(0,true);clock.sample(.4,12,1./30.,true);
 assert(!clock.acceptsFailure({9,0})); // Old-lap failures are stale too.
}
static void readyFramesAndCanceledVisitsNeverRewind() {
 SequenceClock clock;clock.start(0,true);clock.sample(.2,12,1./30.,true);
 SequenceSlot ready{3,0};assert(clock.accepts(ready));
 clock.sample(.25,12,1./30.,true);assert(clock.canDisplay(ready));
 clock.displayed(ready);assert(!clock.accepts(ready));
 assert(!clock.accepts({1,0}));
 ready={9,0};assert(clock.accepts(ready) && !clock.canDisplay(ready));
 clock.sample(.4,12,1./30.,true);assert(!clock.accepts(ready));
 // Map stop/revisit replaces the shared visit; old queue captures remain weak.
 auto visit=std::make_shared<SequenceClock>();std::weak_ptr<SequenceClock> old=visit;
 visit.reset();visit=std::make_shared<SequenceClock>();visit->start(100,true);
 assert(old.expired());assert(visit->sample(100,12,1./30.,true).frame==0);
}
int main(){zeroOriginAndReveal();longSourceDoesNotDrift();loopsAndBoundaries();staleAndFutureResults();finalFrameIsRequired();boundedPrefetchAt60fps();gifAndBadInput();repeated100msAt30fpsMakesProgress();slowDecodeAcrossLoopBoundary();failedLateFrameDoesNotStopNewerFrames();readyFramesAndCanceledVisitsNeverRewind();std::cout<<"PMA map clock: 11 groups passed\n";}
