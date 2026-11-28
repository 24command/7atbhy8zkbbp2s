#pragma once
#include <cmath>
#include <cstdint>

namespace pmsongglitch {
// Native source evidence: resources.assets MonoBehaviours 2172/2173, iOS 4.0.4.
// These are serialized D321 settings, NOT invented ramps or a claimed full replay.
struct OriginalSettings {
    static constexpr float glitchRange = .3f;
    static constexpr float screenDeform = .55f;
    static constexpr float radius = 3.5f;
    static constexpr float layerStrength = 1.f, layerSpeed = 1.f, center = .5f;
};

// Host owns only a newly added camera component, cloned settings and materials.
// prepare must record every acquired object in Lease before a later operation can
// throw. release is retryable; false retains the roots needed for another cleanup.
// Runtime calls belong to the Unity main thread. No audio/chart/persistence calls.
template<class Host> class Visual {
public:
    using Token = std::uint64_t;
    enum class Result { Running, Paused, Finished, Stale, Failed };
    explicit Visual(Host& host) : host_(host) {}
    Visual(const Visual&) = delete;
    Visual& operator=(const Visual&) = delete;
    // Call stop before destroying the Runtime. A failed cleanup must be retried
    // by the host instead of discarding this object while it still holds roots.
    ~Visual() { stop(); }

    bool start(Token token, double duration, double now) {
        if (!token || token < newest_ || !validTime(now) || !std::isfinite(duration) || duration <= 0 || duration > 600)
            return false;
        if (token == newest_) return running_ && duration == duration_; // No re-instantiation.
        if (!stop()) return false;
        newest_ = token; duration_ = duration; elapsed_ = 0; last_ = now; clockStarted_ = false;
        leased_ = true; // Even partially failed prepare must be released.
        try {
            host_.prepare(lease_);
            if (!host_.valid(lease_)) { stop(); return false; }
            host_.enable(lease_, true);
            running_ = true; paused_ = false;
            return true;
        } catch (...) { stop(); return false; }
    }
    // UI-owned timelines use this for their Frame event. This performs no clock
    // accounting and never finishes a valid visual: UI stage Stop is authoritative.
    // A stale token must not clean up or even probe a replacement owner's host.
    bool validate(Token token) {
        if (!owns(token)) return false;
        try { if (host_.valid(lease_)) return true; } catch (...) {}
        stop();
        return false;
    }
    // Optional self-timed mode for standalone callers; DO NOT use this for the
    // UI Frame event, which must use validate() to avoid competing end clocks.
    // First displayed-frame tick starts timing; synchronous resource loading and
    // shader warmup in start must never consume visible effect duration.
    Result frame(Token token, double now) {
        if (!owns(token)) return Result::Stale;
        if (!validTime(now) || now < last_) return fail();
        try { if (!host_.valid(lease_)) return fail(); }
        catch (...) { return fail(); }
        if (paused_) return Result::Paused;
        if (!clockStarted_) { clockStarted_ = true; last_ = now; return Result::Running; }
        accumulate(now);
        if (elapsed_ >= duration_) return stop() ? Result::Finished : Result::Failed;
        return Result::Running;
    }
    bool pause(Token token, double now) {
        if (!owns(token)) return false;
        if (paused_) return true;
        if (!validTime(now) || now < last_) { fail(); return false; }
        if (clockStarted_) accumulate(now);
        try { host_.enable(lease_, false); paused_ = true; return true; }
        catch (...) { fail(); return false; }
    }
    bool resume(Token token, double now) {
        if (!owns(token) || !validTime(now) || now < last_) return false;
        if (!paused_) return true;
        try {
            if (!host_.valid(lease_)) { fail(); return false; }
            host_.enable(lease_, true);
            paused_ = false; last_ = now; // Never charge the inactive interval.
            return true;
        } catch (...) { fail(); return false; }
    }
    bool stop(Token token) { return token == newest_ ? stop() : true; }
    bool stop() {
        running_ = false; paused_ = false; // Retire before cleanup can reenter.
        if (!leased_) return true;
        try { if (!host_.release(lease_)) return false; }
        catch (...) { return false; }
        lease_ = {}; leased_ = false;
        return true;
    }
    bool owns(Token token) const { return token && token == newest_ && running_; }
    bool cleanupPending() const { return leased_ && !running_; }
    double elapsed() const { return elapsed_; }
private:
    static bool validTime(double value) { return std::isfinite(value) && value >= 0; }
    void accumulate(double now) { elapsed_ += now - last_; last_ = now; }
    Result fail() { stop(); return Result::Failed; }
    Host& host_;
    typename Host::Lease lease_{};
    Token newest_ = 0;
    bool leased_ = false, running_ = false, paused_ = false, clockStarted_ = false;
    double duration_ = 0, elapsed_ = 0, last_ = 0;
};
} // namespace pmsongglitch
