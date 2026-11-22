#include "PMNativeOSScene.hpp"
#include "PMIL2CPP.hpp"
#include "PMDiagnostics.h"
#include <memory>

namespace pmnativeosscene {
namespace {
using pmbridge::P;
constexpr const char *sceneNS = "UnityEngine.SceneManagement";
constexpr const char *selector = "Assets/Phigros2/SongSelector/SongSelector";
struct Destination { Route route; int index; const char *path; };
constexpr Destination destinations[] = {
    {Route::SaturnOS, 38, "Assets/PhiMod/OS/PMSaturnOS"},
    {Route::C8, 39, "Assets/PhiMod/OS/PMChapter8SelectMusic"},
    {Route::C9, 40, "Assets/PhiMod/OS/PMChapter9SelectMusic"},
    {Route::C9Phase2, 41, "Assets/PhiMod/OS/PMChapter9Phase2"},
};
const Destination *destination(Route route) {
    for (const auto &d : destinations) if (d.route == route) return &d;
    return nullptr;
}
struct Visit {
    const Destination *target = nullptr;
    uint64_t id = 0;
    Arrived arrived = nullptr;
    int handle = 0;
    uint32_t root = 0;
    bool leaving = false;
};
Visit current;
// The owned scene unloads before the normal selector arrives. Keep only the
// return notification across that boundary, never its Unity objects.
struct ReturnTrip { uint64_t id = 0; Returned done = nullptr; bool toSelector = false; } returning;
bool installed = false;
uint64_t sequence = 0;

int sceneHandle(Runtime &r, P boxed) {
    // The 4.0.4 Scene value type contains just m_Handle. Validate the managed
    // type and its native width before crossing the IL2CPP value-type ABI.
    P type = r.type(sceneNS, "Scene");
    uint32_t alignment = 0;
    if (!boxed || r.object_get_class(boxed) != type || !r.class_is_valuetype(type) ||
        r.class_value_size(type, &alignment) != sizeof(int))
        throw std::runtime_error("Unexpected Unity Scene value");
    int value;
    memcpy(&value, r.object_unbox(boxed), sizeof(value));
    return value;
}
int activeHandle(Runtime &r) {
    return sceneHandle(r, r.stat(r.type(sceneNS, "SceneManager"), "GetActiveScene"));
}
bool matches(Runtime &r, int handle, int index, const char *expectedPath) {
    P s = r.type(sceneNS, "Scene");
    if (r.unbox<int>(r.stat(s, "GetBuildIndexInternal", {"System.Int32"}, {&handle})) != index)
        return false;
    NSString *path = r.string(r.stat(s, "GetPathInternal", {"System.Int32"}, {&handle}));
    return [path isEqualToString:[NSString stringWithFormat:@"%s.unity", expectedPath]];
}
void clear(Runtime &r) {
    if (current.root) r.gchandle_free(current.root);
    current = {};
}
P requestSingle(Runtime &r, int index) {
    P manager = r.type(sceneNS, "SceneManager");
    int count = r.unbox<int>(r.stat(manager, "get_sceneCountInBuildSettings"));
    if (index < 0 || index >= count) {
        PMDiagnosticsWrite([NSString stringWithFormat:@"Chapter OS: build index %d unavailable (%d scenes)",index,count].UTF8String);
        return nullptr;
    }
    // The 4.0.4 player retains the name/index implementation used by its public
    // overloads. Load the exact packaged scene from BuildSettings in Single mode.
    struct { int single = 0; int localPhysics = 0; } parameters;
    uint32_t alignment=0;
    if(r.class_value_size(r.type(sceneNS,"LoadSceneParameters"),&alignment)!=sizeof(parameters))
        throw std::runtime_error("Chapter OS: unexpected LoadSceneParameters layout");
    bool synchronous = false;
    return r.stat(manager,"LoadSceneAsyncNameIndexInternal",{"System.String","System.Int32",
                  "UnityEngine.SceneManagement.LoadSceneParameters","System.Boolean"},
                  {nullptr,&index,&parameters,&synchronous});
}
void notify(Runtime &r, Arrived cb, uint64_t id, Route route, P root) {
    @try {
        try { cb(r, id, route, root); }
        catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
    } @catch (NSException *e) { PMDiagnosticsWrite(e.reason.UTF8String); }
}
}

#include "PMNativeOSPlayTransition.inc"

static void finishLoad(Runtime &r, int handle) {
    if (returning.id) {
        const ReturnTrip trip = returning;
        returning = {};
        if(current.id==trip.id)clear(r); // The old scene can unload without a managed notification.
        bool arrived = false;
        try { arrived = trip.toSelector && activeHandle(r) == handle && matches(r, handle, 7, selector); }
        catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
        if (trip.done) {
            @try {
                try { trip.done(r, trip.id, arrived); }
                catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
            } @catch (NSException *e) { PMDiagnosticsWrite(e.reason.UTF8String); }
        }
        return;
    }
    if (!current.arrived) return;
    auto cb = current.arrived;
    auto d = current.target;
    auto id = current.id;
    current.arrived = nullptr; // Commit the one-shot before calling coordinator code.
    P root = nullptr;
    try {
        if (activeHandle(r) == handle && matches(r, handle, d->index, d->path)) {
            current.handle = handle; // Retain the return route even if the root is damaged.
            P found = r.stat(r.type("UnityEngine", "GameObject"), "Find", {"System.String"},
                             {r.string_new("/PhiModStockOSHost")});
            if (r.alive(found) && sceneHandle(r, r.call(found, "get_scene")) == handle &&
                !r.call(r.call(found, "get_transform"), "get_parent")) {
                current.root = r.gchandle_new(found, false);
                if (current.root) {
                    entrance::checked([&]{ entrance::reserve(r, found, d->route); });
                    root = found;
                }
            }
        }
    } catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
    bool owned = current.handle != 0;
    if (!owned) clear(r);
    notify(r, cb, id, d->route, root);
}

// Unity can deliver scene notifications before the destination is active. The
// retained AsyncOperation is the completion signal even without a notification.
static void waitForLoad(Runtime *r,uint64_t id,bool back,uint32_t op) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        const bool pending=back ? returning.id==id : current.id==id && current.arrived;
        if(!pending){r->gchandle_free(op);return;}
        int handle=0;
        try {
            P operation=r->gchandle_get_target(op);
            if(!operation)throw std::runtime_error("Chapter OS: lost scene operation");
            if(!r->unbox<bool>(r->call(operation,"get_isDone"))){
                waitForLoad(r,id,back,op);return;
            }
            handle=activeHandle(*r);
        } catch(const std::exception &e){PMDiagnosticsWrite(e.what());}
        r->gchandle_free(op);
        finishLoad(*r,handle);
    });
}
static bool watch(Runtime &r,P op,uint64_t id,bool back){
    if(!op)return false;
    uint32_t root=r.gchandle_new(op,false);
    if(!root)throw std::runtime_error("Chapter OS: cannot retain scene load");
    waitForLoad(&r,id,back,root);
    return true;
}
bool sceneLoaded(Runtime &r,int handle,int mode){
    if(mode==0) entrance::loaded(r,handle);
    if(mode!=0 || !current.target || returning.id)return false;
    try{return matches(r,handle,current.target->index,current.target->path);}
    catch(const std::exception &e){PMDiagnosticsWrite(e.what());return false;}
}
void hooksInstalled() { installed = true; }

uint64_t enter(Runtime &r, Route route, Arrived cb) {
    const Destination *d = destination(route);
    if (!NSThread.isMainThread || !installed || current.target || returning.id || entrance::pending() || !d || !cb) return 0;
    if (++sequence == 0) ++sequence;
    uint64_t id = sequence;
    current = {d, id, cb};
    try { if (watch(r, requestSingle(r, d->index), id, false)) return id; }
    catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
    if (current.id == id) clear(r);
    return 0;
}

bool sceneUnloaded(Runtime &r, int handle) {
    if (!current.handle || current.handle != handle) return false;
    entrance::unloaded(r);
    clear(r);
    return true;
}

void *activeRoot(Runtime &r) {
    if (!NSThread.isMainThread || current.leaving || !current.root) return nullptr;
    try {
        if (activeHandle(r) != current.handle) return nullptr;
        P root = r.gchandle_get_target(current.root);
        if (r.alive(root)) return root;
    } catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
    return nullptr;
}

bool isSongSelector(Runtime &r, int handle) { return matches(r, handle, 7, selector); }

static bool leave(Runtime &r, Returned cb, bool toSelector) {
    if (!NSThread.isMainThread || !current.handle || current.leaving || entrance::pending()) return false;
    P info = nullptr, previous = nullptr;
    bool changedNextScene = false;
    try {
        if (activeHandle(r) != current.handle) return false;
        current.leaving = true;
        returning = {current.id, cb, toSelector};
        if (!toSelector) {
            info = r.klass("GameInformation");
            previous = r.staticValue<P>(info,"nextScene","System.String");
            r.setStaticValue<P>(info,"nextScene","System.String",r.string_new("ChapterSelector"));
            changedNextScene = true;
        }
        if (watch(r, requestSingle(r, toSelector ? 7 : 5), current.id, true)) return true;
    } catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
    returning = {};
    current.leaving = false;
    if (changedNextScene) {
        try { r.setStaticValue<P>(info,"nextScene","System.String",previous); }
        catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
    }
    return false;
}

bool leaveToSongSelector(Runtime &r, Returned cb) { return leave(r, cb, true); }
bool leaveToChapter(Runtime &r, Returned cb) { return leave(r, cb, false); }

bool ownsController(Runtime &r, Route route, P self) {
    // Scope to the object's scene, including teardown after the active scene
    // changes. An official visit to the same chapter has a distinct build index.
    if (!current.target || current.target->route != route) return false;
    try {
        int handle = sceneHandle(r, r.call(r.call(self, "get_gameObject"), "get_scene"));
        return current.handle ? current.handle == handle : matches(r, handle, current.target->index, current.target->path);
    } catch (const std::exception &e) {
        PMDiagnosticsWrite(e.what());
        return true; // Fail closed during an owned visit.
    }
}
}
