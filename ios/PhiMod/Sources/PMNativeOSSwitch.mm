#include "PMNativeOSSwitch.hpp"
#include "PMIL2CPP.hpp"
#include "PMDiagnostics.h"

namespace pmnativeswitch {
namespace {
using pmbridge::P;
using pmbridge::Runtime;

struct Binding {
    uint32_t button = 0;
    uint32_t stockClick = 0;
    bool stockActive = false;
    bool stockInteractable = false;
    bool modified = false;
    Face face = Face::Hidden;
    bool input = false;
};
Binding current;

// Every entry point runs on the Unity main thread.
template<class F> bool checked(F work) {
    @try {
        try { work(); return true; }
        catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
    } @catch (NSException *e) { PMDiagnosticsWrite(e.reason.UTF8String); }
    return false;
}
P target(Runtime &r, uint32_t handle) {
    return handle ? r.gchandle_get_target(handle) : nullptr;
}
uint32_t pin(Runtime &r, P object) {
    auto handle = object ? r.gchandle_new(object, false) : 0;
    if (!handle) throw std::runtime_error("Switch: could not retain stock control");
    return handle;
}
bool flag(Runtime &r, P object, const char *getter) {
    return r.unbox<bool>(r.call(object, getter));
}
void setFlag(Runtime &r, P object, const char *setter, bool value) {
    r.call(object, setter, {"System.Boolean"}, {&value});
}
void clickEvent(Runtime &r, P button, P event) {
    r.call(button, "set_onClick", {"UnityEngine.UI.Button.ButtonClickedEvent"}, {event});
}
}

void release(Runtime &r) {
    if (!NSThread.isMainThread) return;
    current.face = Face::Hidden;
    current.input = false;
    if (current.modified) {
        P button = target(r, current.button);
        checked([&] {
            if (!r.alive(button)) return; // Single scene load already destroyed it.
            // Keep Button.Press consumed until restoration has finished.
            P go = r.call(button, "get_gameObject");
            checked([&] { setFlag(r, go, "SetActive", current.stockActive); });
            checked([&] { setFlag(r, button, "set_interactable", current.stockInteractable); });
            clickEvent(r, button, target(r, current.stockClick));
        });
    }
    if (current.stockClick) r.gchandle_free(current.stockClick);
    if (current.button) r.gchandle_free(current.button);
    current = {};
}

bool bind(Runtime &r, P selector, const char *customChapter) {
    if (!NSThread.isMainThread) return false;
    bool bound = false;
    bool ok = checked([&] {
        if (!customChapter || strncmp(customChapter, "pm_", 3) || !customChapter[3] || !r.alive(selector)) return;
        P chapter = r.get<P>(selector, "nowChapterInfo");
        if (!chapter || ![r.string(r.get<P>(chapter, "chapterCode")) isEqualToString:
                          [NSString stringWithUTF8String:customChapter]]) return;
        // The field also resolves the inactive ToggleSimulate in level7. No
        // scene-wide search, clone, or replacement of its sprite/RectTransform.
        P go = r.get<P>(selector, "toggleSimulateButton");
        if (!r.alive(go)) return;
        P buttonType = r.type("UnityEngine.UI", "Button");
        P button = r.component(go, buttonType);
        if (!r.alive(button)) return;
        if (target(r, current.button) == button) { bound = true; return; }
        release(r);
        P stock = r.call(button, "get_onClick");
        if (!stock) return;
        current.button = pin(r, button);
        current.stockClick = pin(r, stock);
        current.stockActive = flag(r, go, "get_activeSelf");
        current.stockInteractable = flag(r, button, "get_interactable");
        P empty = r.object_new(r.nested(buttonType, "ButtonClickedEvent"));
        r.call(empty, ".ctor");
        current.modified = true;
        clickEvent(r, button, empty);
        setFlag(r, button, "set_interactable", false);
        setFlag(r, go, "SetActive", false);
        bound = true;
    });
    if (!ok || !bound) release(r);
    return ok && bound;
}

void show(Runtime &r, Face face, bool inputEnabled) {
    if (!NSThread.isMainThread || !current.button) return;
    current.input = false;
    current.face = Face::Hidden;
    checked([&] {
        P button = target(r, current.button);
        if (!r.alive(button)) return;
        bool visible = face != Face::Hidden;
        setFlag(r, button, "set_interactable", visible && inputEnabled);
        setFlag(r, r.call(button, "get_gameObject"), "SetActive", visible);
        current.face = face;
        current.input = visible && inputEnabled;
    });
}

bool owns(Runtime &r, P button) {
    return NSThread.isMainThread && button && target(r, current.button) == button;
}
P visibleButton(Runtime &r) {
    if (!NSThread.isMainThread || current.face == Face::Hidden) return nullptr;
    P result = nullptr;
    checked([&] {
        P button = target(r, current.button);
        if (r.alive(button) && flag(r, r.call(button, "get_gameObject"), "get_activeInHierarchy")) result = button;
    });
    return result;
}
Press press(Runtime &r, P button) {
    return detail::routePress(owns(r, button), current.face, current.input, [&] {
        // Press is intercepted before Selectable checks the CanvasGroup and
        // active/enabled flags. Preserve both of those stock input gates.
        bool allowed = false;
        checked([&] {
            allowed = r.alive(button) && flag(r, button, "IsActive") && flag(r, button, "IsInteractable");
        });
        return allowed;
    });
}
} // namespace pmnativeswitch
