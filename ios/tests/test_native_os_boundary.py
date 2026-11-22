"""Exercise the native OS boundary with a fake Unity runtime and scene clock."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SRC = Path(__file__).resolve().parents[1] / 'PhiMod/Sources'
COORD = (SRC / 'PMNativeOSCoordinator.mm').read_text(encoding='utf-8-sig')
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
uint64_t generation=3,visit=0;
bool returnBack=false;
namespace toggle {
    bool owns(Runtime&,P b){return b==&ownedButton;}
    void release(Runtime&){++releases;}
}
void clearScene(Runtime&){++closes;}
template<class F>void guardInput(F f){try{f();}catch(const std::exception&){}}
'''
        code += definition(COORD, 'enum class Mode') + '; Mode mode=Mode::idle;\n'
        code += 'void dispatchOwned(Runtime&,P){++actions;mode=Mode::idle;}\n'
        for method in ('void discardHandoff(', 'void returned(', 'bool transitioning(', 'void detach(',
                       'void sceneUnloaded(', 'bool claims(', 'bool dispatch(', 'bool press(', 'bool pointerClick('):
            code += definition(COORD, method) + '\n'
        code += r'''
int main(){
    Runtime &r=runtime; P button=&ownedButton,event=&runtime;
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
