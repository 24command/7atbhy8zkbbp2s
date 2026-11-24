#include "../PhiMod/Sources/PMNativeOSMap.hpp"
#include "../PhiMod/Sources/PMNativeOSMapMediaTiming.hpp"
#include <cassert>
#include <iostream>
#include <vector>
using namespace pmnativeosmap;
using namespace pmnativeosmap::readiness;

static void tickets() {
    Ticket t;
    assert(!t.active() && !t.owns(0,0));
    assert(!t.begin(0,0,100));
    assert(t.begin(41,0,100) && t.owns(41,0));
    assert(!t.owns(42,0) && !t.owns(41,1));
    assert(!t.expired(102.999) && t.expired(103));
    assert(t.begin(41,0,102.5) && t.deadline == 103); // Cannot refresh timeout.
    assert(t.begin(42,0,104) && !t.owns(41,0) && t.deadline == 107);
    t.invalidate(); // Page change / close / reveal.
    assert(!t.active() && !t.owns(42,0) && !t.expired(1000));
}
static void videoFirstFrameAndResume() {
    FirstFrame f;
    std::vector<Action> actions;
    auto act = [&](Action a) { if (a != Action::None) actions.push_back(a); };
    act(f.begin(true));
    act(f.begin(true)); // Repeated prepare must never issue a second Prepare.
    act(f.poll(false,false,false));
    assert(f.phase == Phase::Preparing && !f.held());
    act(f.poll(true,false,false)); // isPrepared alone does not mean frame-ready.
    assert(f.phase == Phase::Decoding && !f.held());
    act(f.poll(true,false,false)); // e.g. texture allocated, frame==-1 or width==0.
    assert(!f.held());
    act(f.poll(true,true,false));
    assert(f.held());
    act(f.poll(true,true,true)); // Held frame survives arbitrary covered wall time.
    assert(f.held());
    assert(f.release()); // Runtime resumes with Play, not Stop or Prepare.
    actions.push_back(Action::Play);
    assert(!f.release() && !f.started());
    assert((actions == std::vector<Action>{Action::Prepare,Action::Play,Action::Hold,Action::Play}));
    f.reset(); // Ordinary hide/page/detail can now stop; next show starts fresh.
    assert(f.begin(true) == Action::Prepare);
    f.reset(); // Cancel while still preparing must discard the ticket's frame.
    assert(!f.started() && f.poll(true,true,false) == Action::None);
}
static void mediaPresentationModes() {
    for (bool active : {false,true}) for (bool staging : {false,true})
    for (bool visible : {false,true}) for (bool running : {false,true}) {
        auto mode = mediaMode(active,staging,visible,running);
        if (!active) assert(mode == MediaMode::Stop); // Page/manual/parent exclusion.
        else if (staging) assert(mode == MediaMode::Warm); // Even frozen/covered.
        else assert(mode == (visible && running ? MediaMode::Play : MediaMode::Stop));
    }
    assert(mediaMode(true,true,false,false) == MediaMode::Warm); // Hidden prepare.
    assert(mediaMode(true,true,true,false) == MediaMode::Warm); // Frozen reveal, hold.
    assert(mediaMode(true,false,true,true) == MediaMode::Play); // Consumed ticket resumes.
    assert(mediaMode(true,false,true,false) == MediaMode::Stop); // Legacy detail pause.
    assert(mediaMode(true,false,false,false) == MediaMode::Stop); // Legacy hide.
}
static void boundedFailures() {
    FirstFrame neverPolled;
    assert(neverPolled.poll(false,false,true) == Action::Fail); // Deadline before first work.
    for (bool prepared : {false,true}) {
        FirstFrame f;
        f.begin(true);
        f.poll(prepared,false,false);
        assert(f.poll(prepared,false,true) == Action::Fail);
        assert(f.phase == Phase::Failed && !f.held() && !f.release());
        assert(f.poll(true,true,false) == Action::None); // Late success cannot revive it.
        assert(f.begin(true) == Action::None); // No retry storm on each poll.
    }
    FirstFrame brokenGif;
    brokenGif.begin(false);
    assert(brokenGif.poll(false,false,false,true) == Action::Fail);
    assert(result(1,0,1).complete() && result(1,0,1).state == Readiness::Fallback);
}
static void gifAndAuthoredTime() {
    FirstFrame gif;
    assert(gif.begin(false) == Action::None && gif.phase == Phase::Decoding);
    assert(gif.poll(false,false,false) == Action::None);
    assert(gif.poll(false,true,false) == Action::Hold);
    double authoredTime = 0;
    PMOSMotion animation{};
    animation.enter = .5;
    animation.bob = .02;
    animation.bobPeriod = 4;
    const auto initial = layout::motion(animation,authoredTime,0);
    Ticket t;
    t.begin(7,0,100);
    for (double wall : {100.,101.,110.,1000.}) {
        assert(gif.poll(false,true,t.expired(wall)) == Action::None);
        const auto frozen = layout::motion(animation,authoredTime,0);
        assert(frozen.scale == initial.scale && frozen.lift == initial.lift);
    }
    assert(gif.held() && gif.release());
    const double delay = playback::frameDelay(.08,.1);
    const double due = authoredTime + delay;
    assert(authoredTime < due && due == .08); // Hidden wait not charged to GIF.
    assert(playback::nextFrame(0,2,false) == 1);
    assert(playback::nextFrame(0,1,true) == 1); // Single frame held forever.
    assert(playback::nextFrame(1,2,false) == 2); // Nonlooping terminal frame retained.
    assert(playback::nextFrame(1,2,true) == 0);
}
static void firstScreenSelection() {
    auto active = [](double start, double duration, double fade, bool screen, bool manual, bool parent) {
        return layout::sample(layout::opacity(0,start,duration,fade),screen,manual,parent,0);
    };
    // Zero-opacity entry fades (including inherited zero alpha) still need media.
    auto fade = active(0,2,.5,true,true,true);
    assert(fade.active && fade.inherited == 0);
    assert(!active(.1,2,0,true,true,true).active); // Future authored start.
    assert(!active(0,2,0,false,true,true).active); // Another screen.
    assert(!active(0,2,0,true,false,true).active); // Manual hidden.
    assert(!active(0,2,0,true,true,false).active); // Inactive parent.
    assert(!active(-1,1,0,true,true,true).active); // Expired half-open interval.
}
static void reservedTransitionScreens() {
    static PMOSPage page;
    page.screens = 3;
    page.entryTransition.declared = 1;
    page.entryTransition.kind = PMOSEntryTransitionTimeline;
    page.entryTransition.screen = 0;
    page.initialScreen = 1;
    page.nodes = 4;
    page.elements[0].screen = page.elements[1].screen = 0;
    page.elements[2].screen = 1;
    page.elements[3].screen = 2;
    assert(layout::reservedScreen(page) == 0);
    std::vector<bool> placeholders;
    for (int i=0;i<page.nodes;++i) placeholders.push_back(layout::suppressed(page,page.elements[i]));
    assert(placeholders.size() == 4 && placeholders[0] && placeholders[1]);
    assert(!placeholders[2] && !placeholders[3]); // Retain original Lua/model indices.
    assert(!layout::canDisplay(page.screens,layout::reservedScreen(page),0));
    assert(layout::canDisplay(page.screens,layout::reservedScreen(page),page.initialScreen));
    assert(layout::canDisplay(page.screens,layout::reservedScreen(page),2));
    assert(!layout::canDisplay(page.screens,layout::reservedScreen(page),-1));
    assert(!layout::canDisplay(page.screens,layout::reservedScreen(page),3));
    page.elements[2].songSuppressed = 1;
    assert(layout::suppressed(page,page.elements[2]));
    page.initialScreen = -1; // Timeline-only declaration: host renders its card sheet.
    assert(!layout::canDisplay(page.screens,layout::reservedScreen(page),page.initialScreen));
    page.entryTransition.kind = PMOSEntryTransitionNative;
    assert(layout::reservedScreen(page) == -1 && !layout::reserved(page,0));
    page.entryTransition.kind = PMOSEntryTransitionTimeline;
    page.entryTransition.declared = 0;
    assert(layout::reservedScreen(page) == -1 && !layout::reserved(page,0));
}
static void aggregation() {
    ReadinessResult invalid;
    assert(invalid.state == Readiness::Invalid && !invalid.complete());
    const auto empty = result(0,0,0);
    assert(empty.state == Readiness::Ready && empty.complete());
    const auto pending = result(3,1,1);
    assert(pending.state == Readiness::Pending && !pending.complete());
    const auto ready = result(3,3,0);
    assert(ready.state == Readiness::Ready && ready.complete());
    const auto degraded = result(3,2,1);
    assert(degraded.state == Readiness::Fallback && degraded.complete());
    assert(degraded.total == 3 && degraded.ready == 2 && degraded.failed == 1);
    FirstFrame slow;
    assert(slow.begin(true)==Action::Prepare);
    const auto delayed=result(1,0,0,1);
    assert(delayed.complete() && delayed.state==Readiness::Fallback && delayed.deferred==1 && delayed.failed==0);
    assert(slow.phase==Phase::Preparing); // Cover budget did not kill the decoder.
    assert(slow.poll(true,false,false)==Action::Play);
    assert(slow.poll(false,true,false)==Action::Hold);
    assert(slow.release() && !slow.release()); // Late first frame resumes once, no restart.

}
int main() {
    tickets(); videoFirstFrameAndResume(); mediaPresentationModes(); boundedFailures(); gifAndAuthoredTime();
    firstScreenSelection(); reservedTransitionScreens(); aggregation();
    std::cout << "map readiness: 8 behavioral groups passed\n";
}
