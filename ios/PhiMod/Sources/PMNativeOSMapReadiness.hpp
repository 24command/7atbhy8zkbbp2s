#pragma once
#include <cstdint>

namespace pmnativeosmap {
enum class Readiness { Invalid, Pending, Ready, Fallback };
struct ReadinessResult {
    Readiness state = Readiness::Invalid;
    unsigned total = 0, ready = 0, failed = 0, deferred = 0;
    bool complete() const { return state == Readiness::Ready || state == Readiness::Fallback; }
};
namespace readiness {
// Wall-clock budget, never authored map time. No callbacks or new engine hooks.
constexpr double timeoutSeconds = 3.;
struct Ticket {
    uint64_t token = 0;
    int page = -1;
    double deadline = 0;
    bool owns(uint64_t candidate, int screen) const {
        return candidate && candidate == token && screen == page;
    }
    bool begin(uint64_t candidate, int screen, double wallTime) {
        if (!candidate) return false;
        if (!owns(candidate, screen)) {
            token = candidate; page = screen; deadline = wallTime + timeoutSeconds;
        }
        return true; // Idempotent polls/prepares cannot extend the deadline.
    }
    bool active() const { return token != 0; }
    bool expired(double wallTime) const { return active() && wallTime >= deadline; }
    void invalidate() { *this = {}; }
};
enum class MediaMode { Stop, Warm, Play };
inline MediaMode mediaMode(bool active, bool staging, bool visible, bool running) {
    if (!active) return MediaMode::Stop;
    if (staging) return MediaMode::Warm;
    return visible && running ? MediaMode::Play : MediaMode::Stop;
}
enum class Phase { Cold, Preparing, Decoding, Held, Failed };
enum class Action { None, Prepare, Play, Hold, Fail };
// Shared by the real media adapter and portable behavioral tests. Prepared is
// not ready: only an uploaded GIF or a decoded, dimensioned video frame is ready.
struct FirstFrame {
    Phase phase = Phase::Cold;
    Action begin(bool video) {
        if (phase != Phase::Cold) return Action::None;
        phase = video ? Phase::Preparing : Phase::Decoding;
        return video ? Action::Prepare : Action::None;
    }
    Action poll(bool prepared, bool decoded, bool expired, bool failed = false) {
        if (phase == Phase::Held || phase == Phase::Failed) return Action::None;
        if (failed || expired) { phase = Phase::Failed; return Action::Fail; }
        if (phase == Phase::Cold) return Action::None;
        if (phase == Phase::Preparing) {
            if (!prepared) return Action::None;
            phase = Phase::Decoding;
            return Action::Play;
        }
        if (decoded) { phase = Phase::Held; return Action::Hold; }
        return Action::None;
    }
    bool held() const { return phase == Phase::Held; }
    bool started() const { return phase != Phase::Cold; }
    bool release() {
        if (!held()) return false;
        phase = Phase::Cold;
        return true;
    }
    void reset() { phase = Phase::Cold; }
};
inline ReadinessResult result(unsigned total, unsigned ready, unsigned failed, unsigned deferred = 0) {
    return {ready + failed + deferred < total ? Readiness::Pending :
            (failed || deferred) ? Readiness::Fallback : Readiness::Ready, total, ready, failed, deferred};
}
} // namespace readiness
} // namespace pmnativeosmap
