#include "PMNativeOSChrome.hpp"
#include "PMNativeOSDetail.hpp"
#import "PMDiagnostics.h"
#include <memory>

namespace pmnativechrome {
namespace {
using pmbridge::P;
constexpr const char *engine = "UnityEngine";
constexpr const char *ui = "UnityEngine.UI";
constexpr const char *events = "UnityEngine.EventSystems";
const char *levels[] = {"EZ", "HD", "IN", "AT"};

void require(bool ok, const char *message) {
    if (!ok) throw std::runtime_error(message);
}
template<class F> bool checked(F work) {
    @try {
        try { work(); return true; }
        catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
    } @catch (NSException *e) { PMDiagnosticsWrite(e.reason.UTF8String); }
    return false;
}
struct Control { P button{}; Press action{}; };
struct Chrome {
    Runtime &r;
    uint64_t id;
    Route route;
    P host{}, stage{}, parking{}, canvas{}, detail{}, model{}, copy{}, group{}, map{}, font{};
    std::vector<Control> fixed, detailButtons;
    Face face = Face::Hidden;
    bool input = false;
    bool allowList = true;
    unsigned slots = 0;
    // Unity owns native objects. Pin the wrappers handed to the coordinator and
    // used for Button.Press identity, including while the hierarchy is hidden.
    std::vector<uint32_t> pins, copyPins;
    Chrome(Runtime &runtime, uint64_t visit, Route target):r(runtime),id(visit),route(target) {}
    void release(std::vector<uint32_t> &list) {
        for (auto h : list) if (h) r.gchandle_free(h);
        list.clear();
    }
    ~Chrome() { release(copyPins); release(pins); }
    P keep(P obj, bool transient=false) {
        require(obj, "Chrome: missing managed object");
        auto &list = transient ? copyPins : pins;
        list.push_back(0);
        list.back() = r.gchandle_new(obj,false);
        require(list.back()!=0, "Chrome: GC handle allocation failed");
        return obj;
    }
};
std::unique_ptr<Chrome> current;
P tr(Runtime &r,P go) { return r.call(go,"get_transform"); }
P go(Runtime &r,P transform) { return r.call(transform,"get_gameObject"); }
P find(Runtime &r,P root,const std::string &path) {
    auto child=r.call(tr(r,root),"Find",{"System.String"},{r.string_new(path.c_str())});
    if (!r.alive(child)) throw std::runtime_error("Chrome: missing donor "+path);
    return go(r,child);
}
P component(Runtime &r,P obj,const char *ns,const char *name) {
    P c=r.component(obj,r.type(ns,name)); require(r.alive(c),name); return c;
}
P add(Runtime &r,P obj,const char *ns,const char *name) {
    return r.call(obj,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type(ns,name)))});
}
void flag(Runtime &r,P obj,const char *fn,bool value) { r.call(obj,fn,{"System.Boolean"},{&value}); }
void active(Runtime &r,P obj,bool yes) { flag(r,obj,"SetActive",yes); }
void move(Runtime &r,P obj,P parent) {
    bool world=false;
    r.call(tr(r,obj),"SetParent",{"UnityEngine.Transform","System.Boolean"},{tr(r,parent),&world});
}
void stretch(Runtime &r,P obj) {
    float zero[2]={}, one[2]={1,1}; P rect=tr(r,obj);
    r.call(rect,"set_anchorMin",{"UnityEngine.Vector2"},{zero});
    r.call(rect,"set_anchorMax",{"UnityEngine.Vector2"},{one});
    r.call(rect,"set_offsetMin",{"UnityEngine.Vector2"},{zero});
    r.call(rect,"set_offsetMax",{"UnityEngine.Vector2"},{zero});
}
P container(Chrome &c,P parent,const char *name,bool rect=false) {
    Runtime &r=c.r; P obj=c.keep(r.object_new(r.type(engine,"GameObject")));
    r.call(obj,".ctor",{"System.String"},{r.string_new(name)});
    active(r,obj,false);
    if (rect) add(r,obj,engine,"RectTransform");
    move(r,obj,parent);
    int layer=r.unbox<int>(r.call(parent,"get_layer")); r.call(obj,"set_layer",{"System.Int32"},{&layer});
    if (rect) stretch(r,obj);
    return obj;
}
void destroy(Runtime &r,P obj,const char *method) {
    r.stat(r.type(engine,"Object"),method,{"UnityEngine.Object"},{obj});
}
// Park siblings before exposing a stock parent. Disabled MonoBehaviours can
// still receive Awake; deactivating a component alone isn't a quarantine.
void parkChildren(Chrome &c,P parent) {
    Runtime &r=c.r; P t=tr(r,parent);
    for (int i=r.unbox<int>(r.call(t,"get_childCount")); i-->0; )
        move(r,go(r,r.call(t,"GetChild",{"System.Int32"},{&i})),c.parking);
}
template<class F> void each(Runtime &r,P array,F work) {
    require(array,"Chrome: missing component inventory");
    for (uintptr_t i=0;i<r.array_length(array);++i) work(r.arrayAt(array,int(i)));
}
void emptyClick(Runtime &r,P button) {
    P e=r.object_new(r.nested(r.type(ui,"Button"),"ButtonClickedEvent"));
    require(e,"Chrome: button event allocation failed"); r.call(e,".ctor");
    r.call(button,"set_onClick",{"UnityEngine.UI.Button.ButtonClickedEvent"},{e});
    require(r.call(button,"get_onClick")==e,"Chrome: listener replacement failed");
    flag(r,button,"set_enabled",false);
}
// These are the presentation components serialized in the four digest-checked
// donors. Refuse additional components, including EventTriggers or input code.
void sanitize(Runtime &r,P root) {
    require(!r.unbox<bool>(r.call(root,"get_activeInHierarchy")),"Chrome: donor already live");
    static const std::set<std::string> allowed={
        "UnityEngine.Transform","UnityEngine.RectTransform","UnityEngine.Camera","UnityEngine.Canvas",
        "UnityEngine.MeshFilter","UnityEngine.PolygonCollider2D","UnityEngine.CanvasGroup","UnityEngine.CanvasRenderer","UnityEngine.UI.Image","UnityEngine.UI.Text",
        "UnityEngine.UI.Mask","UnityEngine.UI.RectMask2D","UnityEngine.UI.ContentSizeFitter",
        "UnityEngine.UI.CanvasScaler","UnityEngine.UI.GraphicRaycaster","Lean.Gui.LeanPolygon","LeTai.TrueShadow.TrueShadow",
        "LevelSliderController","LevelBarController","RatingDisplayController","TweenStateControl",
        "AddressableImageLoaderWithLowResPreview","Chapter9SongDetailsControl","Chapter9SongDetailsIllustrationSizeControl",
        "UnityEngine.EventSystems.StandaloneInputModule"
    };
    each(r,r.children(root,r.type(engine,"Component")),[&](P item){
        require(item,"Chrome: missing script");
        char *raw=r.type_get_name(r.class_get_type(r.object_get_class(item)));
        std::string name=raw ? raw : ""; if(raw) r.free_memory(raw);
        if (allowed.count(name)) return;
        if (name=="UnityEngine.UI.Button") emptyClick(r,item);
        else if (name=="UnityEngine.Animator") flag(r,item,"set_fireEvents",false);
        else if (name=="TweenInfo") {
            r.put(item,"useOnStart",false); r.put(item,"useOnComplete",false); r.put(item,"autoPlay",false);
            // Replace persistent events too, so even a direct event invocation is inert.
            for (auto key:{"onStart","onComplete"}) {
                P e=r.object_new(r.type("UnityEngine.Events","UnityEvent")); r.call(e,".ctor"); r.put(item,key,e);
            }
        } else if (name=="UnityEngine.EventSystems.EventSystem") {
            r.call(item,"set_firstSelectedGameObject",{"UnityEngine.GameObject"},{nullptr});
        } else if (name=="Chapter8SelectMusicControl" || name=="Chapter8HintControl" || name=="WaveDisplay" || name=="ShowTips") {
            flag(r,item,"set_enabled",false);
        } else if (name=="WaveSource") { flag(r,item,"set_enabled",false); }
        else throw std::runtime_error("Chrome: unreviewed component "+name);
    });
}
void registerButton(Chrome &c,P obj,Intent action,int slot=-1,bool copy=false) {
    auto &list=copy ? c.detailButtons : c.fixed;
    list.push_back({c.keep(component(c.r,obj,ui,"Button"),copy),{action,slot}});
}
P readFont(Runtime &r,P root) {
    P result=nullptr;
    each(r,r.children(root,r.type(ui,"Text")),[&](P text){
        if (!result) { P font=r.call(text,"get_font"); if(r.alive(font)) result=font; }
    });
    require(result,"Chrome: no serialized UI font"); return result;
}
void prepareDetail(Chrome &c) {
    Runtime &r=c.r;
    c.model=container(c,c.parking,"PMDetailTemplate",true);
    if (c.route==Route::C8) {
        P control=find(r,c.host,"SceneControl"), panel=find(r,c.host,"SongDetailCanvas");
        move(r,find(r,c.canvas,"Play"),c.model); // also the target of two panel tweens
        parkChildren(c,control); move(r,control,c.model);
        // The private controller needs a live GameObject for its presentation
        // methods. Its save-writing behaviour must remain disabled.
        P script=component(r,control,"","Chapter8SelectMusicControl");
        require(!r.unbox<bool>(r.call(script,"get_enabled")),"Chrome: C8 donor behaviour enabled");
        active(r,control,true);
        move(r,panel,c.model); active(r,panel,true); stretch(r,panel);
        // Its optional blur needs the official camera postprocessor. Keep the
        // private panel and remove the dependency before it can receive Awake.
        P blur=find(r,panel,"BlurBackground");
        destroy(r,component(r,blur,"LeTai.Asset.TranslucentImage","TranslucentImage"),"DestroyImmediate");
    } else {
        move(r,find(r,c.canvas,"SongDetails"),c.model);
    }
    sanitize(r,c.model);
    c.detail=container(c,c.canvas,"PMNativeDetail",true);
    c.group=c.keep(add(r,c.detail,engine,"CanvasGroup"));
    active(r,c.detail,true);
}
void discardCopy(Chrome &c) {
    if (c.copy && c.r.alive(c.copy)) {
        active(c.r,c.copy,false);
        // Deferred destruction would leave two controllers below the stable
        // detail root during a same-frame reopen. Detach the old copy first.
        move(c.r,c.copy,c.parking); destroy(c.r,c.copy,"Destroy");
    }
    c.copy=nullptr; c.detailButtons.clear(); c.release(c.copyPins);
}
// Instantiate only remaps references within the cloned subtree. Verify the
// fields consumed by detail::open before publishing or activating each copy.
void validateDetailCopy(Chrome &c) {
    Runtime &r=c.r;
    bool c8=c.route==Route::C8;
    auto style=c8 ? pmnativedetail::Style::c8 : pmnativedetail::Style::c9;
    P controller=pmnativedetail::findDonor(r,c.detail,style);
    require(r.alive(controller),"Chrome: detail root has no unique matching controller");
    auto inside=[&](P object) {
        if (!r.alive(object) || !r.unbox<bool>(r.call(tr(r,object),"IsChildOf",{"UnityEngine.Transform"},{tr(r,c.copy)})))
            throw std::runtime_error("Chrome: detail reference outside disposable copy");
    };
    auto fields=[&](P owner,std::initializer_list<const char*> keys) {
        for (auto key:keys) inside(r.get<P>(owner,key));
    };
    inside(controller);
    if (c8) {
        fields(controller,{"songDetailCanvas","songNameText","songArtistText","illustratorText","charterText","songCoverImage",
                           "levelBarController","levelSliderController","ratingDisplayController","recordInfoBar","unlockInfoBar",
                           "difficulty","level","score","acc","chapter8HintControl","songDetailTweenControl","playButton"});
        fields(r.get<P>(controller,"chapter8HintControl"),{"waveDisplay","lengthText","contentText","content","hintLB","hintC"});
        require(!r.unbox<bool>(r.call(controller,"get_enabled")),"Chrome: cloned C8 behaviour enabled");
    } else {
        fields(controller,{"titleText","composerText","scoreText","accText","songCoverImage","levelBarController",
                           "levelSliderController","ratingDisplayController","animator","canvasGroup","illustrationSizeControl"});
        fields(r.get<P>(controller,"illustrationSizeControl"),{"rectTransform","targetRectTransform","image"});
    }
}
void freshDetail(Chrome &c) {
    Runtime &r=c.r; discardCopy(c);
    bool world=false;
    c.copy=c.keep(r.stat(r.type(engine,"Object"),"Instantiate",{"UnityEngine.Object","UnityEngine.Transform","System.Boolean"},
                         {c.model,tr(r,c.detail),&world}),true);
    require(!r.unbox<bool>(r.call(c.copy,"get_activeSelf")),"Chrome: expected inactive template");
    // Clone deserialization rebuilds managed UnityEvents. Verify and strip the
    // live copy before first activation, including buttons unused by this UI.
    sanitize(r,c.copy);
    validateDetailCopy(c);
    const bool c8=c.route==Route::C8;
    std::string bar=c8 ? "SongDetailCanvas/SongCoverPanel/LevelBar/" : "SongDetails/DifficultyBar/Contents/Bar/";
    for(int i=0;i<4;++i) registerButton(c,find(r,c.copy,bar+levels[i]),Intent::Slot,i,true);
    registerButton(c,find(r,c.copy,c8 ? "Play" : "SongDetails/Play"),Intent::Start,-1,true);
    active(r,c.copy,true);
}
// Preserve the geometry of the serialized menu ancestors (especially the C9
// bottom bar). Only the ToggleMode branch may leave the dormant hierarchy.
P selectBranch(Chrome &c,P parent,P child) {
    parkChildren(c,parent); move(c.r,child,parent); active(c.r,parent,true); return parent;
}
void bootstrap(Chrome &c) {
    Runtime &r=c.r;
    P camera=find(r,c.host,"Main Camera"), event=find(r,c.host,"EventSystem");
    const bool saturn=c.route==Route::SaturnOS, c8=c.route==Route::C8;
    c.canvas=c.keep(find(r,c.host,saturn ? "Panels/FolderPanel/Canvas" : c8 ? "UICanvas" : "UI/UICanvas"));
    c.font=c.keep(readFont(r,saturn ? c.canvas : c.host));
    P back=find(r,c.canvas,saturn ? "Overlay/Back" : "Back");
    c.stage=container(c,c.host,"PMNativeChrome");
    c.parking=container(c,c.host,"PMDormantDonors");
    // Never activate UI, Panels or SceneControl to reach a descendant.
    move(r,c.canvas,c.stage);
    if (!saturn) prepareDetail(c);
    P menu=nullptr;
    if (saturn) {
        back=selectBranch(c,find(r,c.canvas,"Overlay"),back);
        registerButton(c,find(r,back,"Back"),Intent::Back);
    } else {
        registerButton(c,back,Intent::Back);
        P bottom=c8 ? nullptr : find(r,c.canvas,c.route==Route::C9 ? "BottomMenu" : "Menu");
        P full=c8 ? find(r,c.host,"UILowCanvas/MenuFull") : find(r,bottom,"MenuFull");
        P toggle=find(r,full,"ToggleMode");
        registerButton(c,toggle,Intent::List);
        // The C8 menu is originally under its own full-screen low canvas.
        move(r,full,c.stage);
        menu=selectBranch(c,full,toggle);
        if (bottom) menu=selectBranch(c,bottom,menu);
    }
    parkChildren(c,c.canvas);
    c.map=container(c,c.canvas,"PMMapParent",true); active(r,c.map,true);
    if (c.detail) move(r,c.detail,c.canvas);
    if (menu) move(r,menu,c.canvas);
    move(r,back,c.canvas);
    // Only Camera survives on the stock main camera object. Remove all camera
    // tweens, postprocessing and audio scripts while the object is still cold.
    parkChildren(c,camera); move(r,camera,c.stage);
    P cam=component(r,camera,engine,"Camera");
    each(r,r.children(camera,r.type(engine,"Component")),[&](P obj){
        if (obj!=cam && obj!=tr(r,camera)) destroy(r,obj,"DestroyImmediate");
    });
    r.call(cam,"set_targetTexture",{"UnityEngine.RenderTexture"},{nullptr});
    flag(r,cam,"set_enabled",true); active(r,camera,true);
    parkChildren(c,event); move(r,event,c.stage);
    flag(r,component(r,event,events,"EventSystem"),"set_enabled",true);
    flag(r,component(r,event,events,"StandaloneInputModule"),"set_enabled",true);
    active(r,event,true);
    P canvas=component(r,c.canvas,engine,"Canvas");
    r.call(canvas,"set_worldCamera",{"UnityEngine.Camera"},{cam});
    int display=r.unbox<int>(r.call(canvas,"get_targetDisplay"));
    r.call(cam,"set_targetDisplay",{"System.Int32"},{&display});
    if(c8) {
        int layer=r.unbox<int>(r.call(c.canvas,"get_layer"));
        require(layer>=0 && layer<32,"Chrome: invalid canvas layer");
        int mask=r.unbox<int>(r.call(cam,"get_cullingMask")) | int(1u<<layer);
        r.call(cam,"set_cullingMask",{"System.Int32"},{&mask});
    }
    // Saturn serializes a world-space, transparent panel. Use its Canvas as
    // the screen-space chapter UI, without running the official panel opener.
    int overlay=0; if(saturn) r.call(canvas,"set_renderMode",{"UnityEngine.RenderMode"},{&overlay});
    flag(r,canvas,"set_enabled",true);
    flag(r,component(r,c.canvas,ui,"GraphicRaycaster"),"set_enabled",true);
    active(r,c.canvas,true);
    sanitize(r,c.stage);
}
void verifyLiveStage(Chrome &c) {
    Runtime &r=c.r;
    P camera=component(r,find(r,c.stage,"Main Camera"),engine,"Camera");
    P canvas=component(r,c.canvas,engine,"Canvas");
    P event=find(r,c.stage,"EventSystem");
    P system=component(r,event,events,"EventSystem");
    P module=component(r,event,events,"StandaloneInputModule");
    for(P behaviour:{camera,canvas,system,module})
        require(r.unbox<bool>(r.call(behaviour,"get_isActiveAndEnabled")),"Chrome: inactive render or input component");
    int mode=r.enumValue(r.call(canvas,"get_renderMode"),"UnityEngine.RenderMode");
    require(mode==(c.route==Route::C8 ? 1 : 0),"Chrome: unexpected root canvas render mode");
    if(mode==1) require(r.call(canvas,"get_worldCamera")==camera,"Chrome: mismatched canvas camera");
    // A persistent EventSystem may sort first after a Single scene load.
    P type=r.type(events,"EventSystem");
    if(r.stat(type,"get_current")!=system)
        r.stat(type,"set_current",{"UnityEngine.EventSystems.EventSystem"},{system});
    require(r.stat(type,"get_current")==system,"Chrome: chapter EventSystem did not acquire input");
    if(c.detail) require(r.unbox<bool>(r.call(c.detail,"get_activeInHierarchy")),"Chrome: inactive detail host");
}
void apply(Chrome &c,Face face,bool input,unsigned mask) {
    Runtime &r=c.r; c.input=false;
    flag(r,component(r,c.canvas,ui,"GraphicRaycaster"),"set_enabled",face!=Face::Hidden && input);
    auto setGroup=[&](P obj,bool shown,bool enabled){
        P g=r.component(obj,r.type(engine,"CanvasGroup")); if(!g) return;
        float a=shown?1.f:0.f; r.call(g,"set_alpha",{"System.Single"},{&a});
        flag(r,g,"set_blocksRaycasts",enabled); flag(r,g,"set_interactable",enabled);
    };
    setGroup(c.canvas,face!=Face::Hidden,face!=Face::Hidden && input);
    if (c.group) {
        bool shown=face==Face::Detail;
        float alpha=shown ? 1.f : 0.f;
        r.call(c.group,"set_alpha",{"System.Single"},{&alpha});
        flag(r,c.group,"set_blocksRaycasts",shown && input);
        flag(r,c.group,"set_interactable",shown && input);
        // detail::open turns off every Selectable and GraphicRaycaster. Bring
        // back just the chapter detail canvas raycaster and our owned buttons.
        if(c.route==Route::C8 && c.copy) {
            P panel=find(r,c.copy,"SongDetailCanvas");
            setGroup(panel,shown,shown && input);
            flag(r,component(r,panel,ui,"GraphicRaycaster"),"set_enabled",shown && input);
        } else if(c.copy && shown) {
            setGroup(find(r,c.copy,"SongDetails"),true,input);
        }
    }
    for (auto list:{&c.fixed,&c.detailButtons}) for(const auto &b:*list) {
        bool shown=policy::visible(face,b.action.intent,c.allowList), enabled=policy::enabled(face,input,mask,b.action,c.allowList);
        // Native detail owns layout/slot visibility. Keep inactive native slots
        // inactive; update() may reposition or hide them for a different row.
        if(list==&c.fixed) active(r,go(r,b.button),shown);
        flag(r,b.button,"set_enabled",enabled);
        flag(r,b.button,"set_interactable",enabled);
        if(shown && b.action.intent==Intent::Start) {
            P group=r.component(go(r,b.button),r.type(engine,"CanvasGroup"));
            if(group) {
                float alpha=1; r.call(group,"set_alpha",{"System.Single"},{&alpha});
                flag(r,group,"set_blocksRaycasts",enabled); flag(r,group,"set_interactable",enabled);
            }
        }
    }
    c.face=face; c.slots=mask; c.input=input;
}
bool matches(Runtime &r,uint64_t id) {
    return NSThread.isMainThread && current && &current->r==&r && id==current->id;
}
void dispose(Chrome &c) {
    c.input=false;
    // Only these containers and descendants belong to us. The scene loader
    // owns the host and any unselected stock roots until unload.
    for(P obj:{c.stage,c.parking}) if(obj) checked([&]{
        if(c.r.alive(obj)) { active(c.r,obj,false); destroy(c.r,obj,"Destroy"); }
    });
}
}

bool open(Runtime &r,uint64_t visit,Route route,P root,View &out) {
    out={};
    if(!NSThread.isMainThread || !visit || !root || current) return false;
    auto c=std::make_unique<Chrome>(r,visit,route);
    bool ok=checked([&]{
        require(pmnativeosscene::activeRoot(r)==root,"Chrome: stale scene donor");
        c->host=c->keep(root);
        // Only serialized dormant donors can enter this bootstrap, even if a
        // caller accidentally retries the same half-consumed scene.
        P top=tr(r,root);
        for(int i=r.unbox<int>(r.call(top,"get_childCount"));i-->0;)
            require(!r.unbox<bool>(r.call(go(r,r.call(top,"GetChild",{"System.Int32"},{&i})),"get_activeSelf")),"Chrome: stock root is live");
        bootstrap(*c); apply(*c,Face::Hidden,false,0);
        active(r,c->stage,true);
        verifyLiveStage(*c);
        out={c->keep(tr(r,c->map)),c->font,c->detail};
    });
    if(!ok) { dispose(*c); return false; }
    current=std::move(c); return true;
}
bool present(Runtime &r,uint64_t visit,Face face,bool input,unsigned mask) {
    if(!matches(r,visit) || (face==Face::Detail && !current->copy)) return false;
    return checked([&]{apply(*current,face,input,mask);});
}
bool present(Runtime &r,uint64_t visit,Face face,bool input,unsigned mask,bool allowList) {
    if(!matches(r,visit)) return false;
    current->allowList=allowList;
    return present(r,visit,face,input,mask);
}
bool resetDetail(Runtime &r,uint64_t visit) {
    if(!matches(r,visit) || !current->model) return false;
    bool ok=checked([&]{apply(*current,Face::Hidden,false,0); freshDetail(*current);});
    if(!ok) checked([&]{discardCopy(*current);});
    return ok;
}
Press press(Runtime &r,P button) {
    if(!NSThread.isMainThread || !current || &current->r!=&r || !button) return {};
    for(auto list:{&current->fixed,&current->detailButtons}) for(const auto &b:*list) {
        if(b.button!=button) continue;
        Press result{Intent::Consumed,-1};
        if(policy::enabled(current->face,current->input,current->slots,b.action,current->allowList)) checked([&]{
            if(r.alive(button) && r.unbox<bool>(r.call(button,"IsActive")) && r.unbox<bool>(r.call(button,"IsInteractable"))) result=b.action;
        });
        return result;
    }
    return {};
}
void close(Runtime &r,uint64_t visit) {
    if(matches(r,visit)) { dispose(*current); current.reset(); }
}
}
