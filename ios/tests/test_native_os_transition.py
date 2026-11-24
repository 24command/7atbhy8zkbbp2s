"""Exercise the real pure Gate and extracted persistent-cut adapter entry points.

Unity calls/dispatch are mocked; phase transitions, token fencing, timer ordering,
and callback ownership are production code, not a second implementation.
"""
from pathlib import Path
import re
import tempfile
import unittest
from test_native_os_boundary import definition
from test_native_os_transition_support import compile_cpp, run_cpp

SRC = Path(__file__).resolve().parents[1] / 'PhiMod' / 'Sources'
TRANSITION = (SRC / 'PMNativeOSTransition.mm').read_text(encoding='utf-8-sig')


def harness():
    code = '#include "' + (SRC / 'PMNativeOSTransition.hpp').as_posix() + '"\n'
    code += r"""
#include <cassert>
#include <cstdint>
#include <cstring>
#include <functional>
#include <initializer_list>
#include <limits>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
using namespace pmnativeostran;
using Ticket=uint64_t;
using P=void*;
using Load=std::function<void(Ticket)>;
using Done=std::function<void(Ticket,bool)>;
using dispatch_source_t=void*;
#define nil nullptr
int applicationState=0, cancelledClocks=0, loads=0, dones=0, destroyed=0, frameCount=1;
bool lastOK=false, sourceAlive=true;
double now=0;
std::vector<std::string> events;
std::function<void(Ticket)> onLoad;
std::function<void(Ticket,bool)> onDone;
double CACurrentMediaTime(){return now;}
void dispatch_source_cancel(dispatch_source_t){++cancelledClocks;events.push_back("cancel-clock");}
void PMDiagnosticsWrite(const char*){events.push_back("diagnostic");}
struct Runtime {
    std::set<P> living;
    uint32_t next=0;
    int freed=0;
    bool alive(P p){return living.count(p)!=0;}
    uint32_t gchandle_new(P,bool){return ++next;}
    void gchandle_free(uint32_t){++freed;}
    P type(const char*,const char*){return this;}
    P stat(P,const char* name){assert(!std::strcmp(name,"get_frameCount"));return &frameCount;}
    template<class T>T unbox(P p){return *static_cast<T*>(p);}
    P call(P,const char* name,std::initializer_list<const char*> = {},std::initializer_list<P> = {}){
        assert(!std::strcmp(name,"SampleAnimation"));events.push_back("sample");return nullptr;
    }
} runtime;
template<class F>bool checked(F fn){try{fn();return true;}catch(const std::exception&){return false;}}
void require(bool yes,const char* message){if(!yes)throw std::runtime_error(message);}
void destroy(Runtime&r,P p){if(r.living.erase(p)){++destroyed;events.push_back("destroy");}}
bool request(Ticket);
bool ready(Ticket,bool=false);
bool reveal(Ticket,bool=true);
void cancel(Ticket=0);
"""
    code += definition(TRANSITION, 'struct Cut') + ';\n'
    code += 'std::shared_ptr<Cut> live;Ticket sequence=0;\n'
    # Execute the production notification callback bodies. Only registration and
    # removal are replaced by portable functions, not the suspension state logic.
    observer = definition(TRANSITION, 'void observeCut(')
    bodies = re.findall(r'usingBlock:\^\(NSNotification\s*\*\)\s*\{(.*?)\}\];', observer, re.S)
    assert len(bodies) == 2, 'expected resign/active notification bodies'
    code += 'std::function<void()> resignObserver,activeObserver;\n'
    code += 'void releaseCutObservers(){resignObserver={};activeObserver={};events.push_back("release-observers");}\n'
    code += 'void observeCut(const std::shared_ptr<Cut>&c){releaseCutObservers();std::weak_ptr<Cut> weak=c;\n'
    code += 'resignObserver=[weak]{' + bodies[0] + '};\n'
    code += 'activeObserver=[weak]{' + bodies[1] + '};}\n'
    for signature in ('void finish(', 'void tick(', 'bool request(', 'bool ready(',
                      'bool reveal(', 'void cancel(', 'bool active(', 'bool loading('):
        function = definition(TRANSITION, signature)
        function = function.replace('UIApplication.sharedApplication.applicationState', 'applicationState')
        function = function.replace('UIApplicationStateActive', '0')
        code += function + '\n'
    code += r"""
std::shared_ptr<Cut> start(bool covered=false,bool external=false){
    assert(!live);
    auto c=std::make_shared<Cut>(runtime,++sequence,covered,external);
    c->visual=reinterpret_cast<P>(uintptr_t(1000+sequence));
    c->closing=reinterpret_cast<P>(1);c->opening=reinterpret_cast<P>(2);
    c->clock=reinterpret_cast<P>(3);runtime.living.insert(c->visual);
    c->load=[](Ticket id){++loads;events.push_back("load");if(onLoad)onLoad(id);};
    c->done=[](Ticket id,bool ok){++dones;lastOK=ok;events.push_back("done");if(onDone)onDone(id,ok);};
    live=c;observeCut(c);return c;
}
void step(const std::shared_ptr<Cut>&c,double dt,int newFrame){now+=dt;frameCount=newFrame;tick(c);}
void gatePhases(){
    Gate g;
    assert(g.phase==Phase::Closing && !g.request() && !g.ready() && !g.reveal());
    assert(!g.advance(coveredAt) && g.phase==Phase::Closing); // opaque != load permission
    assert(!g.advance(-1) && !g.advance(std::numeric_limits<double>::quiet_NaN()));
    assert(!g.advance(std::numeric_limits<double>::infinity()) && g.elapsed==coveredAt);
    assert(g.advance(switchAt-coveredAt+.0001) && g.phase==Phase::Covered);
    assert(g.request() && g.phase==Phase::Loading && !g.request());
    assert(!g.advance(1000) && g.phase==Phase::Loading && !g.reveal());
    assert(g.ready() && g.phase==Phase::Ready && !g.ready());
    assert(!g.advance(1000) && g.phase==Phase::Ready);
    assert(g.reveal() && g.phase==Phase::Revealing && !g.reveal());
    assert(g.finish() && g.phase==Phase::Finished && !g.finish());
    assert(!g.request() && !g.ready() && !g.reveal() && !g.advance(1));
    for(auto phase:{Phase::Closing,Phase::Covered,Phase::Loading,Phase::Ready,Phase::Revealing}){
        Gate cancelled;cancelled.phase=phase;assert(cancelled.finish() && !cancelled.finish());
    }
    Gate authored(true,true);assert(!authored.advance(1000) && authored.phase==Phase::Covered);
    assert(authored.request() && authored.ready() && authored.phase==Phase::Ready);
    assert(authored.reveal() && authored.finish());
}
void nativeLifecycle(){
    auto c=start();assert(active() && !loading());
    step(c,coveredAt,2);assert(!loads && c->gate.phase==Phase::Closing);
    step(c,switchAt-coveredAt,3);assert(!loads && c->gate.phase==Phase::Covered);
    step(c,.02,4);assert(loads==1 && loading());
    step(c,.02,5);assert(loads==1 && loading() && !dones);
    assert(ready(c->id) && c->gate.phase==Phase::Revealing);
    step(c,revealDuration-.001,6);assert(active() && !dones);
    step(c,.002,7);assert(!active() && dones==1 && lastOK && destroyed==1 && cancelledClocks==1);
}
void staleAndDuplicate(){
    auto c=start(true);auto id=c->id;
    assert(!request(id+1) && !ready(id+1) && !reveal(id+1));cancel(id+1);assert(active());
    assert(request(id) && !request(id) && loads==1);
    assert(!reveal(id));assert(ready(id) && !ready(id) && !reveal(id));
    finish(c,true);finish(c,true);cancel(id);assert(dones==1 && lastOK);
    auto next=start(true);assert(next->id!=id);
    assert(!request(id) && !ready(id) && !reveal(id));cancel(id);finish(c,false);tick(c);
    assert(live==next && dones==1 && loads==1);
    cancel(next->id);assert(dones==2 && !lastOK);
}
void waitsForReady(){
    auto c=start(true);assert(request(c->id));
    step(c,59,2);assert(active() && loading() && !dones && !reveal(c->id));
    step(c,2,3);assert(!active() && dones==1 && !lastOK); // timeout cancels, never reveals
}
void sourceDestroyed(){
    auto c=start(true);assert(request(c->id));sourceAlive=false; // accepted Single destroys source only
    step(c,.1,2);assert(loading() && runtime.alive(c->visual));
    assert(ready(c->id));step(c,revealDuration+.01,3);
    assert(!active() && dones==1 && lastOK);
    auto lost=start(true);runtime.living.erase(lost->visual);step(lost,.01,4);
    assert(!active() && dones==2 && !lastOK);
}
void cancellationReentry(){
    auto old=start(true);auto id=old->id;std::shared_ptr<Cut> next;events.clear();
    onDone=[&](Ticket ticket,bool ok){if(ticket==id){assert(!ok && !active() && !resignObserver && !activeObserver);next=start(true);}};
    cancel(id);
    assert(live==next && dones==1 && destroyed==1 && cancelledClocks==1);
    assert(events.size()>=4 && events[0]=="cancel-clock" && events[1]=="release-observers" && events[2]=="destroy" && events[3]=="done");
    finish(old,true);tick(old);cancel(id);assert(live==next && dones==1);
    onDone={};cancel(next->id);assert(!active() && dones==2);
}
void loadFailureAndReentry(){
    auto c=start(true);onLoad=[](Ticket){throw std::runtime_error("source gone");};
    assert(request(c->id));assert(!active() && dones==1 && !lastOK && !ready(c->id));
    onLoad={};auto old=start(true);std::shared_ptr<Cut> next;
    onLoad=[&](Ticket id){cancel(id);next=start(true);};
    assert(request(old->id));assert(live==next && dones==2);
    onLoad={};cancel(next->id);
}
void deferredNativeReveal(){
    auto c=start(true);assert(request(c->id));
    assert(ready(c->id,true) && c->gate.phase==Phase::Ready);
    step(c,120,2);assert(active() && !dones && c->gate.phase==Phase::Ready);
    assert(!ready(c->id,true) && loads==1); // Legacy story cannot re-ready/reload.
    assert(reveal(c->id));step(c,revealDuration+.001,3);assert(!active() && lastOK);
}
void suspensionPhases(){
    for(auto phase:{Phase::Closing,Phase::Covered,Phase::Loading,Phase::Revealing}){
        auto c=start(phase!=Phase::Closing);
        if(phase==Phase::Loading || phase==Phase::Revealing)assert(request(c->id));
        if(phase==Phase::Revealing)assert(ready(c->id));
        step(c,.1,++frameCount);
        assert(c->gate.phase==phase);
        const double elapsed=c->gate.elapsed;
        const int beforeLoads=loads,beforeDones=dones;
        assert(resignObserver && activeObserver);
        resignObserver();applicationState=1;
        assert(c->suspended && c->coveredFrame==-1);
        now+=120; // No timer ticks while iOS has actually suspended the process.
        activeObserver();applicationState=0;
        assert(!c->suspended && c->previous==now && c->coveredFrame==-1);
        step(c,.01,++frameCount);
        assert(active() && dones==beforeDones && c->gate.phase==phase);
        assert(std::abs(c->gate.elapsed-elapsed-.01)<1e-8);
        if(phase==Phase::Covered){
            assert(loads==beforeLoads); // A new opaque frame must render after resume.
            step(c,.001,frameCount);assert(loads==beforeLoads);
            step(c,.02,++frameCount);assert(loads==beforeLoads+1 && loading());
        }
        cancel(c->id);assert(!resignObserver && !activeObserver);
    }
}
void coveredFrameBarrier(){
    auto c=start();
    step(c,switchAt+.001,10);assert(c->gate.phase==Phase::Covered && !loads);
    // Multiple dispatch-source callbacks can run between Unity renders at 30fps.
    step(c,.001,10);assert(loads==0 && c->gate.phase==Phase::Covered);
    step(c,.034,11);assert(loads==1 && loading());cancel(c->id);
}
int main(int argc,char**argv){
    assert(argc==2);std::string name=argv[1];
    if(name=="gate")gatePhases();
    else if(name=="lifecycle")nativeLifecycle();
    else if(name=="stale")staleAndDuplicate();
    else if(name=="wait")waitsForReady();
    else if(name=="source")sourceDestroyed();
    else if(name=="reentry")cancellationReentry();
    else if(name=="load-failure")loadFailureAndReentry();
    else if(name=="render-barrier")coveredFrameBarrier();
    else if(name=="deferred")deferredNativeReveal();
    else if(name=="suspension")suspensionPhases();
    else return 2;
}
"""
    return code


class PersistentTransitionBehavior(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='pm-held-cut-')
        cls.addClassCleanup(cls.directory.cleanup)
        cls.executable = compile_cpp(harness(), cls.directory.name, 'held-cut')

    def test_pure_gate_phases_and_invalid_operations(self):
        run_cpp(self, self.executable, 'gate')

    def test_native_closing_covered_loading_ready_revealing_finish(self):
        run_cpp(self, self.executable, 'lifecycle')

    def test_duplicate_and_stale_request_ready_finish(self):
        run_cpp(self, self.executable, 'stale')

    def test_missing_ready_waits_then_cancels_without_success(self):
        run_cpp(self, self.executable, 'wait')

    def test_source_destruction_does_not_destroy_persistent_visual(self):
        run_cpp(self, self.executable, 'source')

    def test_cancellation_allows_reentry_without_old_cleanup(self):
        run_cpp(self, self.executable, 'reentry')

    def test_load_failure_and_callback_cancellation_reentry(self):
        run_cpp(self, self.executable, 'load-failure')

    def test_native_ready_can_hold_for_legacy_story_before_reveal(self):
        run_cpp(self, self.executable, 'deferred')

    def test_suspension_excludes_background_time_and_resets_render_barrier(self):
        run_cpp(self, self.executable, 'suspension')

    def test_observers_are_registered_and_released_before_callbacks(self):
        observe = definition(TRANSITION, 'void observeCut(')
        self.assertIn('UIApplicationWillResignActiveNotification', observe)
        self.assertIn('UIApplicationDidBecomeActiveNotification', observe)
        self.assertIn('observeCut(c)', definition(TRANSITION, 'Ticket begin('))
        release = definition(TRANSITION, 'void releaseCutObservers(')
        self.assertEqual(release.count('removeObserver:'), 2)
        finish = definition(TRANSITION, 'void finish(')
        self.assertLess(finish.index('releaseCutObservers()'), finish.index('done(c->id,ok)'))

    def test_cover_must_render_before_load(self):
        run_cpp(self, self.executable, 'render-barrier')


if __name__ == '__main__':
    unittest.main()
