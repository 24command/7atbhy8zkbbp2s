#include "../PhiMod/Sources/PMNativeOSAudioTimeline.hpp"
#include <cassert>
#include <iostream>
#include <limits>
using namespace pmnativeosaudio;
static Cue page(int screen, const char *src, Channel channel = Channel::BGM, double start = 0,
                double duration = 0, bool loop = false, double length = 10) {
    Cue c; c.screen=screen; c.src=src; c.channel=channel; c.start=start;
    c.duration=duration; c.loop=loop; c.length=length; return c;
}
static Cue tap(int screen, const char *src, const char *target = "", Channel channel = Channel::Effect) {
    Cue c=page(screen,src,channel); c.event=Event::Tap; c.target=target; return c;
}
static void near(double a,double b) { assert(std::fabs(a-b)<1e-9); }
static void preloadAndActivation() {
    Timeline t({page(1,"a",Channel::BGM,0,0,true), page(2,"b")});
    t.tick(20,true); t.tap(1,"x",20); assert(t.slot(0).cue==-1);
    t.activate(1,0); assert(t.slot(0).cue==0); auto serial=t.slot(0).serial;
    t.tick(2,true); near(t.position(0),2);
    t.activate(1,0); assert(t.slot(0).serial==serial); near(t.position(0),2);
    t.activate(2,0); assert(t.slot(0).cue==1 && t.slot(0).serial!=serial); near(t.position(0),0);
}
static void lateAndExpired() {
    Timeline t({page(1,"a",Channel::BGM,2,4,true)});
    t.activate(1,0); assert(t.slot(0).cue==-1);
    t.tick(4,true); assert(t.slot(0).cue==0); near(t.position(0),2);
    t.tick(6,true); assert(t.slot(0).cue==-1);
    t.tick(7,true); assert(t.slot(0).cue==-1);
    Timeline missed({page(1,"a",Channel::BGM,0,0,true),page(1,"b",Channel::BGM,2,1)});
    missed.activate(1,0); missed.tick(5,true); assert(missed.slot(0).cue==-1);
    Timeline natural({page(1,"a",Channel::Effect)});
    natural.activate(1,11); assert(natural.slot(1).cue==-1);
    Timeline loop({page(1,"a",Channel::BGM,0,0,true,3)});
    loop.activate(1,11); near(loop.position(0),2);
}
static void orderAndChannels() {
    Timeline t({page(1,"late",Channel::BGM,4),page(1,"early",Channel::BGM,0),
                page(1,"effect",Channel::Effect,0),page(1,"middle",Channel::BGM,2)});
    t.activate(1,5); assert(t.slot(0).cue==0 && t.slot(1).cue==2); near(t.position(0),1);
    auto serial=t.slot(0).serial; t.tick(6,true); assert(t.slot(0).serial==serial);
    t.activate(2,0); assert(t.slot(0).cue==-1 && t.slot(1).cue==-1);
}
static void continuity() {
    Timeline t({page(1,"a",Channel::BGM,0,0,true),page(2,"a",Channel::BGM,0,3,true),
                page(1,"se",Channel::Effect),page(2,"se",Channel::Effect)});
    t.activate(1,0); t.tick(4,true); auto bgm=t.slot(0).serial, se=t.slot(1).serial;
    t.activate(2,0); assert(t.slot(0).serial==bgm && t.slot(1).serial!=se); near(t.position(0),4);
    t.tick(2,true); near(t.position(0),6); t.tick(3,true); assert(t.slot(0).cue==-1);
    t.activate(1,0); assert(t.slot(0).serial!=bgm);
    Timeline future({page(1,"a",Channel::BGM,0,0,true),page(2,"a",Channel::BGM,1,0,true)});
    future.activate(1,0); future.activate(2,0); assert(future.slot(0).cue==-1);
    future.tick(1,true); near(future.position(0),0);
    Timeline ended({page(1,"a"),page(2,"a")});
    ended.activate(1,0); auto old=ended.slot(0).serial; ended.tick(10,true);
    ended.activate(2,0); assert(ended.slot(0).serial!=old); near(ended.position(0),0);
    Timeline tail({page(1,"a"),page(2,"a")});
    tail.activate(1,0); tail.tick(8,true); auto current=tail.slot(0).serial;
    tail.activate(2,0); assert(tail.slot(0).serial==current); near(tail.position(0),8);
    tail.tick(2,true); assert(tail.slot(0).cue==-1);
}
static void tapPriorityAndDedup() {
    Timeline t({tap(1,"global"),tap(1,"exact","node"),tap(1,"bgm","",Channel::BGM)});
    t.activate(1,0); t.tap(1,"node",0); assert(t.slot(1).cue==1 && t.slot(0).cue==2);
    auto effect=t.slot(1).serial, bgm=t.slot(0).serial;
    t.tap(1,"other",1); assert(t.slot(1).serial==effect && t.slot(0).serial==bgm);
    t.tap(0,"node",1); assert(t.slot(1).serial==effect);
    t.tap(2,"Node",1); assert(t.slot(1).cue==0 && t.slot(1).serial!=effect);
    t.tap(3,"",2); assert(t.slot(1).cue==0);
    t.tap(2,"node",3); assert(t.slot(1).cue==0);
    t.activate(2,0); t.activate(1,0); t.tap(3,"node",0); assert(t.slot(1).cue==-1);
    Timeline reverse({tap(1,"exact","node"),tap(1,"global")});
    reverse.activate(1,0); reverse.tap(1,"node",0); assert(reverse.slot(1).cue==0);
    Cue disabled=tap(1,"bad","node"); disabled.enabled=false;
    Timeline missing({tap(1,"global"),disabled}); missing.activate(1,0);
    missing.tap(1,"node",0); assert(missing.slot(1).cue==-1);
}
static void pauseAndClockValidation() {
    Timeline t({page(1,"a",Channel::BGM,0,0,true),page(1,"b",Channel::BGM,3),tap(1,"tap")});
    t.activate(1,0); t.tick(2,true); auto serial=t.slot(0).serial;
    t.setSuspended(true); t.tick(100,true); t.tap(1,"",100);
    near(t.position(0),2); assert(t.slot(0).serial==serial && t.slot(1).cue==-1);
    t.setSuspended(false); t.tick(2,true); near(t.position(0),2);
    t.tick(100,false); assert(t.paused()); near(t.position(0),2);
    t.tick(2,true); assert(!t.paused());
    t.tick(NAN,true); t.tick(INFINITY,true); t.tick(-1,true); t.tick(1,true); near(t.position(0),2);
    t.activate(2,NAN); t.activate(-1,0); assert(t.slot(0).serial==serial);
    t.tap(1,"",2); assert(t.slot(1).cue==-1); // consumed while suspended
    t.tick(3,true); assert(t.slot(0).cue==1); near(t.position(0),0);
}
static void completionFailureAndStop() {
    Cue bad=page(1,"bad",Channel::BGM,2); bad.enabled=false;
    Timeline t({page(1,"a",Channel::BGM,0,0,true),bad,tap(1,"se")});
    t.activate(1,0); auto serial=t.slot(0).serial;
    t.finish(0,serial+1); assert(t.slot(0).cue==0);
    t.tick(2,true); assert(t.slot(0).cue==-1);
    t.tap(1,"",2); auto se=t.slot(1).serial; t.finish(1,se); t.tick(3,true); assert(t.slot(1).cue==-1);
    t.stop(); t.stop(); t.activate(1,0); t.tick(0,true); t.tap(2,"",0);
    assert(t.stopped() && t.slot(0).cue==-1 && t.slot(1).cue==-1);
    Cue limited=tap(1,"short"); limited.duration=.5;
    Timeline duration({limited}); duration.activate(1,0); duration.tap(1,"",4);
    duration.tick(4.49,true); assert(duration.slot(1).cue==0);
    duration.tick(4.5,true); assert(duration.slot(1).cue==-1);
}
static void reusableReset() {
    Timeline t({page(1,"a",Channel::BGM,0,0,true),tap(1,"se")});
    t.activate(1,0); t.tap(1,"",0); auto bgm=t.slot(0).serial;
    t.tick(5,true); t.tick(5,false); t.resetPlayback();
    assert(!t.stopped() && t.slot(0).cue==-1 && t.slot(1).cue==-1);
    t.tick(5,true); t.tap(2,"",5); assert(t.slot(0).cue==-1 && t.slot(1).cue==-1);
    t.activate(1,0); assert(t.slot(0).serial!=bgm); near(t.position(0),0);
    t.tap(1,"",0); t.tap(2,"",0); assert(t.slot(1).cue==-1);
    t.tap(3,"",0); assert(t.slot(1).cue==1);
    t.setSuspended(true); t.resetPlayback(); t.activate(1,0); assert(t.paused());
    t.setSuspended(false); t.tick(0,true); near(t.position(0),0);
    t.stop(); t.resetPlayback(); t.activate(1,0); assert(t.stopped() && t.slot(0).cue==-1);
}
static void detailClockHold() {
    Timeline t({page(1,"a",Channel::BGM,0,0,true),page(1,"later",Channel::Effect,3),
                page(2,"a",Channel::BGM,0,0,true),tap(1,"tap")});
    t.activate(1,0); t.tick(2,true); const auto serial=t.slot(0).serial;
    t.setPageClockHeld(true); t.tick(100,true); t.tap(1,"",2);
    assert(!t.paused() && t.slot(0).serial==serial && t.slot(1).cue==-1);
    t.syncPlaybackPosition(0,serial,7); near(t.position(0),7);
    t.setSuspended(true); t.tick(2,true); assert(t.paused());
    t.setSuspended(false); t.setPageClockHeld(false); t.tick(2,true);
    near(t.position(0),7); assert(t.slot(0).serial==serial);
    t.tick(3,true); near(t.position(0),8); assert(t.slot(1).cue==1);
    t.activate(2,0); near(t.position(0),8); assert(t.slot(0).serial==serial);
    t.setPageClockHeld(true); t.resetPlayback(); t.activate(1,0); t.tick(3,true);
    assert(t.slot(1).cue==1); // reset clears detail hold
}

// Fake output device, exercising the SAME Transport template used by the native
// AVAudioPlayer adapter. No audio assets or wall-clock sleeps are involved.
struct FakePlayer {
    double &clock;
    double length, cursor=0, starts=0;
    bool queued=false, looping=false, frozen=false;
    bool failPrepare=false, failSchedule=false, failPlay=false;
    int schedules=0, plays=0, stops=0;
    explicit FakePlayer(double &device, double duration):clock(device),length(duration) {}
    double deviceTime() const { return clock; }
    double time() const {
        if (!queued || frozen || clock<starts) return cursor;
        double elapsed=cursor+clock-starts;
        return looping ? std::fmod(elapsed,length) : std::min(elapsed,length);
    }
    bool audible() const { return queued && !frozen && clock>=starts && (looping || cursor+clock-starts<length); }
    bool playing() const { return queued && !frozen && (clock<starts || audible()); }
    void seek(double time) { cursor=time; }
    void loops(bool value) { looping=value; }
    void stop() { cursor=time(); queued=false; frozen=false; ++stops; }
    bool prepare() { return !failPrepare; }
    bool play() { if(failPlay)return false; starts=clock; queued=true; frozen=false; ++plays; return true; }
    bool playAt(double time) { if(failSchedule)return false; starts=time; queued=true; frozen=false; ++schedules; return true; }
    void systemPause() { cursor=time(); frozen=true; }
};
static Cue split(int screen=1,double introLength=10,const char *intro="intro.m4a") {
    Cue c=page(screen,"loop.m4a",Channel::BGM,0,0,true,19.2);
    c.introSrc=intro; c.introLength=introLength; return c;
}
static void splitMappingAndIdentity() {
    Cue a=split(), b=split(2), different=split(3,11.2,"black-intro.m4a");
    Timeline t({a,b,different});
    t.activate(1,0); auto serial=t.slot(0).serial;
    t.tick(9.9,true); near(t.position(0),9.9);
    t.tick(10,true); near(t.position(0),10); // transition, not wrap to intro
    t.tick(29.2,true); near(t.position(0),10);
    t.setPageClockHeld(true); t.syncPlaybackPosition(0,serial,14.2); t.tick(100,true);
    t.activate(2,0); assert(t.slot(0).serial==serial); near(t.position(0),14.2);
    t.activate(3,0); assert(t.slot(0).serial!=serial); near(t.position(0),0);
    Timeline late({split()}); late.activate(1,33.2); near(late.position(0),14);
    Cue broken=split(); broken.introLength=0;
    Timeline invalid({broken}); invalid.activate(1,0); assert(invalid.slot(0).cue==-1);
}
static void deviceScheduledHandoff() {
    // Measured NORMAL and BLACK lengths, no page-clock ticks during intro.
    for(double introLength : {10.0,11.2}) {
        double device=100;
        FakePlayer body(device,19.2),intro(device,introLength);
        Transport transport; transport.configure(split(1,introLength),0);
        assert(transport.resume(body,intro));
        assert(body.schedules==1 && intro.schedules==1 && body.looping && !intro.looping);
        near(body.starts,intro.starts+introLength);
        device=intro.starts+introLength-.001;
        assert(intro.audible() && !body.audible());
        device=body.starts;
        assert(!intro.audible() && body.audible());
        near(transport.sample(body,intro),introLength);
        device+=19.2+3;
        near(transport.sample(body,intro),introLength+3);
        assert(!intro.audible() && body.audible() && transport.healthy(body,intro));
        assert(transport.resume(body,intro)); // focus/cross-page update cannot replay
        assert(body.schedules==1 && intro.schedules==1);
        transport.stop(body,intro); device+=30;
        assert(!intro.audible() && !body.audible());
    }
}
static void suspendPendingIntroAndLoop() {
    // Before start, mid-intro, exact handoff and after a loop wrap.
    for(double elapsed : {-.05,4.0,10.0,31.2}) {
        double device=100;
        FakePlayer body(device,19.2),intro(device,10);
        Transport transport; transport.configure(split(),0); assert(transport.resume(body,intro));
        device=intro.starts+elapsed;
        double expected=elapsed<0 ? 0 : transportPosition(elapsed,10,19.2,true);
        transport.suspend(body,intro); near(transport.position(),expected);
        assert(!body.queued && !intro.queued && !transport.running());
        device+=100; assert(!intro.audible() && !body.audible());
        if(elapsed<0) device=0; // Device clock can reset when both players stop.
        assert(transport.resume(body,intro));
        if(expected<10) {
            near(intro.cursor,expected); near(body.starts,intro.starts+10-expected);
            device=body.starts; assert(body.audible() && !intro.audible());
        } else {
            assert(!intro.queued && body.audible()); near(body.time(),expected-10);
        }
        near(transport.sample(body,intro),expected<10 ? 10 : expected);
        transport.stop(body,intro);
    }
    // An OS interruption froze the intro cursor before main received the event.
    double device=100; FakePlayer body(device,19.2),intro(device,10);
    Transport t; t.configure(split(),0); assert(t.resume(body,intro));
    device=intro.starts+3; intro.systemPause(); body.systemPause(); device+=20;
    t.suspend(body,intro); near(t.position(),3); assert(!body.queued && !intro.queued);
    assert(t.resume(body,intro)); near(body.starts,intro.starts+7);
    t.stop(body,intro); t.configure(split(),0); assert(t.resume(body,intro));
    intro.systemPause(); body.systemPause(); device+=20; // interruption before scheduled start
    t.suspend(body,intro); near(t.position(),0);
    assert(t.resume(body,intro)); near(body.starts,intro.starts+10);
}
static void scheduleFailureAndReplacement() {
    for(int failure=0;failure<4;++failure) {
        double device=100; FakePlayer body(device,19.2),intro(device,10);
        body.failPrepare=failure==0; intro.failPrepare=failure==1;
        body.failSchedule=failure==2; intro.failSchedule=failure==3;
        Transport t; t.configure(split(),0); assert(!t.resume(body,intro));
        device+=100; assert(!body.queued && !intro.queued && !t.running());
    }
    double device=100; FakePlayer body(device,19.2),intro(device,10);
    Transport t; t.configure(split(),0); assert(t.resume(body,intro));
    t.stop(body,intro); // reset/replacement BEFORE either scheduled start
    device+=30; assert(!body.audible() && !intro.audible());
    t.configure(split(),12); assert(t.resume(body,intro));
    assert(!intro.queued && body.audible()); near(body.time(),2);
    t.suspend(body,intro); near(t.position(),12);
    body.failPlay=true; assert(!t.resume(body,intro)); assert(!intro.queued && !body.queued);
}
static void detailFocusKeepsTransport() {
    double device=100; FakePlayer body(device,19.2),intro(device,10);
    Timeline pageClock({split(),split(2)}); pageClock.activate(1,0);
    Transport t; t.configure(pageClock.cues()[0],0); assert(t.resume(body,intro));
    auto serial=pageClock.slot(0).serial;
    device=intro.starts+2; pageClock.tick(2,true);
    pageClock.syncPlaybackPosition(0,serial,t.sample(body,intro));
    pageClock.setPageClockHeld(true);
    device=body.starts+5; // detail remains visible across the intro/loop boundary
    pageClock.tick(2,true); pageClock.syncPlaybackPosition(0,serial,t.sample(body,intro));
    near(pageClock.position(0),15); assert(body.audible() && !intro.audible());
    pageClock.setSuspended(true); t.suspend(body,intro); device+=50;
    assert(!body.audible()); pageClock.setSuspended(false); assert(t.resume(body,intro));
    pageClock.setPageClockHeld(false); pageClock.tick(2,true);
    near(pageClock.position(0),15); near(t.sample(body,intro),15);
    pageClock.activate(2,0); assert(pageClock.slot(0).serial==serial);
    near(pageClock.position(0),15); assert(body.schedules==1 && intro.schedules==1);
    pageClock.resetPlayback(); t.stop(body,intro); device+=30;
    assert(pageClock.slot(0).cue==-1 && !body.audible() && !intro.audible());
}
int main() {
    preloadAndActivation(); lateAndExpired(); orderAndChannels(); continuity();
    tapPriorityAndDedup(); pauseAndClockValidation(); completionFailureAndStop(); reusableReset(); detailClockHold();
    splitMappingAndIdentity(); deviceScheduledHandoff(); suspendPendingIntroAndLoop();
    scheduleFailureAndReplacement(); detailFocusKeepsTransport();
    std::cout << "PMNativeOSAudio: 14 focused suites passed (device scheduling, detail/focus, cross-page, cancel/reset)\n";
}
