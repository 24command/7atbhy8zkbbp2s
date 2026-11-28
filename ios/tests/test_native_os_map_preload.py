"""Entry-target resource scheduling; compile exact production functions with a Unity recorder."""
from pathlib import Path
import os
import re
import tempfile
import unittest
from test_native_os_transition_support import compile_cpp, run_cpp
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'PhiMod/Sources'
MAP = (SRC/'PMNativeOSMap.mm').read_text(encoding='utf8')
PRELOAD = (SRC/'PMNativeOSMapPreload.inc').read_text(encoding='utf8')
MEDIA = (SRC/'PMNativeOSMapMedia.inc').read_text(encoding='utf8')
COORD = (SRC/'PMNativeOSCoordinator.mm').read_text(encoding='utf8')

def function(text, signature):
    start = text.index(signature)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

class TargetPreload(unittest.TestCase):
    def test_production_scheduler_and_cancellation(self):
        code = '#include "' + (SRC/'PMNativeOSMap.hpp').as_posix() + '"\n' + r'''
#include <cassert>
#include <map>
#include <set>
#include <memory>
#include <string>
using namespace pmnativeosmap;
using Handle = unsigned;
struct Path { const char *UTF8String=nullptr; explicit operator bool() const {return UTF8String;} };
struct Media { bool preloaded=false,failed=false; readiness::FirstFrame first; int steps=0,stops=0; };
struct Item {
    unsigned object=1; int screen=1,parent=-1; bool manual=true;
    double start=0,duration=0,fade=0;
    Path artPath; std::shared_ptr<Media> media;
};
struct Payload { bool complete=false; };
struct Stage {
    preload::Plan plan; std::map<std::string,int> art; std::vector<Handle> assets;
    std::set<std::string> failed; std::shared_ptr<Payload> pending; int pendingNode=-1;
};
struct Map {
    Stage preload; std::vector<Item> items; int page=0;
    int requests=0,uploads=0,steps=0,releases=0;
    bool visible=true,running=true,input=false;
};
void stopMedia(Map &,Media &m) {m.preloaded=false; m.first.reset(); ++m.stops;}
void releaseAsset(Map &m,Handle) {++m.releases;}
void warmMedia(Map &m,Media &media,bool) {++m.steps;++media.steps;media.first.begin(false);}
void requestStill(Map &m,int node) {
    ++m.requests;m.preload.pendingNode=node;m.preload.pending=std::make_shared<Payload>();
}
void uploadStill(Map &m) {
    assert(m.preload.pending->complete);++m.uploads;
    m.preload.art[m.items[m.preload.pendingNode].artPath.UTF8String]=1;
    m.preload.pending.reset();m.preload.pendingNode=-1;
}
'''
        code += '\n'.join(function(PRELOAD, s) for s in
                          ('void cancelPreload(', 'void beginPreload(', 'void stepPreload('))
        code += r'''
int main() {
    Map m; m.items.resize(7);
    m.items[0].screen=0; m.items[0].artPath={"intro"};
    m.items[1].artPath={"still"};m.items[2].artPath={"still"}; // deduplicate
    m.items[3].media=std::make_shared<Media>();
    m.items[4].manual=false;m.items[4].artPath={"hidden"};
    m.items[5].parent=4;m.items[5].artPath={"hidden child"};
    m.items[6].start=1;m.items[6].artPath={"future"};
    stepPreload(m,1);
    assert((m.preload.plan.nodes==std::vector<int>{1,2,3}));
    assert(m.requests==1 && m.steps==0 && m.page==0 && m.visible && m.running && !m.input);
    std::weak_ptr<Payload> old=m.preload.pending;
    stepPreload(m,1); // pending still does not starve video/sequence
    assert(m.requests==1 && m.steps==1 && m.items[3].media->preloaded);
    m.preload.pending->complete=true;
    stepPreload(m,1);
    assert(m.uploads==1 && m.steps==1 && old.expired()); // only one expensive operation
    stepPreload(m,1);
    assert(m.requests==1 && m.steps==2); // duplicate still reused
    m.items[3].media->first.poll(false,true,false);
    for(int i=0;i<20;++i)stepPreload(m,1);
    assert(m.steps==2 && m.requests==1 && m.items[3].media->first.held());
    m.preload.assets={4,5};
    cancelPreload(m,1); // matching handoff retains first frame
    assert(m.releases==2 && m.items[3].media->stops==0 && m.items[3].media->preloaded);
    cancelPreload(m); // cancellation releases it exactly once
    assert(m.items[3].media->stops==1 && !m.items[3].media->preloaded);
    stepPreload(m,1);old=m.preload.pending;
    stepPreload(m,2); // replacement invalidates outstanding CPU delivery
    assert(old.expired() && m.preload.plan.matches(0,2));
    assert(m.preload.plan.nodes.empty() && m.page==0 && !m.input);
    m.page=2;stepPreload(m,1); // new source cannot reuse the old ownership
    assert(m.preload.plan.matches(2,1));
    cancelPreload(m);
    assert(!m.preload.pending && m.preload.plan.target==-1);
}
'''
        with tempfile.TemporaryDirectory(prefix='target-scheduler-') as out:
            run_cpp(self, compile_cpp(code, out, 'scheduler'))

    def test_visibility_and_media_handoff(self):
        code=(ROOT/'tests/PMNativeOSMapPreloadTest.cpp').read_text(encoding='utf8')
        code=code.replace('../PhiMod/Sources/PMNativeOSMap.hpp',(SRC/'PMNativeOSMap.hpp').as_posix())
        with tempfile.TemporaryDirectory(prefix='target-handoff-') as out:
            run_cpp(self,compile_cpp(code,out,'handoff'))

    def test_production_upload_rollback(self):
        code = r'''
#include <cassert>
#include <algorithm>
#include <map>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>
using Handle=unsigned;
struct Path {const char *UTF8String="still";};
struct Item {Path artPath;bool artReadable=false;};
struct Art {Handle sprite=0,silhouette=0;float aspect=1;};
struct Payload {int image=1,silhouette=1;float aspect=2;};
struct Stage {
    int pendingNode=0;std::shared_ptr<Payload> pending=std::make_shared<Payload>();
    std::map<std::string,Art> art;std::vector<Handle> assets;std::set<std::string> failed;
};
struct Map {
    std::vector<Item> items{Item{}};Stage preload;
    std::vector<Handle> assets{99};int upload=0,failAt=0,releases=0;
};
template<class F>bool checked(F work) {try{work();return true;}catch(...){return false;}}
Handle uploadSprite(Map &m,int,bool) {
    Handle h=++m.upload;m.assets.push_back(h);
    if(m.upload==m.failAt)throw std::runtime_error("injected Unity upload failure");
    return h;
}
void releaseAsset(Map &m,Handle h) {
    auto it=std::find(m.assets.begin(),m.assets.end(),h);assert(it!=m.assets.end());
    m.assets.erase(it);++m.releases;
}
''' + function(PRELOAD,'void uploadStill(') + r'''
int main() {
    for(int fail=0;fail<=2;++fail) {
        Map m;m.failAt=fail;uploadStill(m);
        assert(!m.preload.pending && m.preload.pendingNode==-1);
        if(fail) {
            assert((m.assets==std::vector<Handle>{99})); // intro resource untouched
            assert(m.preload.assets.empty() && m.preload.art.empty());
            assert(m.preload.failed.count("still") && m.releases==fail);
        } else {
            assert((m.preload.assets==std::vector<Handle>{1,2}));
            assert(m.preload.art.at("still").aspect==2 && !m.releases);
        }
    }
    Map badDecode;badDecode.preload.pending->image=0;uploadStill(badDecode);
    assert(!badDecode.upload && badDecode.preload.failed.count("still"));
}
'''
        with tempfile.TemporaryDirectory(prefix='target-upload-') as out:
            run_cpp(self,compile_cpp(code,out,'upload'))

    def test_read_only_playback_state(self):
        code = r'''
#include <cassert>
#include <chrono>
#include <memory>
#include <cstdint>
using Visit=uint64_t;
using Clock=std::chrono::steady_clock;
struct Runtime {};
struct Map {
    int page=2; bool visible=true,running=true,input=false,foregroundPaused=false;
    double elapsed=2; Clock::time_point resumed=Clock::now()-std::chrono::seconds(5);
''' + function(MAP,'double time() const') + r'''
};
std::unique_ptr<Map> current;
Runtime *owner=nullptr; bool mainThread=true;
bool matches(Runtime &r,Visit id) {return mainThread && current && &r==owner && id==17;}
''' + function(MAP,'bool playbackState(') + r'''
int main() {
    Runtime r,other;owner=&r;current=std::make_unique<Map>();
    int screen=99; double time=99; bool running=true;
    assert(playbackState(r,17,screen,time,running));
    assert(screen==2 && time>=7 && time<8 && running);
    assert(current->page==2 && current->elapsed==2 && !current->input);
    current->elapsed=9;current->foregroundPaused=true;
    assert(playbackState(r,17,screen,time,running) && time==9 && !running);
    current->resumed=Clock::now()-std::chrono::hours(1);
    assert(playbackState(r,17,screen,time,running) && time==9 && !running);
    current->resumed=Clock::now();current->foregroundPaused=false;
    assert(playbackState(r,17,screen,time,running) && time>=9 && time<10 && running);
    current->elapsed=9;current->running=false;
    assert(playbackState(r,17,screen,time,running) && screen==2 && time==9 && !running);
    current->visible=false;
    assert(playbackState(r,17,screen,time,running) && time==9 && !running);
    for(int invalid=0;invalid<3;++invalid) {
        screen=99;time=99;running=true;
        if(invalid==2)mainThread=false;
        assert(!playbackState(invalid==0?other:r,invalid==1?18:17,screen,time,running));
        assert(screen==-1 && time==0 && !running);
    }
    mainThread=true;current.reset();
    assert(!playbackState(r,17,screen,time,running));
}
'''
        query=function(MAP,'bool playbackState(')
        for forbidden in ('refresh(', 'preloadPage(', 'r.call(', 'm.page =', 'm.elapsed ='):
            self.assertNotIn(forbidden,query)
        with tempfile.TemporaryDirectory(prefix='target-playback-state-') as out:
            run_cpp(self,compile_cpp(code,out,'playback'))

    def test_no_page_activation_or_authored_work(self):
        for text in (PRELOAD,function(MAP,'bool preloadPage(')):
            for banned in ('"SetActive"','displayPage(', 'refresh(', 'dispatchNode(',
                           'puzzleInput(', 'm.page =', 'm.running =', 'm.input =', 'm.elapsed ='):
                self.assertNotIn(banned,text)
        api=function(MAP,'bool preloadPage(')
        for guard in ('matches(r,id)','screen == current->page','layout::canDisplay(',
                      '!m.visible || !m.running || m.input','UIApplicationStateActive'):
            self.assertIn(guard,api)
        entry=function(COORD,'void tickEntryScene(')
        self.assertLess(entry.index('map::preloadPage('),entry.index('enterSceneClock.claim('))
        self.assertLess(entry.index('markEntrySceneSeen:'),entry.index('map::displayPage('))
        self.assertEqual(COORD.count('map::preloadPage('),1)
        self.assertIn('enterSceneClock.running && !enterSceneClock.committing',entry)

    def test_adoption_and_worker_ownership(self):
        switch=function(MAP,'bool displayPage(')
        self.assertIn('m.preload.plan.matches(m.page,screen)',switch)
        self.assertLess(switch.index('releasePageArt(m)'),switch.index('m.pageArt.swap'))
        self.assertLess(switch.index('m.pageAssets.swap'),switch.index('cancelPreload(m,adopt ? screen : -1)'))
        self.assertLess(switch.index('cancelPreload(m,adopt ? screen : -1)'),switch.index('m.page = screen'))
        self.assertIn('adopt && item.screen == screen && item.media->preloaded',switch)
        worker=function(PRELOAD,'void requestStill(')
        body=worker.split('dispatch_async(stillDecodeQueue()',1)[1]
        for banned in ('m.', 'Runtime', 'uploadSprite(', 'SetActive'):
            self.assertNotIn(banned,body)
        self.assertIn('std::weak_ptr<StillDelivery>',worker)
        self.assertIn('ticket.lock()',body)
        self.assertIn('m.preload.pending.reset()',function(MAP,'void dispose('))
        self.assertIn('if (!visible) cancelPreload(m)',function(MAP,'bool present('))
        self.assertIn('cancelPreload(*current)',function(MAP,'Visit open('))
        self.assertIn('while (m.assets.size()>first) releaseAsset',function(PRELOAD,'void uploadStill('))

    def test_video_has_separate_silent_resource_host(self):
        build=function(MEDIA,'std::shared_ptr<Media> buildMedia(')
        self.assertIn('resourceParent ? resourceParent : tr',build)
        self.assertIn('"set_audioOutputMode",{"UnityEngine.Video.VideoAudioOutputMode"},{&silent}',build)
        self.assertIn('silent = 0',build)
        self.assertIn('"set_playOnAwake",false',build)
        self.assertIn('m.get(m.rootRect)',function(MAP,'void build('))
        self.assertIn('"SetActive",false',function(MEDIA,'void stopMedia('))

    @unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'),'requires local dump.cs')
    def test_dump_lifecycle_boundaries(self):
        dump=(Path(os.environ['PHIGROS_404_ANALYSIS'])/'dump.cs').read_text(encoding='utf-8-sig')
        chapter=re.search(r'public class Chapter8SelectMusicControl : MonoBehaviour.*?^}',dump,re.M|re.S)[0]
        for signature in ('private void Start()', 'private void Update()', 'private void OnDisable()',
                          'private IEnumerator StartAnimation()', 'public void OpenSongDetail(int index)'):
            self.assertIn(signature,chapter)
        # Metadata establishes distinct lifecycle entrypoints, not their bodies.
        video=re.search(r'public .*class VideoPlayer : Behaviour.*?^}',dump,re.M|re.S)[0]
        for signature in ('void Prepare()', 'void Pause()', 'void Stop()', 'bool get_isPrepared()'):
            self.assertIn(signature,video)

if __name__=='__main__':unittest.main()
