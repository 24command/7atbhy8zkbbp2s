#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace pmpma {
// Main-thread one-shot state. The adapter owns images and a serial decode queue.
// Natural end must display the final frame; accepted Skip may finish earlier.
struct Playback {
    enum class Action { Wait, Decode, Complete, Fail };
    static constexpr std::size_t None = std::numeric_limits<std::size_t>::max();
    std::size_t count=0, shown=None, requested=None;
    double delay=0, limit=0, end=0, created=0, started=0, presented=0, requestedAt=0;
    std::uint64_t generation=0;
    bool ready=false, pending=false, stopped=false;
    explicit Playback(double now=0): created(now) {}
    bool setLimit(double seconds) {
        if (!std::isfinite(seconds) || seconds<0) return false;
        limit=seconds;
        if (count) end=limit>0 ? std::min(limit,count*delay) : count*delay;
        return true;
    }
    bool configure(std::size_t n,double dt,double seconds) {
        if (stopped || ready || !n || n>4096 || !std::isfinite(dt) || dt<1./60. ||
            !std::isfinite(n*dt) || n*dt>600. || !setLimit(seconds)) return false;
        count=n;delay=dt;end=limit>0 ? std::min(limit,n*dt) : n*dt;
        return true;
    }
    std::size_t terminal() const {
        if (!count) return 0;
        // Ceil chooses the last interval intersecting [0,end), not a frame after cutoff.
        return std::min(count-1,std::size_t(std::max(0.,std::ceil(end/delay)-1.)));
    }
    double elapsed(double now) const {return ready ? std::min(end,std::max(0.,now-started)) : 0.;}
    std::size_t target(double now) const {
        return ready ? std::min(terminal(),std::size_t(elapsed(now)/delay)) : 0;
    }
    std::uint64_t request(std::size_t frame,double now) {
        if (stopped || pending || !std::isfinite(now) || (count ? frame>=count : frame!=0)) return 0;
        requested=frame;requestedAt=now;pending=true;return ++generation;
    }
    bool owns(std::uint64_t token,std::size_t frame) const {
        return !stopped && pending && token==generation && frame==requested;
    }
    bool display(std::uint64_t token,std::size_t frame,double now) {
        if (!owns(token,frame) || !count || frame>=count || !std::isfinite(now) || (!ready && frame!=0)) return false;
        pending=false;shown=frame;presented=now;
        if (!ready) {ready=true;started=now;}
        return true;
    }
    Action poll(double now,bool active=true) const {
        if (stopped) return Action::Wait;
        if (!active || !std::isfinite(now) || now<created) return Action::Fail;
        if ((!ready && now-created>20.) || (pending && now-requestedAt>20.) ||
            (ready && now-started>610.)) return Action::Fail;
        if (!ready || pending) return Action::Wait;
        if (shown==terminal()) {
            const double hold=std::max(0.,end-shown*delay);
            if (now>=started+end && now>=presented+hold) return Action::Complete;
        }
        return target(now)!=shown ? Action::Decode : Action::Wait;
    }
    bool canSkip() const {return ready && !stopped;}
    void cancel() {stopped=true;pending=false;++generation;}
};
}
