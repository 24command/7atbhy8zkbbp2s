#include "PMNativeOSTransition.hpp"
#include "PMIL2CPP.hpp"
#import "PMDiagnostics.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <memory>
#include <vector>
namespace pmnativeostran {
namespace {
using pmbridge::Runtime; using pmbridge::P;
template<class F> bool checked(F work) {
    @try {try{work();return true;}catch(const std::exception &e){PMDiagnosticsWrite(e.what());}}
    @catch(NSException *e){PMDiagnosticsWrite(e.reason.UTF8String);} return false;
}
void require(bool yes,const char *why){if(!yes)throw std::runtime_error(why);}
void flag(Runtime&r,P obj,const char*method,bool value){r.call(obj,method,{"System.Boolean"},{&value});}
P clone(Runtime&r,P obj){return r.stat(r.type("UnityEngine","Object"),"Instantiate",{"UnityEngine.Object"},{obj});}
void destroy(Runtime&r,P obj){if(r.alive(obj)){flag(r,obj,"SetActive",false);r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{obj});}}
P clip(Runtime&r,P root,const char *expected){
    P anims=r.children(root,r.type("UnityEngine","Animator")); P result=nullptr;
    for(uintptr_t i=0;i<r.array_length(anims);++i){
        P animator=r.arrayAt(anims,int(i));
        flag(r,animator,"set_fireEvents",false);flag(r,animator,"set_enabled",false);
        P controller=r.call(animator,"get_runtimeAnimatorController");
        if(!controller)continue;
        P clips=r.call(controller,"get_animationClips");
        for(uintptr_t j=0;j<r.array_length(clips);++j){P c=r.arrayAt(clips,int(j));
            if([r.string(r.call(c,"get_name")) isEqualToString:[NSString stringWithUTF8String:expected]])result=c;}
    }
    require(result,"Chapter OS: native transition clip unavailable");return result;
}
void persist(Runtime&r,P root){r.stat(r.type("UnityEngine","Object"),"DontDestroyOnLoad",{"UnityEngine.Object"},{root});}
struct RevealDonor {Runtime *r=nullptr;uint32_t root=0,clip=0;} donor;
struct Cut {
    Runtime&r;Ticket id;Gate gate;std::vector<uint32_t> pins;
    P visual=nullptr,closing=nullptr,opening=nullptr;
    Load load;Done done;dispatch_source_t clock=nil;
    double previous=CACurrentMediaTime(); int coveredFrame=-1; bool suspended=false;
    Cut(Runtime&rt,Ticket ticket,bool covered,bool external):r(rt),id(ticket),gate(covered,external){}
    P keep(P value){require(value,"Chapter OS: cannot retain transition object");auto h=r.gchandle_new(value,false);require(h,"Chapter OS: transition root allocation failed");pins.push_back(h);return value;}
    ~Cut(){for(auto h:pins)r.gchandle_free(h);}
    void sample(P c,double time){float seconds=float(time);r.call(c,"SampleAnimation",{"UnityEngine.GameObject","System.Single"},{visual,&seconds});}
};
std::shared_ptr<Cut> live;Ticket sequence=0;
id resignObserver=nil,activeObserver=nil;
void releaseCutObservers(){
    if(resignObserver)[NSNotificationCenter.defaultCenter removeObserver:resignObserver];
    if(activeObserver)[NSNotificationCenter.defaultCenter removeObserver:activeObserver];
    resignObserver=activeObserver=nil;
}
void observeCut(const std::shared_ptr<Cut>&c){
    releaseCutObservers();std::weak_ptr<Cut> weak=c;
    resignObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *){
        if(auto owner=weak.lock()){owner->suspended=true;owner->previous=CACurrentMediaTime();owner->coveredFrame=-1;}
    }];
    activeObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *){
        if(auto owner=weak.lock()){owner->previous=CACurrentMediaTime();owner->coveredFrame=-1;owner->suspended=false;}
    }];
}
void finish(const std::shared_ptr<Cut>&c,bool ok){
    if(live!=c || !c->gate.finish())return;
    if(c->clock){dispatch_source_cancel(c->clock);c->clock=nil;}
    live.reset();releaseCutObservers();
    checked([&]{destroy(c->r,c->visual);});
    auto done=c->done;c->done=nil;c->load=nil;
    if(done)checked([&]{done(c->id,ok);});
}
void tick(const std::shared_ptr<Cut>&c){
    if(live!=c)return;
    double now=CACurrentMediaTime(),dt=std::max(0.,now-c->previous);c->previous=now;
    if(c->suspended || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    if(!checked([&]{
        require(c->r.alive(c->visual),"Chapter OS: transition object disappeared");
        bool load=c->gate.advance(dt);
        if(c->gate.phase==Phase::Closing)c->sample(c->closing,std::min(coveredAt,c->gate.elapsed));
        else if(c->gate.phase==Phase::Revealing){
            double duration=c->opening?revealDuration:coveredAt;
            if(c->opening)c->sample(c->opening,std::min(duration,c->gate.elapsed));
            else c->sample(c->closing,std::max(0.,coveredAt-c->gate.elapsed));
            if(c->gate.elapsed>=duration){finish(c,true);return;}
        }else c->sample(c->closing,coveredAt);
        // Timer callbacks are not render frames (especially on 30 Hz devices).
        // Require Unity's frame counter to advance after the opaque sample.
        if(load){
            int frame=c->r.unbox<int>(c->r.stat(c->r.type("UnityEngine","Time"),"get_frameCount"));
            if(c->coveredFrame<0)c->coveredFrame=frame;
            else if(frame!=c->coveredFrame)request(c->id);
        }
        if(live==c && c->gate.phase==Phase::Loading && c->gate.elapsed>60){
            PMDiagnosticsWrite("Chapter OS: destination transition timed out");finish(c,false);
        }
    }))finish(c,false);
}
}
void rememberReveal(Runtime&r){
    if(donor.r==&r && donor.root && r.alive(r.gchandle_get_target(donor.root)))return;
    checked([&]{
        P loading=r.staticValue<P>(r.klass("Loading"),"instance","Loading");
        if(!r.alive(loading))return;
        P prefab=r.get<P>(loading,"cutIn");if(!r.alive(prefab))return;
        P root=clone(r,prefab);uint32_t rootPin=0,clipPin=0;
        try{
            // The original CutIn has a separate 0.67s DestroyThis.Update timer.
            // Animator.speed=0 alone would NOT keep this private donor alive.
            P destructors=r.children(root,r.klass("DestroyThis"));
            for(uintptr_t i=0;i<r.array_length(destructors);++i)flag(r,r.arrayAt(destructors,int(i)),"set_enabled",false);
            flag(r,root,"SetActive",false);P revealClip=clip(r,root,"CutInFromBlack");persist(r,root);
            rootPin=r.gchandle_new(root,false);clipPin=r.gchandle_new(revealClip,false);
            require(rootPin&&clipPin,"Chapter OS: cannot reserve stock reveal");
            if(donor.r==&r){if(donor.root){destroy(r,r.gchandle_get_target(donor.root));r.gchandle_free(donor.root);}if(donor.clip)r.gchandle_free(donor.clip);}
            donor={&r,rootPin,clipPin};
        }catch(...){if(rootPin)r.gchandle_free(rootPin);if(clipPin)r.gchandle_free(clipPin);destroy(r,root);throw;}
    });
}
Ticket begin(Runtime&r,P prefab,bool covered,bool authored,Load load,Done done){
    if(!NSThread.isMainThread || live || !load || !done || !r.alive(prefab))return 0;
    rememberReveal(r);if(++sequence==0)++sequence;
    auto c=std::make_shared<Cut>(r,sequence,covered,authored);
    if(!checked([&]{
        c->visual=c->keep(clone(r,prefab));c->closing=c->keep(clip(r,c->visual,"CutOut"));
        persist(r,c->visual);
        P canvases=r.children(c->visual,r.type("UnityEngine","Canvas"));int order=32766;
        for(uintptr_t i=0;i<r.array_length(canvases);++i)r.call(r.arrayAt(canvases,int(i)),"set_sortingOrder",{"System.Int32"},{&order});
        if(donor.r==&r && donor.clip)c->opening=c->keep(r.gchandle_get_target(donor.clip));
        if(!c->opening)PMDiagnosticsWrite("Chapter OS: stock CutIn unavailable; reverse CutOut fallback");
        c->sample(c->closing,covered?coveredAt:0);c->load=[load copy];c->done=[done copy];
    })){checked([&]{destroy(r,c->visual);});return 0;}
    live=c;observeCut(c);c->clock=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(c->clock,DISPATCH_TIME_NOW,NSEC_PER_SEC/60,NSEC_PER_MSEC*2);
    std::weak_ptr<Cut> weak=c;
    dispatch_source_set_event_handler(c->clock,^{if(auto owner=weak.lock())tick(owner);});dispatch_resume(c->clock);
    return c->id;
}
bool request(Ticket id){auto c=live;if(!c||c->id!=id||!c->gate.request())return false;c->sample(c->closing,coveredAt);auto load=c->load;c->load=nil;if(!checked([&]{load(id);}))finish(c,false);return true;}
bool ready(Ticket id,bool deferReveal){auto c=live;if(!c||c->id!=id||!c->gate.ready())return false;return (c->gate.external||deferReveal)?true:reveal(id);}
bool reveal(Ticket id,bool animate){auto c=live;if(!c||c->id!=id||!c->gate.reveal())return false;if(!animate)finish(c,true);return true;}
void cancel(Ticket id){auto c=live;if(c&&(!id||c->id==id))finish(c,false);}
bool active(){return live!=nullptr;}
bool loading(){return live && live->gate.phase==Phase::Loading;}
}
