"""Production route ownership and held-selector staging against a fake runtime."""
from pathlib import Path
import tempfile
import unittest
from test_native_os_boundary import definition
from test_native_os_transition_support import compile_cpp, run_cpp

SRC = Path(__file__).resolve().parents[1] / 'PhiMod' / 'Sources'
COORD = (SRC / 'PMNativeOSCoordinator.mm').read_text(encoding='utf-8-sig')
CUT = (SRC / 'PMNativeOSManualTransition.inc').read_text(encoding='utf-8-sig')
HOOK = (SRC / 'PMHookBackend.mm').read_text(encoding='utf-8-sig')


def harness():
    code = r"""
#include <cassert>
#include <cstdint>
#include <cstring>
#include <functional>
#include <initializer_list>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>
#define nil nullptr
#define YES true
#define NO false
using P=void*;
std::vector<std::string> calls;
int ownerObject=0;
struct Runtime {
    int activeScene=17, ownerScene=17;
    bool loadOver=true,lockTouch=false,exit=false,moving=false,sourceAlive=true,visualReady=true,disabled=false;
    bool alive(P p){return p && sourceAlive;}
    P klass(const char*){return this;}
    P type(const char*,const char*){return this;}
    P mainGame(){return this;}
    P call(P p,const char* name,std::initializer_list<const char*> = {},std::initializer_list<P> = {}){
        if(!std::strcmp(name,"get_scene"))return &ownerScene;
        if(!std::strcmp(name,"get_gameObject"))return p;
        return nullptr;
    }
    P stat(P,const char*){return &activeScene;}
    template<class T>T staticValue(P,const char* name,const char*){return name[1]=='o' && name[2]=='a' ? loadOver : lockTouch;}
    template<class T>T get(P,const char* name){
        if constexpr(std::is_same_v<T,bool>)return !std::strcmp(name,"exit")?exit:!std::strcmp(name,"isMoving")?moving:!std::strcmp(name,"disableSongSelector")?disabled:false;
        else return nullptr;
    }
    void put(P,const char* name,bool value){assert(!std::strcmp(name,"disableSongSelector"));disabled=value;}
} runtime,other;
Runtime*game=&runtime;
P selector=&ownerObject;
int sceneHandle(Runtime&,P p){return *static_cast<int*>(p);}
void PMDiagnosticsWrite(const char*){}
template<class F>bool cutChecked(F fn){try{fn();return true;}catch(const std::exception&){return false;}}
"""
    code += definition(COORD, 'enum class Mode') + ';Mode mode=Mode::listCut;\n'
    code += r"""
namespace transition {
    using Ticket=uint64_t;
    int readyCalls=0,revealCalls=0;
    bool acceptsReady=true;
    bool ready(Ticket,bool defer=false){assert(defer);++readyCalls;calls.push_back("ready");return acceptsReady;}
    bool reveal(Ticket,bool=true){++revealCalls;calls.push_back("reveal");return true;}
    void cancel(Ticket);
}
transition::Ticket cutTicket=101;
struct Bridge {bool cover=false;Runtime* runtime=nullptr;} bridge;
bool unlockBusy=false;
bool PMUnlockMediaBusy(){return unlockBusy;}
namespace pmunlock {
    bool allowAccess=true,modal=false;int accessCalls=0,modalCalls=0;
    bool selectorModalUpdate(Runtime&,P){++modalCalls;calls.push_back("modal");return modal;}
    bool selectorAccess(Runtime&,P){++accessCalls;calls.push_back("access");return allowAccess;}
}
bool cutToList=false,listStaging=false,targetPrepared=false,gated=false,authoredPlaying=false,entryStoryPlaying=false,timelinePreparing=false,busy=false;
int stableListFrames=0,revision=1,entries=0,leaves=0,restores=0,cancels=0,coverReleases=0;
uint64_t mapID=0,visit=7,generation=4,requestedEntry=0;
struct {struct {int revision=1;} shared;} PMContentStore;
std::function<void(bool)> resumeAuthoredLoad;
std::function<void()> mapRevealed;
bool refuse=false,rootAlive=true,mapVisible=false,mapRunning=false,mapInput=false;
namespace scene {
    P activeRoot(Runtime&r){return rootAlive?&r:nullptr;}
    bool isSongSelector(Runtime&r,int scene){return scene==r.ownerScene;}
}
namespace chrome {
    enum class Face{Map};
    bool present(Runtime&,uint64_t,Face,bool,int=0,bool=true){return true;}
}
namespace map {
    bool present(Runtime&,uint64_t,bool visible,bool running,bool input){
        mapVisible=visible;mapRunning=running;mapInput=input;calls.push_back(input?"map-input":"map-reveal");return true;
    }
}
namespace pmscene {void selectorFrame(Runtime&,P){calls.push_back("shortcuts");}}
namespace pmcontent {
    int work=0;
    void restoreSelectorRowVisibility(Runtime&,P){calls.push_back("row-restore");}
    void difficultyTransitionLabel(Runtime&,P){calls.push_back("difficulty-label");}
    void prepareSelectorItems(Runtime&,P){++work;}
    void selectorLoadingBegin(Runtime&,P){++work;}
    void selectorFrame(Runtime&,P){++work;}
    void selectorLoadingFrame(Runtime&,P){++work;}
    void selectorDifficultyUI(Runtime&,P){++work;}
    bool selectorVisualReady(Runtime&r,P){return r.visualReady;}
}
void enter(Runtime&){++entries;if(!refuse)mode=Mode::entering;}
bool leave(Runtime&,bool){++leaves;if(refuse)return false;mode=Mode::returning;return true;}
bool presentMap(Runtime&r){++restores;mode=Mode::map;return map::present(r,mapID,true,true,true);}
void releaseEntryCover(Runtime&){++coverReleases;bridge.cover=false;}
int candidateFrames=0;bool releaseCandidate=false;
void selectorFrame(Runtime&r,P){++candidateFrames;if(releaseCandidate)releaseEntryCover(r);}
struct Page {char entryMovieKey[2]{};bool entryMovieSeen=false;} page;
struct Program {Page* page;} program{&page};
std::function<void(bool)> storyDone;
bool playEntryMovie(std::function<void(bool)> done){storyDone=done;calls.push_back("story");return true;}
void PMCancelUnlockMedia(){calls.push_back("cancel-media");if(storyDone){auto done=storyDone;storyDone={};done(false);}}
void tickPreparedReveal(Runtime*,transition::Ticket,uint64_t){}
void cancelRouteCut();
"""
    for text, signature in ((COORD,'bool selectorReady('), (CUT,'int activeCutScene('),
                            (CUT,'void showPreparedTarget('), (CUT,'void finishRouteCut(')):
        code += definition(text, signature) + '\n'
    code += 'namespace transition {void cancel(Ticket id){++cancels;finishRouteCut(id,false);}}\n'
    for signature in ('void cancelRouteCut(', 'void continueEntrance(', 'void targetReady(', 'void requestCutTarget('):
        function = definition(CUT, signature)
        function = function.replace('^{', '[=]{')
        function = function.replace('[actions playEntryMovie:^(BOOL completed){reveal();}]',
                                    'playEntryMovie([=](bool){reveal();})')
        code += function + '\n'
    code += definition(COORD,'void abortSelectorEntry(') + '\n'
    staged = definition(COORD,'bool stageSelector(')
    staged = staged.replace('void (^nativeUpdate)(void)', 'std::function<void()> nativeUpdate = {}')
    code += staged + '\n'
    code += r"""
void ownershipChecks(){
    requestCutTarget(100);assert(entries==0 && leaves==0); // Stale request is inert.
    runtime.lockTouch=true;
    assert(!cutChecked([&]{requestCutTarget(101);}) && entries==0);
    runtime.lockTouch=false;++revision;
    assert(!cutChecked([&]{requestCutTarget(101);}) && entries==0);--revision;
    runtime.sourceAlive=false;
    assert(!cutChecked([&]{requestCutTarget(101);}) && entries==0);runtime.sourceAlive=true;
    requestCutTarget(101);assert(entries==1 && mode==Mode::entering);
    mode=Mode::mapCut;cutToList=true;gated=true;
    assert(!cutChecked([&]{requestCutTarget(101);}) && leaves==0);gated=false;
    rootAlive=false;assert(!cutChecked([&]{requestCutTarget(101);}) && leaves==0);rootAlive=true;
    requestCutTarget(101);assert(leaves==1 && mode==Mode::returning && listStaging);
}
void activeSceneFence(){
    // Captured source remains alive, but is no longer the active scene.
    assert(runtime.ownerScene==runtime.activeScene);
    ++runtime.activeScene;
    assert(!cutChecked([&]{requestCutTarget(cutTicket);}) && entries==0);
}
void finishOwnership(){
    finishRouteCut(100,false);assert(cutTicket==101 && coverReleases==0 && restores==0);
    finishRouteCut(101,false);assert(!cutTicket && mode==Mode::list && coverReleases==1);
    cutTicket=102;mode=Mode::mapCut;cutToList=true;
    finishRouteCut(102,false);assert(restores==1 && mode==Mode::map);
    cutTicket=103;mode=Mode::listCut;int callbacks=0;
    mapRevealed=[&]{++callbacks;};
    finishRouteCut(103,true);assert(callbacks==1 && !cutTicket);
    finishRouteCut(103,true);assert(callbacks==1);
    cutTicket=104;mode=Mode::mapCut;
    finishRouteCut(103,false);assert(cutTicket==104 && restores==1);
}
void finishReentry(){
    int callbacks=0;
    mapRevealed=[&]{++callbacks;assert(!cutTicket);cutTicket=202;mode=Mode::listCut;};
    finishRouteCut(101,true);
    assert(callbacks==1 && cutTicket==202 && mode==Mode::listCut);
    finishRouteCut(101,false);assert(cutTicket==202 && callbacks==1);
}
void nativeTargetReady(){
    mapID=22;mode=Mode::entering;
    mapRevealed=[&]{presentMap(runtime);};
    targetReady(runtime);
    assert(targetPrepared && mapVisible && mapRunning && !mapInput);
    assert(calls.size()==3 && calls[0]=="ready" && calls[1]=="map-reveal" && calls[2]=="reveal");
    targetReady(runtime);assert(transition::readyCalls==1 && transition::revealCalls==1);
    finishRouteCut(101,true);assert(mapInput && !cutTicket && mode==Mode::map);
}
void authoredTargetReady(){
    mapID=22;mode=Mode::entering;authoredPlaying=true;int resumed=0;
    resumeAuthoredLoad=[&](bool yes){assert(yes && targetPrepared && cutTicket);++resumed;};
    targetReady(runtime);assert(resumed==1 && !resumeAuthoredLoad);
    assert(!mapVisible && !mapRunning && !mapInput && transition::readyCalls==1 && !transition::revealCalls);
    targetReady(runtime);assert(resumed==1); // Media worker alone releases its hold.
}
void selectorStaging(){
    listStaging=true;cutToList=true;mode=Mode::returning;
    assert(stageSelector(runtime,selector) && pmcontent::work==0);
    assert(!stageSelector(other,selector) && pmcontent::work==0);
    mode=Mode::loading;assert(stageSelector(runtime,selector) && pmcontent::work==5 && !targetPrepared);
    mode=Mode::list;runtime.visualReady=false;
    assert(stageSelector(runtime,selector) && !targetPrepared && stableListFrames==0);
    runtime.visualReady=true;
    assert(stageSelector(runtime,selector) && !targetPrepared && stableListFrames==1);
    runtime.lockTouch=true;
    assert(stageSelector(runtime,selector) && !targetPrepared && stableListFrames==0);
    runtime.lockTouch=false;
    assert(stageSelector(runtime,selector) && !targetPrepared);
    assert(stageSelector(runtime,selector) && targetPrepared && transition::readyCalls==1);
    assert(stageSelector(runtime,selector) && transition::readyCalls==1);
    finishRouteCut(101,true);assert(!stageSelector(runtime,selector));
}
void legacyStoryOrdering(){
    mapID=22;mode=Mode::entering;page.entryMovieKey[0]='s';
    targetReady(runtime);
    assert(targetPrepared && entryStoryPlaying && storyDone && !mapVisible && !mapRunning);
    assert(transition::readyCalls==1 && !transition::revealCalls);
    auto complete=storyDone;storyDone={};complete(true);
    assert(!entryStoryPlaying && mapVisible && mapRunning && !mapInput && transition::revealCalls==1);
}
void nativeUpdateAndRestore(){
    listStaging=true;cutToList=true;mode=Mode::list;runtime.loadOver=false;
    int native=0;
    auto update=[&]{assert(runtime.disabled);++native;runtime.loadOver=true;};
    assert(stageSelector(runtime,selector,update) && native==1 && runtime.loadOver && !runtime.disabled);
    assert(!targetPrepared && stableListFrames==1);
    assert(stageSelector(runtime,selector,update) && native==2 && targetPrepared && !runtime.disabled);
    // Restore the prior value even when the original trampoline throws.
    targetPrepared=false;runtime.disabled=true;
    assert(stageSelector(runtime,selector,[]{throw std::runtime_error("native update failed");}));
    assert(runtime.disabled && !cutTicket && cancels==1);
}
void candidateCoverConsumesOriginalExactlyOnce(){
    cutTicket=0;listStaging=false;bridge={true,&runtime};mode=Mode::loading;runtime.loadOver=false;
    int native=0,rawInput=0;
    auto original=[&]{++native;if(!runtime.disabled)++rawInput;runtime.loadOver=true;};
    if(!stageSelector(runtime,selector,original))original();
    assert(native==1 && rawInput==0 && runtime.loadOver && !runtime.disabled);
    assert(bridge.cover && candidateFrames==1 && !targetPrepared && !transition::readyCalls);
    releaseCandidate=true;
    if(!stageSelector(runtime,selector,original))original();
    assert(native==2 && rawInput==0 && !bridge.cover && candidateFrames==2);
    // The next ordinary frame may run normally, but never twice on the release frame.
    if(!stageSelector(runtime,selector,original))original();
    assert(native==3 && rawInput==1);
}
void candidateUnlockPriorityAndAccess(){
    cutTicket=0;bridge={true,&runtime};mode=Mode::loading;unlockBusy=true;int native=0;
    auto original=[&]{++native;};
    assert(!stageSelector(runtime,selector,original));
    assert(bridge.cover && native==0 && pmunlock::accessCalls==0 && pmcontent::work==0);
    unlockBusy=false;pmunlock::modal=true;
    assert(stageSelector(runtime,selector,original));
    assert(!bridge.cover && native==0 && pmunlock::modalCalls==1 && pmunlock::accessCalls==0);
    bridge.cover=true;pmunlock::modal=false;pmunlock::allowAccess=false;
    assert(stageSelector(runtime,selector,original));
    assert(!bridge.cover && native==0 && pmcontent::work==0 && pmunlock::accessCalls==1);
    assert(pmunlock::modalCalls==2 && calls[calls.size()-2]=="modal" && calls.back()=="access");
    // Return staging must preserve the same access guard, cancelling its own ticket.
    cutTicket=202;listStaging=true;mode=Mode::list;pmunlock::modal=true;
    assert(stageSelector(runtime,selector,original));
    assert(!cutTicket && cancels==1 && native==0 && pmcontent::work==0 && pmunlock::accessCalls==2);
    assert(pmunlock::modalCalls==2); // Return cover defers unlock modals until reveal.
}
void wrongReturnScene(){
    listStaging=true;cutToList=true;mode=Mode::list;++runtime.activeScene;
    assert(stageSelector(runtime,selector) && cancels==1 && !cutTicket && !transition::readyCalls);
}
int main(int argc,char**argv){
    assert(argc==2);std::string test=argv[1];
    if(test=="ownership")ownershipChecks();
    else if(test=="active-scene")activeSceneFence();
    else if(test=="finish")finishOwnership();
    else if(test=="reentry")finishReentry();
    else if(test=="native-ready")nativeTargetReady();
    else if(test=="authored-ready")authoredTargetReady();
    else if(test=="selector")selectorStaging();
    else if(test=="wrong-return")wrongReturnScene();
    else if(test=="legacy-story")legacyStoryOrdering();
    else if(test=="native-update")nativeUpdateAndRestore();
    else if(test=="candidate")candidateCoverConsumesOriginalExactlyOnce();
    else if(test=="candidate-access")candidateUnlockPriorityAndAccess();
    else return 2;
}
"""
    return code


class CoordinatorTransitionBehavior(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='pm-route-cut-')
        cls.addClassCleanup(cls.directory.cleanup)
        cls.executable = compile_cpp(harness(), cls.directory.name, 'route-cut')

    def test_source_revision_readiness_and_stale_request_guards(self):
        run_cpp(self, self.executable, 'ownership')

    def test_source_scene_change_before_load_rejects_request(self):
        run_cpp(self, self.executable, 'active-scene')

    def test_refusal_restores_only_current_visit(self):
        run_cpp(self, self.executable, 'finish')

    def test_finish_callback_can_enter_without_old_cleanup(self):
        run_cpp(self, self.executable, 'reentry')

    def test_native_ready_starts_clock_but_input_waits_for_finish(self):
        run_cpp(self, self.executable, 'native-ready')

    def test_authored_continuation_keeps_ready_map_hidden(self):
        run_cpp(self, self.executable, 'authored-ready')

    def test_selector_loading_runs_behind_cover_until_stable_ready(self):
        run_cpp(self, self.executable, 'selector')

    def test_wrong_return_scene_cancels_instead_of_revealing(self):
        run_cpp(self, self.executable, 'wrong-return')

    def test_legacy_story_finishes_while_held_before_first_map_reveal(self):
        run_cpp(self, self.executable, 'legacy-story')

    def test_original_update_publishes_ready_under_restored_input_only_gate(self):
        run_cpp(self, self.executable, 'native-update')

    def test_candidate_preflight_cover_prevents_input_and_double_original_update(self):
        run_cpp(self, self.executable, 'candidate')

    def test_existing_unlock_media_and_selector_access_keep_priority(self):
        run_cpp(self, self.executable, 'candidate-access')

    def test_async_author_preparation_waits_for_foreground(self):
        authored=definition(CUT, 'void authoredCut(')
        self.assertLess(authored.index('UIApplicationStateActive'),authored.index('PMPresentTransitionMedia('))
        self.assertIn('authoredCut(ticket,p,timeline);',authored)
        deferred=definition(CUT, 'void requestForegroundTarget(')
        self.assertLess(deferred.index('ticket!=cutTicket'),deferred.index('UIApplicationStateActive'))
        self.assertLess(deferred.index('UIApplicationStateActive'),deferred.index('transition::request(ticket)'))
        self.assertIn('requestForegroundTarget(ticket);',deferred)

    def test_selector_staging_precedes_stock_input_and_audio(self):
        body = definition(HOOK, 'void onSelector(').split('{', 1)[1].lstrip()
        stage_at = body.index('if(pmnativecoordinator::stageSelector(R(),self,')
        stage_end = body.index('))return;', stage_at) + len('))return;')
        before = body[:stage_at]
        for cleanup in ('pmsecretcourse::menu(R())', 'clearDoorPresentation()',
                        'cancelIdleDoorLaunch(self)', 'pmchallenge::cancelVariable(R())'):
            self.assertIn(cleanup, before)
        self.assertIn('!pmnativecoordinator::transitioning() && (pmchallenge::atResult || pmchallenge::cursor>=0 || pmchallenge::hpRoot)', before)
        self.assertNotIn('orig<VoidFn>(h::selector)', before)
        self.assertIn('^{orig<VoidFn>(h::selector)(self,mi);}', body[stage_at:stage_end])
        self.assertLess(stage_end, body.index('pmcontent::difficultyInput(R(),self)'))
        self.assertIn('if(!difficultyTouch)orig<VoidFn>(h::selector)(self,mi);', body[stage_end:])
        staged = definition(COORD, 'bool stageSelector(')
        self.assertIn('if(nativeUpdate)nativeUpdate()', staged)
        self.assertIn('disableSongSelector', staged)
        self.assertIn('if(!pmunlock::selectorAccess(r,owner))', staged)
        self.assertLess(staged.index('pmunlock::selectorAccess'), staged.index('pmcontent::prepareSelectorItems'))
        self.assertIn('candidate && PMUnlockMediaBusy()', staged)
        self.assertIn('candidate && pmunlock::selectorModalUpdate(r,owner)', staged)
        self.assertLess(staged.index('pmunlock::selectorModalUpdate'), staged.index('pmunlock::selectorAccess'))
        for forbidden in ('difficultyInput(', 'orig<', 'GetMouseButton'):
            self.assertNotIn(forbidden, staged)
        loader = (SRC / 'PMContentRuntime.mm').read_text(encoding='utf-8-sig')
        self.assertIn('!pmnativecoordinator::transitionCoverActive()', definition(loader, 'void selectorLoadingFrame('))


if __name__ == '__main__':
    unittest.main()
