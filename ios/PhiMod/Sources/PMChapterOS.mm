#import "PMChapterOS.h"
#import "PMChapterScript.h"
#import "PMContentStore.h"
#import "PMDiagnostics.h"
#import "PMOSCheckpoint.h"
#import "PMStorySequence.h"

static NSDictionary *bootTarget;
static NSString *attemptedToken;

void PMChapterOSResumeAfterBoot(BOOL (^available)(NSString *), BOOL (^navigate)(NSString *)) {
 if(PMStorySequenceRoute(available,navigate))return;
 NSDictionary *record=PMOSPendingCheckpoint();
 if(!record||[attemptedToken isEqual:record[@"token"]])return;
 NSString *chapter=record[@"chapter"];
 attemptedToken=record[@"token"];
 if(![PMContentStore.shared hasChapterScript:chapter]){
  PMOSClearCheckpoint(attemptedToken);
  PMDiagnosticsWrite("Chapter OS resume discarded: chapter or script removed");return;
 }
 NSString *path=[[PMContentStore.shared asset:chapter] stringByAppendingPathComponent:PMChapterScriptName];
 NSData *source=PMChapterScriptData([NSURL fileURLWithPath:path],nil);
 if(!source||![record[@"scriptHash"] isEqual:PMChapterScriptDigest(source)]){
  PMOSClearCheckpoint(attemptedToken);
  PMDiagnosticsWrite("Chapter OS resume discarded: script changed");return;
 }
 if(!available(chapter)){PMDiagnosticsWrite("Chapter OS resume deferred: chapter unavailable");return;}
 bootTarget=record;
 if(!navigate(chapter)){bootTarget=nil;PMDiagnosticsWrite("Chapter OS resume deferred: navigation unavailable");}
}
BOOL PMChapterOSHasRoutedCheckpoint(NSString *chapter) {
 return NSThread.isMainThread && [bootTarget[@"chapter"] isEqual:chapter];
}
NSDictionary *PMChapterOSTakeCheckpoint(NSString *chapter) {
 if(!PMChapterOSHasRoutedCheckpoint(chapter))return nil;
 NSDictionary *record=bootTarget;
 bootTarget=nil;
 return record;
}
