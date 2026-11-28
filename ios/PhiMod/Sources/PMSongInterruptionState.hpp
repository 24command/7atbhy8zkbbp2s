#pragma once
#include <cmath>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>

namespace pmsonginterruption {
// Explicit timelines measure each stage independently in visible foreground time.
// The legacy path deliberately retains its continuous delay semantics.
struct Timeline {
    bool enabled = false;
    double effect = 0, black = 0, blue = 2;
    bool valid() const {
        for (double value : {effect, black, blue})
            if (!std::isfinite(value) || value < 0 || value > 600) return false;
        return true;
    }
};
enum class Stage { Effect, Black, Blue };

// Shared once-only media gates; resuming never starts a completed sound again.
class MediaLifecycle {
public:
    enum class Event { None, Start, Pause, Resume, Stop };
    Event start() {
        if (started_) return Event::None;
        started_ = true; running_ = true; return Event::Start;
    }
    Event pause() {
        if (!running_ || stopped_) return Event::None;
        running_ = false; return Event::Pause;
    }
    Event resume() {
        if (!started_ || running_ || stopped_) return Event::None;
        running_ = true; return Event::Resume;
    }
    Event stop() {
        if (!started_ || stopped_) return Event::None;
        stopped_ = true; running_ = false; return Event::Stop;
    }
private:
    bool started_ = false, running_ = false, stopped_ = false;
};

// The UIKit owner and CPU tests use this same class. Payload owns prepared pixels;
// no native game pointer, progress state, HP setting or frame counter lives here.
template<class Payload> class Owner {
public:
    using Ticket = std::uint64_t;
    enum class Phase { Idle, Playing, Freezing, AwaitingDisplay, Counting, Alert, Quit };
    struct Entry {
        Payload payload;
        std::string chart;
        int slot;
        double at, delay;
        Timeline timeline;
    };

    bool arm(Payload payload, std::string chart, int slot, double at, double delay, Timeline timeline = {}) {
        pending_.reset();
        if (!payload) return true; // nil clears pending only.
        if (chart.empty() || chart.find('\0') != std::string::npos || slot < 0 ||
            !std::isfinite(at) || at < 0 || !std::isfinite(delay) || delay < 0 || delay > 600 || !timeline.valid())
            return false;
        pending_ = Entry{std::move(payload), std::move(chart), slot, at, delay, timeline};
        return true;
    }
    bool pending() const { return pending_.has_value(); }
    void cancelLaunch() { pending_.reset(); }
    bool begin(const std::string& chart, int slot) {
        // Capture BEFORE ending the old song: end() intentionally clears both.
        auto captured = std::move(pending_);
        pending_.reset();
        retirePlaying();
        if (!captured || captured->chart != chart || captured->slot != slot) return false;
        playing_ = std::move(captured);
        phase_ = Phase::Playing;
        stage_ = playing_->timeline.enabled && playing_->timeline.effect > 0 ? Stage::Effect :
                 playing_->timeline.enabled && playing_->timeline.black > 0 ? Stage::Black : Stage::Blue;
        return true;
    }
    void end() { cancelLaunch(); retirePlaying(); }
    void retirePlaying() {
        playing_.reset();
        phase_ = Phase::Idle;
        firstDisplay_ = 0;
        for(bool &started:audioStarted_)started=false;
        visibleElapsed_ = 0; visible_ = false;
        if (++ticket_ == 0) ++ticket_;
    }
    Ticket ticket() const { return ticket_; }
    bool owns(Ticket ticket) const { return playing_.has_value() && ticket == ticket_; }
    Payload payload() const { return playing_ ? playing_->payload : Payload{}; }
    Phase phase() const { return phase_; }
    Stage stage() const { return stage_; }
    bool staged() const { return playing_ && playing_->timeline.enabled; }
    // Called on WILL-deactivate, not merely after applicationState has changed.
    void suspend(Ticket ticket, double now) {
        if (!owns(ticket) || !staged() || !visible_) return;
        if (std::isfinite(now) && now >= firstDisplay_) visibleElapsed_ += now - firstDisplay_;
        visible_ = false;
    }
    bool advanceStage(Ticket ticket, double now, bool active) {
        if (!staged() || stage_ == Stage::Blue || !elapsed(ticket, now, active)) return false;
        stage_ = stage_ == Stage::Effect && playing_->timeline.black > 0 ? Stage::Black : Stage::Blue;
        phase_ = Phase::AwaitingDisplay;
        visible_ = false; visibleElapsed_ = 0;
        return true; // Next stage must receive its OWN first displayed frame.
    }
    bool due(double songTime) const {
        return playing_ && phase_ == Phase::Playing && std::isfinite(songTime) &&
               songTime >= playing_->at;
    }
    Ticket requestTrigger() {
        if (!playing_ || phase_ != Phase::Playing) return 0;
        phase_ = Phase::Freezing; // Reserve once, but NOT blocking until freeze succeeds.
        return ticket_;
    }
    bool frozen(Ticket ticket, bool success) {
        if (!owns(ticket) || phase_ != Phase::Freezing) return false;
        if (!success) { retirePlaying(); return false; }
        phase_ = Phase::AwaitingDisplay;
        return true;
    }
    bool firstDisplay(Ticket ticket, double monotonicNow, bool attached, bool active) {
        if (!owns(ticket) || (phase_ != Phase::AwaitingDisplay &&
            !(staged() && phase_ == Phase::Counting && !visible_)) || !attached || !active ||
            !std::isfinite(monotonicNow) || monotonicNow < 0) return false;
        firstDisplay_ = monotonicNow;
        visible_ = true;
        phase_ = Phase::Counting;
        return true;
    }
    double stageElapsed(Ticket ticket, double now) const {
        if(!owns(ticket) || phase_!=Phase::Counting || !visible_ || !std::isfinite(now) || now<firstDisplay_)return 0;
        return (staged()?visibleElapsed_:0)+(now-firstDisplay_);
    }
    bool claimAudio(Ticket ticket,double now,double delay) {
        if(!owns(ticket) || phase_!=Phase::Counting || !visible_ || !std::isfinite(delay) || delay<0 ||
           !std::isfinite(now) || now<firstDisplay_ || stageElapsed(ticket,now)<delay)return false;
        auto &started=audioStarted_[static_cast<int>(stage_)];
        if(started)return false;started=true;return true;
    }
    bool claimAlert(Ticket ticket, double monotonicNow, bool active) {
        if (stage_ != Stage::Blue || !elapsed(ticket, monotonicNow, active)) return false;
        phase_ = Phase::Alert; // Claimed before UIKit presentation; no second dialog.
        return true;
    }
    bool claimQuit(Ticket ticket) {
        if (!owns(ticket) || phase_ != Phase::Alert) return false;
        phase_ = Phase::Quit; // Keep blocking until End, even if the callback returns.
        return true;
    }
    bool blocking() const {
        return phase_ == Phase::AwaitingDisplay || phase_ == Phase::Counting ||
               phase_ == Phase::Alert || phase_ == Phase::Quit;
    }
private:
    bool elapsed(Ticket ticket, double now, bool active) const {
        if (!owns(ticket) || phase_ != Phase::Counting || !active ||
            !std::isfinite(now) || now < firstDisplay_) return false;
        if (!staged()) return now - firstDisplay_ >= playing_->delay;
        if (!visible_) return false;
        const auto& t = playing_->timeline;
        const double duration = stage_ == Stage::Effect ? t.effect : stage_ == Stage::Black ? t.black : t.blue;
        return visibleElapsed_ + (now - firstDisplay_) >= duration;
    }
    bool audioStarted_[3]={};
    Stage stage_ = Stage::Blue;
    double visibleElapsed_ = 0;
    bool visible_ = false;
    std::optional<Entry> pending_, playing_;
    Ticket ticket_ = 1;
    Phase phase_ = Phase::Idle;
    double firstDisplay_ = 0;
};
} // namespace pmsonginterruption
