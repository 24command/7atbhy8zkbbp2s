#include "../PhiMod/Core/PMChapterC8C9Unlock.hpp"
#include "../PhiMod/Core/PMStockIntroResolver.h"
#include <cassert>
#include <limits>

using namespace pmc89unlock;
int main() {
    Window w{};
    auto near = [](double a, double b) { return std::abs(a - b) < 1e-6; };
    for (const Profile *p : {&destruction, &distortion, &signals}) {
        int chapter = p == &signals ? 9 : 8;
        assert(PMStockIntroForName(p->movie));
        assert(resolve(chapter, p->movie, p->duration, -1, -1, w));
        assert(w.show == p->show && w.hide == p->hide);
    }
    assert(resolve(8, nullptr, 26.9, -1, -1, w));
    assert(near(w.show, 12.6) && near(w.hide, 22.56666666));
    assert(resolve(9, "", 18, -1, -1, w));
    assert(near(w.show, 12.033333333) && w.hide == 18);
    assert(resolve(8, distortion.movie, 47, -1, -1, w));
    assert(near(w.show, 27.833333333) && near(w.hide, 33.8));
    // A different source does not inherit timestamps from the default movie.
    assert(resolve(9, "teaser.mp4", 2.5, -1, -1, w) && w.show == 0 && w.hide == 2.5);
    assert(resolve(9, destruction.movie, 20, -1, -1, w) && w.show == 0 && w.hide == 20);
    assert(resolve(8, nullptr, 4, -1, -1, w) && w.show == 0 && w.hide == 4);
    assert(resolve(8, nullptr, 26.9, 24, -1, w) && w.show == 24 && w.hide == 26.9);
    assert(resolve(9, nullptr, 18, 0, 3, w) && w.show == 0 && w.hide == 3);
    assert(resolve(9, nullptr, 18, -1, 2, w) && w.show == 0 && w.hide == 2);
    assert(!resolve(7, nullptr, 10, 0, 1, w));
    double nan = std::numeric_limits<double>::quiet_NaN();
    for (double duration : {0., -1., 86401., nan, std::numeric_limits<double>::infinity()})
        assert(!resolve(8, nullptr, duration, 0, 1, w));
    for (Window bad : {Window{2,2}, {3,2}, {-2,1}, {2,-2}, {0,19}, {nan,1}, {1,nan}})
        assert(!resolve(9, nullptr, 18, bad.show, bad.hide, w));
}
