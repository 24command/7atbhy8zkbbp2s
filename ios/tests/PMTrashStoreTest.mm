#import <Foundation/Foundation.h>
#include <cassert>
static NSError*err(NSString*s){return [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:s}];}
static BOOL safeID(NSString*s){return [s isKindOfClass:NSString.class]&&[s hasPrefix:@"pm_"]&&![s containsString:@"/"]&&![s containsString:@".."];}
static id clone(id object){return [NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:object options:0 error:nil] options:NSJSONReadingMutableContainers error:nil];}
static BOOL writeJSON(id object,NSString*path,NSError**error){NSData*d=[NSJSONSerialization dataWithJSONObject:object options:0 error:error];return d&&[d writeToFile:path options:NSDataWritingAtomic error:error];}
@interface TrashTest:NSObject
@property(nonatomic,strong)NSString*root;
@property(nonatomic,strong)NSMutableDictionary*db;
@property(nonatomic,assign)BOOL failCommit;
@end
@implementation TrashTest
- (NSDictionary*)snapshot{return clone(self.db);}
- (NSString*)asset:(NSString*)id{return [[self.root stringByAppendingPathComponent:@"assets"]stringByAppendingPathComponent:id];}
- (BOOL)commit:(NSDictionary*)db error:(NSError**)error{if(self.failCommit){if(error)*error=err(@"forced failure");return NO;}self.db=clone(db);return YES;}
#include "../PhiMod/Sources/PMTrashStore.inc"
@end
int main(){@autoreleasepool{
 NSFileManager*f=NSFileManager.defaultManager;TrashTest*s=[TrashTest new];s.root=[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError*error=nil;
 for(NSString*name in @[@"assets/pm_a",@"trash",@"exports"] )assert([f createDirectoryAtPath:[s.root stringByAppendingPathComponent:name] withIntermediateDirectories:YES attributes:nil error:&error]);
 s.db=clone(@{@"songs":@[@{@"id":@"pm_a",@"title":@"A",@"targetChapter":@"pm_local",@"level":@"AT"}],@"chapters":@[@{@"id":@"pm_local",@"songs":@[@"pm_a"]}],@"chartSelections":@{@"pm_a@3":@"pm_a"}});
 s.failCommit=YES;assert(![s removeSongs:@[@"pm_a"] error:&error]);assert([f fileExistsAtPath:[s asset:@"pm_a"]]);assert([s.db[@"songs"]count]==1);
 error=nil;s.failCommit=NO;assert([s removeSongs:@[@"pm_a"] error:&error]);assert(![f fileExistsAtPath:[s asset:@"pm_a"]]);assert([s.db[@"songs"]count]==0);
 NSArray*items=[s trashItems];assert(items.count==1&&[items[0][@"restorable"]boolValue]);NSString*token=items[0][@"token"];
 assert([s restoreTrash:token error:&error]);assert([s.db[@"songs"]count]==1);assert([s.db[@"chapters"][0][@"songs"]containsObject:@"pm_a"]);assert([s trashItems].count==0);
 assert([s removeSongs:@[@"pm_a"] error:&error]);token=[s trashItems][0][@"token"];assert([s deleteTrash:token error:&error]);assert([s trashItems].count==0);
 assert(![s deleteTrash:@"../assets" error:&error]);assert([f fileExistsAtPath:[s.root stringByAppendingPathComponent:@"assets"]]);
 NSString*exportPath=[s.root stringByAppendingPathComponent:@"exports/a.zip"],*outside=[s.root stringByAppendingPathComponent:@"keep.zip"];
 [@"x" writeToFile:exportPath atomically:YES encoding:NSUTF8StringEncoding error:nil];[@"x" writeToFile:outside atomically:YES encoding:NSUTF8StringEncoding error:nil];
 [s cleanupExports:@[[NSURL fileURLWithPath:exportPath],[NSURL fileURLWithPath:outside]]];assert(![f fileExistsAtPath:exportPath]&&[f fileExistsAtPath:outside]);
 assert([f removeItemAtPath:s.root error:&error]);puts("PASS trash rollback/restore/permanent delete and scoped export cleanup");
}}
