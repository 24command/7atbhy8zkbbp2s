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
 [f removeItemAtPath:root error:nil];puts("PASS unlock progress persistence, semantic changes, stale completion and backup recovery");
}}
