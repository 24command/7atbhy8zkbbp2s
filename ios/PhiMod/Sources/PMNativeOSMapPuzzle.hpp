#pragma once
#include "PMNativeOSMap.hpp"
namespace pmnativeosmap::puzzle {
using layout::Anchors;
using layout::Point;
constexpr Anchors unit{{0,0},{1,1}};
inline Point size(Anchors r) { return {r.high.x-r.low.x,r.high.y-r.low.y}; }
inline Point center(Anchors r) { auto s=size(r); return {r.low.x+s.x/2,r.low.y+s.y/2}; }
inline Anchors compose(Anchors parent, Anchors child) {
    auto s=size(parent);
    return {{parent.low.x+s.x*child.low.x,parent.low.y+s.y*child.low.y},
            {parent.low.x+s.x*child.high.x,parent.low.y+s.y*child.high.y}};
}
inline Anchors relative(Anchors parent, Anchors root) {
    auto s=size(parent);
    return {{(root.low.x-parent.low.x)/s.x,(root.low.y-parent.low.y)/s.y},
            {(root.high.x-parent.low.x)/s.x,(root.high.y-parent.low.y)/s.y}};
}
inline Anchors centered(Point c, Point s) {
    return {{c.x-s.x/2,c.y-s.y/2},{c.x+s.x/2,c.y+s.y/2}};
}
inline bool contains(Anchors r, Point p) {
    return p.x>=r.low.x && p.x<r.high.x && p.y>=r.low.y && p.y<r.high.y;
}
}
