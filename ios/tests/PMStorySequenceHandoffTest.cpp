#include "../PhiMod/Sources/PMStorySequence.hpp"
#include <cassert>
#include <initializer_list>

int main() {
    pmstorysequence::Handoff<int> q;
    auto never = [](int) { assert(false); return false; };
    assert(!q.route(never));
    for (int legs : {1, 2, 3}) {
        int launched = 1, routes = 0;
        for (int left = legs - 1; left > 0; --left) {
            q.issue(left);
            assert(q.route([&](int value) { ++routes; assert(value == left); return q.route(never); }));
            assert(q.route(never)); // duplicate chapter-ready
            assert(q.take() == left);
            ++launched;
            assert(!q.take()); // duplicate selector-ready
        }
        assert(launched == legs && routes == legs - 1);
    }
    q.issue(1);
    assert(q.take() == 1 && !q.take()); // direct selector return
    q.issue(1);
    assert(!q.route([](int){ return false; }) && !q.take());
    q.issue(1);
    try { q.route([](int) -> bool { throw 1; }); assert(false); } catch (int) {}
    assert(!q.take());
    q.issue(1);
    assert(!q.route([&](int){ q.take(); q.issue(2); return false; }));
    assert(q.take() == 2); // stale route failure must not discard a newer clear
}
