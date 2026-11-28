#include "../PhiMod/Sources/PMSongInterruptionState.hpp"
#include <cassert>
#include <iostream>
#include <limits>
#include <memory>
using State = pmsonginterruption::Owner<std::shared_ptr<int>>;
using Stage = pmsonginterruption::Stage;
using Timeline = pmsonginterruption::Timeline;
struct Run {
    State state;
    State::Ticket ticket;
    explicit Run(Timeline timeline = {true, 0, 5, 3}) {
        assert(state.arm(std::make_shared<int>(1), "chart", 0, 159, 2, timeline));
        assert(state.begin("chart", 0));
        assert(!state.due(158.999)); assert(state.due(159));
        ticket = state.requestTrigger(); assert(ticket);
        assert(!state.requestTrigger()); assert(state.frozen(ticket, true));
        assert(!state.frozen(ticket, true)); assert(state.blocking());
    }
    void display(double now) { assert(state.firstDisplay(ticket, now, true, true)); }
};
int main() {
    // Exact boundaries, separate first-frame baselines, no duplicate freeze/alert/quit.
    { Run r; assert(r.state.stage() == Stage::Black); r.display(10);
      assert(!r.state.advanceStage(r.ticket, 14.999999, true));
      assert(!r.state.claimAlert(r.ticket, 15, true));
      assert(r.state.advanceStage(r.ticket, 15, true));
      assert(r.state.stage() == Stage::Blue);
      assert(!r.state.claimAlert(r.ticket, 1000, true)); r.display(1000);
      assert(!r.state.claimAlert(r.ticket, 1002.999999, true));
      assert(r.state.claimAlert(r.ticket, 1003, true));
      assert(!r.state.claimAlert(r.ticket, 1004, true));
      assert(r.state.claimQuit(r.ticket)); assert(!r.state.claimQuit(r.ticket)); }
    // A long display stall finishes only ONE stage; no overshoot carried to blue.
    { Run r; r.display(10); assert(r.state.advanceStage(r.ticket, 5000, true));
      assert(!r.state.advanceStage(r.ticket, 5000, true)); r.display(5001);
      assert(!r.state.claimAlert(r.ticket, 5003.999, true));
      assert(r.state.claimAlert(r.ticket, 5004, true)); }
    // Suspend before first attachment/display does not consume any visible time.
    { Run r; r.state.suspend(r.ticket, 10);
      assert(!r.state.firstDisplay(r.ticket, 100, true, false));
      assert(!r.state.firstDisplay(r.ticket, 100, false, true));
      assert(!r.state.advanceStage(r.ticket, 1000, true)); r.display(1000);
      assert(!r.state.advanceStage(r.ticket, 1004.999, true));
      assert(r.state.advanceStage(r.ticket, 1005, true)); }
    // Repeated inactive notifications, multiple foreground intervals in BLACK.
    { Run r; r.display(10); r.state.suspend(r.ticket, 12); r.state.suspend(r.ticket, 99);
      assert(!r.state.advanceStage(r.ticket, 1000, false));
      assert(!r.state.advanceStage(r.ticket, 1000, true)); r.display(1000);
      r.state.suspend(r.ticket, 1001); r.display(2000);
      assert(!r.state.advanceStage(r.ticket, 2001.999, true));
      assert(r.state.advanceStage(r.ticket, 2002, true)); r.display(2003);
      r.state.suspend(r.ticket, 2004); r.display(3000);
      assert(!r.state.claimAlert(r.ticket, 3001.999, true));
      assert(r.state.claimAlert(r.ticket, 3002, true)); }
    // Deactivation AT a boundary still needs the next visible stage's full hold.
    { Run r; r.display(10); r.state.suspend(r.ticket, 15); r.display(1000);
      assert(r.state.advanceStage(r.ticket, 1000, true));
      r.state.suspend(r.ticket, 1001); r.display(2000);
      assert(!r.state.claimAlert(r.ticket, 2002.999, true));
      assert(r.state.claimAlert(r.ticket, 2003, true)); }
    // Optional effect has the same visible-time policy, then exact black 5/blue 3.
    { Run r({true, 1.5, 5, 3}); assert(r.state.stage() == Stage::Effect); r.display(10);
      r.state.suspend(r.ticket, 10.5); r.display(100);
      assert(!r.state.advanceStage(r.ticket, 100.999, true));
      assert(r.state.advanceStage(r.ticket, 101, true)); assert(r.state.stage() == Stage::Black);
      r.display(102); assert(r.state.advanceStage(r.ticket, 107, true)); r.display(108);
      assert(r.state.claimAlert(r.ticket, 111, true)); }
    // Zero optional stages skip cleanly; even a zero blue hold gets a display.
    { Run r({true, 0, 0, 0}); assert(r.state.stage() == Stage::Blue);
      assert(!r.state.claimAlert(r.ticket, 10, true)); r.display(10);
      assert(r.state.claimAlert(r.ticket, 10, true)); }
    { Run r({true, 1, 0, 3}); r.display(10);
      assert(r.state.advanceStage(r.ticket, 11, true)); assert(r.state.stage() == Stage::Blue); }
    // Old API retains delay=2 and continuous background deadline behavior.
    { Run r({}); r.display(10); r.state.suspend(r.ticket, 11);
      assert(!r.state.claimAlert(r.ticket, 1000, false));
      assert(!r.state.firstDisplay(r.ticket, 1000, true, true));
      assert(r.state.claimAlert(r.ticket, 1000, true)); }
    // Invalid timing, backward/non-finite clocks cannot advance stages.
    { Run r; r.display(10);
      for (double time : {-1., 9., std::numeric_limits<double>::infinity(), std::numeric_limits<double>::quiet_NaN()}) {
          assert(!r.state.advanceStage(r.ticket, time, true));
          assert(!r.state.claimAlert(r.ticket, time, true));
      }
      for (double bad : {-1., 601., std::numeric_limits<double>::infinity(), std::numeric_limits<double>::quiet_NaN()})
          for (int field = 0; field < 3; ++field) {
              Timeline t{true, 1, 5, 3};
              if (field == 0) t.effect = bad; else if (field == 1) t.black = bad; else t.blue = bad;
              assert(!r.state.arm(std::make_shared<int>(2), "new", 0, 159, 2, t));
              assert(r.state.owns(r.ticket));
          }
    }
    // End/replacement during EVERY stage rejects stale clocks and callbacks.
    for (int stage = 0; stage < 3; ++stage) {
        Run r({true, 1, 5, 3}); r.display(10);
        if (stage > 0) { assert(r.state.advanceStage(r.ticket, 11, true)); r.display(12); }
        if (stage > 1) { assert(r.state.advanceStage(r.ticket, 17, true)); r.display(18); }
        assert(r.state.arm(std::make_shared<int>(2), "new", 1, 50, 2, {true, 0, 5, 3}));
        assert(r.state.begin("new", 1)); auto newer = r.state.ticket();
        r.state.suspend(r.ticket, 1000);
        assert(!r.state.firstDisplay(r.ticket, 1000, true, true));
        assert(!r.state.advanceStage(r.ticket, 1000, true));
        assert(!r.state.claimAlert(r.ticket, 1000, true)); assert(!r.state.claimQuit(r.ticket));
        assert(r.state.owns(newer) && r.state.due(50)); r.state.end();
        assert(!r.state.owns(newer) && !r.state.blocking());
    }
    // The production media gate consumes each lifecycle event before callbacks.
    { using Media = pmsonginterruption::MediaLifecycle; using Event = Media::Event;
      Media m; assert(m.pause() == Event::None); assert(m.resume() == Event::None);
      assert(m.start() == Event::Start); assert(m.start() == Event::None);
      assert(m.pause() == Event::Pause); assert(m.pause() == Event::None);
      assert(m.resume() == Event::Resume); assert(m.resume() == Event::None);
      assert(m.pause() == Event::Pause); assert(m.stop() == Event::Stop);
      assert(m.stop() == Event::None); assert(m.resume() == Event::None); assert(m.start() == Event::None);
      Media failed; assert(failed.start() == Event::Start); assert(failed.stop() == Event::Stop);
      assert(failed.stop() == Event::None);
    }
    // Production delayed audio claims: once per stage; suspension does not consume delay.
    { Run r({true,1,5,3});
      assert(!r.state.claimAudio(r.ticket,10,0));r.display(10);
      assert(r.state.claimAudio(r.ticket,10,0));assert(!r.state.claimAudio(r.ticket,10.5,0));
      assert(r.state.advanceStage(r.ticket,11,true));r.display(12);
      assert(!r.state.claimAudio(r.ticket,12.05,.1));r.state.suspend(r.ticket,12.05);
      assert(!r.state.claimAudio(r.ticket,999,.1));r.display(1000);
      assert(!r.state.claimAudio(r.ticket,1000.04,.1));assert(r.state.claimAudio(r.ticket,1000.051,.1));
      assert(!r.state.claimAudio(r.ticket,1001,.1));
      assert(r.state.advanceStage(r.ticket,1005,true));r.display(1006);
      assert(r.state.claimAudio(r.ticket,1006,0));assert(!r.state.claimAudio(r.ticket,1007,0));
      r.state.end();assert(!r.state.claimAudio(r.ticket,1008,0));
    }
    std::cout << "14 timeline/media groups passed\n";
}
