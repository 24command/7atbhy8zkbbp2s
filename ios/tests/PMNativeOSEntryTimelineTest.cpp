// Portable implementation-level tests; no UIKit, VM, Lua, or map singleton.
// c++ -std=c++17 -UNDEBUG PMNativeOSEntryTimelineTest.cpp -o /tmp/entry-test
#include "../PhiMod/Sources/PMNativeOSEntryTimeline.mm"
#include <cassert>
#include <iostream>
#include <limits>

namespace timeline = pmentrytimeline;
static bool near(double a, double b) { return std::abs(a - b) < 1e-6; }
static PMOSNode node(int screen = 2, int parent = -1) {
    PMOSNode n{};
    n.kind = PMOSFrame;
    n.parent = parent;
    n.dest = n.dropIndex = n.tapFaceIndex = -1;
    n.screen = screen;
    n.w = n.h = 1;
    n.motion.tapScale = 1.06;
    n.motion.bobPeriod = 3;
    return n;
}

static void endHoldAndSeek() {
    const double duration = 4;
    PMOSNode n = node();
    n.duration = duration;
    assert(timeline::clock(-2, duration) == 0);
    assert(timeline::clock(std::numeric_limits<double>::quiet_NaN(), duration) == 0);
    assert(timeline::clock(-std::numeric_limits<double>::infinity(), duration) == 0);
    assert(timeline::clock(1.5, duration) == 1.5);
    double last = timeline::clock(duration, duration);
    assert(last < duration && last == std::nextafter(duration, 0.));
    assert(timeline::clock(999, duration) == last);
    assert(timeline::clock(std::numeric_limits<double>::infinity(), duration) == last);
    auto hold = timeline::sample(n, last, nullptr);
    assert(hold.active && hold.local == 1);
    assert(!timeline::sample(n, duration, nullptr).active); // Regression: un-clamped sampler blanks.
    n.fade = 1;
    auto fade = timeline::sample(n, last, nullptr);
    assert(fade.active && fade.local >= 0 && fade.local < 1e-6); // Do not undo an intentional fade.
    assert(timeline::sample(n, timeline::clock(1, duration), nullptr).local == 1); // Backwards seek.
    n.start = 1; n.duration = 1; n.fade = 0;
    assert(!timeline::sample(n, 0, nullptr).active);
    assert(timeline::sample(n, 1, nullptr).active);
    assert(!timeline::sample(n, 2, nullptr).active); // Earlier-ending nodes retain half-open timing.
    n.duration = 0; n.fade = 2;
    assert(timeline::sample(n, 1, nullptr).active && timeline::sample(n, 1, nullptr).local == 0);
    assert(near(timeline::sample(n, 2, nullptr).local, .5));
    assert(timeline::sample(n, last, nullptr).local == 1);
}

static void hierarchyAndPassiveMotion() {
    PMOSNode parent = node(), child = node(2, 1);
    parent.fade = 4; child.fade = 2;
    auto p = timeline::sample(parent, 1, nullptr);
    auto c = timeline::sample(child, 1, &p);
    assert(p.local == .25f && c.local == .5f && c.inherited == .125f);
    parent.hidden = 1;
    p = timeline::sample(parent, 1, nullptr);
    assert(!p.active && !timeline::sample(child, 1, &p).active);
    parent.hidden = 0; parent.songSuppressed = 1;
    p = timeline::sample(parent, 1, nullptr);
    assert(!timeline::sample(child, 1, &p).active);
    parent.songSuppressed = 0; parent.start = 3; parent.fade = 0;
    child.motion.enter = 1; child.motion.bob = .2; child.motion.bobPeriod = 4;
    p = timeline::sample(parent, 3, nullptr);
    c = timeline::sample(child, 3, &p);
    assert(c.shownSince == 3 && near(c.pose.scale, .68) && c.pose.lift == 0);
    c = timeline::sample(child, 4, &p);
    assert(near(c.pose.scale, 1) && near(c.pose.lift, .2));
    auto again = timeline::sample(child, 4, &p);
    assert(again.pose.scale == c.pose.scale && again.pose.lift == c.pose.lift && c.pose.white == 0);
    auto rewind = timeline::sample(child, 3, &p);
    assert(near(rewind.pose.scale, .68) && rewind.pose.lift == 0);
    child.start = 5;
    c = timeline::sample(child, 5, &p);
    assert(c.shownSince == 5 && near(c.pose.scale, .68));
}

static void normalizedLayoutAndRotation() {
    PMOSNode parent = node(), child = node();
    parent.x = .125; parent.y = .25; parent.w = .5; parent.h = .5;
    child.x = -.25; child.y = .5; child.w = 1.5; child.h = .25;
    auto landscape = timeline::fit(1600, 900, 16. / 9.);
    assert(near(landscape.x, 0) && near(landscape.y, 0) && near(landscape.w, 1600));
    auto p = timeline::rect(parent, landscape.w, landscape.h);
    auto c = timeline::rect(child, p.w, p.h);
    assert(near(p.x, 200) && near(p.y, 225) && near(p.w, 800) && near(p.h, 450));
    assert(near(c.x, -200) && near(c.y, 225) && near(c.w, 1200) && near(c.h, 112.5));
    auto portrait = timeline::fit(900, 1600, 16. / 9.);
    assert(near(portrait.x, 0) && near(portrait.w, 900) && near(portrait.h, 506.25));
    assert(near(portrait.y, 546.875));
    p = timeline::rect(parent, portrait.w, portrait.h);
    c = timeline::rect(child, p.w, p.h);
    assert(near(p.w, 450) && near(p.h, 253.125) && near(c.y, 126.5625));
    auto fill = timeline::fit(900, 1600, 0);
    assert(fill.w == 900 && fill.h == 1600 && fill.x == 0 && fill.y == 0);
    auto empty = timeline::fit(0, 0, 16. / 9.);
    assert(empty.w == 0 && empty.h == 0);
    // Recompute from authored data, never from an already-scaled view frame.
    p = timeline::rect(parent, landscape.w, landscape.h);
    assert(p.w == 800 && p.h == 450);
}

static void globalIndicesAndValidation() {
    std::vector<PMOSNode> nodes{node(0), node(), node(1), node(2, 1)};
    assert(timeline::validNode(nodes[1], 1, nodes, 2));
    assert(timeline::validNode(nodes[3], 3, nodes, 2));
    PMOSNode bad = nodes[3];
    bad.parent = 0; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad.parent = 3; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad.parent = -2; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.kind = PMOSHotspot; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.handler = 1; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.open = 1; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.dest = 0; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.loop = 1; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.motion.tapTime = .2; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.x = std::numeric_limits<double>::infinity();
    assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.fade = -1; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.w = 0; assert(!timeline::validNode(bad, 3, nodes, 2));
    bad = nodes[3]; bad.start = bad.duration = std::numeric_limits<double>::max();
    assert(!timeline::validNode(bad, 3, nodes, 2));
}

static void boundedDecodeAccounting() {
    assert(timeline::decodeEdge(4096, 0) == 0);
    assert(timeline::decodeEdge(4096, PMOSMaxNodes + 1) == 0);
    assert(timeline::decodeEdge(4096, 1) == 2048);
    for (size_t count = 1; count <= PMOSMaxNodes; ++count) {
        unsigned edge = timeline::decodeEdge(4096, count);
        size_t row = 0, bytes = 0;
        assert(edge && edge <= 2048 && edge % 16 == 0);
        assert(timeline::imageBytes(edge, edge, timeline::decodedBudget, row, bytes));
        assert(row % 64 == 0 && bytes * count <= timeline::decodedBudget);
        assert(!timeline::imageBytes(edge, edge, bytes - 1, row, bytes));
    }
    size_t row = 0, bytes = 0;
    assert(!timeline::imageBytes(0, 1, timeline::decodedBudget, row, bytes));
    assert(!timeline::imageBytes(2049, 1, timeline::decodedBudget, row, bytes));
    assert(!timeline::imageBytes(1, std::numeric_limits<size_t>::max(), timeline::decodedBudget, row, bytes));
    assert(timeline::imageBytes(1, 1, 64, row, bytes) && row == 64 && bytes == 64);
}

int main() {
    endHoldAndSeek();
    hierarchyAndPassiveMotion();
    normalizedLayoutAndRotation();
    globalIndicesAndValidation();
    boundedDecodeAccounting();
    std::cout << "Entry timeline: 5 portable behavior suites passed\n";
}
