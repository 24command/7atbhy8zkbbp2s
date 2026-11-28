#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace pmnativeosaudio {
// Times are supplied by the host: effective elapsed seconds of this page visit.
// Freeze that clock while inactive/suspended. No wall-clock origin is inferred.
enum class Event { Page, Tap };
enum class Channel { BGM, Effect };
struct Cue {
    int screen = 0;
    Event event = Event::Page;
    Channel channel = Channel::Effect;
    std::string src, introSrc, target;
    double start = 0, duration = 0, volume = 1, length = 0, introLength = 0;
    bool loop = false, enabled = true;
};
// A loop cursor is [introLength, introLength+length); it never wraps back
// into the intro. With no intro this is the ordinary modulo loop position.
inline double transportPosition(double position, double introLength, double length, bool loop) {
    if (!loop || position < introLength) return position;
    return introLength + std::fmod(position - introLength, length);
}

// Device-clock transport shared by the native AV adapter and deterministic
// scheduler tests. Player is a thin adapter, not a new audio backend/hook.
// No calls occur during worker preload. A channel may have two scheduled
// players, with disjoint audible intervals: one-shot intro, then loop forever.
class Transport {
    double introLength_ = 0, length_ = 0, position_ = 0;
    double startsAt_ = 0, handsOffAt_ = 0;
    bool loop_ = false, running_ = false, introPhase_ = false;
    static constexpr double Lead = .1; // Prepare first, then schedule both ahead.
    static constexpr double StartGrace = .02;
public:
    void configure(const Cue &cue, double position) {
        introLength_ = cue.introLength; length_ = cue.length; loop_ = cue.loop;
        position_ = transportPosition(position, introLength_, length_, loop_);
        startsAt_ = handsOffAt_ = 0; running_ = false; introPhase_ = position_ < introLength_;
    }
    void setLooping(bool loop) { loop_ = loop; }
    bool running() const { return running_; }
    double position() const { return position_; }
    template<class Player> double sample(Player &body, Player &intro, bool suspending = false) {
        if (!running_) return position_;
        if (introPhase_) {
            const double device = intro.deviceTime();
            const double head = intro.time(), tail = body.time();
            // If the OS already paused both players, device time may have
            // advanced beyond handoff while the intro cursor remained frozen.
            // Its remaining samples still belong to intro, not to the loop.
            if (suspending && !body.playing() && tail == 0 && head >= 0 && head < introLength_ &&
                (head > 0 || position_ == 0)) {
                position_ = head; return position_;
            }
            if (device < startsAt_) return position_; // Pending start, no progress.
            if (device < handsOffAt_) {
                position_ = std::max(0.0, std::min(head, introLength_));
                return position_;
            }
            introPhase_ = false;
        }
        position_ = transportPosition(introLength_ + std::max(0.0, body.time()), introLength_, length_, loop_);
        return position_;
    }
    template<class Player> bool healthy(Player &body, Player &intro) const {
        if (!running_) return true;
        if (introPhase_) {
            const double now = intro.deviceTime();
            if (now < startsAt_ + StartGrace) return true;
            if (now < handsOffAt_) return intro.playing();
            if (now < handsOffAt_ + StartGrace) return true;
            return body.playing();
        }
        if (handsOffAt_ > 0 && body.deviceTime() < handsOffAt_ + StartGrace) return true;
        return body.playing();
    }
    template<class Player> void stop(Player &body, Player &intro) {
        // stop, not pause: a future playAtTime must be canceled, even when
        // isPlaying is false. Saved position is independent of AV's stop state.
        body.stop(); intro.stop(); running_ = false; startsAt_ = handsOffAt_ = 0;
    }
    template<class Player> void suspend(Player &body, Player &intro) {
        if (!running_) return;
        sample(body, intro, true); stop(body, intro);
    }
    template<class Player> bool resume(Player &body, Player &intro) {
        if (running_) return true;
        if (!(length_ > 0) || !std::isfinite(position_) || position_ < 0) return false;
        stop(body, intro);
        introPhase_ = introLength_ > 0 && position_ < introLength_;
        body.loops(loop_); intro.loops(false);
        if (introPhase_) {
            intro.seek(position_); body.seek(0);
            if (!intro.prepare() || !body.prepare()) { stop(body, intro); return false; }
            const double device = std::max(intro.deviceTime(), body.deviceTime());
            if (!std::isfinite(device) || device < 0) { stop(body, intro); return false; }
            startsAt_ = device + Lead;
            handsOffAt_ = startsAt_ + introLength_ - position_;
            // Arm loop first; if either scheduling call fails, cancel BOTH.
            // Both starts are in the future, so failure cannot play intro alone.
            if (!body.playAt(handsOffAt_) || !intro.playAt(startsAt_) ||
                intro.deviceTime() >= startsAt_) { stop(body, intro); return false; }
        } else {
            body.seek(std::max(0.0, position_ - introLength_));
            if (!body.prepare() || !body.play()) { stop(body, intro); return false; }
        }
        running_ = true; return true;
    }
};
struct Slot {
    int cue = -1;
    uint64_t serial = 0;
    double offset = 0, sampledAt = 0;
    double deadline = std::numeric_limits<double>::infinity();
};
class Timeline {
    std::vector<Cue> cues_;
    std::vector<bool> fired_;
    std::array<Slot, 2> slots_{{Slot{}, Slot{}}};
    int screen_ = -1;
    double time_ = 0;
    uint64_t serial_ = 0, lastTap_ = 0;
    bool stopped_ = false, active_ = true, suspended_ = false, clockHeld_ = false;
    static bool validTime(double t) { return std::isfinite(t) && t >= 0; }
    double position(const Slot &s, double now) const {
        if (s.cue < 0) return 0;
        const Cue &c = cues_[s.cue];
        double p = s.offset + std::max(0.0, now - s.sampledAt);
        return transportPosition(p, c.introLength, c.length, c.loop);
    }
    void expire() {
        for (auto &s : slots_) if (s.cue >= 0) {
            const Cue &c = cues_[s.cue];
            if (time_ >= s.deadline || (!c.loop && position(s, time_) >= c.length)) s = {};
        }
    }
    void apply(int index, double origin, const Slot *carry = nullptr, double carryTime = 0) {
        const Cue &c = cues_[index];
        Slot &s = slots_[static_cast<int>(c.channel)];
        const double elapsed = time_ - origin;
        // Even an expired newer cue replaces an older loop; never resurrect it.
        s = {};
        if (!c.enabled || !(c.length > 0) || !std::isfinite(c.length) ||
            (!c.introSrc.empty() && (!(c.introLength > 0) || !std::isfinite(c.introLength))) || elapsed < 0 ||
            (c.duration > 0 && elapsed >= c.duration)) return;
        double offset = elapsed;
        bool continued = carry && carry->cue >= 0 &&
            cues_[carry->cue].src == c.src && cues_[carry->cue].introSrc == c.introSrc && carryTime < carry->deadline;
        if (continued) {
            const Cue &old = cues_[carry->cue];
            offset = position(*carry, carryTime);
            if (!old.loop && offset >= old.length) continued = false;
        }
        if (!continued) offset = elapsed;
        if (c.loop) offset = transportPosition(offset, c.introLength, c.length, true);
        else if (offset >= c.length) return;
        s.cue = index;
        s.serial = continued ? carry->serial : ++serial_;
        s.offset = offset;
        s.sampledAt = time_;
        if (c.duration > 0) s.deadline = origin + c.duration;
    }
    void due(const Slot *carry = nullptr, double carryTime = 0) {
        std::array<int, 2> selected{{-1, -1}};
        for (std::size_t i = 0; i < cues_.size(); ++i) {
            const Cue &c = cues_[i];
            if (c.screen != screen_ || c.event != Event::Page || fired_[i] || c.start > time_) continue;
            fired_[i] = true;
            int &chosen = selected[static_cast<int>(c.channel)];
            if (chosen < 0 || cues_[chosen].start <= c.start) chosen = static_cast<int>(i);
        }
        for (int ch = 0; ch < 2; ++ch) if (selected[ch] >= 0)
            apply(selected[ch], cues_[selected[ch]].start, ch == 0 ? carry : nullptr, carryTime);
        expire();
    }
public:
    explicit Timeline(std::vector<Cue> cues = {}) : cues_(std::move(cues)), fired_(cues_.size(), false) {}
    const std::vector<Cue> &cues() const { return cues_; }
    const Slot &slot(int channel) const { return slots_[channel]; }
    double position(int channel) const { return position(slots_[channel], time_); }
    bool paused() const { return suspended_ || !active_; }
    bool stopped() const { return stopped_; }
    void setSuspended(bool value) { suspended_ = value; }
    void setPageClockHeld(bool value) { clockHeld_ = value; }
    // The adapter samples AV's real cursor, especially while the page clock is
    // held but audio continues. This never changes the page duration deadline.
    void syncPlaybackPosition(int channel, uint64_t serial, double position) {
        Slot &s = slots_[channel];
        if (s.cue < 0 || s.serial != serial || !validTime(position)) return;
        const Cue &c = cues_[s.cue];
        s.offset = transportPosition(position, c.introLength, c.length, c.loop);
        s.sampledAt = time_;
    }
    void activate(int screen, double time) {
        if (stopped_ || screen < 0 || !validTime(time) || screen_ == screen) return;
        const Slot old = slots_[0];
        const double oldTime = time_;
        screen_ = screen;
        time_ = time;
        slots_ = {{Slot{}, Slot{}}};
        std::fill(fired_.begin(), fired_.end(), false);
        due(&old, oldTime);
    }
    void tick(double time, bool active) {
        if (stopped_) return;
        active_ = active;
        if (paused() || clockHeld_ || screen_ < 0 || !validTime(time) || time < time_) return;
        time_ = time;
        due();
    }
    // IDs are nonzero and strictly increasing for the lifetime of this object.
    // Duplicate/older IDs are ignored. Host rejects callbacks for stale visits.
    void tap(uint64_t id, const std::string &node, double time) {
        if (!id || id <= lastTap_ || stopped_) return;
        lastTap_ = id;
        if (paused() || clockHeld_ || screen_ < 0 || !validTime(time) || time < time_) return;
        tick(time, true);
        std::array<int, 2> selected{{-1, -1}};
        for (std::size_t i = 0; i < cues_.size(); ++i) {
            const Cue &c = cues_[i];
            if (c.screen != screen_ || c.event != Event::Tap ||
                (!c.target.empty() && c.target != node)) continue;
            int &chosen = selected[static_cast<int>(c.channel)];
            // A matching target shadows the wildcard, including unavailable assets.
            if (chosen < 0 || !c.target.empty()) chosen = static_cast<int>(i);
        }
        for (int ch = 0; ch < 2; ++ch) if (selected[ch] >= 0) apply(selected[ch], time);
    }
    void finish(int channel, uint64_t serial) {
        if (slots_[channel].serial == serial) slots_[channel] = {};
    }
    void resetPlayback() {
        if (stopped_) return;
        slots_ = {{Slot{}, Slot{}}};
        screen_ = -1; time_ = 0; active_ = true; clockHeld_ = false;
        std::fill(fired_.begin(), fired_.end(), false);
        // Preserve serial and accepted-tap identity across reused scene visits.
    }
    void stop() { stopped_ = true; slots_ = {{Slot{}, Slot{}}}; }
};
} // namespace pmnativeosaudio
