#pragma once
// Include at translation-unit scope AFTER PMIL2CPP.hpp, outside any anonymous
// namespace. HookBackend owns Runtime and calls this on Unity's main thread.
#include "PMSongInterruptionGlitch.hpp"
#include <array>
#include <vector>
#include <stdexcept>

namespace pmsongglitch {
// Reflection names checked against Phigros 4.0.4 dump.cs, types 4092/4102/4103/4107.
// No raw RVA calls, D321 MonoBehaviour, Start, coroutine, chart clock or sound.
// This renders the original Glitch/RGBShift shaders on the CURRENT camera using
// original D321 assets. Full D321 AnimationDirector curves are not reconstructed.
// Native shader animation uses Unity shader time; pause disables our renderer and
// freezes the presentation's duration clock, without changing global Unity time.
class NativeHost {
public:
    using P = pmbridge::P;
    struct V2 { float x, y; };
    enum Root { Camera, GameObject, GlitchSource, RGBSource, Glitch, RGB,
                GlitchMaterial, RGBMaterial, Manager, EffectList, RootCount };
    struct OriginalManager {
        std::uint32_t manager = 0, list = 0, camera = 0;
        bool enabled = false;
    };
    struct Lease {
        std::array<std::uint32_t, RootCount> roots{};
        // Captured for ownership checks. Never restore by writing over another
        // system's subsequent changes: we leave these original objects untouched.
        std::vector<OriginalManager> originals;
    };
    explicit NativeHost(pmbridge::Runtime& runtime) : r_(runtime) {}

    void prepare(Lease& s) {
        preflight();
        keep(s, Camera, r_.stat(r_.type("UnityEngine", "Camera"), "get_main"));
        requireAlive(object(s, Camera), "D321 visual requires a live main camera");
        keep(s, GameObject, r_.call(object(s, Camera), "get_gameObject"));
        captureOriginals(s);
        cloneSettings(s, GlitchSource, Glitch, GlitchMaterial, "321GlitchSettings", "GlitchSettings");
        cloneSettings(s, RGBSource, RGB, RGBMaterial, "321RGBShiftSettings", "RGBShiftSettings");
        // Restore the known serialized defaults ON CLONES ONLY. Shared Resources
        // assets may have been animated by an earlier level; do not inherit that.
        P glitch = object(s, Glitch), rgb = object(s, RGB);
        r_.put(glitch, "glitchRange", OriginalSettings::glitchRange);
        for (const char* field : {"layer1Strength", "layer2Strength", "layer3Strength"})
            r_.put(glitch, field, V2{OriginalSettings::layerStrength, OriginalSettings::layerStrength});
        for (const char* field : {"layer1Speed", "layer2Speed", "layer3Speed"})
            r_.put(glitch, field, OriginalSettings::layerSpeed);
        r_.put(glitch, "rgbChannelOffset", true);
        r_.put(rgb, "screenDeform", OriginalSettings::screenDeform);
        r_.put(rgb, "radius", OriginalSettings::radius);
        r_.put(rgb, "center", V2{OriginalSettings::center, OriginalSettings::center});
        // AddComponent runs only PostProcessingManager's constructor/OnEnable:
        // 0x15D295C creates an empty list; 0x15D2430 only warms that list.
        // No existing manager or camera property is replaced.
        P managerType = systemType(r_.type("", "PostProcessingManager"));
        P manager = r_.call(object(s, GameObject), "AddComponent", {"System.Type"}, {managerType});
        for (const auto& old : s.originals)
            if (target(old.manager) == manager) throw std::runtime_error("AddComponent returned an existing post manager");
        keepCreated(s, Manager, manager);
        enable(s, false);
        keep(s, EffectList, r_.get<P>(manager, "postEffects"));
        if (!object(s, EffectList) || r_.count(object(s, EffectList)) != 0)
            throw std::runtime_error("New post manager list is not empty");
        for (const auto& old : s.originals)
            if (target(old.list) == object(s, EffectList)) throw std::runtime_error("Post manager list unexpectedly shared");
        r_.call(manager, "set_Camera", {"UnityEngine.Camera"}, {object(s, Camera)});
        // Same order as D321's Start: Glitch, then RGBShift (without ESC/Bloom/UI).
        r_.call(manager, "AddEffects", {"PostEffectSettings"}, {glitch});
        r_.call(manager, "AddEffects", {"PostEffectSettings"}, {rgb});
        if (!r_.unbox<bool>(r_.call(glitch, "get_ShouldRender")) ||
            !r_.unbox<bool>(r_.call(rgb, "get_ShouldRender")))
            throw std::runtime_error("Original D321 shader cannot render on this device");
    }
    bool valid(const Lease& s) {
        P camera = object(s, Camera), manager = object(s, Manager);
        if (!r_.alive(camera) || !r_.alive(manager) ||
            r_.stat(r_.type("UnityEngine", "Camera"), "get_main") != camera) return false;
        if (r_.call(manager, "get_gameObject") != object(s, GameObject) ||
            r_.call(manager, "get_Camera") != camera) return false;
        // Retire on foreign takeover of our private list; do not overwrite it.
        P list = r_.get<P>(manager, "postEffects");
        return list == object(s, EffectList) && r_.count(list) == 2 &&
            r_.at(list, 0) == object(s, Glitch) && r_.at(list, 1) == object(s, RGB) &&
            r_.alive(object(s, Glitch)) && r_.alive(object(s, RGB)) &&
            r_.alive(object(s, GlitchMaterial)) && r_.alive(object(s, RGBMaterial));
    }
    void enable(const Lease& s, bool value) {
        P manager = object(s, Manager);
        requireAlive(manager, "Owned post manager was destroyed");
        r_.call(manager, "set_enabled", {"System.Boolean"}, {&value});
        if (r_.unbox<bool>(r_.call(manager, "get_enabled")) != value)
            throw std::runtime_error("Owned post manager enabled readback failed");
    }
    // Remove ONLY the component/materials/settings this lease created. Existing
    // managers, list references/contents, enabled flags and camera fields remain
    // as captured, or retain legitimate changes made by the game while we ran.
    // Destroy is deferred by Unity, so disable the manager before releasing data.
    bool release(Lease& s) {
        P manager = object(s, Manager);
        if (manager) {
            try {
                if (r_.alive(manager)) enable(s, false);
                if (!destroy(s, Manager)) return false;
            } catch (...) {
                // If disabling failed, still try to remove our component. Never
                // respond by touching an original manager or global camera state.
                if (!destroy(s, Manager)) return false;
            }
        }
        // get_material can allocate/cache before a later Initialize throws.
        // Recover that owned cache so partial setup cannot leak a Material.
        if (!recoverMaterial(s, Glitch, GlitchSource, GlitchMaterial) ||
            !recoverMaterial(s, RGB, RGBSource, RGBMaterial)) return false;
        bool done = true;
        for (Root which : {GlitchMaterial, RGBMaterial, Glitch, RGB})
            if (!destroy(s, which)) done = false;
        if (!done) return false;
        for (auto& root : s.roots) unroot(root);
        for (auto& old : s.originals) { unroot(old.manager); unroot(old.list); unroot(old.camera); }
        s.originals.clear();
        return true;
    }
private:
    pmbridge::Runtime& r_;
    P target(std::uint32_t root) const { return root ? r_.gchandle_get_target(root) : nullptr; }
    P object(const Lease& s, Root which) const { return target(s.roots[which]); }
    void unroot(std::uint32_t& root) { if (root) r_.gchandle_free(root); root = 0; }
    void root(std::uint32_t& slot, P value) {
        if (!value) return;
        slot = r_.gchandle_new(value, false);
        if (!slot) throw std::runtime_error("Cannot root D321 visual object");
    }
    void keep(Lease& s, Root which, P value) { root(s.roots[which], value); }
    void keepCreated(Lease& s, Root which, P value) {
        requireAlive(value, "Cannot create D321 visual object");
        try { keep(s, which, value); }
        catch (...) {
            r_.stat(r_.type("UnityEngine", "Object"), "Destroy", {"UnityEngine.Object"}, {value});
            throw;
        }
    }
    bool recoverMaterial(Lease& s, Root cloneSlot, Root sourceSlot, Root materialSlot) {
        if (s.roots[materialSlot]) return true;
        try {
            P clone = object(s, cloneSlot);
            if (!r_.alive(clone)) return true;
            P material = r_.get<P>(clone, "_material");
            P source = object(s, sourceSlot);
            if (r_.alive(material) && (!source || material != r_.get<P>(source, "_material")))
                keepCreated(s, materialSlot, material);
            return true;
        } catch (...) { return false; }
    }
    bool destroy(Lease& s, Root which) {
        try {
            P value = object(s, which);
            if (r_.alive(value)) r_.stat(r_.type("UnityEngine", "Object"), "Destroy", {"UnityEngine.Object"}, {value});
            unroot(s.roots[which]); return true;
        } catch (...) { return false; }
    }
    void requireAlive(P value, const char* reason) { if (!r_.alive(value)) throw std::runtime_error(reason); }
    P systemType(P klass) { return r_.type_get_object(r_.class_get_type(klass)); }
    void captureOriginals(Lease& s) {
        P kind = systemType(r_.type("", "PostProcessingManager"));
        P array = r_.call(object(s, GameObject), "GetComponents", {"System.Type"}, {kind});
        std::uint32_t arrayRoot = 0;
        root(arrayRoot, array);
        try {
            auto count = array ? r_.array_length(array) : 0;
            if (count > 128) throw std::runtime_error("Unexpected post manager count");
            s.originals.reserve(count);
            for (std::uintptr_t i = 0; i < count; ++i) {
                P manager = r_.arrayAt(array, int(i));
                if (!r_.alive(manager)) continue;
                s.originals.emplace_back();
                auto& old = s.originals.back();
                root(old.manager, manager);
                root(old.list, r_.get<P>(manager, "postEffects"));
                root(old.camera, r_.get<P>(manager, "_camera"));
                old.enabled = r_.unbox<bool>(r_.call(manager, "get_enabled"));
            }
        } catch (...) { unroot(arrayRoot); throw; }
        unroot(arrayRoot);
    }
    void cloneSettings(Lease& s, Root sourceSlot, Root cloneSlot, Root materialSlot,
                       const char* resource, const char* name) {
        P klass = r_.type("", name), kind = systemType(klass);
        P source = r_.stat(r_.type("UnityEngine", "Resources"), "Load",
                           {"System.String", "System.Type"}, {r_.string_new(resource), kind});
        requireAlive(source, "Missing original D321 Resources asset");
        if (r_.object_get_class(source) != klass) throw std::runtime_error("D321 Resources asset type mismatch");
        keep(s, sourceSlot, source);
        P shader = r_.get<P>(source, "shader");
        requireAlive(shader, "D321 asset shader missing");
        if (!r_.unbox<bool>(r_.call(shader, "get_isSupported"))) throw std::runtime_error("D321 shader unsupported");
        if (cloneSlot == Glitch) requireAlive(r_.get<P>(source, "glitchTex"), "D321 glitch texture missing");
        P clone = r_.stat(r_.type("UnityEngine", "Object"), "Instantiate", {"UnityEngine.Object"}, {source});
        if (clone == source) throw std::runtime_error("D321 clone aliases shared resource");
        keepCreated(s, cloneSlot, clone);
        // The original asset may have cached a live material. Reset on the clone
        // before material creation so Initialize/keywords never mutate that cache.
        r_.call(clone, "set_material", {"UnityEngine.Material"}, {nullptr});
        r_.put(clone, "enabled", true);
        if (cloneSlot == Glitch) r_.put(clone, "rgbChannelOffset", true);
        P material = r_.call(clone, "get_material");
        if (material == r_.get<P>(source, "_material")) throw std::runtime_error("D321 material aliases original");
        keepCreated(s, materialSlot, material);
    }
    void preflight() {
        P manager = r_.type("", "PostProcessingManager"), settings = r_.type("", "PostEffectSettings");
        r_.resolve(manager, "AddEffects", {"PostEffectSettings"});
        r_.resolve(manager, "set_Camera", {"UnityEngine.Camera"});
        r_.resolve(manager, "set_enabled", {"System.Boolean"});
        r_.resolve(settings, "set_material", {"UnityEngine.Material"});
        r_.resolve(settings, "get_material");
        r_.resolve(r_.type("UnityEngine", "Resources"), "Load", {"System.String", "System.Type"}, true);
        r_.resolve(r_.type("UnityEngine", "Object"), "Instantiate", {"UnityEngine.Object"}, true);
        r_.resolve(r_.type("UnityEngine", "Object"), "Destroy", {"UnityEngine.Object"}, true);
        r_.resolve(r_.type("UnityEngine", "GameObject"), "AddComponent", {"System.Type"});
        r_.resolve(r_.type("UnityEngine", "GameObject"), "GetComponents", {"System.Type"});
    }
};
using NativeVisual = Visual<NativeHost>;
} // namespace pmsongglitch
