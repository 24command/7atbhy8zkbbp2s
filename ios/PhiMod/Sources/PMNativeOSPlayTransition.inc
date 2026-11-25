// Included in PMNativeOSScene.mm so all entry points share its visit fence.
namespace entrance {
constexpr const char *engine = "UnityEngine";
constexpr const char *blurNS = "LeTai.Asset.TranslucentImage";
constexpr const char *chapter9 = "Phigros2.Chapter9";
void require(bool condition,const char *message) { if (!condition) throw std::runtime_error(message); }
template<class F> bool checked(F work) {
    @try { try { work(); return true; } catch(const std::exception &e){ PMDiagnosticsWrite(e.what()); } }
    @catch(NSException *e){ PMDiagnosticsWrite(e.reason.UTF8String); }
    return false;
}
P child(Runtime &r,P obj,const char *path) {
    P t=r.call(r.call(obj,"get_transform"),"Find",{"System.String"},{r.string_new(path)});
    require(r.alive(t),path); return r.call(t,"get_gameObject");
}
P component(Runtime &r,P obj,const char *ns,const char *type) {
    P c=r.component(obj,r.type(ns,type)); require(r.alive(c),type); return c;
}
P add(Runtime &r,P obj,P type) {
    return r.call(obj,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(type))});
}
void flag(Runtime &r,P obj,const char *method,bool value) { r.call(obj,method,{"System.Boolean"},{&value}); }
void alpha(Runtime &r,P group,float value) { r.call(group,"set_alpha",{"System.Single"},{&value}); }
P copy(Runtime &r,P original,P parent=nullptr) {
    P klass=r.type(engine,"Object"); bool world=false;
    return parent ? r.stat(klass,"Instantiate",{"UnityEngine.Object","UnityEngine.Transform","System.Boolean"},
                           {original,r.call(parent,"get_transform"),&world}) :
                    r.stat(klass,"Instantiate",{"UnityEngine.Object"},{original});
}
void destroy(Runtime &r,P obj,bool immediate=false) {
    if(r.alive(obj))r.stat(r.type(engine,"Object"),immediate?"DestroyImmediate":"Destroy",{"UnityEngine.Object"},{obj});
}
struct Pins {
    Runtime &r; std::vector<uint32_t> handles;
    explicit Pins(Runtime &rt):r(rt){}
    P keep(P obj) {
        require(obj,"Play: missing managed object"); handles.push_back(r.gchandle_new(obj,false));
        require(handles.back(),"Play: could not retain managed object"); return obj;
    }
    ~Pins(){for(auto h:handles)if(h)r.gchandle_free(h);}
};
struct Donor : Pins {
    using Pins::Pins;
    P parking{},panel{},config{},prefab{},captureCamera{};
    bool c8=false;
    float mapUpdateRate=0; int mapDownsample=0;
};
std::unique_ptr<Donor> donor;
// Reserve the cold serialized references before chrome reparents detail and strips
// camera effects. The template lives outside the coordinator's donor search tree.
void reserve(Runtime &r,P host,Route route) {
    donor.reset(); if(route==Route::SaturnOS)return;
    auto d=std::make_unique<Donor>(r); d->c8=route==Route::C8;
    try {
        d->parking=d->keep(r.object_new(r.type(engine,"GameObject")));
        r.call(d->parking,".ctor",{"System.String"},{r.string_new("PMEntranceTemplate")});
        flag(r,d->parking,"SetActive",false);
        P panel=child(r,host,d->c8?"SongDetailCanvas":"UI/StartInfoCanvas");
        d->panel=d->keep(copy(r,panel,d->parking));
        if(d->c8){
            for(auto name:{"Tweens","SongCoverPanel","StartInfos/SongInfoMask"})destroy(r,child(r,d->panel,name),true);
            // Chrome's detail-only copy has no camera postprocessor. Leave the
            // entrance material on our private copy, before it is ever activated.
            destroy(r,component(r,child(r,panel,"StartInfos/StartAnimation"),blurNS,"TranslucentImage"),true);
        } else d->captureCamera=d->keep(child(r,host,"Background Capture Camera"));
        P controller=d->c8?component(r,child(r,host,"SceneControl"),"","Chapter8SelectMusicControl"):
            component(r,child(r,panel,"StartInfos"),chapter9,"Chapter9SongLevelStartControl");
        d->prefab=d->keep(r.get<P>(controller,"backgroundPrefab"));
        P source=component(r,child(r,host,"Main Camera"),blurNS,"TranslucentImageSource");
        d->config=d->keep(r.call(source,"get_BlurConfig"));
        d->mapUpdateRate=r.get<float>(source,"maxUpdateRate");
        d->mapDownsample=r.unbox<int>(r.call(source,"get_Downsample"));
        donor=std::move(d);
    }catch(...){destroy(r,d->parking);throw;}
}
struct Play : Pins {
    Play(Runtime &r,uint64_t id):Pins(r),visit(id){}
    uint64_t visit; ArmPlay arm=nil; PlayFinished finished=nil;
    bool c8=false,shown=false,committed=false,capturing=false;
    P parking{},panel{},info{},controller{},routine{},group{},mapSource{},bg{},bgGO{},cover{},runner{},captureCam{},config{},camera{};
    struct Color { float r,g,b,a; } previousColor{};
    P switchMask{},previousTexture{};
    float previousWidth{},previousHeight{};
    bool hidPreviousBG=false;
    P previousBG{},previousInfo{},captureConfig{},captureTarget{},tweens{},coldController{};
    int mask=0,lastFrame=-1; float resumeAt=0; double deadline=0;
};
std::shared_ptr<Play> live;
bool pending(){return bool(live);}
P imageKey(Runtime &r,P info,bool blurred) {
    P key=r.get<P>(info,"illustrationKey"); NSString *value=r.string(key);
    require(value.length,"Play: missing illustration key"); if(!blurred)return key;
    if([value hasPrefix:@"PM/"]){
        NSMutableArray *parts=[[value componentsSeparatedByString:@"/"] mutableCopy];
        require(parts.count==3,"Play: invalid custom illustration key");
        NSString *variant=parts[2]; NSRange suffix=[variant rangeOfString:@"@"];
        NSString *kind=[variant hasPrefix:@"courseImage"]?@"courseBlur":@"chapterBlur";
        parts[2]=[kind stringByAppendingString:(suffix.location==NSNotFound?@"":[variant substringFromIndex:suffix.location])];
        return r.managedString([parts componentsJoinedByString:@"/"]);
    }
    P builder=r.klass("IdBuilder"),id=r.get<P>(info,"songsId"),level=r.get<P>(info,"songsLevel");
    P alternate=r.stat(builder,"BuildCoverImageId",{"System.String","System.String"},{id,level});
    P suffix=[value isEqual:r.string(alternate)]?level:r.string_new("");
    return r.stat(builder,"BuildBlurImageId",{"System.String","System.String"},{id,suffix});
}
void prepare(Play &p,P host) {
    Runtime &r=p.r; p.c8=donor->c8;
    P chrome=child(r,host,"PMNativeChrome");
    P camGO=child(r,chrome,"Main Camera"); p.camera=p.keep(component(r,camGO,engine,"Camera"));
    p.mask=r.unbox<int>(r.call(p.camera,"get_cullingMask"));
    p.parking=p.keep(r.object_new(r.type(engine,"GameObject")));
    r.call(p.parking,".ctor",{"System.String"},{r.string_new("PMPlayEntrance")}); flag(r,p.parking,"SetActive",false);
    p.panel=p.keep(copy(r,donor->panel,p.parking)); flag(r,p.panel,"SetActive",true);
    P canvas=component(r,p.panel,engine,"Canvas");
    r.call(canvas,"set_worldCamera",{"UnityEngine.Camera"},{p.camera});
    int order=3000; r.call(canvas,"set_sortingOrder",{"System.Int32"},{&order}); flag(r,canvas,"set_enabled",true);
    flag(r,component(r,p.panel,"UnityEngine.UI","GraphicRaycaster"),"set_enabled",false);
    alpha(r,component(r,p.panel,engine,"CanvasGroup"),1);
    P face=child(r,p.panel,"StartInfos"),anim=child(r,face,"StartAnimation"),selected=child(r,face,"SelectedSong");
    flag(r,face,"SetActive",true);flag(r,anim,"SetActive",false);flag(r,selected,"SetActive",false);
    flag(r,child(r,face,"SongsCover"),"SetActive",true);flag(r,child(r,p.panel,"BlurBackground"),"SetActive",false);
    p.tweens=p.keep(r.children(p.panel,r.klass("TweenInfo")));
    for(uintptr_t i=0;i<r.array_length(p.tweens);++i){
        P t=r.arrayAt(p.tweens,i), target=r.get<P>(t,"targetComponent");
        require(r.alive(target) && r.unbox<bool>(r.call(r.call(target,"get_transform"),"IsChildOf",
                {"UnityEngine.Transform"},{r.call(p.panel,"get_transform")})),"Play: external entrance tween target");
        r.put(t,"useOnStart",false);r.put(t,"useOnComplete",false);flag(r,t,"set_enabled",false);
    }
    P animators=r.children(p.panel,r.type(engine,"Animator"));
    for(uintptr_t i=0;i<r.array_length(animators);++i)flag(r,r.arrayAt(animators,i),"set_fireEvents",false);
    P fade=component(r,face,engine,"Animator"); flag(r,fade,"set_enabled",false);
    flag(r,component(r,child(r,selected,"Level"),"UnityEngine.UI","Button"),"set_enabled",false);
    p.group=p.keep(add(r,child(r,chrome,"UICanvas"),r.type(engine,"CanvasGroup")));
    p.mapSource=p.keep(add(r,camGO,r.type(blurNS,"TranslucentImageSource")));
    p.config=p.keep(copy(r,donor->config));
    r.put(p.mapSource,"maxUpdateRate",donor->mapUpdateRate);
    r.call(p.mapSource,"set_Downsample",{"System.Int32"},{&donor->mapDownsample});
    r.call(p.mapSource,"set_BlurConfig",{"LeTai.Asset.TranslucentImage.BlurConfig"},{p.config});
    P blurs=r.children(p.panel,r.type(blurNS,"TranslucentImage"));
    for(uintptr_t i=0;i<r.array_length(blurs);++i)r.put(r.arrayAt(blurs,i),"source",p.mapSource);
    p.cover=p.keep(component(r,child(r,face,"SongsCover/Cover"),"","AddressableImageLoaderWithLowResPreview"));
    // The 4.0.4 entrance canvases have a scaler above the animated cover hierarchy.
    p.runner=p.keep(component(r,p.panel,"UnityEngine.UI","CanvasScaler"));
    if(p.c8){
        // A cold private component supplies the iterator's serialized fields.
        // Its GameObject stays inactive for the entire visit.
        p.coldController=p.keep(r.object_new(r.type(engine,"GameObject")));
        r.call(p.coldController,".ctor",{"System.String"},{r.string_new("PMColdStartIterator")});
        flag(r,p.coldController,"SetActive",false);
        p.controller=p.keep(add(r,p.coldController,r.klass("Chapter8SelectMusicControl")));
        r.put(p.controller,"startFadeOutAnimation",fade); r.put(p.controller,"startFadeOutBackground",child(r,p.panel,"BlurBackground"));
        r.put(p.controller,"selectMusicCanvasGroup",p.group); r.put(p.controller,"UILowCanvasGroup",p.group);
        r.put(p.controller,"bgmPlayer",add(r,p.coldController,r.type(engine,"AudioSource")));
        r.put(p.controller,"particlesToHide",r.array_new(r.type(engine,"ParticleSystem"),0));
        for(auto pair:{std::pair<const char*,const char*>{"SelectedSong/SongName","songsName"},{"SelectedSong/Artist","composer"},
             {"SelectedSong/Level/Difficulty","songsDifficulty"},{"SelectedSong/Level/LevelText","songsLevel"},
             {"StartAnimation/moreInfos/Charter/Text (1)","charter"},{"StartAnimation/moreInfos/Illustrator/Text","illustrator"}})
            r.call(component(r,child(r,face,pair.first),"UnityEngine.UI","Text"),"set_text",{"System.String"},{r.get<P>(p.info,pair.second)});
    }else{
        p.controller=p.keep(component(r,face,chapter9,"Chapter9SongLevelStartControl"));
        p.captureCam=p.keep(copy(r,donor->captureCamera,p.parking));
        P capture=component(r,p.captureCam,engine,"Camera"),source=component(r,p.captureCam,blurNS,"TranslucentImageSource");
        flag(r,capture,"set_enabled",false); flag(r,p.captureCam,"SetActive",true);
        r.put(p.controller,"mainCamera",p.camera);r.put(p.controller,"backgroundCamera",capture);
        r.put(p.controller,"mapBlurSource",p.mapSource);r.put(p.controller,"backgroundBlurSource",source);
        p.captureConfig=p.keep(copy(r,r.get<P>(p.controller,"backgroundBlurConfig")));r.put(p.controller,"backgroundBlurConfig",p.captureConfig);
        r.call(source,"set_BlurConfig",{"LeTai.Asset.TranslucentImage.BlurConfig"},{p.captureConfig});
        r.put(component(r,child(r,anim,"BlurLayers/BackgroundBlur"),blurNS,"TranslucentImage"),"source",source);
        r.call(p.controller,"ConfigureInfo",{"LevelStartInfo"},{p.info});
    }
    // Keep the new renderer transparent until its exact illustration is ready.
    p.bg=p.keep(copy(r,donor->prefab)); p.bgGO=p.keep(r.call(p.bg,"get_gameObject"));
    r.put(p.bg,"disappearBeforeLoaded",true);
    require(r.unbox<bool>(r.call(p.bg,"CheckInitialized")),"Play: missing background renderer");
    float zero=0;r.call(p.bg,"set_Alpha",{"System.Single"},{&zero});
    int layer=p.c8?8:18;r.call(p.bgGO,"set_layer",{"System.Int32"},{&layer});
    // Preload the private canvas while invisible. It can render the existing
    // chapter all the way through the asset wait, including slow local imports.
    alpha(r,component(r,p.panel,engine,"CanvasGroup"),0);flag(r,p.parking,"SetActive",true);
    require(r.unbox<bool>(r.call(p.runner,"get_isActiveAndEnabled")),"Play: inactive entrance runner");
    require(r.unbox<bool>(r.call(p.cover,"CheckInitialized")),"Play: missing cover image");
    // Run one LoadImage per clone. The base setter schedules work on GameInformation,
    // and the preview setter uses the cover itself. Neither owns this visit's lifetime.
    for(P loader:{p.bg,p.cover}){
        P key=imageKey(r,p.info,loader==p.bg);
        P load=r.call(loader,"LoadImage",{"System.String"},{key});
        // An imported sprite can already be in AssetRef.obj and finish without yielding.
        P job=r.call(p.runner,"StartCoroutine",{"System.Collections.IEnumerator"},{load});
        require(job || r.unbox<bool>(r.call(loader,"get_ImageLoaded")),"Play: image load rejected");
    }
}
float clock(Runtime &r) { return r.unbox<float>(r.stat(r.type(engine,"Time"),"get_time")); }
void startAnimation(Play &p) {
    Runtime &r=p.r; P c=p.controller;
    int mask=p.mask|(1<<8),layer=8;
    r.call(p.camera,"set_cullingMask",{"System.Int32"},{&mask});
    r.call(p.bgGO,"set_layer",{"System.Int32"},{&layer});
    P face=child(r,p.panel,"StartInfos");
    for(uintptr_t i=0;i<r.array_length(p.tweens);++i)flag(r,r.arrayAt(p.tweens,i),"set_enabled",true);
    flag(r,child(r,face,"SelectedSong"),"SetActive",true);
    flag(r,child(r,face,"StartAnimation"),"SetActive",true);
    alpha(r,component(r,p.panel,engine,"CanvasGroup"),1);
    if(p.c8){
        p.routine=p.keep(r.call(c,"StartAnimation"));
        P closure=p.keep(r.object_new(r.nested(r.klass("Chapter8SelectMusicControl"),"<>c__DisplayClass81_0")));
        r.call(closure,".ctor");r.put(closure,"bg",p.bg);r.put(p.routine,"<>8__1",closure);
    }else{
        r.put(c,"bg",p.bg);
        r.put(p.mapSource,"maxUpdateRate",0.f);
        alpha(r,r.get<P>(c,"mapStartBlur"),1);alpha(r,r.get<P>(c,"backgroundStartBlur"),0);
        p.routine=p.keep(r.call(c,"StartAnimation",{"LevelStartInfo"},{p.info}));
    }
    // Resume at the first fade iteration with our exact, already-loaded art.
    // State 0 acquires the retail song/cover and assumes the official camera
    // stack. All later animation, fade, wait and capture code is the player’s.
    r.put(p.routine,"<>1__state",1);r.put(p.routine,"<nowTime>5__2",clock(r));
    p.shown=true;
    p.deadline=NSProcessInfo.processInfo.systemUptime+15;
}
void finish(std::shared_ptr<Play> p,bool routed) {
    Runtime &r=p->r;
    if(live!=p)return;
    live.reset();
    // The persistent renderer and captured frame now belong to Level. Destroy
    // only allocations still owned by this attempt, including on early reject.
    if(!routed){
        // This scaler belongs exclusively to the private entrance canvas. Stop loads,
        // capture and any end-of-frame handoff before releasing their Unity objects.
        checked([&]{if(r.alive(p->runner))r.call(p->runner,"StopAllCoroutines");});
        checked([&]{ if(r.alive(p->parking))flag(r,p->parking,"SetActive",false); });
        checked([&]{ if(p->committed){P g=r.mainGame();
            if(r.get<P>(g,"levelStartInfo")==p->info){
                r.put(g,"levelStartInfo",p->previousInfo);
                // Only undo a failed native capture while this visit still owns
                // the displayed scene. Another Single load owns its own mask.
                if(current.id==p->visit && activeHandle(r)==current.handle){
                    P captured=r.call(p->switchMask,"get_texture");
                    if(captured!=p->previousTexture){
                        r.call(p->switchMask,"set_texture",{"UnityEngine.Texture"},{p->previousTexture});
                        r.call(p->switchMask,"set_color",{"UnityEngine.Color"},{&p->previousColor});
                        destroy(r,captured);
                    }
                    r.put(g,"screenW",p->previousWidth);
                    r.put(g,"screenH",p->previousHeight);
                }
            }
            if(r.get<P>(g,"background")==p->bgGO){
                r.put(g,"background",p->previousBG);
                if(p->hidPreviousBG && r.alive(p->previousBG))flag(r,p->previousBG,"SetActive",true);
            }
        }});
        checked([&]{destroy(r,p->bgGO);});
        checked([&]{if(r.alive(p->group))alpha(r,p->group,1);});
        checked([&]{if(r.alive(p->camera))r.call(p->camera,"set_cullingMask",{"System.Int32"},{&p->mask});});
    }else checked([&]{destroy(r,p->previousBG);});
    if(!p->c8)checked([&]{
        P target=p->captureTarget;
        if(!target && r.alive(p->controller))target=r.get<P>(p->controller,"backgroundCaptureTarget");
        if(r.alive(target)){r.call(target,"Release");destroy(r,target);}
    });
    checked([&]{destroy(r,p->captureConfig);});checked([&]{destroy(r,p->coldController);});
    checked([&]{destroy(r,p->parking);});checked([&]{destroy(r,p->group);});
    checked([&]{destroy(r,p->mapSource);});checked([&]{destroy(r,p->config);});
    if(p->finished)checked([&]{p->finished(routed);});
}
void commit(Play &p) {
    Runtime &r=p.r;P g=r.mainGame();
    p.switchMask=p.keep(r.get<P>(g,"sceneSwitchMask"));
    require(r.alive(p.switchMask),"Play: missing persistent sceneSwitchMask");
    p.previousTexture=r.call(p.switchMask,"get_texture"); if(p.previousTexture)p.keep(p.previousTexture);
    p.previousColor=r.unbox<Play::Color>(r.call(p.switchMask,"get_color"));
    p.previousWidth=r.get<float>(g,"screenW");p.previousHeight=r.get<float>(g,"screenH");
    p.previousBG=r.get<P>(g,"background"); if(p.previousBG)p.keep(p.previousBG);
    p.previousInfo=r.get<P>(g,"levelStartInfo"); if(p.previousInfo)p.keep(p.previousInfo);
    require(p.arm(r,p.info),"Play: launch no longer valid");
    require(live.get()==&p && current.id==p.visit && activeHandle(r)==current.handle,"Play: source visit changed");
    p.committed=true;
    r.put(g,"levelStartInfo",p.info);r.put(g,"background",p.bgGO);
    if(r.alive(p.previousBG) && r.unbox<bool>(r.call(p.previousBG,"get_activeSelf"))){
        flag(r,p.previousBG,"SetActive",false);p.hidPreviousBG=true;
    }
    r.stat(r.type(engine,"Object"),"DontDestroyOnLoad",{"UnityEngine.Object"},{p.bgGO});
    // Hand the unconsumed screen-size / WaitForEndOfFrame state to Unity.
    // Its next two MoveNext calls read the final render, install the mask and
    // synchronously request Level. A dispatch timer cannot perform ReadPixels.
    require(r.call(p.runner,"StartCoroutine",{"System.Collections.IEnumerator"},{p.routine}),"Play: frame capture rejected");
    p.deadline=NSProcessInfo.processInfo.systemUptime+15;
}
void tick(std::shared_ptr<Play> p) {
    if(live!=p)return;
    Runtime &r=p->r;
    bool ok=checked([&]{
        if(p->committed){
            int h=activeHandle(r);
            if(matches(r,h,12,"Assets/Phigros2/Level/Level")){finish(p,true);return;}
            require(NSProcessInfo.processInfo.systemUptime<p->deadline,"Play: Level load interrupted"); return;
        }
        require(current.id==p->visit && activeHandle(r)==current.handle,"Play: source visit interrupted");
        require(NSProcessInfo.processInfo.systemUptime<p->deadline,
                p->shown?"Play: entrance animation timed out":"Play: entrance art or capture timed out");
        if(!p->shown){
            if(!r.unbox<bool>(r.call(p->bg,"get_ImageLoaded")) || !r.unbox<bool>(r.call(p->cover,"get_ImageLoaded")))return;
            require(r.alive(r.call(p->bg,"get__settedFile")) &&
                    r.alive(r.call(p->cover,"get__settedFile")),"Play: illustration is unavailable");
            if(!p->c8){
                if(!p->capturing){
                    int version=r.get<int>(p->controller,"backgroundPrepareVersion");
                    P capture=r.call(p->controller,"CaptureBackground",{"AddressableImageLoader","System.Int32"},{p->bg,&version});
                    require(r.call(p->runner,"StartCoroutine",{"System.Collections.IEnumerator"},{capture}),"Play: capture rejected");
                    p->capturing=true;return;
                }
                P target=r.get<P>(p->controller,"backgroundCaptureTarget");
                if(!r.alive(target))return;
                p->captureTarget=p->keep(target);
            }
            startAnimation(*p);
        }
        int frame=r.unbox<int>(r.stat(r.type(engine,"Time"),"get_frameCount"));
        if(frame==p->lastFrame || clock(r)<p->resumeAt)return;
        p->lastFrame=frame;
        if(r.get<int>(p->routine,"<>1__state")== (p->c8?4:3)){commit(*p);return;}
        require(r.unbox<bool>(r.call(p->routine,"MoveNext")),"Play: unexpected end of entrance iterator");
        if(!p->c8)alpha(r,p->group,r.unbox<float>(r.call(r.get<P>(p->controller,"mapStartBlur"),"get_alpha")));
        P wait=r.get<P>(p->routine,"<>2__current");
        if(wait){
            require(r.object_get_class(wait)==r.type(engine,"WaitForSeconds"),"Play: unexpected iterator yield");
            p->resumeAt=clock(r)+r.get<float>(wait,"m_Seconds");
        }
    });
    if(live!=p)return;
    if(!ok){finish(p,false);return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_MSEC),dispatch_get_main_queue(),^{tick(p);});
}
void loaded(Runtime &r,int handle){
    auto p=live;if(!p || handle==current.handle)return;
    bool arrived=false;
    checked([&]{arrived=p->committed && matches(r,handle,12,"Assets/Phigros2/Level/Level");});
    finish(p,arrived);
}
void unloaded(Runtime &){
    donor.reset();auto p=live;
    if(p && !p->committed)finish(p,false);
}
} // namespace entrance

#include "PMNativeOSStartSound.inc"

bool play(Runtime &r,uint64_t visit,P info,ArmPlay arm,PlayFinished finished){
    using namespace entrance;
    if(!NSThread.isMainThread || !visit || visit!=current.id || !donor || !arm || !finished || pending())return false;
    P host=activeRoot(r);if(!host || !info || r.object_get_class(info)!=r.klass("LevelStartInfo"))return false;
    auto p=std::make_shared<Play>(r,visit);live=p;
    if(!checked([&]{p->info=p->keep(info);prepare(*p,host);})){finish(p,false);return false;}
    p->arm=[arm copy];p->finished=[finished copy];p->deadline=NSProcessInfo.processInfo.systemUptime+30;
    dispatch_async(dispatch_get_main_queue(),^{tick(p);});return true;
}
