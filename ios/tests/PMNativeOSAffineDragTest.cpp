// Exercise the actual MapDrag implementation with a small managed-call adapter.
// Geometry helpers come from Map.mm; no duplicate gesture/placement algorithm.
#include "../PhiMod/Sources/PMNativeOSMap.mm"
#include "../PhiMod/Sources/PMNativeOSMapPuzzle.hpp"
#include <array>
#include <cassert>
#include <cstring>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
namespace layout=pmnativeosmap::layout;
namespace rendering=pmnativeosmap::rendering;
namespace puzzle=pmnativeosmap::puzzle;
using Point=layout::Point;
using Handle=unsigned;
struct Managed {
    unsigned char value[32]{};
    Managed *parent=nullptr, *gameObject=nullptr, *press=nullptr, *current=nullptr, *drag=nullptr;
    Point down{}, position{};
    layout::Anchors anchors{{0,0},{1,1}};
    rendering::Transform scale{1,1,1};
    float rotation=0, alpha=1, width=1600, height=900;
    int sibling=0;
    bool active=true;
    std::vector<Managed *> queue;
    size_t cursor=0;
};
using P=Managed *;
struct Runtime {
    std::vector<std::unique_ptr<Managed>> objects;
    std::unordered_map<Handle,P> handles;
    unsigned next=1, parentWrites=0, anchorWrites=0, transformWrites=0, freed=0;
    P make() { objects.emplace_back(new Managed); return objects.back().get(); }
    template<class T> P box(T v) { P p=make(); std::memcpy(p->value,&v,sizeof(v)); return p; }
    template<class T> T unbox(P p) { T v{}; assert(p); std::memcpy(&v,p->value,sizeof(v)); return v; }
    Handle gchandle_new(P p,bool) { auto h=next++; handles[h]=p; return h; }
    void gchandle_free(Handle h) { assert(handles.erase(h)==1); ++freed; }
    P gchandle_get_target(Handle h) { return h ? handles.at(h) : nullptr; }
    int count(P p) { return int(p->queue.size()-p->cursor); }
    int enumValue(P p,const char *) { return unbox<int>(p); }
    template<class T> T get(P p,const char *) { return reinterpret_cast<T>(p->gameObject); }
    P call(P p,const char *name,std::initializer_list<const char *> = {},std::initializer_list<void *> args = {}) {
        assert(p); std::string method=name; auto a=args.begin();
        if (method=="get_rect") return box(std::array<float,4>{0,0,p->width,p->height});
        if (method=="get_button") return box(0);
        if (method=="get_pressPosition") return box(p->down);
        if (method=="get_position") return box(p->position);
        if (method=="get_pressEventCamera") return nullptr;
        if (method=="get_pointerPressRaycast") return p->press;
        if (method=="get_pointerCurrentRaycast") return p->current;
        if (method=="get_pointerDrag") return p->drag;
        if (method=="Dequeue") { assert(p->cursor<p->queue.size()); return p->queue[p->cursor++]; }
        if (method=="GetSiblingIndex") return box(p->sibling);
        if (method=="SetSiblingIndex") { p->sibling=*static_cast<int *>(*a); return nullptr; }
        if (method=="SetAsLastSibling") { p->sibling=99; return nullptr; }
        if (method=="SetParent") { p->parent=static_cast<P>(*a); assert(!*static_cast<bool *>(*(a+1))); ++parentWrites; return nullptr; }
        if (method=="set_anchorMin") { p->anchors.low=*static_cast<Point *>(*a); ++anchorWrites; return nullptr; }
        if (method=="set_anchorMax") { p->anchors.high=*static_cast<Point *>(*a); ++anchorWrites; return nullptr; }
        if (method=="set_localScale") { p->scale=*static_cast<rendering::Transform *>(*a); ++transformWrites; return nullptr; }
        if (method=="set_localEulerAngles") { p->rotation=static_cast<float *>(*a)[2]; ++transformWrites; return nullptr; }
        if (method=="set_alpha") { p->alpha=*static_cast<float *>(*a); ++transformWrites; return nullptr; }
        if (method=="SetActive") { p->active=*static_cast<bool *>(*a); return nullptr; }
        throw std::runtime_error("Unexpected managed call: "+method);
    }
    P stat(P,const char *name,std::initializer_list<const char *>,std::initializer_list<void *> args) {
        assert(std::string(name)=="ScreenPointToLocalPointInRectangle");
        auto a=args.begin(); *static_cast<Point *>(*(a+3))=*static_cast<Point *>(*(a+1)); return box(true);
    }
    P type(const char *,const char *) { return nullptr; }
    P object_new(P) { return make(); }
    P object_get_class(P) { return nullptr; }
    P class_get_parent(P) { return nullptr; }
    P class_get_methods(P,P *) { return nullptr; }
    const char *method_get_name(P) { return ""; }
    int method_get_param_count(P) { return 0; }
    P method_get_param(P,int) { return nullptr; }
    P type_get_object(P) { return nullptr; }
    P nested(P,const char *) { return nullptr; }
    P field(P,const char *,const char *,bool) { return nullptr; }
    void field_set_value(P,P,void *) {}
    P string_new(const char *) { return nullptr; }
    P invokeOn(P,P,std::initializer_list<P>) { return nullptr; }
};
struct DragMirror { int node; Handle rect; layout::Anchors anchors; rendering::Transform scale{1,1,1}; float rotation=0; };
struct DragLayer { Handle object{},rect{},parent{},group{}; std::vector<DragMirror> ancestors; bool attached=false; float alpha=1; };
struct Item {
    layout::Anchors home{},authored{},slot{},placedBounds{};
    layout::Pose pose;
    std::unique_ptr<PMOSNode> numericNode;
    rendering::Transform numericScale{1,1,1};
    float numericRotation=0;
    std::unique_ptr<DragLayer> dragLayer;
    int parent=-1,drop=-1,originalSibling=-1;
    bool placed=false,affineDrag=false,active=true;
    float inheritedAlpha=1;
    Handle rect{},hitObject{};
};
struct Map {
    Runtime r;
    std::vector<Item> items;
    Handle rootRect{},starts{},ends{},pointer{};
    bool input=true,affinePlacements=false;
    int drag=-1;
    unsigned affineMirrors=0;
    Point grab{},dragSize{},pieceSize{};
    rendering::DragPoint affineGrab{};
    Handle keep(P p) { return r.gchandle_new(p,false); }
    P get(Handle h) { return r.gchandle_get_target(h); }
};
struct Object { Handle go,rect; };
Object child(Map &m,P parent,const char *,bool=false) {
    P go=m.r.make(),rect=m.r.make(); rect->parent=parent;
    return {m.keep(go),m.keep(rect)};
}
P add(Runtime &r,P,const char *,const char *) { return r.make(); }
void flag(Runtime &r,P object,const char *name,bool value) { r.call(object,name,{}, {&value}); }
void stretch(Runtime &r,P rect,layout::Anchors a=puzzle::unit) {
    r.call(rect,"set_anchorMin",{}, {&a.low}); r.call(rect,"set_anchorMax",{}, {&a.high});
}
void setSlot(Map &m,Item &item,layout::Anchors a) { item.slot=a; stretch(m.r,m.get(item.rect),layout::lifted(a,item.pose.lift)); }
void applyPose(Map &m,Item &item,layout::Pose p) {
    rendering::Transform scale{p.scale,p.scale,1};
    if (p.scale!=item.pose.scale) m.r.call(m.get(item.rect),"set_localScale",{}, {&scale});
    if (p.lift!=item.pose.lift) stretch(m.r,m.get(item.rect),layout::lifted(item.slot,p.lift));
    item.pose=p;
}
#include "../PhiMod/Sources/PMNativeOSMapDrag.inc"
static bool near(double a,double b) { return std::abs(a-b)<2e-6; }
struct Fixture {
    Map m;
    Fixture(bool affine=true) {
        m.rootRect=m.keep(m.r.make()); m.starts=m.keep(m.r.make()); m.ends=m.keep(m.r.make());
        m.items.resize(4);
        layout::Anchors homes[]={{{.05f,.1f},{.5f,.8f}},{{.2f,.2f},{.45f,.4f}},
                                 {{.5f,.15f},{.9f,.85f}},{{.3f,.3f},{.6f,.6f}}};
        for (int i=0;i<4;++i) {
            auto &item=m.items[i]; item.home=item.slot=homes[i]; item.rect=m.keep(m.r.make());
            item.parent=i%2 ? i-1 : -1;
            item.authored=puzzle::compose(item.parent<0?puzzle::unit:m.items[item.parent].authored,item.home);
            m.get(item.rect)->parent=m.get(item.parent<0?m.rootRect:m.items[item.parent].rect);
            m.get(item.rect)->anchors=item.slot;
        }
        auto &piece=m.items[1]; piece.drop=3; piece.hitObject=m.keep(m.r.make()); piece.affineDrag=affine;
        if (affine) {
            for (int i=0;i<4;++i) m.items[i].numericNode=std::make_unique<PMOSNode>();
            m.items[0].numericScale={-1.3f,.7f,1}; m.items[0].numericRotation=-27;
            piece.numericScale={.8f,1.4f,1}; piece.numericRotation=32;
            m.items[2].numericScale={.9f,-1.2f,1}; m.items[2].numericRotation=18;
            m.items[3].numericRotation=-12;
            m.items[0].inheritedAlpha=.4f;
            buildDragLayer(m,piece);
        }
    }
    P begin(rendering::DragPoint grab={.8,.3}) {
        P e=m.r.make(); auto frame=affineFrame(m,1,{1600,900});
        auto down=rendering::project(frame.matrix,grab);
        e->down=e->position={float(down.x*1600),float(down.y*900)};
        e->press=m.r.make(); e->press->gameObject=m.get(m.items[1].hitObject);
        e->current=m.r.make(); e->current->gameObject=m.r.make(); e->drag=m.get(m.items[1].rect);
        m.get(m.starts)->queue.push_back(e);
        return e;
    }
    void pointForCenter(P e,rendering::DragPoint center) {
        auto frame=affineFrame(m,1,{1600,900});
        auto grip=rendering::project(frame.matrix,m.affineGrab), mid=rendering::project(frame.matrix,{.5,.5});
        e->position={float((center.x+grip.x-mid.x)*1600),float((center.y+grip.y-mid.y)*900)};
    }
    void assertCentered() {
        auto a=rendering::project(affineFrame(m,1,{1600,900}).matrix,{.5,.5});
        auto b=rendering::project(affineFrame(m,3,{1600,900}).matrix,{.5,.5});
        assert(near(a.x,b.x) && near(a.y,b.y));
    }
};
static void transformedGestureAndFollowing() {
    Fixture f; auto &m=f.m; auto &piece=m.items[1]; P e=f.begin();
    e->position.x+=80; e->position.y+=25;
    assert(puzzleInput(m)==-1 && m.drag==1 && piece.dragLayer->attached);
    assert(m.get(piece.rect)->parent==m.get(piece.dragLayer->parent));
    assert(m.get(piece.dragLayer->group)->alpha==.4f && m.affineMirrors==1);
    auto grip=rendering::project(affineFrame(m,1,{1600,900}).matrix,m.affineGrab);
    assert(near(grip.x,e->position.x/1600.) && near(grip.y,e->position.y/900.));
    assert(piece.numericScale.x==.8f && piece.numericRotation==32);
    // Moving/rotating source ancestors under the pointer updates the mirrored chain.
    m.items[0].numericRotation=45; m.items[0].numericScale={.75f,-1.1f,1};
    syncDragLayers(m); assert(puzzleInput(m)==-1);
    grip=rendering::project(affineFrame(m,1,{1600,900}).matrix,m.affineGrab);
    assert(near(grip.x,e->position.x/1600.) && near(grip.y,e->position.y/900.));
    auto center=rendering::project(affineFrame(m,3,{1600,900}).matrix,{.5,.5});
    f.pointForCenter(e,center); m.get(m.ends)->queue.push_back(e);
    assert(puzzleInput(m)==1 && m.drag==-1 && piece.placed && m.affinePlacements);
    f.assertCentered();
    auto before=m.r.anchorWrites, transforms=m.r.transformWrites;
    refreshAffinePlacements(m); syncDragLayers(m);
    assert(m.r.anchorWrites==before && m.r.transformWrites==transforms);
    m.items[2].numericRotation=-21; m.items[2].numericScale={1.1f,-.6f,1};
    refreshAffinePlacements(m); syncDragLayers(m); f.assertCentered();
    // A target that collapses later releases placement safely and restores home.
    m.items[3].numericScale.x=0;
    refreshAffinePlacements(m);
    assert(!piece.placed && !piece.dragLayer->attached && m.affineMirrors==0);
    assert(rendering::same(piece.slot,piece.home));
}
static void cancellationAndSingularGesture() {
    Fixture f; auto &m=f.m; auto &piece=m.items[1]; P e=f.begin();
    assert(puzzleInput(m)==-1 && m.drag==1);
    m.items[0].numericScale.x=0;
    assert(puzzleInput(m)==-1 && m.drag==-1 && !piece.placed);
    assert(!piece.dragLayer->attached && rendering::same(piece.slot,piece.home));
    auto freed=m.r.freed; f.begin(); assert(puzzleInput(m)==-1 && m.drag==-1);
    assert(m.r.freed==freed); // Singular begin never acquires a pointer handle.
    Fixture cancelled; P event=cancelled.begin(); assert(puzzleInput(cancelled.m)==-1);
    event->current->gameObject=nullptr; cancelled.m.get(cancelled.m.ends)->queue.push_back(event);
    assert(puzzleInput(cancelled.m)==-1 && !cancelled.m.items[1].placed && cancelled.m.drag==-1);
}
static void legacyGestureIsUnchanged() {
    Fixture f(false); auto &m=f.m; P e=f.begin();
    assert(puzzleInput(m)==-1 && m.drag==1 && !m.items[1].dragLayer);
    assert(m.get(m.items[1].rect)->parent==m.get(m.rootRect));
    auto center=puzzle::center(bounds(m,3));
    e->position={(center.x-m.grab.x)*1600,(center.y-m.grab.y)*900};
    m.get(m.ends)->queue.push_back(e);
    assert(puzzleInput(m)==1 && m.items[1].placed && m.drag==-1);
    assert(m.get(m.items[1].rect)->parent==m.get(m.items[2].rect));
    assert(m.affineMirrors==0 && !m.affinePlacements);
}
int main() {
    transformedGestureAndFollowing(); cancellationAndSingularGesture(); legacyGestureIsUnchanged();
    std::cout << "Affine drag: 3 implementation gesture suites passed\n";
}
