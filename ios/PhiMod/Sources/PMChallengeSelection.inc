// Included once by PMSceneUI.mm. All managed calls run on the selector thread.
namespace challengeSelection {
using namespace sceneimpl;
constexpr NSUInteger pageSize = 3;
constexpr const char *entryType = "Phigros2.SongSelector.Scripts.ChallengeSongItem";
static uint32_t ownerRoot, listRoot;
static P selectButton;
static UIStackView *panel;
static UILabel *rows;
static UIButton *previous, *next, *undo, *start, *append;
static NSMutableArray<NSString *> *captions;
static NSUInteger page;
static bool launching;
enum class Action { None, Previous, Next, Undo, Start, Add };
static Action pending;
static double pendingTime;

static constexpr NSUInteger lastPage(NSUInteger count) { return count ? (count-1)/pageSize : 0; }
static constexpr bool available(Action action, NSUInteger count, NSUInteger current) {
    switch(action) {
    case Action::Previous: return current>0;
    case Action::Next: return current<lastPage(count);
    case Action::Undo: case Action::Start: return count>0;
    case Action::Add: return true;
    default: return false;
    }
}

struct Root {
    Runtime &r;
    uint32_t handle;
    Root(Runtime &runtime, P value) : r(runtime), handle(value ? r.gchandle_new(value,false) : 0) {}
    ~Root() { if(handle) r.gchandle_free(handle); }
    Root(const Root &) = delete;
    P get() const { return target(r,handle); }
};

static void clear(Runtime &r) {
    [panel removeFromSuperview];
    panel=nil; rows=nil; previous=nil; next=nil; undo=nil; start=nil; append=nil; captions=nil;
    selectButton=nullptr; pending=Action::None; page=0; launching=false;
    dispose(r,listRoot,false);
    dispose(r,ownerRoot,false);
}

static bool owns(P button) { return button && button==selectButton; }

// Temporarily expose our rooted list to the existing lock and freeze helpers.
// Native Update and button listeners always see their own fixed-slot list.
template<class F> static void withQueue(Runtime &r,P control,P list,F work) {
    Root original(r,r.get<P>(control,"challengeSongItems"));
    r.put(control,"challengeSongItems",list);
    try { work(); }
    catch(...) { r.put(control,"challengeSongItems",original.get()); throw; }
    r.put(control,"challengeSongItems",original.get());
}

static void refresh() {
    NSUInteger count=captions.count;
    NSUInteger last=lastPage(count);
    page=std::min(page,last);
    NSMutableArray *lines=[NSMutableArray arrayWithObject:[NSString stringWithFormat:@"自由挑战 · %lu 首   %lu / %lu",(unsigned long)count,(unsigned long)(page+1),(unsigned long)(last+1)]];
    for(NSUInteger i=page*pageSize;i<std::min(count,(page+1)*pageSize);++i)
        [lines addObject:[NSString stringWithFormat:@"%lu. %@",(unsigned long)(i+1),captions[i]]];
    rows.text=[lines componentsJoinedByString:@"\n"];
    previous.enabled=available(Action::Previous,count,page); next.enabled=available(Action::Next,count,page);
    undo.enabled=start.enabled=available(Action::Start,count,page) && !launching;
}

static UIButton *controlButton(UIStackView *bar, NSString *title, Action action) {
    PMOfficialButton *button=[PMOfficialButton new];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1 alpha:.35] forState:UIControlStateDisabled];
    [button addAction:[UIAction actionWithHandler:^(UIAction *event){
        if(!launching && pending==Action::None && available(action,captions.count,page)) {
            pending=action;
            pendingTime=NSDate.timeIntervalSinceReferenceDate;
        }
    }] forControlEvents:UIControlEventTouchUpInside];
    [bar addArrangedSubview:button];
    return button;
}

static void buildPanel(UIWindow *w) {
    panel=[UIStackView new]; panel.axis=UILayoutConstraintAxisVertical;
    PMOfficialCard *card=[PMOfficialCard new]; card.userInteractionEnabled=NO;
    [panel insertSubview:card atIndex:0]; card.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[[card.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [card.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor], [card.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor]]];
    panel.layoutMargins=UIEdgeInsetsMake(4,10,0,10); panel.layoutMarginsRelativeArrangement=YES;
    rows=[UILabel new]; rows.font=[UIFont systemFontOfSize:12]; rows.textColor=UIColor.whiteColor;
    rows.numberOfLines=4; [panel addArrangedSubview:rows];
    UIStackView *bar=[UIStackView new]; bar.distribution=UIStackViewDistributionFillEqually;
    bar.tintColor=UIColor.whiteColor; [panel addArrangedSubview:bar];
    append=controlButton(bar,@"加入",Action::Add); undo=controlButton(bar,@"撤销",Action::Undo);
    start=controlButton(bar,@"开始",Action::Start);
    previous=controlButton(bar,@"‹",Action::Previous); next=controlButton(bar,@"›",Action::Next);
    previous.accessibilityLabel=@"上一页"; next.accessibilityLabel=@"下一页";
    panel.translatesAutoresizingMaskIntoConstraints=NO; [w addSubview:panel];
    [NSLayoutConstraint activateConstraints:@[[panel.bottomAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.bottomAnchor constant:-4],
        [panel.trailingAnchor constraintEqualToAnchor:w.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [panel.widthAnchor constraintEqualToConstant:268], [bar.heightAnchor constraintEqualToConstant:44]]];
    refresh();
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
    if(!r.get<bool>(item,"visible") || !r.unbox<bool>(r.call(item,"get_Unlocked")) || !numbers || uintptr_t(slot)>=r.array_length(numbers) || !(r.unbox<float>(r.arrayAt(numbers,slot))>0)) return;
    P lock=r.get<P>(owner,"locked");
    if(r.alive(lock) && r.unbox<bool>(r.call(lock,"get_activeInHierarchy"))) return;
    NSDictionary *chart=pmcontent::difficultyForSong(r,song,slot);
    if(!chart && !stockChartOpen(r,song,slot)) return;
    NSString *name=chart[@"title"] ?: r.string(r.get<P>(song,"songsName"));
    NSString *level=chart[@"level"] ?: @[@"EZ",@"HD",@"IN",@"AT"][slot];
    NSString *caption=[NSString stringWithFormat:@"%@ · %@",name,level];
    Root entry(r,r.object_new(r.type("Phigros2.SongSelector.Scripts","ChallengeSongItem")));
    r.call(entry.get(),".ctor"); r.put(entry.get(),"songInfo",item); r.put(entry.get(),"levelIndex",slot);
    int tail=r.count(list);
    // Freeze only the new entry. Rebinding AT must never reinterpret an earlier pick.
    Root single(r,r.object_new(r.object_get_class(list))); r.call(single.get(),".ctor");
    r.call(single.get(),"Add",{entryType},{entry.get()});
    withQueue(r,control,single.get(),[&]{pmcontent::freezeChallengeDifficulties(r,owner);});
    r.call(list,"Add",{entryType},{entry.get()});
    [captions addObject:caption]; page=lastPage(NSUInteger(tail)+1); refresh();
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
    if(blocked) { rows.text=@"队列中有已锁定的谱面，请撤销后重选。"; return; }
    P game=r.mainGame();
    Root oldList(r,r.get<P>(game,"challengeSongItems")), hidden(r,r.get<P>(game,"hiddenChallengeSongItem"));
    int oldIndex=r.get<int>(game,"nowChallengeIndex");
    bool oldLife=r.get<bool>(game,"secretChallengeLifeEnabled");
    Root transition(r,r.call(control,"TurnToNextScene",{"System.String"},{r.string_new("ChallengeMode")}));
    launching=true;
    try {
        r.put(game,"challengeSongItems",list); r.put(game,"nowChallengeIndex",0);
        r.put(game,"hiddenChallengeSongItem",P(nullptr)); r.put(game,"secretChallengeLifeEnabled",false);
        pmchallenge::startVariable(r,list);
        if(!r.call(control,"StartCoroutine",{"System.Collections.IEnumerator"},{transition.get()}))
            throw std::runtime_error("Challenge transition did not start");
    } catch(...) {
        launching=false; pmchallenge::cancelVariable(r);
        r.put(game,"challengeSongItems",oldList.get()); r.put(game,"nowChallengeIndex",oldIndex);
        r.put(game,"hiddenChallengeSongItem",hidden.get()); r.put(game,"secretChallengeLifeEnabled",oldLife);
        throw;
    }
    panel.hidden=YES;
}

static void frame(Runtime &r,P owner) {
    if(ownerRoot && target(r,ownerRoot)!=owner) clear(r);
    if(!PMSettingBool("freeChallenge")) { if(ownerRoot) clear(r); return; }
    if(launching) return;
    P control=r.get<P>(owner,"challengeSongSelectorControl");
    if(!r.alive(control) || !r.unbox<bool>(r.call(control,"get_isActiveAndEnabled"))) { if(ownerRoot) clear(r); return; }
    P select=r.get<P>(control,"selectButton");
    if(!r.alive(select) || !r.unbox<bool>(r.call(select,"IsActive")) || r.get<bool>(owner,"exit")) {
        panel.hidden=YES; pending=Action::None; selectButton=nullptr; return;
    }
    P native=r.get<P>(control,"challengeSongItems");
    // If the setting changed mid-stock-course, let that course finish normally.
    if(!native || r.count(native)) { if(ownerRoot) clear(r); return; }
    UIWindow *w=window(); if(!w) return;
    if(!ownerRoot) {
        Root list(r,r.object_new(r.object_get_class(native))); r.call(list.get(),".ctor");
        captions=[NSMutableArray new]; buildPanel(w);
        listRoot=r.gchandle_new(list.get(),false); ownerRoot=r.gchandle_new(owner,false);
    }
    selectButton=select;
    bool modal=pmunlock::selectorButtonBlocked(r,select);
    panel.hidden=modal;
    append.enabled=!modal && r.unbox<bool>(r.call(select,"IsInteractable"));
    Action action=pending; pending=Action::None;
    if(modal || !available(action,captions.count,page) || NSDate.timeIntervalSinceReferenceDate-pendingTime>.5 || r.get<bool>(owner,"isMoving")) return;
    P list=target(r,listRoot);
    try {
        switch(action) {
        case Action::Previous: --page; break;
        case Action::Next: ++page; break;
        case Action::Undo: {
            int tail=r.count(list)-1;
            if(tail>=0) { r.call(list,"RemoveAt",{"System.Int32"},{&tail}); [captions removeLastObject]; }
            break;
        }
        case Action::Add: add(r); return;
        case Action::Start: launch(r,control,list); return;
        case Action::None: return;
        }
        refresh();
    } catch(const std::exception &e) {
        rows.text=@"操作失败，可重试。"; PMDiagnosticsWrite(e.what());
    }
}
}
