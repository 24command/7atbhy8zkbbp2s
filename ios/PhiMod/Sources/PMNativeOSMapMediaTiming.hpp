#pragma once
#include <cmath>
#include <cstddef>
#include <limits>
namespace pmnativeosmap::playback {
inline double frameDelay(double unclamped, double standard) {
    if (std::isfinite(unclamped) && unclamped > 0) return unclamped;
    return std::isfinite(standard) && standard > 0 ? standard : .1;
}
// count is the stop sentinel. The final texture stays attached until hidden.
inline std::size_t nextFrame(std::size_t current, std::size_t count, bool loop) {
    if (current+1 < count) return current+1;
    return loop && count > 1 ? 0 : count;
}
// PMA alone uses an authored-time clock. A cycle is part of the identity: a late
// frame from the previous lap must not be reused at the same modulo frame index.
struct SequenceSlot {
    std::size_t frame=0;
    double cycle=0;
    bool operator==(const SequenceSlot &other) const {return frame==other.frame && cycle==other.cycle;}
    bool operator!=(const SequenceSlot &other) const {return !(*this==other);}
    bool before(const SequenceSlot &other) const {return cycle<other.cycle || (cycle==other.cycle && frame<other.frame);}
};
inline SequenceSlot sequenceSlot(double elapsed,std::size_t count,double delay,bool loop,double subtractionScale=0) {
    if (!count || !std::isfinite(elapsed) || !std::isfinite(delay) || delay<=0 || elapsed<=0) return {};
    double ticks=elapsed/delay;
    if (!std::isfinite(ticks)) return {count-1,0};
    // Avoid falling one frame short at mathematically exact fps/cycle boundaries.
    // This tolerance is roundoff-sized, not a visible frame-time offset.
    const double nearest=std::round(ticks);
    const double tolerance=8*std::numeric_limits<double>::epsilon()*((ticks>1 ? ticks : 1)+subtractionScale/delay);
    if (std::fabs(ticks-nearest)<=tolerance) ticks=nearest;
    ticks=std::floor(ticks);
    if (!loop) return {ticks>=double(count-1) ? count-1 : std::size_t(ticks),0};
    const double cycle=std::floor(ticks/double(count));
    return {std::size_t(std::fmod(ticks,double(count))),cycle};
}
struct SequenceClock {
    double origin=0;
    bool hasShown=false;
    SequenceSlot wanted{},shown{};
    void start(double now,bool heldFirstFrame) {
        origin=now;hasShown=heldFirstFrame;wanted={};shown={};
    }
    SequenceSlot sample(double now,std::size_t count,double delay,bool loop) {
        wanted=sequenceSlot(now-origin,count,delay,loop,std::fabs(now)+std::fabs(origin));return wanted;
    }
    bool accepts(SequenceSlot ticket) const {return !ticket.before(wanted);}
    SequenceSlot next(std::size_t count,bool loop) const {
        if (!count || wanted.frame+1<count) return {count ? wanted.frame+1 : 0,wanted.cycle};
        return loop ? SequenceSlot{0,wanted.cycle+1} : wanted;
    }
    bool needsFrame() const {return !hasShown || shown!=wanted;}
    void displayed(SequenceSlot ticket) {shown=ticket;hasShown=true;}
};

}
