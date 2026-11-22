// Included in the coordinator's private namespace. The retail ToSongList and
// ToSimulateMode both instantiate cutOut. Their TurnToNextScene iterators yield
// while elapsed <= 0.67f (scaled Unity time). The prefab owns its animation.
struct ManualCut {
    Mode direction;
    uint64_t epoch, sourceVisit;
    int sourceScene = 0;
    uint32_t visual = 0;
    double deadline = 0;

    bool current() const {
        return mode == direction && generation == epoch && visit == sourceVisit;
    }
};

template<class F> bool cutChecked(F work) {
    @try {
        try { work(); return true; }
        catch (const std::exception &e) { PMDiagnosticsWrite(e.what()); }
    } @catch (NSException *e) { PMDiagnosticsWrite(e.reason.UTF8String); }
    return false;
}

int activeCutScene(Runtime &r) {
    return sceneHandle(r,r.stat(r.type("UnityEngine.SceneManagement","SceneManager"),"GetActiveScene"));
}
double cutTime(Runtime &r) {
    return r.unbox<double>(r.stat(r.type("UnityEngine","Time"),"get_timeSinceLevelLoadAsDouble"));
}
void destroyCut(Runtime &r,P visual) {
    if (r.alive(visual)) r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{visual});
}
void finishCut(Runtime &r,const ManualCut &cut,bool accepted) {
    // An accepted Single load destroys the overlay along with the source scene.
    if (cut.visual) {
        if (!accepted) cutChecked([&]{ destroyCut(r,r.gchandle_get_target(cut.visual)); });
        r.gchandle_free(cut.visual);
    }
    if (!cut.current()) return;
    if (cut.direction == Mode::listCut) mode = Mode::list;
    else if (!presentMap(r)) leave(r,false,nil);
}

enum class CutStep { waiting, accepted, cancelled };
CutStep advanceCut(Runtime &r,const ManualCut &cut) {
    if (!cut.current()) return CutStep::cancelled;
    if (activeCutScene(r) != cut.sourceScene) {
        if (cut.direction == Mode::listCut) detach(r);
        return CutStep::cancelled;
    }
    if (revision != PMContentStore.shared.revision || !r.alive(r.gchandle_get_target(cut.visual)))
        return CutStep::cancelled;
    if (cutTime(r) <= cut.deadline) return CutStep::waiting;
    if (cut.direction == Mode::listCut) {
        if (!r.alive(selector) || !selectorReady(r,selector)) return CutStep::cancelled;
        enter(r);
        return mode == Mode::entering ? CutStep::accepted : CutStep::cancelled;
    }
    return !gated && scene::activeRoot(r) && leave(r,false,nil) ? CutStep::accepted : CutStep::cancelled;
}

void pollCut(Runtime *runtime,ManualCut cut) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        Runtime &r = *runtime;
        CutStep step = CutStep::cancelled;
        cutChecked([&]{ step = advanceCut(r,cut); });
        if (step == CutStep::waiting) pollCut(runtime,cut);
        else finishCut(r,cut,step == CutStep::accepted);
    });
}

void beginManualCut(Runtime &r,Mode direction) {
    ManualCut cut{direction,generation,visit};
    mode = direction; // Claim Press/Submit, selector Update and map callbacks before any Unity calls.
    bool ok = cutChecked([&]{
        P owner = selector;
        if (direction == Mode::mapCut) {
            P root = scene::activeRoot(r);
            P type = program.nativeChapter == 8 ? r.klass("Chapter8SelectMusicControl") :
                r.type("Phigros2.Chapter9","Chapter9Phase1Control");
            bool inactive = true;
            owner = r.call(root,"GetComponentInChildren",{"System.Type","System.Boolean"},
                           {r.type_get_object(r.class_get_type(type)),&inactive});
            if (!map::present(r,mapID,true,false,false) || !chrome::present(r,visit,chrome::Face::Map,false))
                throw std::runtime_error("Chapter OS: could not suspend map input");
        }
        cut.sourceScene = sceneHandle(r,r.call(r.call(owner,"get_gameObject"),"get_scene"));
        if (!cut.sourceScene || cut.sourceScene != activeCutScene(r))
            throw std::runtime_error("Chapter OS: switch source scene changed");
        P prefab = r.get<P>(owner,"cutOut");
        if (!r.alive(prefab)) throw std::runtime_error("Chapter OS: missing CutOut prefab");
        P visual = r.stat(r.type("UnityEngine","Object"),"Instantiate",{"UnityEngine.Object"},{prefab});
        if (!r.alive(visual)) throw std::runtime_error("Chapter OS: CutOut instantiation failed");
        cut.visual = r.gchandle_new(visual,false);
        if (!cut.visual) {
            destroyCut(r,visual);
            throw std::runtime_error("Chapter OS: could not retain CutOut");
        }
        cut.deadline = cutTime(r) + 0.67f;
    });
    if (ok) pollCut(&r,cut);
    else finishCut(r,cut,false);
}
