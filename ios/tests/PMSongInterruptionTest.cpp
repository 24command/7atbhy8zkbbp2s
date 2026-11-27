#include "../PhiMod/Sources/PMSongInterruptionState.hpp"
#include "../PhiMod/Sources/PMSongInterruptionWindow.hpp"
#include "../PhiMod/Core/PMCoverGeometry.hpp"
#include <cassert>
#include <functional>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <vector>

namespace {
struct Image {
    int& alive;
    explicit Image(int& count):alive(count) { ++alive; }
    ~Image() { --alive; }
};
using Owner = pmsonginterruption::Owner<std::shared_ptr<Image>>;
using Ticket = Owner::Ticket;

// A CPU adapter for the actual runtime state class, not a source-text contract.
// UI/native actions are injected so their order, cancellation and callback counts
// can be asserted without UIKit or the native game. Times are continuous seconds.
struct Harness {
    int alive = 0, freezes = 0, attachments = 0, alerts = 0, quits = 0;
    Owner owner;
    bool attached = false, active = true;
    std::vector<std::string> events;
    void arm(const std::string& chart = "OS/chart", int slot = 3, double at = 159, double delay = 2) {
        assert(owner.arm(std::make_shared<Image>(alive), chart, slot, at, delay));
    }
    bool begin(const std::string& chart = "OS/chart", int slot = 3) {
        attached = false;
        return owner.begin(chart, slot);
    }
    Ticket trigger(const std::function<bool()>& freeze = [] { return true; }) {
        Ticket ticket = owner.requestTrigger();
        if (!ticket) return 0;
        assert(!owner.blocking());
        ++freezes; events.push_back("freeze");
        bool result = freeze();
        if (!owner.frozen(ticket, result)) return 0;
        attached = true; ++attachments; events.push_back("attach");
        return ticket;
    }
    void frame(Ticket ticket, double now) {
        if (owner.firstDisplay(ticket, now, attached, active)) {
            events.push_back("firstDisplay"); return;
        }
        if (owner.claimAlert(ticket, now, active)) { ++alerts; events.push_back("alert"); }
    }
    void close(Ticket ticket, const std::function<void()>& quit = [] {}) {
        if (!owner.claimQuit(ticket)) return;
        ++quits; events.push_back("quit"); quit();
    }
    void invalidate(Ticket ticket) {
        if (!owner.owns(ticket)) return;
        owner.retirePlaying(); attached = false;
    }
};

void fullWindowGeometryAfterOrientationChange() {
    // Exercise the very same geometry PMCompleteCover uses, including portrait
    // window changes. Only the background is cropped; original pixels are fitted.
    for (auto source : {pmcover::Rect{0, 0, 600, 1200}, pmcover::Rect{0, 0, 2400, 400},
                        pmcover::Rect{0, 0, 1000, 1000}}) {
        for (auto window : {pmcover::Rect{0, 0, 1024, 768}, pmcover::Rect{0, 0, 768, 1024},
                            pmcover::Rect{0, 0, 2532, 1170}, pmcover::Rect{0, 0, 1170, 2532}}) {
            auto background = pmcover::fit(source.w, source.h, window.w, window.h, true);
            auto foreground = pmcover::fit(source.w, source.h, window.w, window.h, false);
            assert(background.x <= 1e-8 && background.y <= 1e-8);
            assert(background.x + background.w >= window.w - 1e-8);
            assert(background.y + background.h >= window.h - 1e-8);
            assert(foreground.x >= -1e-8 && foreground.y >= -1e-8);
            assert(foreground.x + foreground.w <= window.w + 1e-8);
            assert(foreground.y + foreground.h <= window.h + 1e-8);
            assert(std::fabs(background.w / background.h - source.w / source.h) < 1e-8);
            assert(std::fabs(foreground.w / foreground.h - source.w / source.h) < 1e-8);
        }
    }
}
void exactIdentityAndOneConsumption() {
    Harness h;
    assert(!h.owner.pending());
    h.arm(); assert(h.owner.pending());
    assert(!h.owner.due(999)); assert(!h.owner.blocking());
    assert(!h.begin("OS/Chart", 3)); // Case is significant.
    assert(!h.owner.pending()); assert(h.alive == 0);
    assert(!h.begin());
    h.arm(); assert(!h.begin("OS/chart", 2)); assert(h.alive == 0);
    h.arm(); assert(h.begin()); assert(!h.owner.pending()); assert(h.alive == 1);
    assert(!h.begin()); assert(h.alive == 0); // Once only, and ends old playing.
}
void capturedPendingSurvivesOldPlayingRetirement() {
    Harness h; h.arm(); assert(h.begin()); auto old = h.trigger();
    h.arm("next", 7, 5, 1); assert(h.alive == 2);
    assert(h.begin("next", 7)); assert(h.alive == 1);
    assert(!h.owner.owns(old)); assert(h.owner.due(5));
    assert(!h.owner.blocking()); assert(!h.owner.pending());
    h.arm("different"); assert(!h.begin("mismatch")); assert(h.alive == 0);
}
void pendingCancellationNeverTouchesPlaying() {
    Harness h; h.arm(); assert(h.begin()); auto ticket = h.trigger();
    h.arm("next"); h.owner.cancelLaunch();
    assert(h.alive == 1 && h.owner.owns(ticket) && h.owner.blocking());
    h.arm("next"); assert(h.owner.arm({}, "", -1, -1, -1));
    assert(!h.owner.pending() && h.owner.owns(ticket) && h.owner.blocking());
    h.arm("next"); h.owner.end();
    assert(h.alive == 0 && !h.owner.pending() && !h.owner.blocking());
}
void payloadLifetimeAndReplacement() {
    Harness h;
    auto image = std::make_shared<Image>(h.alive);
    std::weak_ptr<Image> weak = image;
    assert(h.owner.arm(image, "a", 0, 1, 2)); image.reset(); assert(!weak.expired());
    h.arm("b"); assert(weak.expired()); assert(h.alive == 1);
    assert(h.begin("b")); auto ticket = h.trigger();
    auto held = h.owner.payload(); h.invalidate(ticket);
    assert(h.alive == 1); held.reset(); assert(h.alive == 0);
}
void generalDueAndNonFiniteTimes() {
    Harness h; h.arm(); assert(h.begin());
    assert(!h.owner.due(158.999999)); assert(h.owner.due(159)); assert(h.owner.due(999));
    assert(!h.owner.due(-1));
    assert(!h.owner.due(std::numeric_limits<double>::quiet_NaN()));
    assert(!h.owner.due(std::numeric_limits<double>::infinity()));
    h.trigger(); assert(!h.owner.due(999));
    h.arm("general", 100, .125, 12.5); assert(h.begin("general", 100));
    assert(!h.owner.due(.124)); assert(h.owner.due(.125));
}
void validation() {
    Harness h; auto p = std::make_shared<Image>(h.alive);
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double inf = std::numeric_limits<double>::infinity();
    for (double at : {-1.0, nan, inf}) assert(!h.owner.arm(p, "a", 0, at, 2));
    for (double delay : {-1.0, 600.001, nan, inf}) assert(!h.owner.arm(p, "a", 0, 1, delay));
    assert(!h.owner.arm(p, "", 0, 1, 2));
    assert(!h.owner.arm(p, std::string("a\0b", 3), 0, 1, 2));
    assert(!h.owner.arm(p, "a", -1, 1, 2));
    assert(h.owner.arm(p, "a", 0, 0, 600)); assert(h.owner.pending());
    assert(!h.owner.arm(p, "", 0, 0, 2)); assert(!h.owner.pending());
}
void freezeOnceBeforeOverlay() {
    Harness h; h.arm(); assert(h.begin());
    auto ticket = h.trigger([&] {
        assert(!h.attached && !h.owner.blocking());
        assert(h.owner.requestTrigger() == 0); // Reentrant trigger cannot freeze twice.
        assert(!h.owner.due(159)); return true;
    });
    assert(ticket && h.owner.blocking()); assert(!h.trigger());
    assert(h.freezes == 1 && h.attachments == 1);
    assert((h.events == std::vector<std::string>{"freeze", "attach"}));
}
void freezeFailureDoesNotBlockOrRetry() {
    Harness h; h.arm(); assert(h.begin()); auto old = h.owner.ticket();
    assert(!h.trigger([] { return false; }));
    assert(!h.owner.blocking() && !h.owner.owns(old));
    assert(!h.owner.due(159) && !h.trigger());
    h.frame(old, 9000); h.close(old);
    assert(h.freezes == 1 && h.attachments == 0 && h.alerts == 0 && h.quits == 0 && h.alive == 0);
}
void firstAttachedActiveDisplayStartsDeadline() {
    Harness h; h.arm(); assert(h.begin()); auto ticket = h.trigger();
    assert(!h.owner.claimAlert(ticket, 100000, true)); // Trigger time is not start time.
    h.attached = false; h.frame(ticket, 10); assert(h.owner.phase() == Owner::Phase::AwaitingDisplay);
    h.attached = true; h.active = false; h.frame(ticket, 50);
    assert(h.owner.phase() == Owner::Phase::AwaitingDisplay);
    h.active = true; h.frame(ticket, 100); assert(h.alerts == 0);
    h.frame(ticket, 101.999); assert(h.alerts == 0);
    h.frame(ticket, 102); assert(h.alerts == 1);
    assert((h.events == std::vector<std::string>{"freeze", "attach", "firstDisplay", "alert"}));
}
void timeIsNotFrameCount() {
    for (int frames : {1, 30, 60, 120, 240, 10000}) {
        Harness h; h.arm(); assert(h.begin()); auto ticket = h.trigger(); h.frame(ticket, 20);
        for (int i = 0; i < frames; ++i) h.frame(ticket, 20 + 1.99 * i / frames);
        assert(h.alerts == 0); h.frame(ticket, 22); assert(h.alerts == 1);
        for (int i = 0; i < 30; ++i) h.frame(ticket, 23 + i);
        assert(h.alerts == 1);
    }
    Harness h; h.arm(); assert(h.begin()); auto ticket = h.trigger();
    h.frame(ticket, 0); h.frame(ticket, 1000); assert(h.alerts == 1); // Main-loop stall.
}
void suspensionCountsButCannotPresent() {
    Harness h; h.arm(); assert(h.begin()); auto ticket = h.trigger(); h.frame(ticket, 10);
    h.active = false; h.frame(ticket, 12); h.frame(ticket, 100000); assert(h.alerts == 0);
    h.active = true; h.frame(ticket, 100001); assert(h.alerts == 1); // No fresh 2s wait.
    // A genuine action delivered across a deactivate race is still authorized.
    h.active = false; h.close(ticket); assert(h.quits == 1);
    h.active = true; h.close(ticket); assert(h.quits == 1);
}
void invalidAndBackwardClocksCannotShortenDelay() {
    Harness h; h.arm(); assert(h.begin()); auto ticket = h.trigger();
    h.frame(ticket, std::numeric_limits<double>::quiet_NaN());
    h.frame(ticket, -1); assert(h.owner.phase() == Owner::Phase::AwaitingDisplay);
    h.frame(ticket, 10); h.frame(ticket, 9); h.frame(ticket, std::numeric_limits<double>::infinity());
    h.frame(ticket, 11.999); assert(h.alerts == 0);
    h.frame(ticket, 12); assert(h.alerts == 1);
}
void zeroDelayStillDisplaysAnImageFrame() {
    Harness h; h.arm("a", 0, 0, 0); assert(h.begin("a", 0)); auto ticket = h.trigger();
    h.frame(ticket, 1); assert(h.alerts == 0);
    h.frame(ticket, 1.001); assert(h.alerts == 1);
}
void closeValidOnceBlockingUntilEnd() {
    Harness h; h.arm(); assert(h.begin()); auto ticket = h.trigger();
    h.close(ticket); assert(h.quits == 0); // Cannot quit before the action exists.
    h.frame(ticket, 1); h.frame(ticket, 3);
    h.close(ticket, [&] { h.close(ticket); assert(h.owner.blocking()); });
    h.close(ticket); h.frame(ticket, 9);
    assert(h.quits == 1 && h.alerts == 1 && h.owner.blocking());
    h.owner.end(); assert(!h.owner.blocking() && h.alive == 0);
}
void cancellationInvalidatesAllOldCallbacks() {
    Harness h; h.arm(); assert(h.begin()); auto old = h.trigger(); h.frame(old, 1);
    h.invalidate(old); h.frame(old, 999); h.close(old); assert(h.alerts == 0 && h.quits == 0);
    h.arm(); assert(h.begin()); auto fresh = h.trigger();
    h.invalidate(old); h.frame(old, 1000); h.close(old);
    assert(h.owner.owns(fresh) && h.owner.blocking());
    h.frame(fresh, 10); h.frame(fresh, 12); assert(h.alerts == 1);
    h.owner.end(); h.close(fresh); assert(h.quits == 0);
}
void reentrantFreezeCannotAttachOldPixels() {
    Harness h; h.arm(); assert(h.begin()); auto old = h.owner.ticket();
    assert(!h.trigger([&] { h.owner.end(); h.arm("next"); assert(h.begin("next")); return true; }));
    assert(h.attachments == 0 && !h.owner.owns(old) && !h.owner.blocking());
    assert(h.owner.due(159)); auto fresh = h.trigger(); assert(fresh != old && h.attachments == 1);
}
void hostLossKeepsNextPendingButEndClearsAll() {
    Harness h; h.arm(); assert(h.begin()); auto old = h.trigger();
    h.arm("next"); h.invalidate(old);
    assert(h.owner.pending() && !h.owner.blocking() && h.alive == 1);
    assert(h.begin("next")); auto fresh = h.trigger();
    h.frame(old, 999); h.close(old); assert(h.alerts == 0);
    h.frame(fresh, 1); h.frame(fresh, 3); assert(h.alerts == 1);
    h.arm("third"); h.owner.end(); assert(!h.owner.pending() && h.alive == 0);
}
}
static void legacyAndSceneWindowEligibility() {
 using pmsonginterruption::windowActive;
 assert(windowActive(true,false,true,false,false)); // Retail legacy Unity, no scene manifest.
 assert(windowActive(true,false,true,true,true));
 assert(!windowActive(false,false,true,false,false));
 assert(!windowActive(true,true,true,false,false));
 assert(!windowActive(true,false,false,false,false));
 assert(!windowActive(true,false,true,true,false));
 // Both host kinds run the exact same first-display / realtime-two-second owner.
 for(bool scene:{false,true}){
  assert(windowActive(true,false,true,scene,scene));
 }
}
int main() {
    legacyAndSceneWindowEligibility();
    fullWindowGeometryAfterOrientationChange();
    exactIdentityAndOneConsumption();
    capturedPendingSurvivesOldPlayingRetirement();
    pendingCancellationNeverTouchesPlaying();
    payloadLifetimeAndReplacement();
    generalDueAndNonFiniteTimes();
    validation();
    freezeOnceBeforeOverlay();
    freezeFailureDoesNotBlockOrRetry();
    firstAttachedActiveDisplayStartsDeadline();
    timeIsNotFrameCount();
    suspensionCountsButCannotPresent();
    invalidAndBackwardClocksCannotShortenDelay();
    zeroDelayStillDisplaysAnImageFrame();
    closeValidOnceBlockingUntilEnd();
    cancellationInvalidatesAllOldCallbacks();
    reentrantFreezeCannotAttachOldPixels();
    hostLossKeepsNextPendingButEndClearsAll();
    std::cout << "Song interruption ownership/timing: 19 groups passed\n";
}
