#include "PMNativeOSCoordinator.hpp"
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
namespace pmnativecoordinator {
using pmbridge::Runtime; using pmbridge::P;
namespace scene=pmnativeosscene; namespace chrome=pmnativechrome; namespace map=pmnativeosmap; namespace rows=pmnativeosrows; namespace panel=pmnativedetail; namespace toggle=pmnativeswitch;
namespace {
enum class Mode { idle, loading, list, entering, map, detail, returning };
Mode mode=Mode::idle;
Runtime *game=nullptr; P selector=nullptr; uint64_t generation=0,visit=0,mapID=0,detailID=0;
PMNativeOSProgram *program; NSString *chapter; NSDictionary *detail,*pendingStart,*selected;
NSArray<NSDictionary *> *choices; NSInteger lifeTier=0; NSUInteger revision=0;
bool gated=false,busy=false,returnBack=false,reuseList=false; chrome::View chromeView;
PMNativeOSActions *actions;
BOOL (^mountMap)(void);
BOOL (^applyCheckpoint)(NSDictionary *);
dispatch_source_t clockSource;
void stopClock(){if(clockSource){dispatch_source_cancel(clockSource);clockSource=nil;}}
void clearScene(Runtime &r){[actions invalidate]; actions=nil; mountMap=nil; applyCheckpoint=nil; stopClock(); if(detailID)panel::close(r,detailID);detailID=0;if(mapID)map::close(r,mapID);mapID=0;if(visit)chrome::close(r,visit);chromeView={};rows::release();detail=nil;selected=nil;choices=nil;busy=false;}
NSDictionary *entry(NSDictionary *card){NSString *sid=card[@"sid"]?:card[@"installedID"];if(!sid)return nil;NSMutableDictionary *e=[@{@"songID":sid} mutableCopy];if(card[@"difficulty"])e[@"difficulty"]=card[@"difficulty"];return e;}
NSArray *options(NSDictionary *card){NSArray *replays=card[@"replaySongs"];if(replays.count)return replays;NSDictionary *e=entry(card);return e?@[e]:@[];}
void returned(Runtime&,uint64_t token,bool ok){if(visit!=token)return;if(!ok){pendingStart=nil;returnBack=false;reuseList=false;program=nil;mode=Mode::idle;}visit=0;}
bool leave(Runtime &r,bool back,NSDictionary *launch){
 if(mode!=Mode::detail&&mode!=Mode::map&&mode!=Mode::entering)return false;
 if(!scene::leaveToSongSelector(r,returned))return false;
 pendingStart=[launch copy];returnBack=back;reuseList=true;mode=Mode::returning;clearScene(r);return true;
}
bool presentMap(Runtime &r){mode=Mode::map;busy=false;return chrome::present(r,visit,chrome::Face::Map,true,0,!gated)&&map::present(r,mapID,true,true,true);}
void closePanel(Runtime &r){if(detailID)panel::close(r,detailID);detailID=0;detail=nil;choices=nil;selected=nil;if(!chrome::resetDetail(r,visit)||!presentMap(r))leave(r,false,nil);}
bool rowFor(NSDictionary *e,rows::Row &out){return e&&rows::lookup(e[@"songID"],e[@"difficulty"],out);}
unsigned allowedSlots(){unsigned mask=0;for(NSDictionary *e in choices){rows::Row row;if(rowFor(e,row)&&row.slot>=0&&row.slot<4)mask|=1u<<row.slot;}return mask;}
void openPanel(Runtime &r,NSDictionary *card){
 if(!card||mode!=Mode::map)return;NSArray *available=options(card);NSDictionary *first=available.firstObject;rows::Row row;if(!rowFor(first,row))return;
 map::present(r,mapID,false,false,false);chrome::present(r,visit,chrome::Face::Detail,false);
 panel::Speech speech{card[@"speechHeading"],card[@"caption"],[card[@"seconds"] doubleValue]};
 detailID=panel::open(r,program.nativeChapter==8?panel::Style::c8:panel::Style::c9,chromeView.detailRoot,row.row,row.slot,speech,false,row.cover);
 if(!detailID){if(!chrome::resetDetail(r,visit)||!presentMap(r))leave(r,false,nil);return;}
 detail=card;selected=first;choices=available;mode=Mode::detail;
 if(!chrome::present(r,visit,chrome::Face::Detail,true,allowedSlots()))closePanel(r);
}
void showDetail(Runtime &r, NSDictionary *card) {
    if (!card || mode != Mode::map || [card[@"lockedChallenge"] boolValue]) return;
    if (!card[@"challengeID"] || [card[@"replaySongs"] count]) { openPanel(r,card); return; }
    uint64_t token = visit;
    auto afterIntro = ^(BOOL completed) {
        if (visit != token || mode != Mode::map) return;
        if (!presentMap(*game) || !completed) return;
        NSDictionary *e = entry(card);
        // Keep the full challenge attached through the selector handoff so startSelection
        // arms HP/delta, noPause, cues, sequence and course life tier at launch time.
        if (![card[@"showDetail"] boolValue] && e && leave(*game,false,@{@"detail":card,@"entry":e})) return;
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
void activate(uint64_t mapVisit, int index) {
    if (mode != Mode::map || busy || mapID != mapVisit) return;
    if (actions.cardOnly) {
        [actions activateCardNode:index open:^(NSDictionary *card){ showDetail(*game,card); }
                          rebuild:^{ if (!mountMap || !mountMap()) leave(*game,false,nil); }];
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
        if (a->checkpoint || a->revealTitle[0]) {
            busy=true;
            map::present(r,mapID,true,false,false);
            chrome::present(r,visit,chrome::Face::Map,false);
            BOOL shown;
            if (a->checkpoint) {
                shown=[actions checkpoint:a resume:^(NSDictionary *record){
                    if (!applyCheckpoint || !applyCheckpoint(record)) presentMap(*game);
                } leave:^{ if (!leave(*game,gated,nil)) presentMap(*game); }];
            } else {
                NSDictionary *card = a->song>0 && NSUInteger(a->song)<=program.order.count ? program.bySong[program.order[a->song-1]] : nil;
                shown=[actions reveal:a fromNode:index completion:^(PMNativeRevealChoice choice){
                    if (!presentMap(*game) || !card || choice==PMNativeRevealContinue) return;
                    NSDictionary *e=entry(card);
                    if (choice==PMNativeRevealStart && e && leave(*game,false,@{@"detail":card,@"entry":e})) return;
                    showDetail(*game,card);
                }];
            }
            if (!shown) { PMDiagnosticsWrite("Native chapter action could not be presented"); presentMap(r); }
            return;
        }
        if (a->challenge>0 && NSUInteger(a->challenge)<=program.challengeRows.count) { showDetail(r,program.challengeRows[a->challenge-1]); return; }
        if (a->song>0 && NSUInteger(a->song)<=program.order.count) { showDetail(r,program.bySong[program.order[a->song-1]]); return; }
        if (a->dest>=0) map::displayPage(r,mapID,a->dest);
        else if (a->element>=0) map::setElement(r,mapID,a->element,a->visible);
    }];
}
void arrived(Runtime &r,uint64_t token,scene::Route,P root){
 if(mode!=Mode::entering||token!=visit)return;
 if(!root||!chrome::open(r,visit,program.nativeChapter==8?scene::Route::C8:scene::Route::C9,root,chromeView)){if(!leave(r,false,nil)){clearScene(r);mode=Mode::idle;}return;}
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
 if (!mountMap()) { leave(r,false,nil); return; }
 applyCheckpoint=^BOOL(NSDictionary *record){
     if (visit!=token || generation!=epoch || mode!=Mode::map || ![record[@"chapter"] isEqual:chapter] ||
         ![record[@"scriptHash"] isEqual:program.scriptHash]) return NO;
     id page=record[@"page"];
     if (page) {
         NSUInteger index=[page isKindOfClass:NSNumber.class] ? [page unsignedIntegerValue] : [program.screens indexOfObject:page];
         return index<program.screens.count && map::displayPage(*game,mapID,(int)index) && presentMap(*game);
     }
     NSString *sid=record[@"songID"];
     NSDictionary *card=sid ? program.bySong[sid] : nil;
     if (!card) return NO;
     NSMutableDictionary *e=[@{@"songID":sid} mutableCopy];
     if (record[@"difficulty"]) e[@"difficulty"]=record[@"difficulty"];
     return leave(*game,false,@{@"detail":card,@"entry":e});
 };
 NSDictionary *record=PMChapterOSTakeCheckpoint(chapter);
 if (record) {
     BOOL applied=applyCheckpoint(record);
     PMOSClearCheckpoint(record[@"token"]);
     if (!applied) PMDiagnosticsWrite("Native chapter checkpoint destination changed or unavailable");
     if (mode!=Mode::map) return;
 }
 clockSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
 dispatch_source_set_timer(clockSource,DISPATCH_TIME_NOW,NSEC_PER_SEC/30,NSEC_PER_MSEC*3);
 dispatch_source_set_event_handler(clockSource,^{if(visit==token && mode==Mode::map)map::tick(*game,mapID);});dispatch_resume(clockSource);
}
void enter(Runtime &r){if(mode!=Mode::list||!selector||revision!=PMContentStore.shared.revision)return;
 NSMutableOrderedSet *targets=[NSMutableOrderedSet orderedSet];
 if (program.nodes.count) {
     // A Lua callback may return a song that has no static map node.
     for (NSString *sid in program.order) [targets addObjectsFromArray:options(program.bySong[sid])];
     for (NSUInteger i=0; i<program.challengeRows.count; ++i)
         if (program.page->challenges[i].state!=PMOSChallengeLocked)
             [targets addObjectsFromArray:options(program.challengeRows[i])];
 } else {
     for (NSDictionary *card in program.cards) if (![card[@"lockedChallenge"] boolValue])
         [targets addObjectsFromArray:options(card[@"challengeDetail"]?:card)];
 }
 NSArray *entries=targets.array;
 if(entries.count&&!rows::prepare(r,selector,chapter,entries))return;
 mode=Mode::entering;visit=scene::enter(r,program.nativeChapter==8?scene::Route::C8:scene::Route::C9,arrived);
 if(!visit){mode=Mode::list;rows::release();PMDiagnosticsWrite("Native chapter scene unavailable; check packaged scene resources");}
}
bool startSelection(NSDictionary *launch,PMStoryStartSong start){
 NSDictionary *card=launch[@"detail"],*e=launch[@"entry"];NSString *key=chapter;
 if(card[@"secretCourse"]){NSInteger tier=[card[@"lifeTier"] integerValue];return PMChapterStartSecretCourseWithPauseLock(key,card[@"challengeID"],card[@"secretCourse"],tier<0?lifeTier:tier,[card[@"noPause"] boolValue]);}
 if([card[@"replaySongs"] count])return start(e[@"songID"],e[@"difficulty"],^BOOL(NSString *g,int s,NSString *idValue){return PMDoorArmReplay(g,s,idValue);});
 if(!card[@"challengeID"])return start(e[@"songID"],e[@"difficulty"],nil);
 return start(e[@"songID"],e[@"difficulty"],^BOOL(NSString *g,int s,NSString *idValue){if(!PMDoorArm(key,card[@"challengeID"],g,s,idValue,[card[@"hp"] doubleValue],card[@"delta"]))return NO;
 if(!PMDoorSetPendingNoPause([card[@"noPause"] boolValue])||!PMStorySequenceArm(key,card[@"nextSongs"])){PMDoorCancelPending();return NO;}PMStoryCueArm(card[@"cues"]);return YES;});
}
}
void ready(Runtime &r,P owner,NSString *key,PMStoryStartSong start){
 bool returning=mode==Mode::returning&&[chapter isEqual:key]&&reuseList;NSDictionary *launch=returning?pendingStart:nil;bool back=returning&&returnBack;
 pendingStart=nil;returnBack=false;reuseList=false;selector=owner;game=&r;chapter=[key copy];uint64_t epoch=++generation;mode=Mode::loading;
 if(back){mode=Mode::idle;r.call(owner,"Back");return;}if(launch&&revision==PMContentStore.shared.revision&&startSelection(launch,start))return;
 [PMNativeOSProgram loadChapter:key completion:^(PMNativeOSProgram *p,NSError *err){if(epoch!=generation||selector!=owner)return;
  if(!p){mode=Mode::idle;PMDiagnosticsWrite(err.localizedDescription.UTF8String);return;}program=p;revision=PMContentStore.shared.revision;lifeTier=p.selectedLifeTier;gated=p.listSwitchHidden;mode=Mode::list;
  if(toggle::bind(*game,owner,key.UTF8String))toggle::show(*game,gated?toggle::Face::Hidden:toggle::Face::List,!gated);
  if(!returning&&(gated||!p.listFirst))enter(*game);
 }];
}
void detach(Runtime &r){selector=nullptr;toggle::release(r);if(mode==Mode::entering||mode==Mode::returning||mode==Mode::map||mode==Mode::detail)return;++generation;program=nil;mode=Mode::idle;}
bool transitioning(){return mode==Mode::entering;}
bool press(Runtime &r,P b){
 if(mode==Mode::idle||mode==Mode::loading)return false;
 if(mode==Mode::list){auto intent=toggle::press(r,b);if(intent==toggle::Press::OpenOS)enter(r);return intent!=toggle::Press::Pass;}
 if(mode==Mode::entering||mode==Mode::returning)return true;
 if(busy)return true;
 if(mode==Mode::map && map::press(r,b))return true;
 auto action=chrome::press(r,b);switch(action.intent){
 case chrome::Intent::Back:if(mode==Mode::detail)closePanel(r);else leave(r,true,nil);break;
 case chrome::Intent::List:if(!gated)leave(r,false,nil);break;
 case chrome::Intent::Start:if(detail&&selected)leave(r,false,@{@"detail":detail,@"entry":selected});break;
 case chrome::Intent::Slot:for(NSDictionary *e in choices){rows::Row row;if(rowFor(e,row)&&row.slot==action.slot&&panel::update(r,detailID,row.row,row.slot,row.cover)){selected=e;chrome::present(r,visit,chrome::Face::Detail,true,allowedSlots());break;}}break;
 default:break;
 }return true;
}
}
