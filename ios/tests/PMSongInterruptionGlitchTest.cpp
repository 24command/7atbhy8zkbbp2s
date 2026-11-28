// Execute production NativeHost and Visual with a fake checked reflection bridge.
// No second implementation of the visual lifecycle or cleanup algorithm.
#include <any>
#include <cassert>
#include <iostream>
#include <map>
#include <memory>
#include <string>
#include <vector>
#include <stdexcept>
#include <cstdint>
#include <initializer_list>
#include <limits>
namespace pmbridge {
using P = void*;
struct Node {
    std::string type, text;
    bool alive = true, owned = false, enabled = true;
    P klass = nullptr;
    std::map<std::string, std::any> fields;
    std::vector<P> items;
    std::any boxed;
};
struct Runtime {
    std::vector<std::unique_ptr<Node>> nodes;
    std::map<std::string, P> types, resources;
    std::map<std::uint32_t, P> roots;
    P camera = nullptr, go = nullptr, original = nullptr, originalList = nullptr;
    P gsource = nullptr, rsource = nullptr, gmaterial = nullptr, rmaterial = nullptr;
    int steps = 0, failAt = 0, adds = 0, ownedDestroys = 0;
    bool materialThrow = false, aliasManager = false, denyDestroy = false;
    std::uint32_t nextRoot = 1;
    static Node& n(P p) { if (!p) throw std::runtime_error("null"); return *static_cast<Node*>(p); }
    void point() { if (++steps == failAt) throw std::runtime_error("injected bridge failure"); }
    P make(const std::string& kind, bool owned = false) {
        auto q = std::make_unique<Node>(); q->type = kind; q->owned = owned;
        P p = q.get(); nodes.push_back(std::move(q)); return p;
    }
    P type(const char*, const char* name) { if (!types.count(name)) types[name] = make(name); return types[name]; }
    P class_get_type(P p) { return p; }
    P type_get_object(P p) { return p; }
    P object_get_class(P p) { return n(p).klass; }
    P resolve(P, const char*, std::initializer_list<const char*> = {}, bool = false) { point(); return nullptr; }
    P string_new(const char* s) { P p = make("String"); n(p).text = s; return p; }
    bool alive(P p) { return p && n(p).alive; }
    std::uint32_t gchandle_new(P p, bool) { point(); auto id = nextRoot++; roots[id] = p; return id; }
    P gchandle_get_target(std::uint32_t id) { return roots.at(id); }
    void gchandle_free(std::uint32_t id) { roots.erase(id); }
    template<class T> T get(P p, const char* key) { point(); return std::any_cast<T>(n(p).fields.at(key)); }
    template<class T> void put(P p, const char* key, T value) { point(); n(p).fields[key] = value; }
    template<class T> P box(T value) { P p = make("box"); n(p).boxed = value; return p; }
    template<class T> T unbox(P p) { return std::any_cast<T>(n(p).boxed); }
    std::uintptr_t array_length(P p) { return n(p).items.size(); }
    P arrayAt(P p, int i) { point(); return n(p).items.at(i); }
    int count(P p) { point(); return int(n(p).items.size()); }
    P at(P p, int i) { point(); return n(p).items.at(i); }
    P stat(P, const char* method, std::initializer_list<const char*> = {}, std::initializer_list<P> args = {}) {
        point(); std::string m = method; std::vector<P> a(args);
        if (m == "get_main") return camera;
        if (m == "Load") return resources.at(n(a[0]).text);
        if (m == "Instantiate") {
            P p = make(n(a[0]).type, true); n(p).klass = n(a[0]).klass; n(p).fields = n(a[0]).fields; return p;
        }
        if (m == "Destroy") {
            if (denyDestroy) throw std::runtime_error("destroy unavailable");
            assert(n(a[0]).owned); assert(n(a[0]).alive);
            n(a[0]).alive = false; ++ownedDestroys; return nullptr;
        }
        throw std::runtime_error("unexpected static: " + m);
    }
    P call(P p, const char* method, std::initializer_list<const char*> = {}, std::initializer_list<P> args = {}) {
        point(); std::string m = method; std::vector<P> a(args);
        if (m == "get_gameObject") return go;
        if (m == "get_Camera") return std::any_cast<P>(n(p).fields.at("_camera"));
        if (m == "set_Camera") { n(p).fields["_camera"] = a[0]; return nullptr; }
        if (m == "get_enabled") return box(n(p).enabled);
        if (m == "set_enabled") { n(p).enabled = *static_cast<bool*>(a[0]); return nullptr; }
        if (m == "get_isSupported" || m == "get_ShouldRender") return box(true);
        if (m == "GetComponents") {
            P array = make("Array");
            for (const auto& node : nodes) if (node->type == "PostProcessingManager" && node->klass && node->alive)
                n(array).items.push_back(node.get());
            return array;
        }
        if (m == "AddComponent") {
            ++adds; if (aliasManager) return original;
            P manager = make("PostProcessingManager", true); n(manager).klass = a[0];
            n(manager).fields["postEffects"] = make("List"); n(manager).fields["_camera"] = P{};
            return manager;
        }
        if (m == "AddEffects") { n(std::any_cast<P>(n(p).fields.at("postEffects"))).items.push_back(a[0]); return nullptr; }
        if (m == "set_material") { n(p).fields["_material"] = a[0]; return nullptr; }
        if (m == "get_material") {
            P material = std::any_cast<P>(n(p).fields.at("_material"));
            if (!material) { material = make("Material", true); n(p).fields["_material"] = material; }
            if (materialThrow) { materialThrow = false; throw std::runtime_error("Initialize failed after allocation"); }
            return material;
        }
        throw std::runtime_error("unexpected call: " + m);
    }
    Runtime() {
        go = make("GameObject"); camera = make("Camera");
        original = make("PostProcessingManager"); n(original).klass = type("", "PostProcessingManager");
        originalList = make("List"); n(originalList).items = {make("ExistingEffect")};
        n(original).fields["postEffects"] = originalList; n(original).fields["_camera"] = camera;
        n(original).enabled = false; // A disabled existing chain stays disabled.
        gmaterial = make("Material"); rmaterial = make("Material");
        gsource = make("GlitchSettings"); rsource = make("RGBShiftSettings");
        for (P source : {gsource, rsource}) {
            n(source).klass = type("", n(source).type.c_str()); n(source).fields["shader"] = make("Shader");
            n(source).fields["enabled"] = false;
        }
        n(gsource).fields["_material"] = gmaterial; n(gsource).fields["glitchTex"] = make("Texture");
        n(gsource).fields["glitchRange"] = .01f; n(rsource).fields["_material"] = rmaterial;
        n(rsource).fields["screenDeform"] = .1f; n(rsource).fields["radius"] = 1.f;
        resources["321GlitchSettings"] = gsource; resources["321RGBShiftSettings"] = rsource;
    }
    void originalsUntouched() {
        assert(n(original).alive && !n(original).enabled);
        assert(std::any_cast<P>(n(original).fields["postEffects"]) == originalList);
        assert(n(originalList).items.size() == 1);
        assert(n(gsource).alive && n(rsource).alive && n(gmaterial).alive && n(rmaterial).alive);
        assert(std::any_cast<P>(n(gsource).fields["_material"]) == gmaterial);
        assert(std::any_cast<P>(n(rsource).fields["_material"]) == rmaterial);
        assert(std::any_cast<float>(n(gsource).fields["glitchRange"]) == .01f);
        assert(std::any_cast<float>(n(rsource).fields["radius"]) == 1.f);
    }
    int liveOwned() const { int n = 0; for (const auto& p : nodes) n += p->alive && p->owned; return n; }
    P owned(const char* kind) { for (const auto& p : nodes) if (p->alive && p->owned && p->type == kind) return p.get(); return nullptr; }
};
}
#include "../PhiMod/Sources/PMSongInterruptionGlitch.inc"
using Host = pmsongglitch::NativeHost;
using Visual = pmsongglitch::NativeVisual;
using Result = Visual::Result;
using Runtime = pmbridge::Runtime;
int main() {
    int setupSteps = 0;
    { Runtime r; Host h(r); Visual v(h);
      assert(v.start(1, 3.972489, 10)); setupSteps = r.steps;
      assert(r.liveOwned() == 5 && r.adds == 1); r.originalsUntouched();
      assert(v.frame(1, 10) == Result::Running);
      auto glitch = r.owned("GlitchSettings"), rgb = r.owned("RGBShiftSettings");
      assert(r.get<float>(glitch,"glitchRange") == .3f);
      assert(r.get<float>(rgb,"screenDeform") == .55f && r.get<float>(rgb,"radius") == 3.5f);
      assert(v.start(1, 3.972489, 11)); assert(r.adds == 1);
      assert(v.frame(1, 11) == Result::Running);
      assert(v.pause(1, 11)); assert(v.pause(1, 100));
      assert(!Runtime::n(r.owned("PostProcessingManager")).enabled);
      assert(v.frame(1, 1000) == Result::Paused); assert(v.elapsed() == 1);
      assert(v.resume(1, 1000)); assert(v.resume(1, 1001));
      assert(v.frame(1, 1002.972488) == Result::Running);
      assert(v.frame(1, 1002.972490) == Result::Finished);
      assert(v.frame(1, 1004) == Result::Stale);
      assert(!v.start(1, 4, 1004)); assert(v.stop(1));
      assert(r.liveOwned() == 0 && r.roots.empty()); r.originalsUntouched(); }
    // Real production setup failure at every checked reflection/root operation.
    for (int fail = 1; fail <= setupSteps; ++fail) {
        Runtime r; r.failAt = fail; Host h(r); Visual v(h);
        v.start(1, 4, 10); assert(v.stop()); assert(!v.cleanupPending());
        assert(r.liveOwned() == 0 && r.roots.empty()); r.originalsUntouched();
    }
    { Runtime r; r.materialThrow = true; Host h(r); Visual v(h);
      assert(!v.start(1,4,0)); assert(r.liveOwned()==0 && r.roots.empty()); r.originalsUntouched(); }
    { Runtime r; r.aliasManager = true; Host h(r); Visual v(h);
      assert(!v.start(1,4,0)); assert(r.liveOwned()==0 && r.roots.empty()); r.originalsUntouched(); }
    // Replacement, stale stop/pause/frame, and camera loss cannot affect a new owner.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0)); assert(v.start(2,4,1));
      assert(v.stop(1)); assert(!v.pause(1,2)); assert(v.frame(1,2)==Result::Stale);
      assert(v.owns(2) && r.liveOwned()==5); r.camera=r.make("Camera");
      assert(v.frame(2,2)==Result::Failed); assert(r.liveOwned()==0); r.originalsUntouched(); }
    // Cleanup failure retains handles and blocks replacement until retry succeeds.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0)); r.denyDestroy=true;
      assert(!v.stop(1)); assert(v.cleanupPending()); assert(!v.start(2,4,1));
      assert(!Runtime::n(r.owned("PostProcessingManager")).enabled);
      r.denyDestroy=false; assert(v.stop()); assert(v.start(2,4,2)); assert(v.stop());
      assert(r.liveOwned()==0 && r.roots.empty()); r.originalsUntouched(); }
    // Losing an owned component and foreign edits to its private chain retire safely.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0));
      Runtime::n(r.owned("PostProcessingManager")).alive=false;
      assert(v.frame(1,1)==Result::Failed); assert(r.liveOwned()==0 && r.roots.empty()); }
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0));
      Runtime::n(r.owned("PostProcessingManager")).fields["postEffects"]=r.originalList;
      assert(v.frame(1,1)==Result::Failed); r.originalsUntouched(); assert(r.liveOwned()==0); }
    { Runtime r; Host h(r); Visual v(h);
      assert(!v.start(0,4,0)); assert(!v.start(1,0,0)); assert(!v.start(1,601,0));
      assert(!v.start(1,std::numeric_limits<double>::quiet_NaN(),0)); assert(r.liveOwned()==0);
      assert(v.start(1,4,10)); assert(v.frame(1,9)==Result::Failed); assert(r.liveOwned()==0); }
    // Warmup and suspension before the first frame do not consume visible time.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0));
      assert(v.pause(1,10)); assert(v.resume(1,100));
      assert(v.frame(1,1000)==Result::Running); assert(v.elapsed()==0);
      assert(v.frame(1,1003.999)==Result::Running); assert(v.frame(1,1004)==Result::Finished); }
    // Retry transient cleanup errors without losing ownership of live objects.
    for (int offset = 1; offset <= 18; ++offset) {
        Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0));
        r.failAt = r.steps + offset; v.stop(); r.failAt = 0;
        assert(v.stop()); assert(r.liveOwned()==0 && r.roots.empty()); r.originalsUntouched();
    }
    // Legitimate concurrent updates to the original chain are never rolled back.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0));
      auto replacement = r.make("List"); Runtime::n(r.original).fields["postEffects"] = replacement;
      Runtime::n(r.original).enabled = true;
      assert(v.frame(1,0)==Result::Running); assert(v.stop());
      assert(Runtime::n(r.original).enabled);
      assert(std::any_cast<pmbridge::P>(Runtime::n(r.original).fields["postEffects"])==replacement);
      assert(r.liveOwned()==0 && r.roots.empty()); }
    // UI Frame validation never advances a clock or ends at adapter duration.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,.001,0));
      for (int i=0; i<8; ++i) assert(v.validate(1));
      assert(v.pause(1,1000)); assert(v.validate(1));
      assert(!Runtime::n(r.owned("PostProcessingManager")).enabled);
      assert(v.resume(1,100000));
      for (int i=0; i<8; ++i) assert(v.validate(1));
      assert(v.elapsed()==0 && v.owns(1) && r.liveOwned()==5);
      assert(v.stop(1)); assert(!v.validate(1));
      assert(r.liveOwned()==0 && r.roots.empty()); r.originalsUntouched(); }
    // Host loss during UI Frame retires once and releases the owned chain.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0));
      r.camera=r.make("ReplacementCamera"); assert(!v.validate(1));
      int destroys=r.ownedDestroys; assert(!v.validate(1));
      assert(r.ownedDestroys==destroys && r.liveOwned()==0 && r.roots.empty());
      r.originalsUntouched(); }
    // Reflection exceptions during validation fail closed and clean up as well.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0));
      r.failAt=r.steps+1; assert(!v.validate(1));
      assert(!v.owns(1) && r.liveOwned()==0 && r.roots.empty()); r.originalsUntouched(); }
    // Stale UI Frame callbacks cannot probe or retire the replacement.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0)); assert(v.start(2,4,1));
      int steps=r.steps; assert(!v.validate(0)); assert(!v.validate(1));
      assert(r.steps==steps && v.owns(2) && r.liveOwned()==5); assert(v.validate(2));
      assert(v.stop(2)); r.originalsUntouched(); }
    // Validation failure preserves retryable cleanup state if native Destroy fails.
    { Runtime r; Host h(r); Visual v(h); assert(v.start(1,4,0));
      r.camera=r.make("ReplacementCamera"); r.denyDestroy=true;
      assert(!v.validate(1)); assert(v.cleanupPending() && !v.owns(1));
      assert(!Runtime::n(r.owned("PostProcessingManager")).enabled);
      r.denyDestroy=false; assert(v.stop());
      assert(r.liveOwned()==0 && r.roots.empty()); r.originalsUntouched(); }
    std::cout << "native D321 visual: 18 groups + " << setupSteps << " setup failure points + 18 cleanup failure points passed\n";
}
