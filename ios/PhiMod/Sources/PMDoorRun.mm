#import "PMDoorRun.h"
#ifdef PMDOOR_RUN_HOST_TEST
extern NSString *PMDoorRunTestRoot(void);
#else
#import "PMContentStore.h"
#endif
#import "PMDiagnostics.h"
#import "PMOSAuthorProgress.h"
#include <climits>

namespace {
NSString *progressRoot() {
#ifdef PMDOOR_RUN_HOST_TEST
 return PMDoorRunTestRoot();
#else
 return PMContentStore.shared.root;
#endif
}
// Game and selector calls are on Unity's main thread. Disk writes use a serial worker.
NSDictionary *pending, *playing;
dispatch_queue_t writes(){
 static dispatch_queue_t queue; static dispatch_once_t once;
 dispatch_once(&once, ^{queue=dispatch_queue_create("PhiMod.DoorProgress", DISPATCH_QUEUE_SERIAL);});return queue;
}
}
BOOL PMDoorArm(NSString *chapter,NSString *door,NSString *group,int slot,NSString *chart,double hp,NSArray<NSNumber*> *delta){
 if(!chapter.length||!door.length||!group.length||!chart.length||slot<0||slot>3||delta.count!=4||!(hp>=1&&hp<=10000)||playing)return NO;
 for(NSNumber *number in delta){double value=number.doubleValue;if(!(value>=-10000&&value<=10000))return NO;}
 pending=@{@"chapter":chapter,@"door":door,@"group":group,@"slot":@(slot),@"chart":chart,@"hp":@(hp),@"delta":[delta copy]};return YES;
}
BOOL PMDoorBeginExactTrack(NSString *group,int slot,NSString *chart,double *hp,double delta[4]){
 NSDictionary *candidate=pending;pending=nil;playing=nil;
 if(!hp||!delta||![candidate[@"group"] isEqual:group]||slot!=[candidate[@"slot"] intValue]||![candidate[@"chart"] isEqual:chart])return NO;
 playing=candidate;*hp=[candidate[@"hp"] doubleValue];for(int i=0;i<4;++i)delta[i]=[candidate[@"delta"][i] doubleValue];return YES;
}
BOOL PMDoorBeginTrack(NSString *group,int slot,double *hp,double delta[4]){return PMDoorBeginExactTrack(group,slot,group,hp,delta);}
BOOL PMDoorActive(){return playing!=nil;}
void PMDoorAbandon(){pending=nil;playing=nil;}
void PMDoorCancelPending(){pending=nil;}
void PMDoorFinish(BOOL clear){
 NSDictionary *run=playing;playing=nil;if(!run)return;
 dispatch_async(writes(),^{@autoreleasepool{
  PMOSAuthorProgress *store=[[PMOSAuthorProgress alloc]initWithRoot:progressRoot() chapter:run[@"chapter"]];
  NSString *key=[NSString stringWithFormat:@"door.%@.%@",run[@"door"],clear?@"clear":@"fail"];
  int value=0;BOOL ok=[store readKey:key value:&value];
  if(ok){int next=clear?1:(value>=INT_MAX?INT_MAX:MAX(value,0)+1);ok=[store commitValues:@{key:@(next)}];}
  if(!ok)PMDiagnosticsWrite("Chapter OS door outcome could not be saved");
 }});
}
void PMDoorProgressBarrier(){dispatch_sync(writes(),^{});}
