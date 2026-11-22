// State is scoped to the incoming Single scene, before SongSelector.Start.
// Initializing loadingSelector calls detach(), so it cannot own this state.
struct SelectorEntry {
    Runtime *runtime = nullptr;
    int handle = 0;
    NSUInteger revision = 0;
    NSString *chapter = nil;
    PMNativeOSProgram *program = nil;
    bool loading = false;
    PMNativeOSLoadCompletion waiter = nil; // Set if the live selector arrives first.
    uint32_t cover = 0;
    uint64_t ticket = 0;
} bridge;

void destroyEntryCover(Runtime &r,P go){
    if(r.alive(go))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{go});
}
void releaseEntryCover(Runtime &r){
    const auto pin=bridge.cover;
    bridge.cover=0;
    if(!pin)return;
    @try {
        try { destroyEntryCover(r,r.gchandle_get_target(pin)); }
        catch(const std::exception &e){PMDiagnosticsWrite(e.what());}
    } @catch(NSException *e){PMDiagnosticsWrite(e.reason.UTF8String);}
    r.gchandle_free(pin);
}
void resetEntryBridge(Runtime &r){
    releaseEntryCover(r);
    auto next=bridge.ticket+1;
    bridge={};
    bridge.ticket=next;
}
bool coverSelector(Runtime &r,int handle){
    P go=nullptr;
    bool installed=false;
    @try {
        try {
            go=r.object_new(r.type("UnityEngine","GameObject"));
            r.call(go,".ctor",{"System.String"},{r.string_new("PhiMod_SelectorEntry")});
            if(sceneHandle(r,r.call(go,"get_scene"))!=handle){
                // Internal_SceneLoaded can precede the active-scene change. Parent
                // through the incoming selector to move the new root to its scene.
                P type=r.type_get_object(r.class_get_type(r.klass("SongSelector")));
                P owner=r.stat(r.type("UnityEngine","Object"),"FindObjectOfType",{"System.Type"},{type});
                if(!r.alive(owner) || sceneHandle(r,r.call(r.call(owner,"get_gameObject"),"get_scene"))!=handle)
                    throw std::runtime_error("Chapter OS: selector cover scene changed");
                P tr=r.call(go,"get_transform");
                bool keepWorld=false;
                r.call(tr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{r.call(owner,"get_transform"),&keepWorld});
                r.call(tr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{nullptr,&keepWorld});
                if(sceneHandle(r,r.call(go,"get_scene"))!=handle)
                    throw std::runtime_error("Chapter OS: could not place selector cover");
            }
            auto add=[&](const char *ns,const char *name){
                return r.call(go,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type(ns,name)))});
            };
            P canvas=add("UnityEngine","Canvas");
            int overlay=0,order=32767;
            r.call(canvas,"set_renderMode",{"UnityEngine.RenderMode"},{&overlay});
            r.call(canvas,"set_sortingOrder",{"System.Int32"},{&order});
            P image=add("UnityEngine.UI","RawImage");
            P mask=r.get<P>(r.mainGame(),"sceneSwitchMask");
            P texture=r.alive(mask)?r.call(mask,"get_texture"):nullptr;
            // Preserve the incoming transition frame when stock supplied one.
            // The scene-local opaque fallback also covers camera-space list UI.
            float shade=r.alive(texture)?1.f:0.f,color[]={shade,shade,shade,1.f};
            if(shade)r.call(image,"set_texture",{"UnityEngine.Texture"},{texture});
            r.call(image,"set_color",{"UnityEngine.Color"},{color});
            add("UnityEngine.UI","GraphicRaycaster");
            bridge.cover=r.gchandle_new(go,false);
            installed=bridge.cover!=0;
            bridge.runtime=&r;
        } catch(const std::exception &e){PMDiagnosticsWrite(e.what());}
    } @catch(NSException *e){PMDiagnosticsWrite(e.reason.UTF8String);}
    if(!installed && go)destroyEntryCover(r,go);
    return installed;
}
