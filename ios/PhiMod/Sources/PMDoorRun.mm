#import "PMDoorRun.h"
#import "PMStorySequence.hpp"
#ifdef PMDOOR_RUN_HOST_TEST
extern NSString *PMDoorRunTestRoot(void);
#else
#import "PMContentStore.h"
#import "PMSettings.h"
#include "PMOptions.hpp"
#endif
#import "PMDiagnostics.h"
#import "PMOSAuthorProgress.h"
#include <climits>
#include "../Core/PMChapterLife.inc"

namespace {
NSString *progressRoot() {
#ifdef PMDOOR_RUN_HOST_TEST
 return PMDoorRunTestRoot();
#else
 return PMContentStore.shared.root;
#endif
}
// Game and selector calls are on Unity's main thread. Disk writes use a serial worker.
NSDictionary *pending, *playing, *replay;
dispatch_queue_t writes(){
 static dispatch_queue_t queue; static dispatch_once_t once;
 dispatch_once(&once, ^{queue=dispatch_queue_create("PhiMod.DoorProgress", DISPATCH_QUEUE_SERIAL);});return queue;
}
}
namespace pmstorysequence {
Handoff<NSDictionary *> handoff;
BOOL attachToPending(NSString *chapter, NSArray<NSDictionary *> *songs) {
 if (!pending || ![pending[@"chapter"] isEqual:chapter]) return NO;
 NSMutableDictionary *run = [pending mutableCopy];
 run[@"nextSongs"] = songs;
 pending = [run copy];
 return YES;
}
}
BOOL PMDoorArm(NSString *chapter,NSString *door,NSString *group,int slot,NSString *chart,double hp,NSArray<NSNumber*> *delta){
 if(!chapter.length||!door.length||!group.length||!chart.length||slot<0||slot>3||delta.count!=4||!(hp>=1&&hp<=10000)||playing)return NO;
 for(NSNumber *number in delta){double value=number.doubleValue;if(!(value>=-10000&&value<=10000))return NO;}
 pmstorysequence::handoff.take();
 replay=nil;
 pending=@{@"chapter":chapter,@"door":door,@"group":group,@"slot":@(slot),@"chart":chart,@"hp":@(hp),@"delta":[delta copy]};return YES;
}
BOOL PMDoorBeginExactTrack(NSString *group,int slot,NSString *chart,double *hp,double delta[4]){
 pmstorysequence::handoff.take(); // A replay or unrelated level cannot claim an older clear.
 NSDictionary *candidate=pending;pending=nil;playing=nil;
 if(!hp||!delta||![candidate[@"group"] isEqual:group]||slot!=[candidate[@"slot"] intValue]||![candidate[@"chart"] isEqual:chart])return NO;
 playing=candidate;*hp=[candidate[@"hp"] doubleValue];for(int i=0;i<4;++i)delta[i]=[candidate[@"delta"][i] doubleValue];return YES;
}
BOOL PMDoorBeginTrack(NSString *group,int slot,double *hp,double delta[4]){return PMDoorBeginExactTrack(group,slot,group,hp,delta);}
BOOL PMDoorSetPendingNoPause(BOOL value){
 if(!pending)return NO;
#ifndef PMDOOR_RUN_HOST_TEST
 // Level.Awake excludes assisted attempts. Reject this launch before NormalStart
 // so it cannot silently start a regular, pausable song instead of the challenge.
 if(value && !PMReadOptions(PMSettings.shared.snapshot).allowsDoorChallenge()){
  PMDiagnosticsWrite("Chapter challenge requires manual play at normal speed outside practice mode");
  return NO;
 }
#endif
 NSMutableDictionary *run=[pending mutableCopy];run[@"noPause"]=@(value);pending=[run copy];return YES;
}
BOOL PMDoorPlayingNoPause(){return [playing[@"noPause"] boolValue];}
BOOL PMDoorArmReplay(NSString *group,int slot,NSString *chart){
 if(pending||playing||replay||!group.length||!chart.length||slot<0||slot>3)return NO;
 pmstorysequence::handoff.take();replay=@{@"group":[group copy],@"slot":@(slot),@"chart":[chart copy]};return YES;
}
BOOL PMDoorReplayPending(){return replay!=nil;}
BOOL PMDoorConsumeReplay(NSString *group,int slot,NSString *chart){
 NSDictionary *request=replay;replay=nil;
 return [request[@"group"] isEqual:group]&&slot==[request[@"slot"] intValue]&&[request[@"chart"] isEqual:chart];
}
BOOL PMDoorActive(){return playing!=nil;}
void PMDoorAbandon(){replay=nil;pending=nil;playing=nil;pmstorysequence::handoff.take();}
void PMDoorCancelPending(){pending=nil;replay=nil;}
static void enqueueOutcome(NSString *chapter, NSString *door, int tier, BOOL clear);
void PMDoorFinish(BOOL clear){
 NSDictionary *run=playing;playing=nil;if(!run)return;
 // Only the final clear unlocks the door. A failure on any leg is recorded once.
 if(clear && [run[@"nextSongs"] count]){pmstorysequence::handoff.issue(run);return;}
 enqueueOutcome(run[@"chapter"],run[@"door"],-1,clear);
}
void PMDoorRecordCourseOutcome(NSString *chapter,NSString *door,int launchedTier,BOOL clear){
 if(launchedTier<0||launchedTier>PMChapterLifeMax)return;
 enqueueOutcome(chapter,door,launchedTier,clear);
}
static void enqueueOutcome(NSString *chapter,NSString *door,int tier,BOOL clear){
 dispatch_async(writes(),^{@autoreleasepool{
  PMOSAuthorProgress *store=[[PMOSAuthorProgress alloc]initWithRoot:progressRoot() chapter:chapter];
  NSString *key=[NSString stringWithFormat:@"door.%@.%@",door,clear?@"clear":@"fail"];
  BOOL ok=[store updateValues:^NSDictionary *(NSDictionary *current){
   int value=[current[key] intValue];
   int next=clear?1:(value>=INT_MAX?INT_MAX:MAX(value,0)+1);
   NSMutableDictionary *updates=[@{key:@(next)} mutableCopy];
   // A first-clear event is separate from permanent clear state. Old saves with
   // clear=1 do not retroactively queue a new return scene after a script update.
   if(clear && value<=0)updates[[NSString stringWithFormat:@"door.%@.new",door]]=@1;
   if(tier>=0){
    PMChapterLifeState life=PMChapterLifeRead([current[@PMChapterLifeCeilingKey] intValue],
                                             [current[@PMChapterLifeChoiceKey] intValue]);
    if(PMChapterLifeApplyOutcome(&life,tier,clear))
     [updates addEntriesFromDictionary:@{@PMChapterLifeCeilingKey:@(life.ceiling), @PMChapterLifeChoiceKey:@(life.selected+1)}];
   }
   return updates;
  }];
  if(!ok)PMDiagnosticsWrite("Chapter OS door outcome could not be saved");
 }});
}
void PMDoorProgressBarrier(){dispatch_sync(writes(),^{});}
