// One transition owner spans the Single unload. Native clip sampling and authored
// movies/timelines share this destination-ready handshake; neither owns a second OS.
template<class F> bool cutChecked(F work) {
    @try {try{work();return true;}catch(const std::exception &e){PMDiagnosticsWrite(e.what());}}
    @catch(NSException *e){PMDiagnosticsWrite(e.reason.UTF8String);}return false;
}
int activeCutScene(Runtime &r){return sceneHandle(r,r.stat(r.type("UnityEngine.SceneManagement","SceneManager"),"GetActiveScene"));}
bool authoredPlaying=false,entryStoryPlaying=false,timelinePreparing=false;
void tickPreparedReveal(Runtime *runtime,transition::Ticket ticket,uint64_t mapVisit){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(ticket!=cutTicket || mapVisit!=mapID || !targetPrepared || cutToList)return;
        if(!map::tick(*runtime,mapVisit)){cancelRouteCut();return;}
        tickPreparedReveal(runtime,ticket,mapVisit);
    });
}
void showPreparedTarget(Runtime&r){
    if(cutToList)return;
    if(!mapID || !chrome::present(r,visit,chrome::Face::Map,false,0,!gated) ||
       !map::present(r,mapID,true,true,false))throw std::runtime_error("Chapter OS: prepared target disappeared");
    tickPreparedReveal(&r,cutTicket,mapID);
    // A captured stock entrance frame must not cover the now-ready OS behind CutIn.
    P mask=r.get<P>(r.mainGame(),"sceneSwitchMask");
    if(r.alive(mask) && r.call(mask,"get_texture")){
        float transparent[4]={};r.call(mask,"set_texture",{"UnityEngine.Texture"},{nullptr});
        r.call(mask,"set_color",{"UnityEngine.Color"},{transparent});
    }
}
void finishRouteCut(transition::Ticket ticket,bool ok){
    if(ticket!=cutTicket)return;
    auto resume=resumeAuthoredLoad;auto revealed=mapRevealed;
    cutTicket=0;resumeAuthoredLoad=nil;mapRevealed=nil;
    bool mediaOwned=authoredPlaying||entryStoryPlaying;authoredPlaying=false;entryStoryPlaying=false;timelinePreparing=false;targetPrepared=false;listStaging=false;stableListFrames=0;
    if(mediaOwned)PMCancelUnlockMedia();
    if(resume)resume(NO);
    releaseEntryCover(*game);
    if(ok){if(revealed)revealed();return;}
    PMDiagnosticsWrite("Chapter OS: transition cancelled; restoring the current usable page");
    if(mode==Mode::listCut)mode=Mode::list;
    else if(mode==Mode::mapCut || (mapID && scene::activeRoot(*game))){
        if(revealed)revealed();else presentMap(*game);
    }
    // A Single request already accepted by Unity cannot be undone. Its fenced
    // arrival remains valid and will mount normally if the cover has timed out.
}
void cancelRouteCut(){if(cutTicket)transition::cancel(cutTicket);}
void continueEntrance(Runtime&r,bool animate=true){
    const auto ticket=cutTicket;if(!ticket||!targetPrepared)return;
    auto reveal=^{
        if(ticket!=cutTicket)return;
        entryStoryPlaying=false;
        if(!cutChecked([&]{showPreparedTarget(*game);transition::reveal(ticket,animate);}))cancelRouteCut();
    };
    // Preserve legacy onEnterMovie ordering: story first, then reveal the map.
    // The target is already ready, so a long story does not consume the load timeout.
    if(!cutToList && program.page->entryMovieKey[0] && !program.page->entryMovieSeen){
        mode=Mode::map;busy=true;entryStoryPlaying=true;
        if([actions playEntryMovie:^(BOOL completed){reveal();}])return;
        entryStoryPlaying=false;
    }
    reveal();
}
void targetReady(Runtime&r){
    if(!cutTicket || targetPrepared)return;
    auto ticket=cutTicket;targetPrepared=true;
    if(!transition::ready(ticket,true)){cancelRouteCut();return;}
    if(authoredPlaying){auto resume=resumeAuthoredLoad;resumeAuthoredLoad=nil;if(resume)resume(YES);}
    else continueEntrance(r);
}
void pollPreparedMap(Runtime *runtime,uint64_t token,uint64_t epoch,transition::Ticket ticket){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(ticket!=cutTicket || token!=visit || epoch!=generation)return;
        if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){pollPreparedMap(runtime,token,epoch,ticket);return;}
        if(!cutChecked([&]{
            if(revision!=PMContentStore.shared.revision)throw std::runtime_error("Chapter OS: content changed during transition");
            auto readiness=map::pollPrepared(*runtime,mapID,ticket);
            if(readiness.state==map::Readiness::Invalid)throw std::runtime_error("Chapter OS: map readiness visit changed");
            if(readiness.complete()){
                if(readiness.failed)PMDiagnosticsWrite("Chapter OS: unavailable media uses its authored poster/fallback");
                targetReady(*runtime);
            }else pollPreparedMap(runtime,token,epoch,ticket);
        }))cancelRouteCut();
    });
}
P cutSource(Runtime&r,Mode direction){
    if(direction==Mode::listCut)return selector;
    P root=scene::activeRoot(r),type=nullptr;
    switch(chapterRoute()){
        case scene::Route::C8:type=r.klass("Chapter8SelectMusicControl");break;
        case scene::Route::C9:type=r.type("Phigros2.Chapter9","Chapter9Phase1Control");break;
        case scene::Route::C9Phase2:type=r.type("Phigros2.Chapter9.Scripts","Chapter9Phase2Control");break;
        default:throw std::runtime_error("Chapter OS: unknown transition source");
    }
    bool inactive=true;
    return r.call(root,"GetComponentInChildren",{"System.Type","System.Boolean"},
                  {r.type_get_object(r.class_get_type(type)),&inactive});
}
void requestCutTarget(transition::Ticket ticket){
    if(ticket!=cutTicket)return;
    Runtime&r=*game;
    if(revision!=PMContentStore.shared.revision)throw std::runtime_error("Chapter OS: content changed before scene handoff");
    if(cutToList){
        listStaging=true;
        if(!scene::activeRoot(r) || gated || !leave(r,false))throw std::runtime_error("Chapter OS: list transition rejected");
    }else{
        if(!r.alive(selector) || !selectorReady(r,selector) ||
           sceneHandle(r,r.call(r.call(selector,"get_gameObject"),"get_scene"))!=activeCutScene(r))
            throw std::runtime_error("Chapter OS: source selector is no longer ready or active");
        enter(r);if(mode!=Mode::entering)throw std::runtime_error("Chapter OS: OS transition rejected");
    }
}
void requestForegroundTarget(transition::Ticket ticket){
    if(ticket!=cutTicket)return;
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{requestForegroundTarget(ticket);});return;
    }
    transition::request(ticket);
}
void authoredCut(transition::Ticket ticket,PMNativeOSProgram *p,PMNativeOSEntryTimeline *timeline){
    if(ticket!=cutTicket)return;
    // An async image preparation can finish while the app is inactive. Do not
    // mistake a temporarily unavailable presentation window for a bad animation.
    if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{authoredCut(ticket,p,timeline);});return;
    }
    const auto &config=p.page->entryTransition;
    double marker=config.load==PMOSEntryLoadEnd?-1:config.at;
    authoredPlaying=true;
    void (^sample)(double)=nil;if(timeline)sample=^(double t){[timeline sample:t];};
    const bool nativeReveal=config.reveal!=PMOSEntryRevealNone;
    BOOL accepted=PMPresentTransitionMedia(p.transitionPath,timeline.view,config.duration,marker,
        sample,
        ^(void (^resume)(BOOL)){
            if(ticket!=cutTicket){resume(NO);return;}
            resumeAuthoredLoad=[resume copy];
            if(!transition::request(ticket)){resumeAuthoredLoad=nil;resume(NO);}
        },^(BOOL completed){
            if(ticket!=cutTicket)return;
            authoredPlaying=false;
            if(!completed)PMDiagnosticsWrite("Chapter OS: authored transition unavailable; using native reveal");
            if(targetPrepared)continueEntrance(*game,!completed || nativeReveal);
            else cancelRouteCut();
        });
    if(!accepted){authoredPlaying=false;requestForegroundTarget(ticket);}
}
void beginRouteCut(Runtime&r,Mode direction,bool autoEntry){
    if(cutTicket)return;
    mode=direction;cutToList=direction==Mode::mapCut;targetPrepared=false;stableListFrames=0;
    PMNativeOSProgram *p=program;
    bool authored=autoEntry && p.page->entryTransition.declared && p.page->entryTransition.kind!=PMOSEntryTransitionNative && !p.transitionError;
    if(p.transitionError)PMDiagnosticsWrite(p.transitionError.UTF8String);
    if(!cutChecked([&]{
        P owner=cutSource(r,direction);
        if(sceneHandle(r,r.call(r.call(owner,"get_gameObject"),"get_scene"))!=activeCutScene(r))throw std::runtime_error("Chapter OS: switch source scene changed");
        if(cutToList && (!map::present(r,mapID,true,false,false)||!chrome::present(r,visit,chrome::Face::Map,false)))throw std::runtime_error("Chapter OS: could not suspend map input");
        cutTicket=transition::begin(r,r.get<P>(owner,"cutOut"),autoEntry,authored,
            ^(transition::Ticket ticket){requestCutTarget(ticket);},
            ^(transition::Ticket ticket,bool ok){finishRouteCut(ticket,ok);});
        if(!cutTicket)throw std::runtime_error("Chapter OS: could not create persistent cut");
        if(authored){
            auto ticket=cutTicket;
            if(p.page->entryTransition.kind==PMOSEntryTransitionTimeline){
                timelinePreparing=true;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                    if(ticket!=cutTicket || !timelinePreparing)return;
                    timelinePreparing=false;
                    PMDiagnosticsWrite("Chapter OS: timeline preparation timed out; using native entry");
                    requestForegroundTarget(ticket);
                });
                [PMNativeOSEntryTimeline prepareWithProgram:p completion:^(PMNativeOSEntryTimeline *timeline,NSError *error){
                    if(ticket!=cutTicket || !timelinePreparing)return;
                    timelinePreparing=false;
                    if(!timeline){PMDiagnosticsWrite(error.localizedDescription.UTF8String);requestForegroundTarget(ticket);}
                    else authoredCut(ticket,p,timeline);
                }];
            }else authoredCut(ticket,p,nil);
        }
    })){
        if(cutTicket)cancelRouteCut();
        else{if(direction==Mode::listCut){mode=Mode::list;releaseEntryCover(r);}else presentMap(r);}
    }
}
void beginManualCut(Runtime&r,Mode direction){beginRouteCut(r,direction,false);}
void beginChapterCut(Runtime&r){beginRouteCut(r,Mode::listCut,true);}
