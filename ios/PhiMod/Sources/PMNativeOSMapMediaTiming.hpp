#pragma once
#include <cmath>
#include <cstddef>
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
}
