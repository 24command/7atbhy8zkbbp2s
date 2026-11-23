#include "PMNativeOSCoordinator.hpp"
#include <deque>
#import <QuartzCore/QuartzCore.h>
#include "PMIL2CPP.hpp"
#include "PMNativeOSScene.hpp"
#include "PMNativeOSMap.hpp"
#include "PMNativeOSDetail.hpp"
#include "PMNativeOSChrome.hpp"
#include "PMNativeOSRows.hpp"
#include "PMNativeOSSwitch.hpp"
#import "PMNativeOSProgram.h"
#import "PMNativeOSActions.hpp"
#import "PMChapterOS.h"
#import "PMOSCheckpoint.h"
#import "PMContentStore.h"
#import "PMDoorRun.h"
#import "PMChapterSecretCourse.h"
#import "PMStoryCueRun.h"
#import "PMDiagnostics.h"
#import "PMUnlockMedia.h"
#include "PMUnlockRuntime.hpp"
namespace pmnativecoordinator {
using pmbridge::Runtime; using pmbridge::P;
namespace scene=pmnativeosscene; namespace chrome=pmnativechrome; namespace map=pmnativeosmap; namespace rows=pmnativeosrows; namespace panel=pmnativedetail; namespace toggle=pmnativeswitch;
namespace {
enum class Mode { idle, loading, list, listPending, listCut, entering, map, mapCut, detail, returning };
Mode mode=Mode::idle;
Runtime *game=nullptr; P selector=nullptr; uint64_t generation=0,visit=0,mapID=0,detailID=0;
PMNativeOSProgram *program; NSString *chapter; NSDictionary *detail,*selected;
NSArray<NSDictionary *> *choices; NSInteger lifeTier=0; NSUInteger revision=0;
uint64_t requestedEntry=0;
int handoffScene=0; // Only the selector scene that received this return may consume it.
bool gated=false,busy=false; chrome::View chromeView;
PMNativeOSActions *actions;
BOOL (^mountMap)(void);
BOOL (^applyCheckpoint)(NSDictionary *);
dispatch_source_t clockSource;
void stopClock(){if(clockSource){dispatch_source_cancel(clockSource);clockSource=nil;}}
struct ScheduledUnlock { int index; double remaining; };
std::deque<ScheduledUnlock> unlockQueue;
double previousUnlockTick=0;
void clearScene(Runtime &r,uint64_t closingVisit=visit){unlockQueue.clear();previousUnlockTick=0;stopClock(); [actions invalidate]; actions=nil; mountMap=nil; applyCheckpoint=nil; if(detailID)panel::close(r,detailID);detailID=0;if(mapID)map::close(r,mapID);mapID=0;if(closingVisit)chrome::close(r,closingVisit);chromeView={};rows::release();detail=nil;selected=nil;choices=nil;busy=false;}
NSDictionary *entry(NSDictionary *card){NSString *sid=card[@"sid"]?:card[@"installedID"];if(!sid)return nil;NSMutableDictionary *e=[@{@"songID":sid} mutableCopy];if(card[@"difficulty"])e[@"difficulty"]=card[@"difficulty"];return e;}
NSArray *options(NSDictionary *card){NSArray *replays=card[@"replaySongs"];if(replays.count)return replays;NSDictionary *e=entry(card);return e?@[e]:@[];}
void discardHandoff(){handoffScene=0;}
int sceneHandle(Runtime &r,P sceneValue){
 struct SceneValue { int32_t handle; };
 if(!sceneValue || r.object_get_class(sceneValue)!=r.type("UnityEngine.SceneManagement","Scene"))
     throw std::runtime_error("Unexpected selector scene");
 return r.unbox<SceneValue>(sceneValue).handle;
}
#include "PMNativeOSSelectorEntry.inc"
void returned(Runtime &r,uint64_t token,bool ok){
 if(&r!=game || mode!=Mode::returning || token!=visit || !token)return;
 visit=0;
 mode=Mode::idle; // Retail/challenge selectors may never call ready().
 program=nil;
 if(ok){
     try { handoffScene=sceneHandle(r,r.stat(r.type("UnityEngine.SceneManagement","SceneManager"),"GetActiveScene")); }
     catch(const std::exception &e){PMDiagnosticsWrite(e.what());}
 }
 if(!handoffScene)discardHandoff();
}
bool leave(Runtime &r,bool back){
 if(mode!=Mode::detail&&mode!=Mode::map&&mode!=Mode::mapCut&&mode!=Mode::entering)return false;
 if(!(back ? scene::leaveToChapter(r,returned) : scene::leaveToSongSelector(r,returned)))return false;
 mode=Mode::returning;clearScene(r);return true;
}
bool presentMap(Runtime &r){mode=Mode::map;busy=false;return chrome::present(r,visit,chrome::Face::Map,true,0,!gated)&&map::present(r,mapID,true,true,true);}
void closePanel(Runtime &r){if(detailID)panel::close(r,detailID);detailID=0;detail=nil;choices=nil;selected=nil;if(!presentMap(r))leave(r,false);}
bool rowFor(NSDictionary *e,rows::Row &out){return e&&rows::lookup(e[@"songID"],e[@"difficulty"],out);}
unsigned allowedSlots(){unsigned mask=0;for(NSDictionary *e in choices){rows::Row row;if(rowFor(e,row)&&row.slot>=0&&row.slot<4)mask|=1u<<row.slot;}return mask;}
void openPanel(Runtime &r,NSDictionary *card){
 if(!card||mode!=Mode::map)return;
 NSArray *available=options(card);NSDictionary *first=nil;rows::Row row;
 for(NSDictionary *entry in available){if(rowFor(entry,row)){first=entry;break;}}
 if(!first){PMDiagnosticsWrite("Chapter OS: selected song has no available difficulty");return;}
 // The detail copy belongs to this selection. Its creation must not block entry to the map.
 if(!chrome::resetDetail(r,visit)){presentMap(r);return;}
 map::present(r,mapID,false,false,false);chrome::present(r,visit,chrome::Face::Detail,false);
 panel::Speech speech{card[@"speechHeading"],card[@"caption"],[card[@"seconds"] doubleValue],card[@"waveform"]};
 detailID=panel::open(r,program.nativeChapter==8?panel::Style::c8:panel::Style::c9,chromeView.detailRoot,row.row,row.slot,speech,false,row.cover);
 if(!detailID){if(!presentMap(r))leave(r,false);return;}
 detail=card;selected=first;choices=available;mode=Mode::detail;
 if(!chrome::present(r,visit,chrome::Face::Detail,true,allowedSlots()))closePanel(r);
}
bool playSelection(Runtime &r,NSDictionary *card,NSDictionary *choice);
void showDetail(Runtime &r, NSDictionary *card) {
    if (!card || mode != Mode::map || [card[@"lockedChallenge"] boolValue]) return;
    if (!card[@"challengeID"] || [card[@"replaySongs"] count]) { openPanel(r,card); return; }
    uint64_t token = visit;
    auto afterIntro = ^(BOOL completed) {
        if (visit != token || mode != Mode::map) return;
        if (!presentMap(*game) || !completed) return;
        NSDictionary *e = entry(card);
        // Keep the complete challenge descriptor until the exact chart starts.
        if (![card[@"showDetail"] boolValue] && e && playSelection(*game,card,e)) return;
        openPanel(*game,card);
    };
    if (![card[@"intro"] count]) { afterIntro(YES); return; }
    busy=true;
    map::present(r,mapID,true,false,false);
    chrome::present(r,visit,chrome::Face::Map,false);
    if (![actions playIntro:card completion:afterIntro]) {
        PMDiagnosticsWrite("Native chapter intro unavailable");
        presentMap(r);
    }
}
void scheduleUnlock(int index){
 const auto *page=program.page;
 if(!page || index<0 || index>=page->unlockAnimationCount)return;
 const auto &spec=page->unlockAnimations[index];
 if(spec.once && spec.seen)return;
 for(const auto &queued:unlockQueue)if(queued.index==index)return;
 unlockQueue.push_back({index,spec.after});
}
void tickUnlocks(Runtime &r){
 double now=CACurrentMediaTime(),elapsed=previousUnlockTick?now-previousUnlockTick:0;
 previousUnlockTick=now;
 if(mode!=Mode::map || busy || unlockQueue.empty() || UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
 auto &head=unlockQueue.front();
 // Count time only while the map can accept input. Ignore suspended/background gaps.
 if(elapsed>=0 && elapsed<1)head.remaining-=elapsed;
 if(head.remaining>0)return;
 int index=head.index;unlockQueue.pop_front();
 uint64_t token=visit,epoch=generation;
 busy=true;
 map::present(r,mapID,true,false,false);chrome::present(r,visit,chrome::Face::Map,false);
 BOOL accepted=[actions playUnlockAtIndex:index completion:^(BOOL ok){
   if(token!=visit || epoch!=generation || mode!=Mode::map)return;
   if(!ok)PMDiagnosticsWrite("Chapter OS: unlock animation interrupted or unavailable");
   presentMap(*game);
 }];
 if(!accepted)presentMap(r);
}
void activate(uint64_t mapVisit, int index) {
    if (mode != Mode::map || busy || mapID != mapVisit) return;
    if (actions.cardOnly) {
        [actions activateCardNode:index open:^(NSDictionary *card){ showDetail(*game,card); }
                          rebuild:^{ if (!mountMap || !mountMap()) leave(*game,false); }];
        return;
    }
    busy=true;
    uint64_t epoch=generation;
    [program clickNode:index completion:^(BOOL ok,const PMOSAction *a){
        if (epoch!=generation || mapID!=mapVisit || mode!=Mode::map) return;
        busy=false;
        if (!ok) { PMDiagnosticsWrite(a->error); return; }
        gated=a->listSwitchHidden; lifeTier=a->selectedLifeTier;
        Runtime &r=*game;
        chrome::present(r,visit,chrome::Face::Map,true,0,!gated);
        if(a->unlockAnimation){scheduleUnlock(a->unlockAnimation-1);return;}
        if (a->checkpoint || a->revealTitle[0]) {
            busy=true;
            map::present(r,mapID,true,false,false);
            chrome::present(r,visit,chrome::Face::Map,false);
            BOOL shown;
            if (a->checkpoint) {
                shown=[actions checkpoint:a resume:^(NSDictionary *record){
                    if (!applyCheckpoint || !applyCheckpoint(record)) presentMap(*game);
                } leave:^{ if (!leave(*game,gated)) presentMap(*game); }];
            } else {
                NSDictionary *card = a->song>0 && NSUInteger(a->song)<=program.order.count ? program.visibleBySong[program.order[a->song-1]] : nil;
                shown=[actions reveal:a fromNode:index completion:^(PMNativeRevealChoice choice){
                    if (!presentMap(*game) || !card || choice==PMNativeRevealContinue) return;
                    NSDictionary *e=entry(card);
                    if (choice==PMNativeRevealStart && e && playSelection(*game,card,e)) return;
                    showDetail(*game,card);
                }];
            }
            if (!shown) { PMDiagnosticsWrite("Native chapter action could not be presented"); presentMap(r); }
            return;
        }
        if (a->challenge>0 && NSUInteger(a->challenge)<=program.challengeRows.count) { showDetail(r,program.challengeRows[a->challenge-1]); return; }
        if (a->song>0 && NSUInteger(a->song)<=program.order.count) { showDetail(r,program.visibleBySong[program.order[a->song-1]]); return; }
        if (a->dest>=0) map::displayPage(r,mapID,a->dest);
        else if (a->element>=0) map::setElement(r,mapID,a->element,a->visible);
    }];
}
scene::Route chapterRoute() {
    if (program.nativeChapter == 8) return scene::Route::C8;
    return program.page->nativePhase == 2 ? scene::Route::C9Phase2 : scene::Route::C9;
}
void arrived(Runtime &r,uint64_t token,scene::Route route,P root){
 if(mode!=Mode::entering||token!=visit)return;
 if(!root||route!=chapterRoute()||!chrome::open(r,visit,route,root,chromeView)){
  PMDiagnosticsWrite(root?"Chapter OS: native chapter controls unavailable":"Chapter OS: loaded scene host unavailable");
  if(!leave(r,false)){
   clearScene(r);visit=0;
   mode=selector && r.alive(selector) ? Mode::list : Mode::idle;
   abortSelectorEntry(r);
  }
  return;
 }
 uint64_t epoch=generation;
 actions=[[PMNativeOSActions alloc] initWithProgram:program current:^BOOL{
     return visit==token && generation==epoch && mode==Mode::map;
 }];
 mountMap=^BOOL{
     if (visit!=token || generation!=epoch) return NO;
     if (mapID) map::close(*game,mapID);
     NSString *reason=nil;
     mapID=map::open(*game,chromeView.parent,*actions.page,actions.nodes,chromeView.font,^(uint64_t m,int i){activate(m,i);},&reason);
     if (!mapID || !presentMap(*game)) { PMDiagnosticsWrite(reason.UTF8String?:"Native chapter map unavailable"); return NO; }
     return YES;
 };
 auto startMap = ^{
 if(visit!=token || generation!=epoch)return;
 Runtime &r=*game;
 if (!mountMap()) { leave(r,false); return; }
 // The stock transition may leave a captured frame on the persistent RawImage.
 // Release it only after this visit owns a rendered map and its input controls.
 try{
  P mask=r.get<P>(r.mainGame(),"sceneSwitchMask");
  if(r.alive(mask) && r.call(mask,"get_texture")){
   float transparent[4]={};
   r.call(mask,"set_texture",{"UnityEngine.Texture"},{nullptr});
   r.call(mask,"set_color",{"UnityEngine.Color"},{transparent});
  }
 }catch(const std::exception &e){PMDiagnosticsWrite(e.what());}
 PMDiagnosticsWrite("Chapter OS: map ready");
 applyCheckpoint=^BOOL(NSDictionary *record){
     if (visit!=token || generation!=epoch || mode!=Mode::map || ![record[@"chapter"] isEqual:chapter] ||
         ![record[@"scriptHash"] isEqual:program.scriptHash]) return NO;
     id page=record[@"page"];
     if (page) {
         NSUInteger index=[page isKindOfClass:NSNumber.class] ? [page unsignedIntegerValue] : [program.screens indexOfObject:page];
         return index<program.screens.count && map::displayPage(*game,mapID,(int)index) && presentMap(*game);
     }
     NSString *sid=record[@"songID"];
     NSDictionary *card=sid ? program.visibleBySong[sid] : nil;
     if (!card) return NO;
     NSMutableDictionary *e=[@{@"songID":sid} mutableCopy];
     if (record[@"difficulty"]) e[@"difficulty"]=record[@"difficulty"];
     return playSelection(*game,card,e);
 };
 NSDictionary *record=PMChapterOSTakeCheckpoint(chapter);
 if (record) {
     BOOL applied=applyCheckpoint(record);
     PMOSClearCheckpoint(record[@"token"]);
     if (!applied) PMDiagnosticsWrite("Native chapter checkpoint destination changed or unavailable");
     if (mode!=Mode::map) return;
 }
 for(int i=0;i<program.page->unlockAnimationCount;++i)
     if(program.page->unlockAnimations[i].when==PMOSUnlockEnter)scheduleUnlock(i);
 previousUnlockTick=CACurrentMediaTime();
 clockSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 dispatch_source_set_timer(clockSource,DISPATCH_TIME_NOW,NSEC_PER_SEC/30,NSEC_PER_MSEC*3);
 dispatch_source_set_event_handler(clockSource,^{if(visit!=token)return;tickUnlocks(*game);if(mode==Mode::map)map::tick(*game,mapID);});dispatch_resume(clockSource);
 };
 if(program.page->entryMovieKey[0] && !program.page->entryMovieSeen){
     mode=Mode::map;busy=true;
     if([actions playEntryMovie:^(BOOL completed){ startMap(); }])return;
 }
 startMap();
}
// Both manual entry and the deferred automatic entry respect SongSelector.Update's gates.
bool selectorReady(Runtime &r,P owner){
 P loading=r.klass("Loading");
 return r.staticValue<bool>(loading,"loadOver","System.Boolean") &&
        !r.staticValue<bool>(loading,"lockTouch","System.Boolean") &&
        !r.get<bool>(owner,"exit") && !r.get<bool>(owner,"isMoving");
}
void beginManualCut(Runtime &r,Mode cut);
void enter(Runtime &r){
 if(mode==Mode::listPending){beginManualCut(r,Mode::listCut);return;}
 if((mode!=Mode::list && mode!=Mode::listCut)||!selector)return;
 if(revision!=PMContentStore.shared.revision){PMDiagnosticsWrite("Chapter OS: chapter library changed before entry");return;}
 PMDiagnosticsWrite([NSString stringWithFormat:@"Chapter OS: entering %@ with chapter %d phase %d layout",chapter,(int)program.nativeChapter,program.page->nativePhase].UTF8String);
 NSMutableOrderedSet *targets=[NSMutableOrderedSet orderedSet];
 if (program.nodes.count) {
     // A Lua callback may return a song that has no static map node.
     for (NSString *sid in program.order) {
         NSDictionary *card = program.visibleBySong[sid];
         if (card) [targets addObjectsFromArray:options(card)];
     }
     for (NSUInteger i=0; i<program.challengeRows.count; ++i)
         if (program.page->challenges[i].state!=PMOSChallengeLocked)
             [targets addObjectsFromArray:options(program.challengeRows[i])];
 } else {
     for (NSDictionary *card in program.cards) if (![card[@"lockedChallenge"] boolValue])
         [targets addObjectsFromArray:options(card[@"challengeDetail"]?:card)];
 }
 // Secret courses capture every leg before the selector is unloaded, including the hidden fourth leg.
 for (NSDictionary *card in program.challengeRows)
     if (card[@"secretCourse"]) [targets addObjectsFromArray:card[@"secretCourse"]];
 NSArray *entries=targets.array;
 if(!rows::prepare(r,selector,chapter,entries)){
   PMDiagnosticsWrite("Chapter OS: selector changed before songs could be captured");return;
 }
 mode=Mode::entering;visit=scene::enter(r,chapterRoute(),arrived);
 if(!visit){mode=Mode::list;rows::release();PMDiagnosticsWrite("Native chapter scene unavailable; check packaged scene resources");}
}
#include "PMNativeOSManualTransition.inc"

bool armGameplay(NSDictionary *card,const rows::Start &song){
 if(PMDoorActive() || PMUnlockMediaBusy())return false;
 if([card[@"replaySongs"] count])return PMDoorArmReplay(song.group,song.slot,song.chartID);
 if(!card[@"challengeID"]){PMDoorCancelPending();pmstory::cancelLaunch();return true;}
 if(!PMDoorArm(chapter,card[@"challengeID"],song.group,song.slot,song.chartID,[card[@"hp"] doubleValue],card[@"delta"]))return false;
 if(!PMDoorSetPendingNoPause([card[@"noPause"] boolValue]) || !PMStorySequenceArm(chapter,card[@"nextSongs"])){
  PMDoorCancelPending();return false;
 }
 PMStoryCueArm(card[@"cues"]);pmstory::captureLaunch();return true;
}

bool playSelection(Runtime &r,NSDictionary *card,NSDictionary *choice){
 if(!card || !choice || !program.visibleBySong[choice[@"songID"]] || busy || (mode!=Mode::map && mode!=Mode::detail) ||
    revision!=PMContentStore.shared.revision || !scene::activeRoot(r) || PMUnlockMediaBusy())return false;
 if(card[@"secretCourse"]){
  NSInteger tier=[card[@"lifeTier"] integerValue];busy=true;
  bool started=PMChapterStartSecretCourseWithPauseLock(chapter,card[@"challengeID"],card[@"secretCourse"],tier<0?lifeTier:tier,[card[@"noPause"] boolValue]);
  if(!started)busy=false;
  return started;
 }
 NSString *sid=choice[@"songID"], *diff=choice[@"difficulty"];
 auto song=rows::resolveStart(r,sid,diff);
 if(!song.info){PMDiagnosticsWrite("Chapter OS: selected chart is unavailable at Start");return false;}
 const uint64_t token=visit,epoch=generation;
 const Mode source=mode;Runtime *rt=&r;
 busy=true;
 BOOL (^sameFace)(void)=^BOOL{return visit==token && generation==epoch && mode==source;};
 auto valid=^BOOL{return sameFace() && revision==PMContentStore.shared.revision && scene::activeRoot(*rt);};
 __block bool started=false,armed=false;
 auto resume=^(BOOL completed){
  if(!sameFace())return;
  auto finished=^(bool routed){
   if(!routed && armed){PMDoorCancelPending();pmstory::cancelLaunch();armed=false;}
   if(!routed && sameFace())busy=false;
  };
  if(completed && valid()){
   auto arm=^bool(Runtime &gameRuntime,P info){
    if(!valid())return false;
    auto exact=rows::resolveStart(gameRuntime,sid,diff);
    if(!exact.info || exact.info!=info)return false;
    armed=armGameplay(card,exact);return armed;
   };
   started=scene::play(*rt,token,song.info,arm,finished);
  }
  if(!started)finished(false);
 };
 if(pmunlock::chapterStartIntro(r,song.chartID,valid,resume))return true;
 resume(YES);
 return started;
}
bool wantsOSHome(PMNativeOSProgram *p,NSString *key){
 return p.listSwitchHidden || !p.listFirst || PMChapterOSHasRoutedCheckpoint(key);
}
void selectorPreloaded(uint64_t ticket,PMNativeOSProgram *p,NSError *err){
 if(ticket!=bridge.ticket || !bridge.loading)return;
 bridge.loading=false;
 if(bridge.revision!=PMContentStore.shared.revision)p=nil;
 if(err)PMDiagnosticsWrite(err.localizedDescription.UTF8String);
 if(!p || !wantsOSHome(p,bridge.chapter))releaseEntryCover(*bridge.runtime);
 PMNativeOSLoadCompletion waiter=bridge.waiter;
 bridge.waiter=nil;
 if(waiter)waiter(p,err);
 else bridge.program=p;
}
}
void selectorLoaded(Runtime &r,int handle,NSString *key){
 if(!handle || bridge.handle==handle || handle==handoffScene || transitioning() || mode==Mode::map || mode==Mode::detail)return;
 resetEntryBridge(r);
 bridge.runtime=&r;
 bridge.handle=handle;
 bridge.chapter=[key copy];
 bridge.revision=PMContentStore.shared.revision;
 bridge.loading=true;
 const auto ticket=bridge.ticket;
 // The home policy can read saved Lua progress. Cover the candidate selector
 // until the worker determines its home, even if Start has not supplied rows.
 cutChecked([&]{coverSelector(r,handle);});
 [PMNativeOSProgram loadChapter:key completion:^(PMNativeOSProgram *p,NSError *err){
     selectorPreloaded(ticket,p,err);
 }];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{
     if(bridge.ticket==ticket && bridge.cover && mode!=Mode::entering){
         PMDiagnosticsWrite("Chapter OS: selector readiness timed out");
         releaseEntryCover(*bridge.runtime); // Stop obscuring input while stock readiness is pending.
     }
 });
}
void abortSelectorEntry(Runtime &r){
 if(!bridge.cover || mode==Mode::entering)return;
 requestedEntry=0;
 releaseEntryCover(r);
}
void ready(Runtime &r,P owner,NSString *key){
 if(transitioning() || mode==Mode::map || mode==Mode::detail)return;
 // Scene staging is optional. A failed preflight or Unity scene lookup must
 // still allow the live selector to load the declaration and bind its switch.
 int ownerScene=0;
 if(handoffScene || bridge.handle)
     cutChecked([&]{ownerScene=sceneHandle(r,r.call(r.call(owner,"get_gameObject"),"get_scene"));});
 const bool returning=handoffScene && handoffScene==ownerScene && [chapter isEqual:key] &&
                      revision==PMContentStore.shared.revision;
 discardHandoff();
 const bool matches=bridge.handle && bridge.handle==ownerScene && [bridge.chapter isEqual:key] &&
                    bridge.revision==PMContentStore.shared.revision;
 if(bridge.handle && !matches)resetEntryBridge(r);
 if(returning)releaseEntryCover(r);
 selector=owner;game=&r;chapter=[key copy];
 const auto epoch=++generation,ticket=bridge.ticket;
 const auto libraryRevision=PMContentStore.shared.revision;
 mode=Mode::loading;
 auto current=^bool{return epoch==generation && ticket==bridge.ticket && selector==owner && mode==Mode::loading;};
 PMNativeOSLoadCompletion loaded=^(PMNativeOSProgram *p,NSError *err){
  if(!current())return;
  if(!p || libraryRevision!=PMContentStore.shared.revision){
   mode=Mode::idle;
   releaseEntryCover(*game);
   if(err)PMDiagnosticsWrite(err.localizedDescription.UTF8String);
   return;
  }
  program=p;revision=libraryRevision;lifeTier=p.selectedLifeTier;gated=p.listSwitchHidden;mode=Mode::list;
  if(toggle::bind(*game,owner,key.UTF8String))toggle::show(*game,gated?toggle::Face::Hidden:toggle::Face::List,!gated);
  if(!returning && wantsOSHome(p,key))requestedEntry=epoch;
 };
 // Join the preflight if it is still running. A missing result gets one
 // live load, while a successful declaration is consumed exactly once.
 PMNativeOSLoadCompletion usePreload=^(PMNativeOSProgram *p,NSError *){
  if(!current())return;
  if(p || libraryRevision!=PMContentStore.shared.revision)loaded(p,nil);
  else [PMNativeOSProgram loadChapter:key completion:loaded];
 };
 if(bridge.loading){bridge.waiter=usePreload;return;}
 PMNativeOSProgram *staged=bridge.program;
 bridge.program=nil;
 usePreload(staged,nil);
}
void selectorFrame(Runtime &r,P owner){
 if(!requestedEntry || requestedEntry!=generation || (mode!=Mode::list && mode!=Mode::listPending) || selector!=owner)return;
 // 4.0.4 SongSelector.Update uses these same two Loading flags before input.
 // Leave the stock transition in charge until it finishes unlocking the selector.
 if(!cutChecked([&]{
     if(!selectorReady(r,owner))return;
     requestedEntry=0;
     enter(r);
 }) || !requestedEntry)abortSelectorEntry(r);
}
void detach(Runtime &r){
 if(&r!=game)return;
 selector=nullptr;
 if(mode==Mode::listCut)mode=Mode::idle; // No async scene request yet.
 toggle::release(r);
 // Selector teardown is expected during a Single load. Keep the scene's
 // generation and any scene-scoped return until the corresponding unload.
 if(transitioning() || mode==Mode::map || mode==Mode::detail)return;
 ++generation;
 program=nil;
 mode=Mode::idle;
}
bool transitioning(){return mode==Mode::listCut || mode==Mode::mapCut || mode==Mode::entering || mode==Mode::returning;}
void sceneUnloaded(Runtime &r,int handle,bool owned){
 if(handle && handle==bridge.handle)resetEntryBridge(r);
 if(&r!=game)return;
 if(!owned){
     if(handle && handle==handoffScene)discardHandoff();
     return;
 }
 // leave() already closed this graph. Keep its token until returned() can
 // compare and consume it, including when a different Single load wins.
 if(!visit || mode==Mode::returning)return;
 // Consume the visit before cleanup can trigger any more Unity callbacks.
 const uint64_t closingVisit=visit;
 visit=0;
 ++generation;
 mode=Mode::idle;
 selector=nullptr;program=nil;chapter=nil;
 discardHandoff();
 clearScene(r,closingVisit);
 toggle::release(r);
}
namespace {
bool claims(Runtime &r,P button){
 if(bridge.cover && bridge.runtime==&r)return true;
 if(&r!=game || mode==Mode::idle || mode==Mode::loading)return false;
 return mode!=Mode::list || toggle::owns(r,button);
}
void dispatchOwned(Runtime &r,P b){
 if(bridge.cover)return;
 if(mode==Mode::list){
  if(toggle::press(r,b)==toggle::Press::OpenOS){PMDiagnosticsWrite("Chapter OS: list switch pressed");mode=Mode::listPending;requestedEntry=generation;}
  return;
 }
 if(mode==Mode::listPending || transitioning())return;
 if(busy)return;
 if(mode==Mode::map && map::press(r,b))return;
 auto action=chrome::press(r,b);switch(action.intent){
 case chrome::Intent::Back:if(mode==Mode::detail)closePanel(r);else leave(r,true);break;
 case chrome::Intent::List:if(mode==Mode::map && !gated)beginManualCut(r,Mode::mapCut);break;
 case chrome::Intent::Start:if(detail&&selected)playSelection(r,detail,selected);break;
 case chrome::Intent::Slot:for(NSDictionary *e in choices){rows::Row row;if(rowFor(e,row)&&row.slot==action.slot&&panel::update(r,detailID,row.row,row.slot,row.cover)){selected=e;chrome::present(r,visit,chrome::Face::Detail,true,allowedSlots());break;}}break;
 default:break;
 }
}
template<class F> void guardInput(F work){
 @try {
     try { work(); }
     catch(const std::exception &e){PMDiagnosticsWrite(e.what());}
 } @catch(NSException *e){PMDiagnosticsWrite(e.reason.UTF8String);}
}
bool dispatch(Runtime &r,P button,P event,bool pointer){
 if(!claims(r,button))return false;
 // Claim before invoking managed code. Even if the action leaves the scene,
 // the outer hook must consume this event and skip the nested Button.Press.
 guardInput([&]{
     if(!pointer || (event && r.enumValue(r.call(event,"get_button"),
         "UnityEngine.EventSystems.PointerEventData.InputButton")==0))
         dispatchOwned(r,button);
 });
 return true;
}
}
bool press(Runtime &r,P button){return dispatch(r,button,nullptr,false);}
bool pointerClick(Runtime &r,P button,P event){return dispatch(r,button,event,true);}
}
