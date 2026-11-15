"""Source contracts plus the real C++ placement/update bodies with a fake bridge.

No Unity/device profiling: counters measure native loop work only. A C++17
compiler is optional (CXX executable, or clang++/g++/cl on PATH).
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / "PhiMod/Sources"
PACK = (ROOT / "PMPackEffects.inc").read_text(encoding="utf-8")
FEATURES = (ROOT / "PMRuntimeFeatures.mm").read_text(encoding="utf-8")
TAIL = """ auto first=packEffects.end();
 while(first!=packEffects.begin()&&!(first-1)->initialized)--first;
 for(auto it=first;it!=packEffects.end();++it){auto&e=*it;"""
LINEAR = " for(auto&e:packEffects){"

HARNESS = r"""
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <initializer_list>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
using P=void*;
struct V3 {float x,y,z;};
struct Rect {float x,y,w,h;};
struct Object {
 int id; bool alive=true,enabled=false;
 V3 position{0,0,0},scale{1,1,1}; Rect rect{0,0,100,100};
 float ppu=100; P sprite=nullptr;
};
struct Runtime {
 float time=10; int calls=0,fail=-1; uint32_t next=1;
 std::vector<std::unique_ptr<Object>> objects;
 std::map<uint32_t,P> handles; std::vector<std::string> events;
 P make(){auto p=std::make_unique<Object>();p->id=int(objects.size()+1);P out=p.get();objects.push_back(std::move(p));return out;}
 int id(P p){return p?static_cast<Object*>(p)->id:0;}
 void event(const std::string& s){events.push_back(s);if(calls++==fail)throw std::runtime_error("injected");}
 uint32_t root(P p){handles[next]=p;return next++;}
 P type(const char*,const char*){return nullptr;}
 template<class T>T unbox(P p){return *static_cast<T*>(p);}
 bool alive(P p){event("alive:"+std::to_string(id(p)));return p&&static_cast<Object*>(p)->alive;}
 void gchandle_free(uint32_t h){event("free:"+std::to_string(h));handles.erase(h);}
 P stat(P,const char* name,std::initializer_list<const char*> = {},std::initializer_list<P> args = {}){
  std::string s=name;
  if(s=="get_time"){event(s);return &time;}
  if(s=="Destroy"){P p=*args.begin();event(s+":"+std::to_string(id(p)));static_cast<Object*>(p)->alive=false;return nullptr;}
  throw std::runtime_error("unexpected stat");
 }
 P call(P p,const char* name,std::initializer_list<const char*> = {},std::initializer_list<P> args = {}){
  auto& o=*static_cast<Object*>(p);std::string s=name;event(s+":"+std::to_string(o.id));
  if(s=="get_position")return &o.position;
  if(s=="get_lossyScale")return &o.scale;
  if(s=="get_sprite")return o.sprite;
  if(s=="get_rect")return &o.rect;
  if(s=="get_pixelsPerUnit")return &o.ppu;
  if(s=="get_transform")return p;
  if(s=="set_position")o.position=*static_cast<V3*>(*args.begin());
  else if(s=="set_localScale")o.scale=*static_cast<V3*>(*args.begin());
  else if(s=="set_sprite")o.sprite=*args.begin();
  else if(s=="set_enabled")o.enabled=*static_cast<bool*>(*args.begin());
  else throw std::runtime_error("unexpected call");
  return nullptr;
 }
};
P target(Runtime& r,uint32_t h){auto it=r.handles.find(h);return it==r.handles.end()?nullptr:it->second;}
void logf(const char*,...){}
int visits=0,boundaryChecks=0;
__STATE__
__FINISH__
__LINEAR_FINISH__
__UPDATE__
__LINEAR_UPDATE__
void require(bool ok,const char* what){if(!ok)throw std::runtime_error(what);}
void reset(Runtime& r){
 packEffects.clear();packEffectsPending=false;packEffectPlacementLogged=false;
 packFrames={r.make(),r.make()};packFxDuration=.5f;packFxScale=1.25f;
 visits=boundaryChecks=0;
}
void append(Runtime& r,bool alive=true,bool reference=true){
 P go=r.make(),source=r.make(),sprite=r.make();auto& o=*static_cast<Object*>(source);
 o.position={float(o.id),2,3};o.scale={2,3,1};o.sprite=sprite;o.alive=alive;
 static_cast<Object*>(sprite)->rect.w=200;
 packEffects.push_back({r.root(go),r.root(source),go,0,-1,false,go,source,reference?source:nullptr});
 packEffectsPending=true;
}
void snapshot(Runtime& r){
 std::ostringstream out;out<<"state:"<<packEffectsPending<<":"<<packEffectPlacementLogged<<":"<<r.handles.size();
 for(auto& e:packEffects)out<<"/"<<e.go<<","<<e.source<<","<<e.frame<<","<<e.start<<","<<e.initialized<<","<<r.id(e.sourceTransform)<<","<<r.id(e.referenceRenderer);
 for(auto& p:r.objects)out<<"|"<<p->id<<","<<p->alive<<","<<p->enabled<<","<<r.id(p->sprite)<<","<<p->position.x<<","<<p->position.y<<","<<p->position.z<<","<<p->scale.x<<","<<p->scale.y<<","<<p->scale.z;
 r.events.push_back(out.str());
}
using Step=void(*)(Runtime&);
std::vector<std::string> scenario(Step finish,Step update,int fault){
 Runtime r;reset(r);finish(r);append(r);append(r);finish(r);snapshot(r);
 r.time+=.1f;update(r);snapshot(r);
 append(r);append(r,false);append(r,true,false);
 // Native placement changes after enqueue and before the post-move flush.
 static_cast<Object*>(packEffects.back().sourceTransform)->position.x=777;
 r.fail=fault<0?-1:r.calls+fault;
 try{finish(r);}catch(const std::runtime_error&){r.events.push_back("caught");}
 snapshot(r);r.fail=-1;finish(r);snapshot(r);
 // More hits at the SAME Unity time must still publish at this boundary.
 append(r);finish(r);snapshot(r);
 static_cast<Object*>(target(r,packEffects.front().go))->alive=false;
 r.time+=.1f;update(r);snapshot(r);
 r.time+=1;update(r);snapshot(r);require(packEffects.empty(),"expiry");
 append(r);update(r);snapshot(r); // Tick's fallback placement remains intact.
 return r.events;
}
int dense(Step finish){
 Runtime r;reset(r);for(int i=0;i<63;++i)append(r);finish(r);
 visits=boundaryChecks=0;append(r);finish(r);
 require(packEffects.back().initialized,"dense last effect not published");
 require(!packEffectsPending,"pending flag not cleared");return visits;
}
int main(){
 try{
  int injected=0;
  for(int fault=-1;fault<90;++fault){
   auto actual=scenario(finishPackEffects,updatePackEffects,fault);
   require(actual==scenario(finishPackEffectsLinear,updatePackEffectsLinear,fault),"placement/update trace differs");
   if(std::find(actual.begin(),actual.end(),"caught")!=actual.end())++injected;
  }
  require(injected>0,"fault injection did not execute");
  // Every possible initialized-prefix/pending-suffix shape up to the real cap.
  for(int total=0;total<=64;++total)for(int prefix=0;prefix<=total;++prefix){
   Runtime r;reset(r);for(int i=0;i<prefix;++i)append(r);finishPackEffects(r);
   for(int i=prefix;i<total;++i)append(r);
   packEffectsPending=true;visits=boundaryChecks=0;finishPackEffects(r);
   require(visits==total-prefix,"published prefix revisited");
   require(!packEffectsPending,"empty pending suffix not cleared");
   for(auto& e:packEffects)require(e.initialized,"pending suffix incomplete");
  }
  int oldVisits=dense(finishPackEffectsLinear),newVisits=dense(finishPackEffects);
  require(oldVisits==64&&newVisits==1&&boundaryChecks==2,"dense loop counts");
  std::cout<<"mock bridge traces: 91 comparisons ("<<injected<<" injected failures); suffix shapes: 2145; dense loop visits: "<<oldVisits<<" -> "<<newVisits<<" + "<<boundaryChecks<<" boundary checks\n";
 }catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}
}
"""


class DenseEffectsRegression(unittest.TestCase):
    def test_pending_suffix_producers_and_retry_invariant(self):
        self.assertEqual(FEATURES.count("packEffects.push_back("), 1)
        self.assertIn("packEffects.push_back({handle,sourceRoot,renderer,0,-1,false,", FEATURES)
        self.assertIn("referenceRenderer});packEffectsPending=true;", FEATURES)
        self.assertNotIn(".initialized=false", PACK + FEATURES)
        for mutation in ("packEffects.insert(", "packEffects.emplace(", "packEffects.emplace_back(",
                         "packEffects.assign(", "packEffects.resize("):
            self.assertNotIn(mutation, PACK + FEATURES)
        self.assertIn("packEffects.clear();packEffectsPending=false;", PACK)
        self.assertIn("it=packEffects.erase(it);continue;", PACK)
        finish = PACK.split("void finishPackEffects(", 1)[1].split("void updatePackEffects(", 1)[0]
        self.assertEqual(finish.count(TAIL), 1)
        self.assertIn("if(!packEffectsPending)return;", finish)
        self.assertIn("e.initialized=true;e.start=now-packFxDuration;continue;", finish)
        self.assertLess(finish.index("e.frame=0;e.start=now;e.initialized=true;"), finish.index("r.gchandle_free(e.source)"))

    def test_post_move_and_tick_publication_boundaries_remain(self):
        self.assertIn("void noteMoved(Runtime&r,void*control,bool hold){flushHitEffects(r);if(!skinReady||!control)return;", FEATURES)
        before = FEATURES.split("void beforeNoteMove(", 1)[1].split("void* noteSprite", 1)[0]
        self.assertIn("bound->second==note)return;", before)
        self.assertNotIn("updatePackEffects(", before)
        moved = FEATURES.split("void noteMoved(", 1)[1].split("void tick(", 1)[0]
        self.assertNotIn("updatePackEffects(", moved)
        self.assertEqual(FEATURES.count("updatePackEffects(r)"), 1)
        self.assertIn("if(packEffects.empty())return;finishPackEffects(r);", PACK)
        finish = PACK.split("void finishPackEffects(", 1)[1].split("void updatePackEffects(", 1)[0]
        for setter in ("set_position", "set_localScale", "set_sprite"):
            self.assertLess(finish.index(setter), finish.index("set_enabled"))
        self.assertNotIn("get_frameCount", finish)
        hook = (ROOT / "PMHookBackend.mm").read_text(encoding="utf-8")
        manager = hook.split("void onNoteManager(", 1)[1].split("P onSkinInstantiate(", 1)[0]
        self.assertLess(manager.index("orig<VoidFn>(h::noteManager)"), manager.index("pmfeatures::flushHitEffects"))

    def test_real_cpp_bodies_match_linear_reference(self):
        candidates = [os.environ.get("CXX", ""), "clang++", "g++", "cl"]
        compiler = next((shutil.which(c) for c in candidates if c and shutil.which(c)), None)
        if not compiler:
            self.skipTest("C++17 compiler unavailable; source contracts still run")
        finish = "void finishPackEffects(" + PACK.split("void finishPackEffects(", 1)[1].split("void updatePackEffects(", 1)[0]
        self.assertEqual(finish.count(TAIL), 1)
        linear = finish.replace(TAIL, LINEAR).replace("void finishPackEffects(", "void finishPackEffectsLinear(", 1)
        finish = finish.replace("if(e.initialized)", "if((++visits,e.initialized))").replace("&&!(first-1)->initialized", "&&!(++boundaryChecks,(first-1)->initialized)")
        linear = linear.replace("if(e.initialized)", "if((++visits,e.initialized))")
        update = "void updatePackEffects(" + PACK.split("void updatePackEffects(", 1)[1]
        state = "\n".join(line for line in PACK.splitlines() if line.startswith(("struct PackEffect{", "bool packEffectsPending=", "std::vector<PackEffect>", "float packFxDuration=")))
        program = HARNESS.replace("__STATE__", state).replace("__FINISH__", finish).replace("__LINEAR_FINISH__", linear).replace("__UPDATE__", update).replace("__LINEAR_UPDATE__", update.replace("updatePackEffects(", "updatePackEffectsLinear(", 1).replace("finishPackEffects(r)", "finishPackEffectsLinear(r)"))
        with tempfile.TemporaryDirectory(prefix="pm-dense-effects-") as tmp:
            cpp = Path(tmp) / "dense.cpp"
            exe = Path(tmp) / ("dense.exe" if os.name == "nt" else "dense")
            cpp.write_text(program, encoding="utf-8")
            if Path(compiler).stem.lower() == "cl":
                command = [compiler, "/nologo", "/std:c++17", "/EHsc", "/W4", "/WX", str(cpp), f"/Fe:{exe}"]
            else:
                command = [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-pedantic", str(cpp), "-o", str(exe)]
            built = subprocess.run(command, cwd=tmp, capture_output=True, text=True, timeout=120)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            ran = subprocess.run([str(exe)], cwd=tmp, capture_output=True, text=True, timeout=60)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)
            print(ran.stdout.strip())


if __name__ == "__main__":
    unittest.main()
