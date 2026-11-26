#include "../PhiMod/Sources/PMNativeOSMap.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstring>
using namespace pmnativeosmap::layout;
static PMOSPage page;
static void near(double a, double b) { assert(std::abs(a-b) < 1e-9); }
static void build(const char *source) {
    int ok = PMBuildOSPage(source, std::strlen(source), 3, &page);
    if (!ok) std::fprintf(stderr, "%s\n", page.error);
    assert(ok);
}
static void defaults() {
    PMOSNode legacy{};
    auto a = numeric(legacy, 0);
    assert(a.scaleX == 1 && a.scaleY == 1 && a.opacity == 1 && a.rotation == 0);
    assert(a.x == 0 && a.y == 0 && a.w == 0 && a.h == 0 && a.alpha == 0);
    legacy.kind = PMOSImage;
    a = numeric(legacy, 100);
    assert(a.red == 1 && a.green == 1 && a.blue == 1 && a.alpha == 1);
    build("frame{};image{src='a.png'};hotspot{open=1};frame{scaleX=0,scaleY=0,opacity=0};"
          "image{src='a.png',color='#00000000'}");
    for (int i = 0; i < 3; ++i) {
        const auto &n = page.elements[i];
        a = numeric(n, 9);
        auto b = numeric(page, n, 9);
        assert(a.scaleX == 1 && a.scaleY == 1 && a.opacity == 1 && a.rotation == 0);
        assert(b.scaleX == a.scaleX && b.alpha == a.alpha && b.red == a.red);
        auto old = anchors(n), current = anchors(a);
        assert(old.low.x == current.low.x && old.low.y == current.low.y);
        assert(old.high.x == current.high.x && old.high.y == current.high.y);
    }
    a = numeric(page.elements[3], 0);
    assert(a.scaleX == 0 && a.scaleY == 0 && a.opacity == 0);
    a = numeric(page.elements[4], 0);
    assert(a.alpha == 0 && a.red == 0);
}
static void curves() {
    build("frame{x=.25,y=.5,w=1,h=2,color='#20408080',rotation=20,tracks={"
          "x={{time=2,value=-2},{time=4,value=2,ease='step'},{time=6,value=4}},"
          "rotation={{time=0,value=0},{time=4,value=360}},"
          "scaleX={{time=0,value=-1},{time=4,value=1}},"
          "scaleY={{time=0,value=0},{time=4,value=-4}},"
          "w={{time=0,value=0},{time=4,value=8}},h={{time=0,value=8},{time=4,value=0}},"
          "opacity={{time=0,value=0},{time=4,value=1}},"
          "red={{time=0,value=0},{time=4,value=1}},"
          "green={{time=0,value=1},{time=4,value=0}},blue={{time=0,value=.2}}}}");
    auto &n = page.elements[0];
    auto a = numeric(page, n, -5);
    assert(a.x == -2 && a.rotation == 0 && a.scaleX == -1 && a.opacity == 0);
    a = numeric(page, n, 2);
    assert(a.x == -2 && a.rotation == 180 && a.scaleX == 0 && a.scaleY == -2);
    assert(a.w == 4 && a.h == 4 && a.opacity == .5 && a.red == .5 && a.green == .5);
    near(a.blue, .2); near(a.alpha, 128./255.); near(a.y, .5);
    near(numeric(page, n, 3).x, 0);
    near(numeric(page, n, 4).x, 2);
    near(numeric(page, n, 5.999).x, 2);
    near(numeric(page, n, 6).x, 4);
    near(numeric(page, n, 1e100).x, 4);
    // Backwards sampling is independent of the previous tick.
    near(numeric(page, n, 3).x, 0);
    assert(numeric(n, 3).rotation == 20); // Safe fallback without a pool.
    n.trackLoop = 4;
    near(numeric(page, n, 4).rotation, 0);
    near(numeric(page, n, 5).rotation, 90);
    near(numeric(page, n, 8).scaleX, -1);
    n.trackLoop = 1;
    near(numeric(page, n, .5).x, -2); // Loop ends before the first key.
    auto alpha = sample(float(a.opacity * a.alpha), true, true, true, .25f);
    near(alpha.inherited, float(a.opacity * a.alpha) * .25f);
    assert(!sample(float(a.opacity), true, true, false, 1).active);
}
static void cubicAndAge() {
    build("frame{start=4,tracks={x={{time=1,value=0,ease='cubic',outTangent=2},"
          "{time=3,value=1,inTangent=0}},opacity={{time=0,value=0,ease='cubic',outTangent=100},"
          "{time=1,value=1,inTangent=-100}}}}");
    auto &n = page.elements[0];
    near(numeric(page, n, 2).x, 1.); // dt=2; Hermite tangent contribution is .5.
    near(numeric(page, n, 1).x, 0);
    near(numeric(page, n, 3).x, 1);
    near(numeric(page, n, .5).opacity, 1); // Clamp cubic overshoot to legal property bounds.
    near(nodeAge(10, 4, 7, 8), 2);
    near(nodeAge(6, 4, 7, 8), 0);
    near(nodeAge(10, 4), 6);
    near(numeric(page, n, nodeAge(10, n.start, 7, 8)).x, 1);
    near(numeric(page, n, nodeAge(10, n.start, 10, 8)).x, 0); // Reshow resets age.
    near(boundedNumeric(PMOSTrackRotation, 2e6), 1e6);
    near(boundedNumeric(PMOSTrackScaleX, -99), -16);
    near(boundedNumeric(PMOSTrackW, -99), 0);
}
// A donor polynomial in absolute segment dt converts without changing its
// duration or slope units; incoming and outgoing tangents remain independent.
static void packedPolynomial() {
    build("frame{tracks={x={{time=5,value=.1,ease='cubic',outTangent=.4},"
          "{time=7,value=1.3,inTangent=1.6,ease='cubic',outTangent=-.5},"
          "{time=8,value=.8,inTangent=-.5}}}}");
    const auto &n = page.elements[0];
    for (int i = 0; i <= 100; ++i) {
        double dt = 2.*i/100.;
        near(numeric(page, n, 5 + dt).x, ((.2*dt - .3)*dt + .4)*dt + .1);
    }
    near(numeric(page, n, 7.5).x, 1.05);
}
static void largeAndCopied() {
    build("local k={};for i=1,8192 do k[i]={time=i-1,value=(i-1)/8192} end;"
          "frame{tracks={x=k,y=k,w=k,h=k}}");
    static PMOSPage copied;
    copied = page;
    std::memset(&page, 0, sizeof(page)); // Pool offsets survive page value copies.
    for (int i = 8190; i >= 0; i -= 7) {
        auto a = numeric(copied, copied.elements[0], i + .25);
        near(a.x, (i + .25)/8192.);
        near(a.y, a.x); near(a.w, a.x); near(a.h, a.x);
    }
    PMOSTrack invalid{PMOSMaxPageTrackKeys, 1};
    near(trackValue(invalid, copied.trackKeys, copied.trackKeyCount, 0, .2), .2);
}
int main() {
    defaults(); curves(); cubicAndAge(); packedPolynomial(); largeAndCopied();
    std::puts("PMNativeOSNumericTracksTest passed");
}
