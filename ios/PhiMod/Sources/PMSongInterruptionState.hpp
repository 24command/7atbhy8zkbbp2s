#pragma once
#include <cmath>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>

namespace pmsonginterruption {
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
    };

    bool arm(Payload payload, std::string chart, int slot, double at, double delay) {
        pending_.reset();
        if (!payload) return true; // nil clears pending only.
        if (chart.empty() || chart.find('\0') != std::string::npos || slot < 0 ||
            !std::isfinite(at) || at < 0 || !std::isfinite(delay) || delay < 0 || delay > 600)
            return false;
        pending_ = Entry{std::move(payload), std::move(chart), slot, at, delay};
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
        return true;
    }
    void end() { cancelLaunch(); retirePlaying(); }
    void retirePlaying() {
        playing_.reset();
        phase_ = Phase::Idle;
        firstDisplay_ = 0;
        if (++ticket_ == 0) ++ticket_;
    }
    Ticket ticket() const { return ticket_; }
    bool owns(Ticket ticket) const { return playing_.has_value() && ticket == ticket_; }
    Payload payload() const { return playing_ ? playing_->payload : Payload{}; }
    Phase phase() const { return phase_; }
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
        if (!owns(ticket) || phase_ != Phase::AwaitingDisplay || !attached || !active ||
            !std::isfinite(monotonicNow) || monotonicNow < 0) return false;
        firstDisplay_ = monotonicNow;
        phase_ = Phase::Counting;
        return true;
    }
    bool claimAlert(Ticket ticket, double monotonicNow, bool active) {
        if (!owns(ticket) || phase_ != Phase::Counting || !active ||
            !std::isfinite(monotonicNow) || monotonicNow < firstDisplay_ ||
            monotonicNow - firstDisplay_ < playing_->delay) return false;
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
    std::optional<Entry> pending_, playing_;
    Ticket ticket_ = 1;
    Phase phase_ = Phase::Idle;
    double firstDisplay_ = 0;
};
} // namespace pmsonginterruption
