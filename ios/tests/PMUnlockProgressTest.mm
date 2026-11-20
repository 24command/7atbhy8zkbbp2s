#import <Foundation/Foundation.h>
#import "../PhiMod/Sources/PMUnlockProgress.h"
#include <cassert>
#import "../PhiMod/Sources/PMUnlockRules.h"
int main(){@autoreleasepool{
 assert(PMNormalizeUnlockRule(NSNull.null)==nil);
 id compatible=PMNormalizeUnlockRule(@{@"enabled":@"true",@"mode":NSNull.null,@"animation":NSNull.null,@"chain":NSNull.null,@"conditions":@[@{@"type":@"score",@"ref":@"pm_dependency",@"value":@"700000",@"slot":@"2"}]});
 assert(PMUnlockValidationError(compatible)==nil);
 assert([compatible[@"enabled"] boolValue]&&[compatible[@"conditions"][0][@"value"] intValue]==700000);
 assert(PMUnlockValidationError(PMNormalizeUnlockRule(@{@"enabled":@YES,@"conditions":@[@{@"type":@"unknown",@"ref":@"pm_dep"}]}))!=nil);
 assert(PMUnlockValidationError(PMNormalizeUnlockRule(@"broken"))!=nil);

 // An imported SP chart and the official IN chart persist under distinct keys.
 NSDictionary*extra=@{@"id":@"custom-sp",@"groupId":@"official",@"level":@"SP"};
 NSDictionary*officialSong=@{@"songsId":@"official",@"difficulty":@[@0,@0,@12,@0]};
 NSArray*mixed=PMUnlockRecordCandidates(@[extra],@"official",officialSong,-1,false);
 assert(mixed.count==2 && [mixed containsObject:extra]);
 NSDictionary*nativeIN=@{@"id":@"official",@"level":@"IN"};
 assert([mixed containsObject:nativeIN]);
 assert([PMUnlockRecordCandidates(@[extra],@"custom-sp",nil,-1,false) isEqual:@[extra]]);
 assert([PMUnlockRecordCandidates(@[extra],@"official",nil,-1,false) isEqual:@[extra]]);
 NSDictionary*inChart=@{@"id":@"root",@"level":@"IN"};
 NSDictionary*atChart=@{@"id":@"variant",@"groupId":@"root",@"level":@"AT",@"targetChapter":@"destination"};
 NSArray*merged=@[atChart,inChart]; // Exact match must win regardless of import order.
 assert([PMUnlockRecordCandidates(merged,@"root",nil,-1,false) isEqual:@[inChart]]);
 assert([PMUnlockRecordCandidates(merged,@"root",nil,2,false) isEqual:@[inChart]]);
 assert([PMUnlockRecordCandidates(merged,@"root",nil,3,false) isEqual:@[atChart]]);
 assert(!PMUnlockRecordCandidates(merged,@"root",nil,1,false).count);
 assert(!PMUnlockRecordCandidates(@[atChart],@"variant",nil,2,false).count);
 assert([PMUnlockRecordCandidates(merged,@"root",nil,-1,true) isEqual:merged]);
 assert(!PMUnlockRecordCandidates(nil,@"official",officialSong,3,true).count);

 NSDictionary*entities=@{@"root":inChart,@"variant":atChart};
 NSDictionary*db=@{@"songs":merged,@"chapters":@[@{@"id":@"destination",@"songs":@[@"root"]}],
                    @"chapterOverrides":@{@"destination":@{@"addedSongs":@[@"variant"]}},
                    @"officialMoves":@{@"official":@"destination"}};
 NSDictionary*official=@{@"chapters":@[@{@"chapterCode":@"origin",@"songInfo":@{@"songs":@[@{@"songsId":@"official"}]}}]};
 __block int checks=0;
 assert(PMUnlockChapterPass(db,official,@"destination",entities,^bool(NSString*group){
  ++checks;
  if([group isEqual:@"official"])return true;
  return [PMUnlockRecordCandidates(merged,group,nil,2,true) isEqual:@[inChart]]==YES;
 }));
 assert(checks==2); // root + variant count once, moved official counts once.
 assert(!PMUnlockChapterPass(db,official,@"origin",entities,^bool(NSString*){return true;}));
 assert(!PMUnlockChapterPass(db,official,@"destination",entities,^bool(NSString*group){
  return ![group isEqual:@"official"] || PMUnlockRecordCandidates(nil,group,officialSong,3,true).count>0;
 }));
 NSString*root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSFileManager*f=NSFileManager.defaultManager;assert([f createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]);
 NSDictionary*rule=@{@"enabled":@YES,@"mode":@"all",@"conditions":@[@{@"type":@"score",@"ref":@"pm_song",@"value":@700000}]};
 PMUnlockProgress*p=[[PMUnlockProgress alloc]initWithRoot:root];assert(![p isOpen:@"pm_chapter" rule:rule]);NSError*error=nil;
 assert([p open:@"pm_chapter" rule:rule error:&error]);assert(!error);assert(![p isSeen:@"pm_chapter" rule:rule]);
 p=[[PMUnlockProgress alloc]initWithRoot:root];assert([p isOpen:@"pm_chapter" rule:rule]);
 assert(![p seen:@"pm_chapter" signature:@"stale" error:nil]);
 assert([p seen:@"pm_chapter" signature:PMUnlockSignature(rule) error:&error]);
 p=[[PMUnlockProgress alloc]initWithRoot:root];assert([p isSeen:@"pm_chapter" rule:rule]);
 NSMutableDictionary*media=[rule mutableCopy];media[@"animation"]=@"unlock-other.gif";assert([PMUnlockSignature(media) isEqualToString:PMUnlockSignature(rule)]);
 NSDictionary*changed=@{@"enabled":@YES,@"conditions":@[@{@"type":@"score",@"ref":@"pm_song",@"value":@900000}]};assert(![p isOpen:@"pm_chapter" rule:changed]);
 [@"broken json" writeToFile:[root stringByAppendingPathComponent:@"unlock-progress.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];p=[[PMUnlockProgress alloc]initWithRoot:root];assert([p isOpen:@"pm_chapter" rule:rule]);assert(![p isSeen:@"pm_chapter" rule:rule]);
 assert([p open:@"pm_chapter" rule:changed error:&error]);assert([p isOpen:@"pm_chapter" rule:changed]);assert(![p isSeen:@"pm_chapter" rule:changed]);
 // Equal rules/media in a merged group must still use independent entity IDs.
 assert([p open:@"merged-in" rule:rule error:&error]);
 assert(![p isOpen:@"merged-at" rule:rule]);
 assert([p open:@"merged-at" rule:rule error:&error]);
 assert([p seen:@"merged-in" signature:PMUnlockSignature(rule) error:&error]);
 assert(![p isSeen:@"merged-at" rule:rule]);
 [f removeItemAtPath:root error:nil];puts("PASS unlock progress persistence, semantic changes, stale completion and backup recovery");
}}
