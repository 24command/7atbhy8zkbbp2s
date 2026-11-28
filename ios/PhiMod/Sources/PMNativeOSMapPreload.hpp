#pragma once
#include <cstddef>
#include <vector>
namespace pmnativeosmap { namespace preload {
// Resource ownership only: deliberately has no visible/input/clock state.
struct Plan {
    int source = -1, target = -1;
    std::vector<int> nodes;
    size_t cursor = 0;
    bool matches(int from, int to) const { return source == from && target == to && to >= 0; }
    int next() {
        if (nodes.empty()) return -1;
        int node = nodes[cursor];
        cursor = (cursor + 1) % nodes.size();
        return node;
    }
};
// Retain an inactive target or its frozen first display. Once the selected
// page really runs, release held media; hidden current nodes stop normally.
inline bool retainMedia(bool prepared, int screen, int current, bool active,
                        bool visible, bool running) {
    return prepared && (screen != current || (active && !(visible && running)));
}
// Matches refresh's t=0 activity, not opacity: zero-alpha fades also need art.
inline bool eligible(bool object, int page, int target, bool manual,
                     bool parentActive, float opacity) {
    return object && page == target && manual && parentActive && opacity >= 0;
}
} }
