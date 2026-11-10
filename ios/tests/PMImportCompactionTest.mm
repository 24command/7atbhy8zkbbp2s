#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include <cassert>
static NSError*err(NSString*s){return [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:s}];}
static BOOL writeJSONCompact(id obj,NSString*path,NSError**error){NSData*d=[NSJSONSerialization dataWithJSONObject:obj options:0 error:error];return d&&[d writeToFile:path options:NSDataWritingAtomic error:error];}
static void PMDiagnosticsWrite(const char*){}
#include "../PhiMod/Sources/PMImportCompaction.inc"
int main(){@autoreleasepool{
 NSFileManager*f=NSFileManager.defaultManager;NSString*root=[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSError*error=nil;
 assert([f createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error]);
 for(NSNumber*referenced in @[@NO,@YES]){
  NSString*folder=[root stringByAppendingPathComponent:referenced.boolValue?@"referenced":@"ordinary"];
  assert([f createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]);
  NSDictionary*source=@{@"META":@{@"name":@"Example"},@"judgeLineList":@[]};
  NSData*pretty=[NSJSONSerialization dataWithJSONObject:source options:NSJSONWritingPrettyPrinted error:&error];
  for(NSString*name in @[@"original.json",@"source.rpe.json"])assert([pretty writeToFile:[folder stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error]);
  NSData*audio=[@"same encoded audio" dataUsingEncoding:NSUTF8StringEncoding];
  for(NSString*name in @[@"song.mp3",@"audio.source.mp3"])assert([audio writeToFile:[folder stringByAppendingPathComponent:name] options:NSDataWritingAtomic error:&error]);
  assert(writeJSONCompact(@{@"file":@"audio.source.mp3"},[folder stringByAppendingPathComponent:@"source-audio.json"],&error));
  assert(writeJSONCompact(@{@"asset":@1},[folder stringByAppendingPathComponent:@"unrelated.json"],&error));
  NSDictionary*chart=referenced.boolValue?@{@"pmFormat":@"RPE",@"resource":@"original.json",@"sound":@"song.mp3"}:@{@"pmFormat":@"RPE"};
  NSDictionary*result=compactImportedSong(folder,[folder stringByAppendingPathComponent:@"original.json"],[folder stringByAppendingPathComponent:@"song.mp3"],chart,@{},&error);
  assert(result&&error==nil);assert([result[@"sourceChart"]isEqualToString:@"source.rpe.json"]);assert([result[@"sourceMusic"]isEqualToString:@"audio.source.mp3"]);
  assert([f fileExistsAtPath:[folder stringByAppendingPathComponent:@"original.json"]]==referenced.boolValue);
  assert([f fileExistsAtPath:[folder stringByAppendingPathComponent:@"song.mp3"]]==referenced.boolValue);
  for(NSString*name in @[@"unrelated.json",@"source.rpe.json",@"audio.source.mp3"])assert([f fileExistsAtPath:[folder stringByAppendingPathComponent:name]]);
  result=compactImportedSong(folder,[folder stringByAppendingPathComponent:@"source.rpe.json"],[folder stringByAppendingPathComponent:@"audio.source.mp3"],chart,@{},&error);assert(result);
 }
 assert([f removeItemAtPath:root error:&error]);puts("PASS canonical source retention, duplicate cleanup, referenced assets and repeated import cleanup");
}}
