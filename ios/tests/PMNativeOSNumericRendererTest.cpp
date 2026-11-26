// Renderer parity tests compile the portable parts of both owned implementations.
#include "../PhiMod/Sources/PMNativeOSMap.mm"
#include "../PhiMod/Sources/PMNativeOSEntryTimeline.mm"
#include <cassert>
#include <cstdlib>
#include <iostream>
#include <new>

static size_t allocations;
void *operator new(std::size_t n) {
    ++allocations;
    if (void *p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc();
}
void operator delete(void *p) noexcept { std::free(p); }
void operator delete(void *p, std::size_t) noexcept { std::free(p); }
namespace layout = pmnativeosmap::layout;
namespace maprender = pmnativeosmap::rendering;
namespace timeline = pmentrytimeline;
static bool near(double a, double b) { return std::abs(a-b) < 1e-6; }
static PMOSNode node() {
    PMOSNode n{};
    n.kind = PMOSFrame;
    n.parent = n.dest = n.dropIndex = n.tapFaceIndex = -1;
    n.w = n.h = 1;
    n.rgba = 0xffffffffu;
    return n;
}
static void unchangedAndStatic() {
    auto n = node();
    assert(!maprender::numericEnabled(n) && !timeline::numericEnabled(n));
    auto value = layout::numeric(n, 20);
    assert(value.scaleX == 1 && value.scaleY == 1 && value.opacity == 1);
    n.numericFlags = PMOSHasScaleX | PMOSHasScaleY | PMOSHasOpacity;
    n.scaleX = n.scaleY = n.opacity = 1;
    assert(!maprender::numericEnabled(n) && !timeline::numericEnabled(n));
    n.scaleX = 0;
    assert(maprender::numericEnabled(n) && timeline::numericEnabled(n));
    assert(layout::numeric(n, 0).scaleX == 0);
    n.scaleX = -2; n.scaleY = .5; n.rotation = 90; n.opacity = .4;
    value = layout::numeric(n, 0);
    layout::Pose motion; motion.scale = 1.5; motion.lift = .25;
    auto unity = maprender::scale(value, motion);
    auto ui = timeline::transform(value, motion, 80);
    assert(unity.x == -3 && unity.y == .75 && unity.z == 1);
    assert(maprender::unityRotation(value) == -90);
    assert(near(ui.a, 0) && near(ui.b, -3) && near(ui.c, -.75) && near(ui.d, 0));
    assert(ui.tx == 0 && ui.ty == -20); // Lift isn't scaled or rotated.
    n.kind = PMOSImage; n.numericFlags = PMOSHasColor; n.rotation = 0;
    // Existing static image/background color alone keeps the original path.
    assert(!maprender::numericEnabled(n) && !timeline::numericEnabled(n));
    for (int property = 0; property < PMOSTrackPropertyCount; ++property) {
        auto plain = node(); plain.tracks[property].count = 1;
        assert(maprender::numericEnabled(plain) && timeline::numericEnabled(plain));
    }
}
static void visibilityAgeOpacityAndLoop() {
    PMOSTrackKey keys[] = {{0,0,0,0,PMOSTrackLinear}, {4,1,0,0,PMOSTrackLinear}};
    auto p = node(), c = node();
    p.start = 4; p.numericFlags = PMOSHasOpacity; p.opacity = .5;
    c.start = 1; c.fade = 4;
    c.tracks[PMOSTrackOpacity] = {0,2};
    c.motion.enter = 2;
    // Non-looping and looping clips both begin with the parent's visibility.
    for (double loop : {0., 4.}) {
        c.trackLoop = loop;
        auto parent = timeline::sample(p, 4, nullptr, keys, 2, true);
        auto child = timeline::sample(c, 4, &parent, keys, 2, true);
        assert(parent.local == .5f && child.shownSince == 4);
        assert(child.active && child.numeric.opacity == 0 && child.local == 0);
        assert(child.pose.scale < 1); // Numeric and passive motion both start now.
        parent = timeline::sample(p, 5, nullptr, keys, 2, true);
        child = timeline::sample(c, 5, &parent, keys, 2, true);
        assert(near(child.numeric.opacity, .25) && near(child.local, .25));
        assert(near(child.inherited, .125)); // Fade uses its existing authored clock.
        auto unity = maprender::sampleNumeric(c, 5, child.shownSince, keys, 2);
        assert(unity.opacity == child.numeric.opacity);
        child = timeline::sample(c, 8, &parent, keys, 2, true);
        assert(child.numeric.opacity == (loop ? 0 : 1)); // Loop from shownSince=4.
        child = timeline::sample(c, 5, &parent, keys, 2, true);
        assert(near(child.numeric.opacity, .25)); // Absolute backward seek.
        // Simulate the Map's manual show or an ancestor's manual reshow at 10.
        // The same maximum is passed to production Map sampling and passive motion.
        for (bool own : {false, true}) {
            double manualSince = own ? 10 : 0, parentShown = own ? 4 : 10;
            double shown = std::max({c.start, manualSince, parentShown});
            auto reset = maprender::sampleNumeric(c, 10, shown, keys, 2);
            auto later = maprender::sampleNumeric(c, 11, shown, keys, 2);
            assert(reset.opacity == 0 && later.opacity == .25);
            assert(layout::nodeAge(11, c.start, manualSince, parentShown) == 1);
            auto end = maprender::sampleNumeric(c, 14, shown, keys, 2);
            assert(end.opacity == (loop ? 0 : 1));
            parent.shownSince = shown;
            child = timeline::sample(c, 11, &parent, keys, 2, true);
            assert(child.shownSince == shown && child.numeric.opacity == later.opacity);
        }
        child = timeline::sample(c, .5, nullptr, keys, 2, true);
        assert(!child.active && child.local == 0);
    }
    c.duration = 4;
    assert(!timeline::sample(c, 5, nullptr, keys, 2, true).active);
    p.hidden = 1;
    auto parent = timeline::sample(p, 4, nullptr, keys, 2, true);
    assert(!timeline::sample(c, 4, &parent, keys, 2, true).active);
    // Starts-zero generated unlock nodes retain their previous sampled values.
    c.start = 0; c.duration = c.fade = c.trackLoop = 0;
    for (double t : {0., .25, 1., 4., 9.}) {
        auto sampled = timeline::sample(c, t, nullptr, keys, 2, true);
        assert(sampled.numeric.opacity == layout::numeric(c, t, keys, 2).opacity);
    }
}
static void geometryAndInheritedFlips() {
    auto p = node(), c = node();
    p.x = .1; p.y = .2; p.w = .5; p.h = .4;
    p.numericFlags = PMOSHasScaleX; p.scaleX = -1;
    c.x = .2; c.y = .25; c.w = .4; c.h = .5;
    PMOSTrackKey keys[] = {{0,.5,0,0,PMOSTrackLinear}, {2,1,0,0,PMOSTrackLinear},
                          {0,.2,0,0,PMOSTrackLinear}, {2,.6,0,0,PMOSTrackLinear}};
    p.tracks[PMOSTrackW] = {0,2}; c.tracks[PMOSTrackX] = {2,2};
    auto pv = layout::numeric(p, 1, keys, 4), cv = layout::numeric(c, 1, keys, 4);
    auto pr = timeline::rect(pv, 1000, 600), cr = timeline::rect(cv, pr.w, pr.h);
    auto pa = layout::anchors(pv), ca = layout::anchors(cv);
    assert(near(pr.w, 750) && near(cr.x, 300) && near(cr.w, 300));
    assert(near(pa.low.y, .4) && near(pa.high.y, .8));
    assert(near(ca.low.x, .4) && near(ca.low.y, .25) && near(ca.high.y, .75));
    // Local center position inherits the parent's flip; don't flip anchors twice.
    auto pt = timeline::transform(pv, {}, pr.h);
    double localCenter = cr.x + cr.w/2 - pr.w/2;
    assert(near(pr.x + pr.w/2 + pt.a*localCenter, 400));
    auto unchanged = layout::anchors(layout::numeric(p, 1, keys, 4));
    assert(maprender::same(pa, unchanged));
    assert(!maprender::same(pa, layout::anchors(layout::numeric(p, 2, keys, 4))));
}
static void colorAndNoAllocation() {
    auto n = node(); n.kind = PMOSImage; n.rgba = 0;
    auto white = layout::numeric(n, 0);
    assert(white.red == 1 && white.green == 1 && white.blue == 1 && white.alpha == 1);
    n.numericFlags = PMOSHasColor; n.rgba = 0x80402080u;
    PMOSTrackKey keys[] = {{0,0,0,0,PMOSTrackStep}, {1,1,0,0,PMOSTrackLinear},
                          {0,0,0,1,PMOSTrackCubic}, {1,1,1,0,PMOSTrackLinear}};
    n.tracks[PMOSTrackRed] = {0,2}; n.tracks[PMOSTrackBlue] = {2,2};
    auto s = timeline::sample(n, .5, nullptr, keys, 4, true);
    assert(s.numeric.red == 0 && near(s.numeric.green, 64./255) && near(s.numeric.blue, .5));
    assert(near(s.numeric.alpha, 128./255) && s.local == 1); // Sprite alpha != group opacity.
    assert(timeline::sample(n, 1, nullptr, keys, 4, true).numeric.red == 1);
    // Copy the page's shared pool once at preparation, exactly as each renderer
    // does. Sampling reuses its stable address even after the source page dies.
    std::vector<PMOSTrackKey> retainedKeys;
    PMOSNode retainedNode;
    {
        auto page = std::make_unique<PMOSPage>();
        page->nodes = 1; page->elements[0] = n; page->trackKeyCount = 4;
        std::copy(std::begin(keys), std::end(keys), page->trackKeys);
        retainedNode = page->elements[0];
        retainedKeys.assign(page->trackKeys, page->trackKeys + page->trackKeyCount);
    }
    const auto *pool = retainedKeys.data();
    const auto capacity = retainedKeys.capacity();
    size_t before = allocations;
    double checksum = 0;
    for (int i = 0; i < 10000; ++i) {
        auto state = timeline::sample(retainedNode, (i%100)/100., nullptr,
                                      retainedKeys.data(), int(retainedKeys.size()), true);
        auto v = maprender::sampleNumeric(retainedNode, (i%100)/100., 0,
                                          retainedKeys.data(), int(retainedKeys.size()));
        assert(state.numeric.blue == v.blue && state.numeric.red == v.red);
        checksum += timeline::transform(v, state.pose, 100).a;
    }
    assert(allocations == before && checksum == 10000);
    assert(retainedKeys.data() == pool && retainedKeys.capacity() == capacity && retainedKeys.size() == 4);
}
static void boundedTintCache() {
    timeline::TintCache cache;
    using Use = timeline::TintCache::Use;
    auto n = node(); n.kind = PMOSImage;
    auto white = layout::numeric(n, 0), tint = white;
    tint.red = .5; tint.green = .25;
    assert(cache.lookup(white) == Use::Source && !cache.ready);
    assert(cache.lookup(tint) == Use::Create);
    cache.remember(tint);
    size_t before = allocations;
    for (int i = 0; i < 10000; ++i) {
        white.opacity = tint.opacity = (i%100)/100.;
        white.alpha = tint.alpha = (i%50)/50.;
        assert(cache.lookup(white) == Use::Source);
        assert(cache.lookup(tint) == Use::Cached); // White flashes do not evict tint.
    }
    assert(allocations == before);
    auto other = tint;
    other.red = std::nextafter(tint.red, 1.);
    assert(cache.lookup(other) == Use::Create); // Exact RGB: no quantization.
    cache.remember(other);
    assert(cache.lookup(other) == Use::Cached && cache.lookup(tint) == Use::Create);
    for (int i = 0; i < 10000; ++i) {
        other.green = i/10000.;
        if (cache.lookup(other) == Use::Create) cache.remember(other);
        assert(cache.lookup(other) == Use::Cached && cache.lookup(white) == Use::Source);
    }
    assert(allocations == before); // Fixed capacity also for continuous RGB ramps.
}

static void legacyImageColorRouting() {
    auto n=node(); n.kind=PMOSImage; n.rgba=0x80402080u;
    // Both renderers retain the solid backing and untouched artwork until RGB
    // is explicitly animated, including every non-color numeric property.
    for (int property=PMOSTrackX; property<=PMOSTrackOpacity; ++property) {
        n.tracks[property]={0,2};
        assert(maprender::numericEnabled(n) && timeline::numericEnabled(n));
        assert(!maprender::rgbTracks(n) && !timeline::rgbTracks(n));
        n.tracks[property]={};
    }
    n.rotation=30; n.numericFlags=PMOSHasScaleX|PMOSHasOpacity|PMOSHasColor;
    n.scaleX=-2; n.opacity=.25;
    assert(!maprender::rgbTracks(n) && !timeline::rgbTracks(n));
    for (int property=PMOSTrackRed; property<=PMOSTrackBlue; ++property) {
        n.tracks[property]={0,1};
        assert(maprender::rgbTracks(n) && timeline::rgbTracks(n));
        n.tracks[property]={};
    }
}
static void affineGeometryAndPointer() {
    using namespace maprender;
    DragFrame root{{},1600,900};
    layout::Anchors slot{{.25f,.25f},{.75f,.75f}};
    auto turned=dragFrame(root,slot,1,1,-90,0);
    auto right=project(turned.matrix,{1,.5});
    assert(near(right.x,.5) && near(right.y,.5-400./900));
    auto top=project(turned.matrix,{.5,1});
    assert(near(top.x,.5+225./1600) && near(top.y,.5));
    // Nonuniform scale + nested rotation creates shear. Keep the full matrix.
    auto parent=dragFrame(root,{{.1f,.2f},{.9f,.8f}},-1.7,.65,-31,.08);
    layout::Anchors home{{.2f,.15f},{.45f,.35f}};
    auto piece=dragFrame(parent,home,.7,-1.4,23,.2);
    for (DragPoint local : {DragPoint{.1,.2},DragPoint{.8,.9},DragPoint{.5,.5}}) {
        auto world=project(piece.matrix,local); DragPoint roundtrip;
        assert(unproject(piece.matrix,world,roundtrip));
        assert(near(roundtrip.x,local.x) && near(roundtrip.y,local.y));
        assert(contains(piece,world));
    }
    assert(!contains(piece,project(piece.matrix,{1.2,.5})));
    assert(std::abs(piece.matrix.a*piece.matrix.c+piece.matrix.b*piece.matrix.d)>1e-4);
    auto diamond=dragFrame({{},1000,1000},{{.4f,.45f},{.6f,.55f}},1,1,45,0);
    assert(contains(diamond,{.5,.5}) && !contains(diamond,{.6,.6})); // AABB would accept the latter.
    DragPoint grab{.85,.2}, pointer{.55,.42}, center;
    assert(dragCenter(piece,grab,pointer,center));
    layout::Anchors moved;
    layout::Point size{home.high.x-home.low.x,home.high.y-home.low.y};
    assert(placeCenter(parent,center,size,.2,moved));
    auto movedPiece=dragFrame(parent,moved,.7,-1.4,23,.2);
    auto held=project(movedPiece.matrix,grab);
    assert(near(held.x,pointer.x) && near(held.y,pointer.y));
    // Drag tracks can change size, rotation and parent flips under the pointer.
    parent=dragFrame(root,{{.15f,.1f},{.85f,.9f}},.9,-1.2,47,.04);
    size={.3f,.12f};
    piece=dragFrame(parent,{{.2f,.2f},{.5f,.32f}},1.3,.6,-62,.1);
    assert(dragCenter(piece,grab,pointer,center));
    assert(placeCenter(parent,center,size,.1,moved));
    held=project(dragFrame(parent,moved,1.3,.6,-62,.1).matrix,grab);
    assert(near(held.x,pointer.x) && near(held.y,pointer.y));
    auto target=dragFrame(root,{{.6f,.3f},{.85f,.6f}},-1,1.5,19,0);
    auto targetCenter=project(target.matrix,{.5,.5});
    assert(placeCenter(parent,targetCenter,size,.1,moved));
    auto snapped=dragFrame(parent,moved,1.3,.6,-62,.1);
    auto snappedCenter=project(snapped.matrix,{.5,.5});
    assert(near(snappedCenter.x,targetCenter.x) && near(snappedCenter.y,targetCenter.y));
    assert(near(snapped.matrix.a,piece.matrix.a) && near(snapped.matrix.b,piece.matrix.b));
    assert(near(snapped.matrix.c,piece.matrix.c) && near(snapped.matrix.d,piece.matrix.d));
    DragPoint out;
    auto collapsed=dragFrame(root,slot,0,1,30,0);
    assert(!unproject(collapsed.matrix,{.5,.5},out) && !contains(collapsed,{.5,.5}));
    assert(!dragCenter(collapsed,grab,pointer,out));
    assert(!placeCenter(collapsed,pointer,size,0,moved));
    assert(!placeCenter(root,pointer,{0,.1f},0,moved));
    assert(!contains(dragFrame(root,{{0,0},{0,1}},1,1,0,0),{0,.5}));
    auto heldSlot=moved;
    for (int i=0;i<10000;++i) {
        moved=geometrySlot(moved,home,home,true);
        assert(maprender::same(moved,heldSlot)); // No float re-centering jitter while placed.
    }
    assert(maprender::same(geometrySlot(moved,home,home,false),home));
    auto resized=geometrySlot(moved,home,{{.2f,.2f},{.6f,.5f}},true);
    assert(near(resized.high.x-resized.low.x,.4) && near(resized.high.y-resized.low.y,.3));
    size_t before=allocations;
    for (int i=0;i<10000;++i) {
        auto movingTarget=dragFrame(root,{{.2f,.2f},{.4f,.4f}},1,1,i%360,0);
        auto point=project(movingTarget.matrix,{.5,.5});
        assert(placeCenter(parent,point,size,.1,moved));
    }
    assert(before==allocations);
}
static void affineRoutingPreservesLegacy() {
    static PMOSPage page;
    page.nodes=4;
    for (int i=0;i<4;++i) page.elements[i]=node();
    page.elements[1].parent=0; page.elements[1].dropIndex=3;
    page.elements[3].parent=2;
    assert(!maprender::affineDrag(page,1));
    page.elements[1].numericFlags=PMOSHasOpacity;
    page.elements[1].opacity=.5;
    page.elements[1].tracks[PMOSTrackRed]={0,1};
    assert(!maprender::affineDrag(page,1)); // Tint/fade do not change legacy dragging.
    page.elements[0].rotation=20;
    assert(maprender::affineDrag(page,1)); // Source ancestor transform.
    page.elements[0].rotation=0;
    page.elements[2].tracks[PMOSTrackScaleX]={0,2};
    assert(maprender::affineDrag(page,1)); // Target ancestor can animate or flip.
    page.elements[2].tracks[PMOSTrackScaleX]={};
    page.elements[3].tracks[PMOSTrackX]={0,2};
    assert(maprender::affineDrag(page,1)); // Target geometry follows authored tracks.
    assert(!maprender::affineDrag(page,0)); // Ordinary frames allocate no drag state.
    assert(!maprender::unsupportedNestedDrag(page,1));
    page.elements[0].dropIndex=3;
    assert(maprender::unsupportedNestedDrag(page,1));
    page.elements[3].tracks[PMOSTrackX]={};
    assert(!maprender::unsupportedNestedDrag(page,1)); // Legacy nested behavior is untouched.
}

int main() {
    unchangedAndStatic(); visibilityAgeOpacityAndLoop(); geometryAndInheritedFlips(); colorAndNoAllocation(); boundedTintCache();
    legacyImageColorRouting(); affineGeometryAndPointer(); affineRoutingPreservesLegacy();
    std::cout << "Numeric renderer: 8 portable behavior suites passed\n";
}
