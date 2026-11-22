"""Exercise the native OS boundary with a fake Unity runtime and scene clock."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[1] / 'PhiMod/Sources'
COORD = (SRC / 'PMNativeOSCoordinator.mm').read_text(encoding='utf-8-sig')
CUT = (SRC / 'PMNativeOSManualTransition.inc').read_text(encoding='utf-8-sig')
HOOK = (SRC / 'PMHookBackend.mm').read_text(encoding='utf-8-sig')


def definition(text, signature):
    start = text.index(signature)
    depth = 0
    for pos in range(text.index('{', start), len(text)):
        depth += (text[pos] == '{') - (text[pos] == '}')
        if not depth:
            return text[start:pos + 1]
    raise AssertionError(signature)


class BoundaryTests(unittest.TestCase):
    def test_hook_precedence(self):
        for name, call in [('onPointerClick', 'pointerClick(R(),self,event)'),
                           ('onSubmit', 'press(R(),self)'), ('onPress', 'press(R(),self)')]:
            body = definition(HOOK, 'void ' + name + '(').split('{', 1)[1].lstrip()
            self.assertTrue(body.startswith('if(pmnativecoordinator::' + call + ')return;'))
            self.assertEqual(body.count('pmnativecoordinator::'), 1)
        unload = definition(HOOK, 'void onOSSceneUnloaded(')
        self.assertLess(unload.index('os::sceneUnloaded'), unload.index('pmnativecoordinator::sceneUnloaded'))
        self.assertLess(unload.index('if (!owned)'), unload.index('orig<'))

    def test_return_claim_and_graph_cleanup(self):
        ready = definition(COORD, 'void ready(')
        for check in ('[chapter isEqual:key]', 'revision==PMContentStore.shared.revision',
                      'handoffScene==sceneHandle(', 'epoch!=generation', 'selector!=owner'):
            self.assertIn(check, ready)
        self.assertLess(ready.index('discardHandoff()'), ready.index('startSelection('))
        clear = definition(COORD, 'void clearScene(')
        for operation in ('stopClock()', '[actions invalidate]', 'panel::close(', 'map::close(',
                          'chrome::close(', 'rows::release()'):
            self.assertIn(operation, clear)

    def test_dispatch_and_scene_lifetime(self):
        # Compile the production entry points with simulated Unity calls. No Apple SDK required.
        cxx = os.getenv('CXX') or shutil.which('clang++') or shutil.which('g++')
        if not cxx:
            self.skipTest('requires C++17 compiler')
        command = [cxx] + (['c++'] if Path(cxx).stem == 'zig' else [])
        code = r'''
#include <cassert>
#include <cstdint>
#include <initializer_list>
#include <stdexcept>
using P=void*;
#define nil nullptr
struct Runtime {
    int activeScene=17, queries=0, mouse=0;
    bool loadOver=false,lockTouch=false,exit=false,moving=false;
    bool alive(P p){return p!=nullptr;}
    P gchandle_get_target(uint32_t handle){return handle ? this : nullptr;}
    void gchandle_free(uint32_t) {++freed;}
    int freed=0;
    P klass(const char*) {return this;}
    template<class T>T staticValue(P,const char *name,const char*){return name[1]=='o' && name[2]=='a' ? loadOver : lockTouch;}
    template<class T>T get(P,const char *name){return name[0]=='e' ? exit : moving;}
    P type(const char*,const char*) {return this;}
    P stat(P,const char*) {return &activeScene;}
    P call(P,const char*) {++queries; if(mouse<0)throw std::runtime_error("event expired");return &mouse;}
    int enumValue(P v,const char*) {return *static_cast<int*>(v);}
} runtime, other;
int sceneHandle(Runtime&,P value){return *static_cast<int*>(value);}
void PMDiagnosticsWrite(const char*){}
Runtime *game=&runtime;
int handoffScene=0, actions=0, closes=0, releases=0, ownedButton, retailButton;
P selector=nullptr, program=nullptr, chapter=nullptr, pendingStart=nullptr;
uint64_t generation=3,visit=0,requestedEntry=0;
int entries=0;

bool returnBack=false;
namespace toggle {
    bool owns(Runtime&,P b){return b==&ownedButton;}
    void release(Runtime&){++releases;}
}
void sceneUnloaded(Runtime&,int,bool);
void clearScene(Runtime& r,uint64_t closingVisit){
    assert(visit==0 && closingVisit==33);++closes;
    sceneUnloaded(r,9,true);  // synchronous callback during cleanup
}
template<class F>void guardInput(F f){try{f();}catch(const std::exception&){}}
'''
        code += definition(COORD, 'enum class Mode') + '; Mode mode=Mode::idle;\n'
        code += r'''
bool refuse=false, gated=false;
int revision=1, leaves=0, restores=0, destroys=0;
struct {struct {int revision=1;} shared;} PMContentStore;
double now=0;
double cutTime(Runtime&) {return now;}
int activeCutScene(Runtime&r){return r.activeScene;}
void enter(Runtime&){++entries;if(mode==Mode::listCut && !refuse)mode=Mode::entering;}
namespace scene { P activeRoot(Runtime &r){return &r;} }
bool leave(Runtime&,bool,P){++leaves;if(refuse)return false;mode=Mode::returning;return true;}
bool presentMap(Runtime&){++restores;mode=Mode::map;return true;}
void destroyCut(Runtime&,P){++destroys;}
template<class F>void cutChecked(F f){f();}
'''
        code += 'void dispatchOwned(Runtime&,P){++actions;mode=Mode::idle;}\n'
        for method in ('bool selectorReady(', 'void selectorFrame(', 'void discardHandoff(', 'void returned(', 'bool transitioning(', 'void detach(',
                       'void sceneUnloaded(', 'bool claims(', 'bool dispatch(', 'bool press(', 'bool pointerClick('):
            code += definition(COORD, method) + '\n'
        for method in ('struct ManualCut', 'enum class CutStep', 'CutStep advanceCut(', 'void finishCut('):
            code += definition(CUT, method) + ';\n'
        code += r'''
int main(){
    Runtime &r=runtime; P button=&ownedButton,event=&runtime;
    mode=Mode::list;selector=button;requestedEntry=generation;
    selectorFrame(r,button);assert(!entries && requestedEntry);
    r.lockTouch=true;r.loadOver=true;selectorFrame(r,button);assert(!entries);
    r.lockTouch=false;r.moving=true;selectorFrame(r,button);assert(!entries);
    r.moving=false;selectorFrame(r,event);assert(!entries);
    selectorFrame(r,button);selectorFrame(r,button);assert(entries==1 && !requestedEntry);
    for(auto passive:{Mode::idle,Mode::loading}){
        mode=passive; assert(!pointerClick(r,button,event));assert(!press(r,button));
    }
    mode=Mode::list;assert(!pointerClick(r,&retailButton,event));assert(r.queries==0);
    for(auto owned:{Mode::list,Mode::entering,Mode::map,Mode::detail,Mode::returning}){
        mode=owned; P b=owned==Mode::list?button:&retailButton;
        int before=actions;
        for(int ignored:{1,2,-1}){r.mouse=ignored;assert(pointerClick(r,b,event));}
        assert(pointerClick(r,b,nullptr));assert(actions==before);
        r.mouse=0; assert(pointerClick(r,b,event));assert(actions==before+1);
        mode=owned;int queries=r.queries;assert(press(r,b));assert(actions==before+2 && r.queries==queries);
    }
    mode=Mode::detail;visit=33;sceneUnloaded(other,9,true);sceneUnloaded(r,9,false);
    assert(visit==33 && closes==0);sceneUnloaded(r,9,true);sceneUnloaded(r,9,true);
    assert(closes==1 && releases==1 && generation==4 && !visit && !claims(r,button));
    mode=Mode::returning;visit=34;pendingStart=button;returnBack=true;
    sceneUnloaded(r,9,true);assert(visit==34 && closes==1 && transitioning());
    returned(r,33,true);assert(visit==34 && transitioning());
    returned(r,34,true);assert(!visit && !claims(r,button) && handoffScene==17);
    detach(r);sceneUnloaded(r,98,false);assert(handoffScene==17 && pendingStart==button);
    sceneUnloaded(r,17,false);assert(!handoffScene && !pendingStart && !returnBack);
    mode=Mode::returning;visit=35;pendingStart=button;returned(r,35,false);
    assert(!claims(r,button) && !pendingStart && !handoffScene);
    // Both manual directions claim retail input, wait through equality, and
    // release the pin without removing an accepted load's outgoing visual.
    selector=button;
    for(auto dir:{Mode::listCut,Mode::mapCut}){
        mode=dir;assert(transitioning() && claims(r,&retailButton));
        ManualCut cut{dir,generation,visit,r.activeScene,1,1.67};
        now=cut.deadline;assert(advanceCut(r,cut)==CutStep::waiting);
        now+=0.016; assert(advanceCut(r,cut)==CutStep::accepted);
        assert(advanceCut(r,cut)==CutStep::cancelled);
        int priorDestroys=destroys;finishCut(r,cut,true);assert(destroys==priorDestroys);
        mode=dir;refuse=true;assert(advanceCut(r,cut)==CutStep::cancelled);
        finishCut(r,cut,false);refuse=false;
        assert(mode==(dir==Mode::mapCut?Mode::map:Mode::list));
    }
    assert(destroys==2 && restores==1 && leaves==2 && r.freed==4);
    mode=Mode::listCut;ManualCut cut{mode,generation,visit,r.activeScene,1,now-1};
    int before=entries;r.lockTouch=true;assert(advanceCut(r,cut)==CutStep::cancelled);
    r.lockTouch=false;++revision;assert(advanceCut(r,cut)==CutStep::cancelled);--revision;
    ++r.activeScene;assert(advanceCut(r,cut)==CutStep::cancelled && mode==Mode::idle);
    mode=Mode::listCut;assert(advanceCut(r,cut)==CutStep::cancelled && entries==before);
    mode=Mode::mapCut;cut={mode,generation,visit,r.activeScene,1,0};gated=true;
    assert(advanceCut(r,cut)==CutStep::cancelled);gated=false;++visit;
    assert(advanceCut(r,cut)==CutStep::cancelled && leaves==2);
    finishCut(r,cut,false);assert(restores==1); // obsolete callback cannot revive a new visit
    mode=Mode::listPending;assert(!transitioning() && claims(r,&retailButton));
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / 'boundary.cpp'
            exe = src.with_suffix('.exe')
            src.write_text(code, encoding='utf-8')
            subprocess.run(command + ['-std=c++17', str(src), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    unittest.main()
