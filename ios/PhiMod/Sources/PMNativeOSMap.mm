#include "PMNativeOSMap.hpp"

namespace pmnativeosmap { namespace rendering {
inline bool rgbTracks(const PMOSNode &n) {
    return n.tracks[PMOSTrackRed].count || n.tracks[PMOSTrackGreen].count || n.tracks[PMOSTrackBlue].count;
}
inline bool numericEnabled(const PMOSNode &n) {
    if (n.rotation || ((n.numericFlags & PMOSHasScaleX) && n.scaleX != 1) ||
        ((n.numericFlags & PMOSHasScaleY) && n.scaleY != 1) ||
        ((n.numericFlags & PMOSHasOpacity) && n.opacity != 1)) return true;
    for (const auto &track : n.tracks) if (track.count) return true;
    return false;
}
// Numeric tracks and passive motion share the visibility epoch, including
// manual/ancestor reshow. The shared sampler wraps this age for trackLoop.
inline layout::Numeric sampleNumeric(const PMOSNode &n, double now, double shownSince,
                                      const PMOSTrackKey *keys, int keyCount) {
    return layout::numeric(n, layout::nodeAge(now, shownSince), keys, keyCount);
}
// Local normalized rect -> root normalized rect. Physical parent dimensions
// matter for rotation on a non-square canvas; inherited matrices retain shear.
struct DragPoint { double x, y; };
struct DragMatrix { double a=1, b=0, c=0, d=1, tx=0, ty=0; };
struct DragFrame { DragMatrix matrix; double width=0, height=0; };
inline DragPoint project(DragMatrix m, DragPoint p) {
    return {m.a*p.x+m.c*p.y+m.tx, m.b*p.x+m.d*p.y+m.ty};
}
inline bool unproject(DragMatrix m, DragPoint p, DragPoint &out) {
    double det=m.a*m.d-m.b*m.c;
    double norm=std::max({std::abs(m.a),std::abs(m.b),std::abs(m.c),std::abs(m.d)});
    if (!std::isfinite(det) || !std::isfinite(norm) || norm==0 || std::abs(det)<=1e-12*norm*norm) return false;
    double x=p.x-m.tx, y=p.y-m.ty;
    DragPoint value{(m.d*x-m.c*y)/det, (m.a*y-m.b*x)/det};
    if (!std::isfinite(value.x) || !std::isfinite(value.y)) return false;
    out=value; return true;
}
inline DragMatrix compose(DragMatrix p, DragMatrix n) {
    return {p.a*n.a+p.c*n.b, p.b*n.a+p.d*n.b,
            p.a*n.c+p.c*n.d, p.b*n.c+p.d*n.d,
            p.a*n.tx+p.c*n.ty+p.tx, p.b*n.tx+p.d*n.ty+p.ty};
}
inline DragFrame dragFrame(DragFrame parent, layout::Anchors slot, double sx, double sy, double degrees, double lift) {
    double w=double(slot.high.x)-slot.low.x, h=double(slot.high.y)-slot.low.y;
    if (!(parent.width>0 && parent.height>0 && w>0 && h>0)) return {{0,0,0,0,0,0},0,0};
    double radians=degrees*(3.14159265358979323846/180.), c=std::cos(radians), sn=std::sin(radians);
    double a=c*sx*w, b=sn*sx*w*parent.width/parent.height;
    double x=-sn*sy*h*parent.height/parent.width, d=c*sy*h;
    DragMatrix local{a,b,x,d,slot.low.x+w/2-(a+x)/2,slot.low.y+h/2+h*lift-(b+d)/2};
    return {compose(parent.matrix,local),parent.width*w,parent.height*h};
}
inline bool contains(DragFrame frame, DragPoint p) {
    DragPoint local;
    return unproject(frame.matrix,p,local) && local.x>=0 && local.x<1 && local.y>=0 && local.y<1;
}
inline bool dragCenter(DragFrame frame, DragPoint grab, DragPoint pointer, DragPoint &center) {
    DragPoint unused;
    if (!unproject(frame.matrix,pointer,unused)) return false;
    auto &m=frame.matrix;
    center={pointer.x-m.a*(grab.x-.5)-m.c*(grab.y-.5),pointer.y-m.b*(grab.x-.5)-m.d*(grab.y-.5)};
    return std::isfinite(center.x) && std::isfinite(center.y);
}
inline bool placeCenter(DragFrame parent, DragPoint center, layout::Point size, double lift, layout::Anchors &slot) {
    DragPoint local;
    if (!(size.x>0 && size.y>0) || !unproject(parent.matrix,center,local)) return false;
    double x=local.x-size.x/2., y=local.y-size.y/2.-size.y*lift;
    slot={{float(x),float(y)},{float(x+size.x),float(y+size.y)}};
    return std::isfinite(slot.low.x) && std::isfinite(slot.low.y) && std::isfinite(slot.high.x) && std::isfinite(slot.high.y);
}
inline layout::Anchors geometrySlot(layout::Anchors current, layout::Anchors previousHome,
                                    layout::Anchors home, bool centerOwned) {
    if (!centerOwned) return home;
    float w=home.high.x-home.low.x, h=home.high.y-home.low.y;
    if (w==previousHome.high.x-previousHome.low.x && h==previousHome.high.y-previousHome.low.y) return current;
    double x=(double(current.low.x)+current.high.x)/2, y=(double(current.low.y)+current.high.y)/2;
    return {{float(x-w/2.),float(y-h/2.)},{float(x+w/2.),float(y+h/2.)}};
}
inline bool spatialNumeric(const PMOSNode &n) {
    if (n.rotation || ((n.numericFlags & PMOSHasScaleX) && n.scaleX!=1) ||
        ((n.numericFlags & PMOSHasScaleY) && n.scaleY!=1)) return true;
    for (int i=PMOSTrackX;i<=PMOSTrackScaleY;++i) if (n.tracks[i].count) return true;
    return false;
}
inline bool affineDrag(const PMOSPage &page, int index) {
    if (page.elements[index].dropIndex<0) return false;
    for (int start : {index,page.elements[index].dropIndex})
        for (int i=start;i>=0;i=page.elements[i].parent)
            if (spatialNumeric(page.elements[i])) return true;
    return false;
}
inline bool unsupportedNestedDrag(const PMOSPage &page, int index) {
    if (!affineDrag(page,index)) return false;
    for (int i=page.elements[index].parent;i>=0;i=page.elements[i].parent)
        if (page.elements[i].dropIndex>=0) return true;
    return false;
}
struct Transform { float x, y, z; };
struct Color { float red, green, blue, alpha; };
inline Color color(const layout::Numeric &n) {
    return {float(n.red), float(n.green), float(n.blue), float(n.alpha)};
}
inline bool same(Color a, Color b) {
    return a.red == b.red && a.green == b.green && a.blue == b.blue && a.alpha == b.alpha;
}
inline Transform scale(const layout::Numeric &n, const layout::Pose &p) {
    return {float(n.scaleX * p.scale), float(n.scaleY * p.scale), 1};
}
inline float unityRotation(const layout::Numeric &n) { return float(-n.rotation); }
inline bool same(layout::Anchors a, layout::Anchors b) {
    return a.low.x == b.low.x && a.low.y == b.low.y && a.high.x == b.high.x && a.high.y == b.high.y;
}
}}

#ifdef __OBJC__
#include "PMNativeOSMapPuzzle.hpp"
#include "PMNativeOSMapFlash.hpp"
#include "PMNativeOSMapMediaTiming.hpp"
#include "PMIL2CPP.hpp"
#import "PMDiagnostics.h"
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#include <chrono>
#include <memory>

namespace pmnativeosmap {
namespace {
using pmbridge::P;
using layout::Point;
using Clock = std::chrono::steady_clock;
using Handle = uint32_t;
struct Media;
struct DragMirror {
    int node;
    Handle rect;
    layout::Anchors anchors;
    rendering::Transform scale{1,1,1};
    float rotation=0;
};
struct DragLayer {
    Handle object{}, rect{}, parent{}, group{};
    std::vector<DragMirror> ancestors;
    bool attached=false;
    float alpha=1;
};
struct Item {
    std::shared_ptr<Media> media;
    layout::Anchors home{}, authored{}, slot{}, placedBounds{};
    PMOSMotion motion{};
    layout::Pose pose;
    std::unique_ptr<PMOSNode> numericNode; // Absent on the unchanged legacy path.
    rendering::Transform numericScale{1,1,1};
    float numericRotation = 0;
    Handle tint{};
    rendering::Color tintColor{1,1,1,1};
    Handle flash{}, pictureRect{}, silhouette{};
    int feedbackOwner = -1;
    bool locked = false;
    int drop = -1, originalSibling = -1;
    bool placed = false, affineDrag = false;
    std::unique_ptr<DragLayer> dragLayer;
    Handle hitObject{};
    Handle object{}, rect{}, group{}, button{};
    int screen{}, parent{};
    double start{}, duration{}, fade{}, manualSince{}, shownSince{};
    bool manual{}, active = true;
    float alpha = 1, inheritedAlpha = 1;
};
struct Map {
    explicit Map(Runtime &runtime): r(runtime) {}
    Runtime &r;
    id<NSObject> resignObserver = nil;
    Visit id{};
    Activate activate = nil;
    layout::PendingTap tap;
    readiness::Ticket preparation;
    Handle root{}, rootGroup{}, orphan{};
    std::vector<Handle> handles, assets;
    std::vector<Item> items;
    std::vector<PMOSTrackKey> trackKeys;
    int layer{}, screens{}, page{};
    int transitionScreen = -1;
    Handle rootRect{}, pointer{}, starts{}, ends{};
    int drag = -1;
    Point grab{}, dragSize{}, pieceSize{};
    rendering::DragPoint affineGrab{};
    bool affinePlacements = false;
    unsigned affineMirrors = 0;
    bool visible{}, running{}, input{};
    Clock::time_point resumed;
    double elapsed{};
    Handle keep(P value) {
        if (!value) throw std::runtime_error("Map object creation failed");
        handles.push_back(0);
        handles.back() = r.gchandle_new(value, false);
        if (!handles.back()) throw std::runtime_error("Map GC handle allocation failed");
        return handles.back();
    }
    P get(Handle h) { return h ? r.gchandle_get_target(h) : nullptr; }
    double time() const { return elapsed + (running ? std::chrono::duration<double>(Clock::now()-resumed).count() : 0.); }
};
std::unique_ptr<Map> current;
Visit sequence{};
double wallTime() { return std::chrono::duration<double>(Clock::now().time_since_epoch()).count(); }

P add(Runtime &r, P obj, const char *ns, const char *name) {
    return r.call(obj, "AddComponent", {"System.Type"}, {r.type_get_object(r.class_get_type(r.type(ns, name)))});
}
void flag(Runtime &r, P obj, const char *method, bool value) {
    r.call(obj, method, {"System.Boolean"}, {&value});
}
void destroy(Map &m, Handle handle) {
    P obj = m.get(handle);
    if (m.r.alive(obj)) m.r.stat(m.r.type("UnityEngine", "Object"), "Destroy", {"UnityEngine.Object"}, {obj});
}
template<class Work> bool checked(Work work, NSString **reason = nullptr) {
    NSString *message = nil;
    @try {
        try { work(); return true; }
        catch (const std::exception &e) { message = [NSString stringWithUTF8String:e.what()]; }
    } @catch (NSException *e) { message = e.reason; }
    message = message ?: @"Native map operation failed";
    if (reason) *reason = message;
    PMDiagnosticsWrite(message.UTF8String);
    return false;
}
void dispose(Map &m) {
    if (m.resignObserver) [NSNotificationCenter.defaultCenter removeObserver:m.resignObserver];
    if (m.root) checked([&]{ if (m.r.alive(m.get(m.root))) flag(m.r, m.get(m.root), "SetActive", false); });
    if (m.orphan && m.orphan != m.root) checked([&]{ destroy(m, m.orphan); });
    checked([&]{ destroy(m, m.root); });
    for (auto i = m.assets.rbegin(); i != m.assets.rend(); ++i) checked([&]{ destroy(m, *i); });
    if (m.pointer) m.r.gchandle_free(m.pointer);
    for (Handle h : m.handles) if (h) m.r.gchandle_free(h);
}
void stretch(Runtime &r, P rect, layout::Anchors a = {{0,0},{1,1}}) {
    Point zero{};
    r.call(rect, "set_anchorMin", {"UnityEngine.Vector2"}, {&a.low});
    r.call(rect, "set_anchorMax", {"UnityEngine.Vector2"}, {&a.high});
    r.call(rect, "set_offsetMin", {"UnityEngine.Vector2"}, {&zero});
    r.call(rect, "set_offsetMax", {"UnityEngine.Vector2"}, {&zero});
}
struct Object { Handle go, rect; };
Object child(Map &m, P parent, const char *name, bool root = false) {
    Runtime &r = m.r;
    P go = r.object_new(r.type("UnityEngine", "GameObject"));
    Handle obj = m.orphan = m.keep(go);
    r.call(go, ".ctor", {"System.String"}, {r.string_new(name)});
    if (root) { m.root = obj; flag(r, go, "SetActive", false); }
    P rect = add(r, go, "UnityEngine", "RectTransform");
    bool world = false;
    r.call(rect, "SetParent", {"UnityEngine.Transform", "System.Boolean"}, {parent, &world});
    m.orphan = 0;
    r.call(go, "set_layer", {"System.Int32"}, {&m.layer});
    return {obj, m.keep(rect)};
}
P fit(Runtime &r, P go, float aspect, bool cover) {
    P fitter = add(r, go, "UnityEngine.UI", "AspectRatioFitter");
    int mode = cover ? 4 : 3; // EnvelopeParent / FitInParent
    r.call(fitter, "set_aspectRatio", {"System.Single"}, {&aspect});
    r.call(fitter, "set_aspectMode", {"UnityEngine.UI.AspectRatioFitter.AspectMode"}, {&mode});
    return fitter;
}
// Normalize stills (including WebP and EXIF orientation) to a bounded PNG for
// Unity's LoadImage. Duplicate paths share the same texture and sprite per map.
NSData *encodeImage(CGImageRef image) {
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, nullptr);
    if (dest) CGImageDestinationAddImage(dest, image, nullptr);
    bool ok = dest && CGImageDestinationFinalize(dest);
    if (dest) CFRelease(dest);
    if (!ok || !data.length || data.length > INT32_MAX) throw std::runtime_error("Map thumbnail encode failed");
    return data;
}
CGImageRef createThumbnail(NSString *path, int pixels) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nullptr);
    if (!src) throw std::runtime_error("Map image could not be opened");
    NSDictionary *opts = @{(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(pixels),
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES};
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opts);
    CFRelease(src);
    if (!image) throw std::runtime_error("Map thumbnail decode failed");
    return image;
}
struct Art { Handle sprite, silhouette; float aspect; };
Handle newTexture(Map &m) {
    Runtime &r = m.r;
    P tex = r.object_new(r.type("UnityEngine", "Texture2D"));
    m.assets.push_back(m.keep(tex));
    int size = 2, format = 4;
    bool mip = false;
    r.call(tex, ".ctor", {"System.Int32", "System.Int32", "UnityEngine.TextureFormat", "System.Boolean"}, {&size,&size,&format,&mip});
    return m.assets.back();
}
void upload(Runtime &r, P tex, NSData *data, bool discardCPU) {
    P bytes = r.array_new(r.type("System", "Byte"), data.length);
    Handle temporary = bytes ? r.gchandle_new(bytes, false) : 0;
    if (!temporary) throw std::runtime_error("Map image byte allocation failed");
    struct Release { Runtime &r; Handle h; ~Release(){ r.gchandle_free(h); } } release{r, temporary};
    int zero = 0, count = int(data.length);
    const void *ptr = data.bytes;
    r.stat(r.type("System.Runtime.InteropServices", "Marshal"), "copy_from_unmanaged",
           {"System.IntPtr", "System.Int32", "System.Array", "System.Int32"}, {&ptr, &zero, bytes, &count});
    if (!r.unbox<bool>(r.stat(r.type("UnityEngine", "ImageConversion"), "LoadImage",
        {"UnityEngine.Texture2D", "System.Byte[]", "System.Boolean"}, {tex,bytes,&discardCPU})))
        throw std::runtime_error("Unity rejected map image");
}
Handle loadSprite(Map &m, CGImageRef image, bool readable) {
    Runtime &r = m.r;
    NSData *data = encodeImage(image);
    P tex = m.get(newTexture(m));
    upload(r, tex, data, !readable);
    float rect[] = {0,0,float(r.unbox<int>(r.call(tex,"get_width"))),float(r.unbox<int>(r.call(tex,"get_height")))};
    Point pivot{.5f,.5f}; float ppu = 100;
    P sprite = r.stat(r.type("UnityEngine", "Sprite"), "Create", {"UnityEngine.Texture2D", "UnityEngine.Rect", "UnityEngine.Vector2", "System.Single"}, {tex,rect,&pivot,&ppu});
    Handle handle = m.keep(sprite);
    m.assets.push_back(handle);
    return handle;
}
Art loadArt(Map &m, NSString *path, int pixels, bool readable, bool needsSilhouette) {
    CGImageRef image = createThumbnail(path, pixels);
    CGImageRef silhouette = nullptr;
    Art art{};
    @try {
        art.aspect = float(CGImageGetWidth(image)) / float(CGImageGetHeight(image));
        art.sprite = loadSprite(m, image, readable);
        if (needsSilhouette) {
            silhouette = createFlashSilhouette(image);
            if (!silhouette) throw std::runtime_error("Map flash silhouette creation failed");
            art.silhouette = loadSprite(m, silhouette, false);
        }
    } @finally {
        if (silhouette) CGImageRelease(silhouette);
        CGImageRelease(image);
    }
    return art;
}
#include "PMNativeOSMapMedia.inc"
void setSlot(Map &m, Item &item, layout::Anchors base) {
    item.slot = base;
    stretch(m.r, m.get(item.rect), layout::lifted(base, item.pose.lift));
}
void applyPose(Map &m, Item &item, layout::Pose pose) {
    if (item.pose.scale != pose.scale) {
        float scale[] = {pose.scale, pose.scale, 1};
        m.r.call(m.get(item.rect), "set_localScale", {"UnityEngine.Vector3"}, {scale});
    }
    if (item.pose.lift != pose.lift)
        stretch(m.r, m.get(item.rect), layout::lifted(item.slot, pose.lift));
    if (item.flash && item.pose.white != pose.white) {
        float white[] = {1,1,1,pose.white};
        m.r.call(m.get(item.flash), "set_color", {"UnityEngine.Color"}, {white});
    }
    item.pose = pose;
}
// Only changed properties cross the managed boundary. Geometry is local to the
// parent; Unity inherits rotations and signed scales around the default center.
void applyNumeric(Map &m, Item &item, const layout::Numeric &value, layout::Pose pose) {
    auto scale = rendering::scale(value, pose);
    if (item.numericScale.x != scale.x || item.numericScale.y != scale.y) {
        m.r.call(m.get(item.rect), "set_localScale", {"UnityEngine.Vector3"}, {&scale});
        item.numericScale = scale;
    }
    float rotation = rendering::unityRotation(value);
    if (item.numericRotation != rotation) {
        float euler[] = {0, 0, rotation};
        m.r.call(m.get(item.rect), "set_localEulerAngles", {"UnityEngine.Vector3"}, {euler});
        item.numericRotation = rotation;
    }
    auto home = layout::anchors(value);
    auto previousHome = item.home;
    item.home = home;
    item.authored = puzzle::compose(item.parent < 0 ? puzzle::unit : m.items[item.parent].authored, home);
    if ((m.drag != int(&item - m.items.data()) && !item.placed) || item.affineDrag) {
        // While pointer/target owns the center, authored size/rotation/scale may
        // continue animating. Keep full local transforms, including parent shear.
        auto slot = rendering::geometrySlot(item.slot,previousHome,home,
            m.drag == int(&item - m.items.data()) || item.placed);
        auto before = layout::lifted(item.slot, item.pose.lift), after = layout::lifted(slot, pose.lift);
        if (before.low.x != after.low.x || before.low.y != after.low.y)
            m.r.call(m.get(item.rect), "set_anchorMin", {"UnityEngine.Vector2"}, {&after.low});
        if (before.high.x != after.high.x || before.high.y != after.high.y)
            m.r.call(m.get(item.rect), "set_anchorMax", {"UnityEngine.Vector2"}, {&after.high});
        item.slot = slot;
    }
    auto color = rendering::color(value);
    if (item.tint && !rendering::same(item.tintColor, color)) {
        m.r.call(m.get(item.tint), "set_color", {"UnityEngine.Color"}, {&color});
        item.tintColor = color;
    }
    if (item.flash && item.pose.white != pose.white) {
        float white[] = {1,1,1,pose.white};
        m.r.call(m.get(item.flash), "set_color", {"UnityEngine.Color"}, {white});
    }
    item.pose = pose;
}
#include "PMNativeOSMapDrag.inc"

int preflight(const PMOSPage &page, NSArray<NSDictionary *> *models, NSMutableSet<NSString *> *maskPaths) {
    if (page.nodes <= 0 || page.nodes > PMOSMaxNodes || models.count != NSUInteger(page.nodes) ||
        page.screens <= 0 || page.screens > PMOSMaxScreens) throw std::runtime_error("Map declaration/model count mismatch");
    int transition = layout::reservedScreen(page);
    if (transition >= page.screens || transition < -1 || page.initialScreen < -1 ||
        (page.initialScreen >= 0 && !layout::canDisplay(page.screens,transition,page.initialScreen)))
        throw std::runtime_error("Map has an invalid initial or reserved screen");
    NSMutableSet<NSString *> *paths = [NSMutableSet set];
    NSUInteger animatedNodes = 0;
    for (int i = 0; i < page.nodes; ++i) {
        const auto &n = page.elements[i];
        if (layout::reserved(page,n.screen)) continue; // Owned by the transition renderer, not this map.
        if (n.screen < 0 || n.screen >= page.screens || n.parent < -1 || n.parent >= i ||
            (n.parent >= 0 && (page.elements[n.parent].screen != n.screen || page.elements[n.parent].kind != PMOSFrame)))
            throw std::runtime_error("Map node has invalid screen or parent");
        if (n.songSuppressed) continue;
        NSDictionary *model = models[i];
        if (n.dropIndex < -1 || n.dropIndex >= page.nodes || (n.dropIndex >= 0 && page.elements[n.dropIndex].screen != n.screen))
            throw std::runtime_error("Invalid map drop target");
        NSString *path = model[@"path"];
        if (!path && n.src[0]) throw std::runtime_error("Map image is missing its resolved path");
        if (!path) continue; // A locked song may intentionally have no cover.
        if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath) throw std::runtime_error("Map image requires a resolved absolute path");

        if (isAnimated(path)) ++animatedNodes;
        else [paths addObject:path];
    }
    // Core owns schema validation; this is a renderer capability guard. A
    // stationary authored chain is mirrored exactly, including animated TRS.
    // A draggable ancestor can change topology and cannot use that fixed chain.
    for (int i=0;i<page.nodes;++i)
        if (!layout::suppressed(page,page.elements[i]) && rendering::unsupportedNestedDrag(page,i))
            throw std::runtime_error("Numeric draggable nodes cannot have draggable ancestors; use a stationary parent frame");
    // Each distinct named still contributes one extra texture to the same pixel budget.
    for (int i = 0; i < page.nodes; ++i) {
        const auto &n = page.elements[i];
        if (layout::suppressed(page,n)) continue;
        if (!n.tapFace[0] || !n.motion.tapTime || !n.motion.tapFlash) continue;
        if (n.tapFaceIndex <= i || n.tapFaceIndex >= page.nodes)
            throw std::runtime_error("Invalid map flash face");
        if (page.elements[n.tapFaceIndex].kind != PMOSImage) continue;
        NSString *path = models[n.tapFaceIndex][@"path"];
        if (path && !isAnimated(path)) [maskPaths addObject:path];
    }
    return std::min(1536, int(std::sqrt(4.*1024*1024 / std::max<NSUInteger>(1, paths.count + maskPaths.count + animatedNodes))));
}
void validateParent(Runtime &r, P parent) {
    if (!r.alive(parent) || r.object_get_class(parent) != r.type("UnityEngine", "RectTransform"))
        throw std::runtime_error("Map requires a private canvas RectTransform");
    P go = r.call(parent, "get_gameObject");
    P scene = r.call(go, "get_scene");
    if (!scene) throw std::runtime_error("Map parent has no Unity scene");
    P path = r.invokeOn(r.resolve(r.object_get_class(scene), "get_path"), r.object_unbox(scene), {});
    NSString *sceneName = r.string(path).lastPathComponent.stringByDeletingPathExtension;
    if (!sceneName.length || [sceneName isEqualToString:@"SongSelector"]) throw std::runtime_error("Map requires its own chapter scene");
    P canvas = r.type("UnityEngine", "Canvas");
    for (P tr = parent; tr; tr = r.call(tr,"get_parent"))
        if (r.component(r.call(tr,"get_gameObject"),canvas)) return;
    throw std::runtime_error("Map parent is outside a Unity canvas");
}
void caption(Map &m, P parent, P font, const char *label) {
    Runtime &r = m.r;
    if (!r.alive(font)) throw std::runtime_error("Map label requires a live Unity font");
    Object o = child(m, parent, "Label");
    stretch(r, m.get(o.rect));
    P text = add(r, m.get(o.go), "UnityEngine.UI", "Text");
    r.call(text, "set_font", {"UnityEngine.Font"}, {font});
    flag(r, text, "set_supportRichText", false);
    r.text(text, label);
    int center = 4, minimum = 14, size = 24;
    r.call(text, "set_alignment", {"UnityEngine.TextAnchor"}, {&center});
    r.call(text, "set_fontSize", {"System.Int32"}, {&size});
    flag(r, text, "set_resizeTextForBestFit", true);
    r.call(text, "set_resizeTextMinSize", {"System.Int32"}, {&minimum});
    r.call(text, "set_resizeTextMaxSize", {"System.Int32"}, {&size});
    flag(r, text, "set_raycastTarget", false);
}
void build(Map &m, P parent, const PMOSPage &page, NSArray<NSDictionary *> *models, P font, int pixels, NSSet<NSString *> *maskPaths) {
    Runtime &r = m.r;
    m.screens = page.screens;
    m.transitionScreen = layout::reservedScreen(page);
    m.page = page.initialScreen; // -1 is the caller's card sheet, never the reserved timeline.
    m.layer = r.unbox<int>(r.call(r.call(parent, "get_gameObject"), "get_layer"));
    Object root = child(m, parent, "PhiMod Authored Map", true);
    m.rootRect = root.rect;
    stretch(r, m.get(root.rect));
    if (page.aspect > 0) fit(r, m.get(root.go), float(page.aspect), false);
    add(r, m.get(root.go), "UnityEngine.UI", "RectMask2D");
    m.rootGroup = m.keep(add(r, m.get(root.go), "UnityEngine", "CanvasGroup"));
    std::map<std::string,Art> art;
    NSMutableSet *readable = [NSMutableSet set];
    bool hasBacking = false;
    for (int i = 0; i < page.nodes; ++i) {
        if (layout::suppressed(page,page.elements[i])) continue;
        NSString *path = models[i][@"path"];
        if (page.elements[i].dropIndex >= 0 && !hasBacking) {
            P backing = add(r,m.get(root.go),"UnityEngine.UI","Image");
            hasBacking = true;
            float clear[4]{};
            r.call(backing,"set_color",{"UnityEngine.Color"},{clear});
            flag(r,backing,"set_raycastTarget",true);
        }
        if (page.elements[i].alphaHit && path) [readable addObject:path];
    }
    for (int i = 0; i < page.nodes; ++i) @autoreleasepool {
        const PMOSNode &n = page.elements[i];
        Item item;
        if (layout::suppressed(page,n)) {
            item.active = false;
            m.items.push_back(std::move(item)); // Reserve the index without creating Unity objects.
            continue;
        }
        item.screen = n.screen; item.parent = n.parent; item.manual = !n.hidden;
        NSString *path = models[i][@"path"];
        bool animated = isAnimated(path);
        bool alphaHit = n.alphaHit && !animated;
        // Legacy image color is a backing rectangle, not a sprite tint. Only an
        // explicit RGB track opts into applying sampled color to the artwork.
        bool spriteTint = n.kind == PMOSImage && rendering::rgbTracks(n);
        item.drop = n.dropIndex;
        item.affineDrag = rendering::affineDrag(page,i);
        item.motion = n.motion;
        if (rendering::numericEnabled(n)) {
            item.numericNode = std::make_unique<PMOSNode>(n);
            if (m.trackKeys.empty() && page.trackKeyCount)
                m.trackKeys.assign(page.trackKeys, page.trackKeys + page.trackKeyCount);
        }
        item.feedbackOwner = layout::feedbackOwner(n, i, n.parent < 0 ? -1 : m.items[n.parent].feedbackOwner);
        item.locked = n.challenge && !n.handler;

        item.home = layout::anchors(n);
        item.authored = puzzle::compose(n.parent < 0 ? puzzle::unit : m.items[n.parent].authored, item.home);
        item.start = n.start; item.duration = n.duration; item.fade = n.fade;
        Object o = child(m, m.get(n.parent < 0 ? root.rect : m.items[n.parent].rect), n.id[0] ? n.id : "Element");
        item.object = o.go; item.rect = o.rect;
        P go = m.get(o.go), tr = m.get(o.rect);
        setSlot(m, item, item.home);
        add(r, go, "UnityEngine.UI", "RectMask2D");
        item.group = m.keep(add(r, go, "UnityEngine", "CanvasGroup"));
        bool action = layout::actionable(n);
        if (action || item.locked || (n.rgba & 255)) {
            P surface = add(r, go, "UnityEngine.UI", "Image");
            float color[] = {float(n.rgba>>24)/255, float((n.rgba>>16)&255)/255,
                             float((n.rgba>>8)&255)/255, float(n.rgba&255)/255};
            if (spriteTint) color[3] = 0;
            r.call(surface, "set_color", {"UnityEngine.Color"}, {color});
            if (rendering::rgbTracks(n) && n.kind != PMOSImage) {
                item.tint = m.keep(surface);
                item.tintColor = {color[0], color[1], color[2], color[3]};
            }
            flag(r, surface, "set_raycastTarget", (action || item.locked) && !alphaHit);
            if (item.drop >= 0 && !alphaHit) item.hitObject = o.go;
            if (action || item.locked) {
                P button = add(r, go, "UnityEngine.UI", "Button");
                item.button = m.keep(button);
                if (item.locked) flag(r, button, "set_interactable", false);
                r.call(button, "set_targetGraphic", {"UnityEngine.UI.Graphic"}, {surface});
                int none = 0;
                r.call(button, "set_transition", {"UnityEngine.UI.Selectable.Transition"}, {&none});
            }
        }
        if (animated) {
            item.media = buildMedia(m, tr, path, n.fill, n.loop, pixels);
            if (spriteTint) item.tint = item.media->raw;
        } else if (path) {
            const char *key = path.UTF8String;
            if (!key) throw std::runtime_error("Invalid map image path");
            auto found = art.find(key);
            if (found == art.end()) {
                Art loaded = loadArt(m, path, pixels, [readable containsObject:path], [maskPaths containsObject:path]);
                found = art.emplace(key, loaded).first;
            }
            item.silhouette = found->second.silhouette;
            Object picture = child(m, tr, "Artwork");
            item.pictureRect = picture.rect;
            P image = add(r, m.get(picture.go), "UnityEngine.UI", "Image");
            if (spriteTint) item.tint = m.keep(image);
            stretch(r, m.get(picture.rect));
            r.call(image, "set_sprite", {"UnityEngine.Sprite"}, {m.get(found->second.sprite)});
            flag(r, image, "set_raycastTarget", alphaHit);
            if (alphaHit) {
                float threshold = 51.5f / 255;
                r.call(image, "set_alphaHitTestMinimumThreshold", {"System.Single"}, {&threshold});
                item.hitObject = picture.go;
            }
            fit(r, m.get(picture.go), found->second.aspect, n.fill);
        }
        if (item.affineDrag) buildDragLayer(m,item);
        if (item.drop >= 0) bindDrag(m,go);
        if (n.label[0] && n.kind != PMOSHotspot) caption(m, tr, font, n.label);
        m.items.push_back(std::move(item));
    }
    // Append after all authored children so artwork cannot obscure the flash.
    for (int i = 0; i < page.nodes; ++i) {
        Item &item = m.items[i];
        if (!item.motion.tapTime || !item.motion.tapFlash) continue;
        int face = page.elements[i].tapFaceIndex;
        const Item &target = m.items.at(face);
        if (!target.rect) continue;
        bool masked = page.elements[i].tapFace[0] && page.elements[face].kind == PMOSImage && target.pictureRect;
        Handle rect = masked ? target.pictureRect : target.rect;
        Object overlay = child(m, m.get(rect), "Tap flash");
        stretch(r, m.get(overlay.rect));
        P graphic = add(r, m.get(overlay.go), "UnityEngine.UI", "Image");
        if (masked) {
            if (!target.silhouette) throw std::runtime_error("Missing map flash silhouette");
            r.call(graphic, "set_sprite", {"UnityEngine.Sprite"}, {m.get(target.silhouette)});
        }
        flag(r, graphic, "set_raycastTarget", false);
        float clearWhite[] = {1,1,1,0};
        r.call(graphic, "set_color", {"UnityEngine.Color"}, {clearWhite});
        item.flash = m.keep(graphic);
    }
}
void refresh(Map &m, double t) {
    if (!m.r.alive(m.get(m.root))) throw std::runtime_error("Map scene has unloaded");
    for (size_t i = 0; i < m.items.size(); ++i) {
        Item &item = m.items[i];
        if (!item.object) continue;
        const Item *parent = item.parent < 0 ? nullptr : &m.items[item.parent];
        float alpha = layout::opacity(t, item.start, item.duration, item.fade);
        item.shownSince = std::max({item.start, item.manualSince, parent ? parent->shownSince : 0.});
        layout::Numeric numeric;
        if (item.numericNode && alpha >= 0 && item.screen == m.page && item.manual && (!parent || parent->active)) {
            numeric = rendering::sampleNumeric(*item.numericNode, t, item.shownSince,
                                               m.trackKeys.data(), int(m.trackKeys.size()));
            alpha *= float(numeric.opacity);
        }
        auto state = layout::sample(alpha, item.screen == m.page, item.manual,
                                    !parent || parent->active, parent ? parent->inheritedAlpha : 1.f);
        bool active = state.active;
        if (item.active != active) {
            flag(m.r, m.get(item.object), "SetActive", active);
            item.active = active;
        }
        if (item.media) {
            auto mode = readiness::mediaMode(active,m.preparation.active(),m.visible,m.running);
            if (mode == readiness::MediaMode::Warm) warmMedia(m, *item.media, m.preparation.expired(wallTime()));
            else syncMedia(m, *item.media, mode == readiness::MediaMode::Play, t);
        }
        if (!active) continue;
        if (item.numericNode || item.motion.enter || item.motion.bob || item.motion.tapTime) {
            float pulse = m.tap.owner == int(i) ? m.tap.pulse(t) : 0;
            auto pose = layout::motion(item.motion, t - item.shownSince, pulse);
            if (m.drag == int(i) && !item.affineDrag) pose = {}; // Legacy root-reparent drag.
            if (item.numericNode) applyNumeric(m, item, numeric, pose);
            else applyPose(m, item, pose);
        }
        if (item.alpha != alpha) {
            m.r.call(m.get(item.group), "set_alpha", {"System.Single"}, {&alpha});
            item.alpha = alpha;
        }
        float inherited = state.inherited;
        if ((item.inheritedAlpha > .01f) != (inherited > .01f)) {
            flag(m.r, m.get(item.group), "set_blocksRaycasts", inherited > .01f);
            flag(m.r, m.get(item.group), "set_interactable", inherited > .01f);
        }
        item.inheritedAlpha = inherited;
    }
    if (m.affinePlacements) refreshAffinePlacements(m);
    if (m.affineMirrors) syncDragLayers(m);
    if (m.tap.busy() && !eligible(m, m.tap.node)) m.tap.cancel();
}
bool matches(Runtime &r, Visit id) {
    return NSThread.isMainThread && current && &current->r == &r && current->id == id;
}
int owned(Runtime &r, P button) {
    if (!NSThread.isMainThread || !current || &current->r != &r || !button) return -1;
    for (size_t i = 0; i < current->items.size(); ++i) {
        Handle h = current->items[i].button;
        if (h && current->get(h) == button) return int(i);
    }
    return -1;
}
template<class Work> bool change(Runtime &r, Visit id, Work work) {
    if (!matches(r, id)) return false;
    if (checked([&]{ work(*current); refresh(*current, current->time()); })) return true;
    close(r, id);
    return false;
}
} // namespace

Visit open(Runtime &r, P parent, const PMOSPage &page, NSArray<NSDictionary *> *models, P font, Activate activate, NSString **reason) {
    if (reason) *reason = nil;
    if (!NSThread.isMainThread || current || !activate) {
        if (reason) *reason = @"Native map needs a main-thread owner and activation callback";
        return 0;
    }
    auto m = std::make_unique<Map>(r);
    if (!checked([&]{
        NSMutableSet<NSString *> *maskPaths = [NSMutableSet set];
        int pixels = preflight(page, models, maskPaths);
        validateParent(r, parent);
        build(*m, parent, page, models, font, pixels, maskPaths);
        refresh(*m, m->time());
    }, reason)) { dispose(*m); return 0; }
    if (++sequence == 0) ++sequence;
    m->id = sequence;
    m->activate = [activate copy];
    Visit token = m->id;
    m->resignObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *) {
            if (current && current->id == token) current->tap.cancel();
        }];
    current = std::move(m);
    return sequence;
}
bool displayPage(Runtime &r, Visit id, int screen) {
    if (!matches(r,id) || !layout::canDisplay(current->screens,current->transitionScreen,screen)) return false;
    return change(r,id,[&](Map &m){
        m.tap.cancel();
        cancelDrag(m);
        if (m.preparation.active() && !m.visible) flag(r,m.get(m.root),"SetActive",false);
        m.preparation.invalidate();
        for (auto &item : m.items) {
            if (item.media) stopMedia(m, *item.media);
            item.manualSince = 0;
        }
        m.page = screen;
        m.elapsed = 0;
        m.resumed = Clock::now();
    });
}
bool setElement(Runtime &r, Visit id, int index, bool visible) {
    if (!matches(r,id) || index < 0 || size_t(index) >= current->items.size() || !current->items[index].object) return false;
    return change(r,id,[&](Map &m){
        auto &item = m.items[index];
        if (visible && !item.manual) item.manualSince = m.time();
        item.manual = visible;
    });
}
bool prepare(Runtime &r, Visit id, uint64_t token) {
    if (!matches(r,id) || !token || current->visible || current->running || current->elapsed != 0) return false;
    return change(r,id,[&](Map &m){
        m.preparation.begin(token,m.page,wallTime());
        m.tap.cancel(); cancelDrag(m);
        m.input = false;
        flag(r,m.get(m.rootGroup),"set_interactable",false);
        flag(r,m.get(m.rootGroup),"set_blocksRaycasts",false);
        float alpha = 0;
        r.call(m.get(m.rootGroup),"set_alpha",{"System.Single"},{&alpha});
        // VideoPlayer Prepare/Play needs an active hierarchy. Rendering stays
        // suppressed even if the transition cover has not been drawn yet.
        flag(r,m.get(m.root),"SetActive",true);
    });
}
ReadinessResult pollPrepared(Runtime &r, Visit id, uint64_t token) {
    if (!matches(r,id) || !current->preparation.owns(token,current->page)) return {};
    ReadinessResult result;
    if (!checked([&]{
        Map &m = *current;
        refresh(m,0); // Deliberately NOT tick: no input/Lua and no authored time.
        unsigned total = 0, ready = 0, failed = 0, deferred = 0;
        for (auto &item : m.items) {
            if (!item.object || !item.active || !item.media) continue;
            ++total;
            if (item.media->failed) ++failed;
            else if (item.media->deferred) ++deferred;
            else if (item.media->first.held()) ++ready;
        }
        result = readiness::result(total,ready,failed,deferred);
    })) { close(r,id); return {}; }
    return result;
}
bool present(Runtime &r, Visit id, bool visible, bool runClock, bool input) {
    return change(r,id,[&](Map &m){
        bool hierarchyWasActive = m.visible || m.preparation.active();
        bool running = visible && runClock;
        if (running && m.preparation.active()) {
            for (auto &item : m.items) {
                if (item.media && item.media->first.started() && !item.media->first.held() && !item.media->failed)
                    deferMedia(*item.media,@"revealed before first frame was ready");
            }
            m.preparation.invalidate();
        }
        if (m.running != running) {
            m.elapsed = m.time(); m.resumed = Clock::now(); m.running = running;
        }
        bool acceptInput = running && input;
        if (!acceptInput) m.tap.cancel();
        if (m.input != acceptInput) cancelDrag(m);
        m.input = acceptInput;
        flag(r, m.get(m.rootGroup), "set_interactable", m.input);
        flag(r, m.get(m.rootGroup), "set_blocksRaycasts", m.input);
        float alpha = visible ? 1.f : 0.f;
        r.call(m.get(m.rootGroup),"set_alpha",{"System.Single"},{&alpha});
        bool hierarchyActive = visible || m.preparation.active();
        if (hierarchyWasActive != hierarchyActive) flag(r, m.get(m.root), "SetActive", hierarchyActive);
        m.visible = visible;
    });
}
// May run Lua and synchronously close/replace this visit. Do not access m after dispatch.
void dispatchNode(Map &m, int index) {
    Activate callback = m.activate;
    callback(m.id, index);
}
void selectNode(Map &m, int index) {
    if (!m.input || m.tap.busy() || !eligible(m, index) || m.items[index].locked) return;
    int owner = m.items[index].feedbackOwner;
    if (owner >= 0) {
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        m.tap.begin(index, owner, m.time(), m.items[owner].motion.tapTime);
        refresh(m, m.time());
        return;
    }
    dispatchNode(m, index);
}
bool tick(Runtime &r, Visit id) {
    if (!matches(r,id)) return false;
    if (!checked([&]{
        Map &m = *current;
        const double now = m.time();
        refresh(m, now);
        if (m.tap.busy()) {
            cancelDrag(m); // Discard gestures queued during feedback.
            int node = m.tap.take(now, m.input && eligible(m, m.tap.node));
            if (node >= 0) dispatchNode(m, node);
            return;
        }
        int release = puzzleInput(m);
        if (release >= 0) selectNode(m, release);
    })) { close(r,id); return false; }
    return true;
}
P anchor(Runtime &r, Visit id, int index) {
    if (!matches(r,id) || index < 0 || size_t(index) >= current->items.size()) return nullptr;
    auto &item = current->items[index];
    return item.screen == current->page ? current->get(item.rect) : nullptr;
}
bool owns(Runtime &r, P button) { return owned(r,button) >= 0; }
bool press(Runtime &r, P button) {
    int index = owned(r,button);
    if (index < 0) return false;
    Visit id = current->id;
    if (!current->input || current->tap.busy() || !change(r,id,[](Map &){})) return true;
    const Item &item = current->items[index];
    if (item.drop >= 0 || current->drag >= 0 || !item.active || item.inheritedAlpha <= .01f) return true;
    if (!checked([&]{
        if (r.unbox<bool>(r.call(button,"IsActive")) && r.unbox<bool>(r.call(button,"IsInteractable"))) {
            selectNode(*current, index);
        }
    })) close(r,id);
    return true;
}
void close(Runtime &r, Visit id) {
    if (!matches(r,id)) return;
    auto m = std::move(current); // Relinquish input before touching Unity's hierarchy.
    dispose(*m);
}
}

#endif // __OBJC__
