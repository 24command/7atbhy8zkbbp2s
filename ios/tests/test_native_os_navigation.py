"""Chapter-visit return faces: real C++ policy and production hook/observer paths."""
import os
from pathlib import Path
import tempfile
import unittest
from zipfile import ZipFile

from test_native_os_boundary import definition
from test_native_os_transition_support import compile_cpp, run_cpp

SRC = Path(__file__).resolve().parents[1] / 'PhiMod/Sources'
COORD = (SRC / 'PMNativeOSCoordinator.mm').read_text('utf-8-sig')
HOOK = (SRC / 'PMHookBackend.mm').read_text('utf-8-sig')
HEADER = (SRC / 'PMNativeOSNavigation.hpp').as_posix()
PRELUDE = '#include "' + HEADER + '"\n#include <cassert>\n'


class NavigationTests(unittest.TestCase):
    def check_cpp(self, code):
        with tempfile.TemporaryDirectory(prefix='os-navigation-') as directory:
            run_cpp(self, compile_cpp(PRELUDE + code, directory, 'navigation'))

    def test_result_quit_retry_pending_and_cancel(self):
        self.check_cpp(r"""
using pmnativeosnavigation::Visit;
int main(){
 for(bool listFirst : {false,true}) for(bool fromOS : {false,true}) {
  Visit v;
  assert(v.wantsOS("kld",listFirst,false,false)==!listFirst); // fresh authored home
  v.presentedOS("kld");
  if(!fromOS)v.presentedList("kld",true,true,true); // manual OS -> List
  auto check=[&]{assert(v.wantsOS("kld",listFirst,false,false)==fromOS);};
  // A pending Start, cancellation and retry have no scene arrival to consume.
  check(); check();
  // Hidden nextSongs or secret-course selector has no owned visible list.
  v.presentedList("kld",false,true,true);check();
  v.presentedList("kld",true,false,true);check();
  v.presentedList("kld",true,true,false);check();
  for(int retry=0;retry<3;++retry){
   v.chapterReady(12,"Assets/Phigros2/Level/Level.unity",true,false);check();
  }
  // Even a boundary check during result Back / pause Quit cannot consume transient scenes.
  for(bool result : {false,true}){
   if(result)v.chapterReady(13,"Assets/Phigros2/Level/LevelOver.unity",true,false);
   v.chapterReady(4,"Assets/Phigros2/Basic/TurnToScene.unity",true,false);check();
   v.chapterReady(5,"Assets/Phigros2/Loading/Loading.unity",true,false);check();
   v.chapterReady(7,"Assets/Phigros2/SongSelector/SongSelector.unity",true,false);check();
   check(); // querying/preloading the destination never consumes the memory
  }
  // A confirmed user face change replaces the old origin in either direction.
  v.presentedList("kld",true,true,true);assert(!v.wantsOS("kld",false,false,false));
  v.presentedOS("kld");assert(v.wantsOS("kld",true,false,false));
 }
}
""")

    def test_new_chapter_verified_clear_and_checkpoint_precedence(self):
        self.check_cpp(r"""
int main(){
 pmnativeosnavigation::Visit v;
 const char* menu="Assets/Phigros2/ChapterSelector/ChapterSelector.unity";
 v.presentedList("kld",true,true,true);
 assert(!v.wantsOS("kld",false,false,false));
 assert(v.wantsOS("kld",false,false,true)); // routed checkpoint wins
 assert(v.wantsOS("kld",false,true,false)); // OS-only chapter wins
 assert(!v.wantsOS("kld",false,false,false)); // overrides do not consume memory
 assert(v.wantsOS("other",false,false,false));
 assert(!v.wantsOS("other",true,false,false));
 v.chapterReady(6,menu,true,true);assert(!v.wantsOS("kld",false,false,false)); // hidden auto-route
 v.chapterReady(6,menu,false,false);assert(!v.wantsOS("kld",false,false,false));
 v.chapterReady(5,menu,true,false);assert(!v.wantsOS("kld",false,false,false));
 v.chapterReady(6,"Assets/Fake/ChapterSelector.unity",true,false);
 assert(!v.wantsOS("kld",false,false,false));
 v.chapterReady(6,menu,true,false);assert(v.wantsOS("kld",false,false,false));
 v.presentedOS("kld");v.chapterReady(6,menu,true,false);
 assert(!v.wantsOS("kld",true,false,false)); // fresh list-first also restored
 v.presentedList("kld",true,true,true);v.chapter("other");v.chapter("kld");
 assert(v.wantsOS("kld",false,false,false)); // in-selector chapter change clears
 v.presentedList("",true,true,true);v.presentedOS("");
 assert(v.wantsOS("kld",false,false,false));
}
""")

    def test_production_visible_observer_and_both_normal_start_gate_paths(self):
        code = r"""
#include <cstdint>
#include <cstring>
#include <functional>
#include <stdexcept>
using P=void*;
struct Runtime {
 bool loaded=true,locked=false,exit=false,moving=false;
 P klass(const char*){return this;}
 template<class T>T staticValue(P,const char* field,const char*){
  return !strcmp(field,"loadOver") ? loaded : locked;
 }
 template<class T>T get(P,const char* field){return !strcmp(field,"exit") ? exit : moving;}
} runtime,other;
Runtime& R(){return runtime;}
Runtime* game=&runtime;
int owner,hidden;
P selector=&owner;
uint64_t requestedEntry=0,generation=1,visit=2,mapID=3,cutTicket=0;
struct {bool cover=false;} bridge;
bool gated=false,busy=false,mapOK=true,chromeOK=true;
pmnativeosnavigation::Visit navigation;
struct Plan{struct Intro{bool declared=false;} enterScene;} plan;
struct Program{Plan*page=&plan;bool entrySceneSeen=false;explicit operator bool()const{return true;}} program;
struct Clock{bool finished=false,committing=false;int starts=0;void shown(double){++starts;}} enterSceneClock;
double CACurrentMediaTime(){return 100;}
int canceledInterruptions=0;
void PMCancelSongInterruptionLaunch(){++canceledInterruptions;}

template<class F>bool cutChecked(F f){try{f();return true;}catch(...){return false;}}
namespace chrome {enum class Face{Map};bool present(Runtime&,uint64_t,Face,bool,int,bool){return chromeOK;}}
namespace map {bool present(Runtime&,uint64_t,bool,bool,bool){return mapOK;}}
"""
        code += definition(COORD, 'enum class Mode') + ';Mode mode=Mode::list;\n'
        code += definition(COORD, 'bool selectorReady(') + '\n'
        code += definition(COORD, 'bool presentMap(').replace('chapter.UTF8String?:""', '"kld"') + '\n'
        code += 'namespace pmnativecoordinator {\n'
        code += definition(COORD, 'void normalStart(').replace('chapter.UTF8String?:""', '"kld"') + '\n}\n'
        code += r"""
namespace pmstory {void captureLaunch(){}}
bool watchingDoorLaunch=false;
int launches=0,ends=0,gate=0;
bool expectedOS=false;
std::function<void()> resume;
namespace pmunlock {
 bool beforeStart(Runtime&,P,std::function<void()> callback){
  if(gate==3)throw std::runtime_error("gate rejected");
  if(gate==1)resume=callback;
  return gate!=0;
 }
}
namespace pmcontent {
 void selectorLoadingEnd(Runtime&,bool accepted){
  assert(accepted);++ends;
  assert(navigation.wantsOS("kld",false,false,false)==expectedOS);
  selector=nullptr;mode=Mode::idle;
 }
 void difficultyTransitionLabel(Runtime&,P){}
}
void nativeStart(P,P){assert(!selector);++launches;}
using VoidFn=void(*)(P,P);
namespace h {enum {normalStart};}
template<class T>T orig(int){return &nativeStart;}
void diagf(const char*,const char*){}
void reset(){
 navigation={};navigation.presentedOS("kld");
 runtime={};selector=&owner;mode=Mode::list;bridge.cover=false;cutTicket=0;
 requestedEntry=0;generation=1;resume={};gate=0;launches=ends=0;expectedOS=false;
 plan={};program={};enterSceneClock={};canceledInterruptions=0;
}
"""
        code += definition(HOOK, 'void onNormalStart(').replace('^{', '[=]{') + '\n'
        code += r"""
int main(){
 using pmnativecoordinator::normalStart;
 // No staging, hidden selector, stale owner or unsettled frame can record List.
 for(Mode m:{Mode::idle,Mode::loading,Mode::listPending,Mode::listCut,
             Mode::entering,Mode::map,Mode::mapCut,Mode::detail,Mode::returning}){
  reset();mode=m;normalStart(runtime,&owner);
  assert(navigation.wantsOS("kld",false,false,false));
 }
 for(int fence=0;fence<9;++fence){
  reset();
  if(fence==0)bridge.cover=true;if(fence==1)cutTicket=4;
  if(fence==2)requestedEntry=generation;if(fence==3)runtime.loaded=false;
  if(fence==4)runtime.locked=true;if(fence==5)runtime.exit=true;
  if(fence==6)runtime.moving=true;if(fence==7)selector=&hidden;
  normalStart(fence==8?other:runtime,&owner);
  assert(navigation.wantsOS("kld",false,false,false));
 }
 reset();requestedEntry=99;normalStart(runtime,&owner); // stale request isn't pending
 assert(!navigation.wantsOS("kld",false,false,false));
 reset();onNormalStart(&owner,nullptr);assert(launches==1&&ends==1&&canceledInterruptions==1);
 reset();gate=1;onNormalStart(&owner,nullptr);
 assert(resume&&launches==0&&ends==0&&navigation.wantsOS("kld",false,false,false));
 resume();assert(launches==1&&ends==1); // observer runs before async detach
 for(int rejected:{1,2,3}){
  reset();gate=rejected;onNormalStart(&owner,nullptr);resume={}; // cancel deferred intro
  assert(!launches&&!ends&&navigation.wantsOS("kld",false,false,false));
  gate=0;onNormalStart(&owner,nullptr);assert(launches==1&&ends==1); // retry
 }
 reset();selector=&hidden;mode=Mode::idle;expectedOS=true;
 onNormalStart(&owner,nullptr);assert(launches==1); // hidden story launch keeps OS
 // Stale async resume after a chapter visit changes must not write the old List.
 reset();gate=1;onNormalStart(&owner,nullptr);selector=&hidden;mode=Mode::loading;
 navigation.chapter("other");expectedOS=true;resume();
 assert(navigation.wantsOS("kld",false,false,false));
 // Only successful presentation records OS, not a failed mount/preparation.
 reset();normalStart(runtime,&owner);mapOK=false;assert(!presentMap(runtime));
 assert(!navigation.wantsOS("kld",false,false,false));
 mapOK=true;chromeOK=false;assert(!presentMap(runtime));
 assert(!navigation.wantsOS("kld",false,false,false));
 chromeOK=true;assert(presentMap(runtime));assert(navigation.wantsOS("kld",true,false,false));
}
"""
        self.check_cpp(code)

    def test_production_chapter_boundary_after_automatic_routing(self):
        code = r"""
#include <cstring>
#include <initializer_list>
#include <stdexcept>
using P=void*;
struct Runtime {
 int active=17,ownerScene=17,index=6;
 const char* path="Assets/Phigros2/ChapterSelector/ChapterSelector.unity";
 bool fail=false;int queries=0;
 P type(const char*,const char*){return this;}
 P call(P p,const char* method){return !strcmp(method,"get_scene") ? &ownerScene : p;}
 P stat(P,const char* method,std::initializer_list<const char*> = {},std::initializer_list<P> = {}){
  ++queries;if(fail)throw std::runtime_error("scene unavailable");
  if(!strcmp(method,"GetActiveScene"))return &active;
  if(!strcmp(method,"GetBuildIndexInternal"))return &index;
  return const_cast<char*>(path);
 }
 template<class T>T unbox(P p){return *static_cast<T*>(p);}
 const char* string(P p){return static_cast<const char*>(p);}
};
int sceneHandle(Runtime&,P p){return *static_cast<int*>(p);}
template<class F>bool cutChecked(F f){try{f();return true;}catch(...){return false;}}
pmnativeosnavigation::Visit navigation;
struct Plan{struct Intro{bool declared=false;} enterScene;} plan;
struct Program{Plan*page=&plan;bool entrySceneSeen=false;explicit operator bool()const{return true;}} program;
struct Clock{bool finished=false,committing=false;int starts=0;void shown(double){++starts;}} enterSceneClock;
double CACurrentMediaTime(){return 100;}
int canceledInterruptions=0;
void PMCancelSongInterruptionLaunch(){++canceledInterruptions;}

"""
        code += definition(COORD, 'void chapterReady(').replace('NSString *path', 'const char *path').replace('path.UTF8String?:""', 'path')
        code += r"""
int main(){
 Runtime r;
 auto retained=[&]{assert(!navigation.wantsOS("kld",false,false,false));};
 navigation.presentedList("kld",true,true,true);
 chapterReady(r,&r,true);retained();assert(!r.queries); // accepted hidden story/checkpoint route
 chapterReady(r,nullptr,false);retained();
 r.ownerScene=18;chapterReady(r,&r,false);retained(); // stale/additive owner
 r.ownerScene=17;
 for(int index:{4,5,7,12,13}){r.index=index;chapterReady(r,&r,false);retained();}
 r.index=6;r.path="Assets/Fake/ChapterSelector.unity";chapterReady(r,&r,false);retained();
 r.path="Assets/Phigros2/ChapterSelector/ChapterSelector.unity";
 r.fail=true;chapterReady(r,&r,false);retained();
 r.fail=false;chapterReady(r,&r,false);assert(navigation.wantsOS("kld",false,false,false));
 // A rejected automatic story route leaves the real menu: next visit uses home.
 navigation.presentedOS("kld");chapterReady(r,&r,true);
 assert(navigation.wantsOS("kld",true,false,false));
 chapterReady(r,&r,false);assert(!navigation.wantsOS("kld",true,false,false));
}
"""
        self.check_cpp(code)

    def test_wiring_keeps_hidden_launches_and_transient_scenes_out(self):
        frame = definition(COORD, 'void selectorFrame(')
        self.assertIn('normalStart(r,owner)', frame)
        self.assertIn('navigation.chapter(key.UTF8String', definition(COORD, 'void ready('))
        policy = definition(COORD, 'bool wantsOSHome(')
        self.assertIn('navigation.wantsOS(', policy)
        self.assertIn('PMChapterOSHasRoutedCheckpoint(key)', policy)
        for method in ('void detach(', 'void sceneUnloaded(', 'void clearScene(', 'void returned('):
            self.assertNotIn('navigation.', definition(COORD, method))
        scene = definition(COORD, 'void chapterReady(')
        for required in ('automaticallyRouted || !owner', 'GetBuildIndexInternal', 'GetPathInternal',
                         'GetActiveScene', 'handle!=active'):
            self.assertIn(required, scene)
        hook = definition(HOOK, 'void onChapterStart(')
        self.assertLess(hook.index('PMChapterOSResumeAfterBoot'), hook.index('pmnativecoordinator::chapterReady'))
        self.assertIn('*routedResult=[pmcontent::command', hook)
        self.assertIn('bool *const routedResult=&chapterAutoRouted', hook)
        self.assertNotIn('__block', hook)
        self.assertIn('chapterReady(R(),self,chapterAutoRouted)', hook)
        self.assertNotIn('navigation.', definition(HOOK, 'void onOSSceneLoaded('))
        content = (SRC / 'PMContentRuntime.mm').read_text('utf-8-sig')
        begin = definition(content, 'static void beginChapterOS(')
        self.assertLess(begin.index('PMStorySequenceSelectorReady'), begin.index('pmnativecoordinator::ready'))
        self.assertIn('return;', begin.split('if(PMStorySequenceSelectorReady', 1)[1].split('pmnativecoordinator::ready', 1)[0])
        play = definition(COORD, 'bool playSelection(Runtime &r,NSDictionary *card,NSDictionary *choice){')
        self.assertNotIn('navigation.', play)  # cancelled/failed Start is not a face transition
        self.assertLess(play.index('if(card[@"secretCourse"])'), play.index('scene::playStartSound(r)'))
        self.assertIn('if(shown)navigation.presentedOS', definition(COORD, 'bool presentMap('))

    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'requires retail 4.0.4 IPA')
    def test_clear_boundary_matches_actual_build_settings(self):
        from test_native_os_scene import donors, settings
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa:
            scenes, _ = donors.scene_paths(settings(donors.SerializedFile(
                ipa.read('Payload/Phigros.app/Data/globalgamemanagers'))))
        self.assertEqual(scenes[6], 'Assets/Phigros2/ChapterSelector/ChapterSelector.unity')
        for index, path in ((4, 'Basic/TurnToScene'), (5, 'Loading/Loading'),
                            (7, 'SongSelector/SongSelector'), (12, 'Level/Level'), (13, 'Level/LevelOver')):
            self.assertEqual(scenes[index], 'Assets/Phigros2/' + path + '.unity')


if __name__ == '__main__':
    unittest.main()
