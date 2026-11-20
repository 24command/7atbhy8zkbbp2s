// Included once by PMSceneUI.mm. All managed calls run on the selector thread.
namespace challengeSelection {
using namespace sceneimpl;
constexpr NSUInteger pageSize = 3;
constexpr const char *entryType = "Phigros2.SongSelector.Scripts.ChallengeSongItem";
static uint32_t ownerRoot, listRoot;
static P selectButton, undoButton, playButton, previous, next;
static uint32_t arrows[2]{}, ordinalLabels[3]{};
static NSString *originalLabels[3];
static double nextLayout=0;
static int page=0;
static bool launching=false;
static constexpr int lastPage(int count){return count ? (count-1)/3 : 0;}
static P gameObject(Runtime &r,P component){return go(r,component);}
#include "PMChallengePager.inc"
struct Root {
    Runtime &r;
    uint32_t handle;
    Root(Runtime &runtime, P value) : r(runtime), handle(value ? r.gchandle_new(value,false) : 0) {}
    ~Root() { if(handle) r.gchandle_free(handle); }
    Root(const Root &) = delete;
    P get() const { return target(r,handle); }
};

static void clear(Runtime &r) {
    for(int i=0;i<3;++i){
        P label=target(r,ordinalLabels[i]);
        if(originalLabels[i] && r.alive(label))
            r.call(label,"set_text",{"System.String"},{r.managedString(originalLabels[i])});
        originalLabels[i]=nil;
        dispose(r,ordinalLabels[i],false);
    }
    for(auto &handle:arrows) dispose(r,handle,true);
    nextLayout=0;
    selectButton=undoButton=playButton=previous=next=nullptr;
    page=0; launching=false;
    dispose(r,listRoot,false);
    dispose(r,ownerRoot,false);
}

static bool owns(P button) { return button && (button==selectButton || button==previous || button==next || button==undoButton || button==playButton); }

// Temporarily expose our rooted list to the existing lock and freeze helpers.
// Native Update and button listeners always see their own fixed-slot list.
template<class F> static void withQueue(Runtime &r,P control,P list,F work) {
    Root original(r,r.get<P>(control,"challengeSongItems"));
    r.put(control,"challengeSongItems",list);
    try { work(); }
    catch(...) { r.put(control,"challengeSongItems",original.get()); throw; }
    r.put(control,"challengeSongItems",original.get());
}

static void interactable(Runtime &r,P button,bool enabled){
    if (r.unbox<bool>(r.call(button,"get_interactable"))!=enabled)
        r.call(button,"set_interactable",{"System.Boolean"},{&enabled});
}
static NSString *ordinal(int64_t number){
    int tens=number%100, ones=number%10;
    const char *suffix="th";
    if(tens<11 || tens>13){
        if(ones==1)suffix="st";
        else if(ones==2)suffix="nd";
        else if(ones==3)suffix="rd";
    }
    return [NSString stringWithFormat:@"%lld%s",(long long)number,suffix];
}
static void refresh(Runtime &r,P control,P list){
    int count=r.count(list);
    page=std::clamp(page,0,lastPage(count));
    P owner=target(r,ownerRoot), colors=r.get<P>(owner,"levelColor");
    P images=r.get<P>(control,"songCoverImages"),labels=r.get<P>(control,"difficulty"),bands=r.get<P>(control,"levelImage");
    for(int i=0;i<3;++i){
        int index=page*3+i;P image=r.at(images,i);
        P placeholder=target(r,ordinalLabels[i]);
        if(placeholder)r.call(placeholder,"set_text",{"System.String"},{r.managedString(ordinal(int64_t(page)*3+i+1))});
        active(r,go(r,image),index<count);
        if(index>=count)continue;
        P entry=r.at(list,index),item=r.get<P>(entry,"songInfo"),song=r.get<P>(item,"songInfo");
        int slot=r.get<int>(entry,"levelIndex");
        NSDictionary *chart=pmcontent::challengeEntryChart(r,entry);
        P key=r.get<P>(item,"coverBlurAssetCode");
        if(chart)key=r.managedString([NSString stringWithFormat:@"PM/%@/blur@%lu",chart[@"id"],(unsigned long)PMContentStore.shared.revision]);
        r.call(image,"set_Code",{"System.String"},{key});
        NSString *number=chart?PMDifficultyText(chart):[@(int(r.unbox<float>(r.arrayAt(r.get<P>(song,"difficulty"),slot)))) stringValue];
        r.call(r.at(labels,i),"set_text",{"System.String"},{r.managedString(number)});
        Color color=r.unbox<Color>(r.arrayAt(colors,slot));
        NSArray *rgb=chart?PMDifficultyRGB(chart[@"difficultyRGB"]?:@""):nil;
        if(rgb.count==3){color.r=[rgb[0] floatValue]/255; color.g=[rgb[1] floatValue]/255; color.b=[rgb[2] floatValue]/255;}
        r.call(r.at(bands,i),"set_color",{"UnityEngine.Color"},{&color});
    }
    for(P arrow:{previous,next}){
        bool enabled=arrow==previous?page>0:page<lastPage(count);
        Color color=enabled?Color{.08f,.09f,.11f,.95f}:Color{.32f,.32f,.32f,.8f};
        r.call(r.call(arrow,"get_targetGraphic"),"set_color",{"UnityEngine.Color"},{&color});
        interactable(r,arrow,enabled);
    }
    interactable(r,undoButton,count>0); interactable(r,playButton,count>0);
}
// The serialized songCoverImages are the three visible cells in the queue bar.
static P slotRect(Runtime &r,P control,int slot){
    P image=r.at(r.get<P>(control,"songCoverImages"),slot);
    return r.call(transform(r,image),"get_parent");
}
static P queueCanvas(Runtime &r,P end){
    P bar=r.call(end,"get_parent");
    P canvasRect=r.call(bar,"get_parent");
    P canvas=r.component(go(r,canvasRect),r.type("UnityEngine","Canvas"));
    return transform(r,r.call(canvas,"get_rootCanvas"));
}
static void layoutArrows(Runtime &r,P control){
    P end=slotRect(r,control,2);
    auto cell=r.unbox<sceneimpl::Rect>(r.call(end,"get_rect"));
    P canvas=queueCanvas(r,end);
    auto canvasRect=r.unbox<sceneimpl::Rect>(r.call(canvas,"get_rect"));
    P screen=r.type("UnityEngine","Screen");
    auto safe=r.unbox<sceneimpl::Rect>(r.stat(screen,"get_safeArea"));
    int width=r.unbox<int>(r.stat(screen,"get_width")),height=r.unbox<int>(r.stat(screen,"get_height"));
    if(width<=0 || height<=0 || canvasRect.w<=0 || canvasRect.h<=0)return;
    if(safe.w<=0 || safe.h<=0)safe={0,0,float(width),float(height)};
    float left=canvasRect.x+safe.x/width*canvasRect.w, right=left+safe.w/width*canvasRect.w;
    float bottom=canvasRect.y+safe.y/height*canvasRect.h, top=bottom+safe.h/height*canvasRect.h;
    for(int i=0;i<2;++i){
        P rect=transform(r,i?next:previous);
        auto size=r.unbox<V2>(r.call(rect,"get_sizeDelta"));
        V3 corner{cell.x+cell.w,cell.y+cell.h*(i?.25f:.75f),0};
        V3 world=r.unbox<V3>(r.call(end,"TransformPoint",{"UnityEngine.Vector3"},{&corner}));
        V3 pos=r.unbox<V3>(r.call(canvas,"InverseTransformPoint",{"UnityEngine.Vector3"},{&world}));
        float mx=size.x*.5f+6,my=size.y*.5f+6;
        pos.x=right-left>=2*mx?std::clamp(pos.x+mx,left+mx,right-mx):(left+right)*.5f;
        pos.y=top-bottom>=2*my?std::clamp(pos.y,bottom+my,top-my):(bottom+top)*.5f;
        world=r.unbox<V3>(r.call(canvas,"TransformPoint",{"UnityEngine.Vector3"},{&pos}));
        r.call(rect,"set_position",{"UnityEngine.Vector3"},{&world});
    }
}
static void buildArrows(Runtime &r,P control){
    const char *names[]={"Text","Text (1)","3rdText"};
    for(int i=0;i<3;++i){
        P object=child(r,slotRect(r,control,i),names[i]);
        if(object){
            P label=r.component(object,r.type("UnityEngine.UI","Text"));
            if(label){ordinalLabels[i]=r.gchandle_new(label,false); originalLabels[i]=r.string(r.call(label,"get_text"));}
        }
    }
    P label=r.at(r.get<P>(control,"difficulty"),0), font=r.call(label,"get_font");
    P canvas=queueCanvas(r,slotRect(r,control,2));
    auto cell=r.unbox<sceneimpl::Rect>(r.call(slotRect(r,control,2),"get_rect"));
    V2 size{std::max(42.f,cell.h*.55f),cell.h*.47f};
    for(int i=0;i<2;++i){
        P button=pagerLabel(r,canvas,font,i?"→":"←",0,true,size);
        arrows[i]=r.gchandle_new(go(r,button),false);
        (i?next:previous)=button;
    }
}
// Native song visibility and individual chart unlocks are separate. Custom
// chart IDs use the content unlock guard, including chapter requirements.
static bool stockChartOpen(Runtime &r,P song,int slot) {
    int unlockType=0; P mask=nullptr, hint=nullptr; bool appeared=false;
    r.call(r.mainGame(),"CheckSongUnlock",{"System.String","System.Int32&","System.Boolean[]&","System.Boolean&","System.String&"},
           {r.get<P>(song,"songsId"),&unlockType,&mask,&appeared,&hint});
    return appeared && mask && slot>=0 && uintptr_t(slot)<r.array_length(mask) && r.unbox<bool>(r.arrayAt(mask,slot));
}

static void add(Runtime &r) {
    P owner=target(r,ownerRoot), list=target(r,listRoot);
    if(launching || !PMSettingBool("freeChallenge") || !r.alive(owner) || !list || r.get<bool>(owner,"exit") || r.get<bool>(owner,"isMoving")) return;
    P control=r.get<P>(owner,"challengeSongSelectorControl");
    if(!selectButton || !r.unbox<bool>(r.call(selectButton,"IsInteractable")) || pmunlock::blockChallengeButton(r,selectButton)) return;
    P items=r.call(owner,"get_SongItems"); int index=r.get<int>(owner,"nowSong"), slot=r.get<int>(owner,"nowLevel");
    if(index<0 || index>=r.count(items) || slot<0 || slot>3) return;
    P item=r.at(items,index), song=r.get<P>(item,"songInfo"), numbers=r.get<P>(song,"difficulty");
    if(!r.get<bool>(item,"visible") || !r.unbox<bool>(r.call(item,"get_Unlocked")) || !numbers || uintptr_t(slot)>=r.array_length(numbers)) return;
    P lock=r.get<P>(owner,"locked");
    if(r.alive(lock) && r.unbox<bool>(r.call(lock,"get_activeInHierarchy"))) return;
    NSDictionary *chart=pmcontent::difficultyForSong(r,song,slot);
    if(!chart && (!(r.unbox<float>(r.arrayAt(numbers,slot))>0) || !stockChartOpen(r,song,slot))) return;
    Root entry(r,r.object_new(r.type("Phigros2.SongSelector.Scripts","ChallengeSongItem")));
    r.call(entry.get(),".ctor"); r.put(entry.get(),"songInfo",item); r.put(entry.get(),"levelIndex",slot);
    int tail=r.count(list);
    // Freeze only the new entry. Rebinding AT must never reinterpret an earlier pick.
    Root single(r,r.object_new(r.object_get_class(list))); r.call(single.get(),".ctor");
    r.call(single.get(),"Add",{entryType},{entry.get()});
    withQueue(r,control,single.get(),[&]{pmcontent::freezeChallengeDifficulties(r,owner);});
    r.call(list,"Add",{entryType},{entry.get()});
    page=lastPage(tail+1); refresh(r,control,list);
}

static void launch(Runtime &r,P control,P list) {
    if(!r.count(list)) return;
    bool blocked=true;
    withQueue(r,control,list,[&]{blocked=pmunlock::blockChallengeButton(r,r.get<P>(control,"playButton"));});
    for(int i=0,n=r.count(list);!blocked && i<n;++i) {
        P entry=r.at(list,i), item=r.get<P>(entry,"songInfo"), song=r.get<P>(item,"songInfo");
        int slot=r.get<int>(entry,"levelIndex");
        if(r.get<int>(item,"sortIndex")!=-2147483000) blocked=!stockChartOpen(r,song,slot);
    }
    if(blocked) { PMDiagnosticsWrite("Challenge contains a locked chart"); return; }
    P game=r.mainGame();
    Root oldList(r,r.get<P>(game,"challengeSongItems")), hidden(r,r.get<P>(game,"hiddenChallengeSongItem"));
    int oldIndex=r.get<int>(game,"nowChallengeIndex");
    bool oldLife=r.get<bool>(game,"secretChallengeLifeEnabled");
    // Stock Play validates three slots and truncates its list. Give it a
    // separate launch list; the run controller owns the actual playing order.
    Root slots(r,r.object_new(r.object_get_class(list)));
    r.call(slots.get(),".ctor");
    int count=r.count(list);
    for(int i=0;i<3;++i){
        P entry=r.at(list,std::min(i,count-1));
        r.call(slots.get(),"Add",{entryType},{entry});
    }
    launching=true;
    try {
        pmchallenge::startVariable(r,list);
        withQueue(r,control,slots.get(),[&]{ r.call(control,"Play"); });
        // Play may reject a protected Chapter 9 combination without throwing.
        if(r.get<P>(game,"challengeSongItems")!=slots.get())
            throw std::runtime_error("Native challenge start declined");
        r.put(game,"challengeSongItems",list);
        r.put(game,"secretChallengeLifeEnabled",false);
    } catch(...) {
        launching=false; pmchallenge::cancelVariable(r);
        r.put(game,"challengeSongItems",oldList.get()); r.put(game,"nowChallengeIndex",oldIndex);
        r.put(game,"hiddenChallengeSongItem",hidden.get()); r.put(game,"secretChallengeLifeEnabled",oldLife);
        throw;
    }
    for(auto handle:arrows)active(r,target(r,handle),false);
}

static void press(Runtime &r,P button){
    P owner=target(r,ownerRoot),list=target(r,listRoot);
    if(launching || !r.alive(owner) || r.get<bool>(owner,"exit") || r.get<bool>(owner,"isMoving") || pmunlock::selectorButtonBlocked(r,button))return;
    P control=r.get<P>(owner,"challengeSongSelectorControl");int count=r.count(list);
    if(button==selectButton){add(r);return;}
    if(button==playButton){if(count)launch(r,control,list);return;}
    if(button==undoButton && count){int tail=count-1;r.call(list,"RemoveAt",{"System.Int32"},{&tail});}
    else if(button==previous && page>0)--page;
    else if(button==next && page<lastPage(count))++page;
    else return;
    refresh(r,control,list);
}
static void frame(Runtime &r,P owner){
    if(ownerRoot && target(r,ownerRoot)!=owner)clear(r);
    if(!PMSettingBool("freeChallenge")){
        if(ownerRoot && !launching){
            P control=r.get<P>(owner,"challengeSongSelectorControl");
            clear(r);
            if(r.alive(control)){
                P images=r.get<P>(control,"songCoverImages");
                for(int i=0;i<r.count(images);++i)active(r,go(r,r.at(images,i)),false);
                r.call(control,"SetText");
            }
        }
        return;
    }
    if(launching)return;
    P control=r.get<P>(owner,"challengeSongSelectorControl");
    if(!r.alive(control)||!r.unbox<bool>(r.call(control,"get_isActiveAndEnabled"))){if(ownerRoot)clear(r);return;}
    if(r.get<bool>(owner,"exit"))return;
    if(!ownerRoot){
        P stock=r.get<P>(control,"challengeSongItems");
        if(!stock||r.count(stock))return;
        if(r.count(r.get<P>(control,"songCoverImages"))<3)return;
        sceneimpl::Rect box=r.unbox<sceneimpl::Rect>(r.call(slotRect(r,control,2),"get_rect"));
        if(box.w<=0||box.h<=0)return;
        Root list(r,r.object_new(r.object_get_class(stock)));r.call(list.get(),".ctor");
        ownerRoot=r.gchandle_new(owner,false);listRoot=r.gchandle_new(list.get(),false);
        try{selectButton=r.get<P>(control,"selectButton"); undoButton=r.get<P>(control,"undoButton"); playButton=r.get<P>(control,"playButton");
            buildArrows(r,control);refresh(r,control,list.get());
        }catch(...){clear(r);throw;}
    }
    double now=NSDate.timeIntervalSinceReferenceDate;
    if(now>=nextLayout){layoutArrows(r,control);nextLayout=now+.25;}
    // The stock selector may reset these states after a difficulty change.
    bool filled=r.count(target(r,listRoot))>0;
    interactable(r,playButton,filled);interactable(r,undoButton,filled);
}
}
