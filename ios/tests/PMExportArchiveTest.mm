#import <Foundation/Foundation.h>
#import "../PhiMod/Sources/PMArchive.h"
#import "../PhiMod/Sources/PMFileDigest.h"
#include "../PhiMod/Vendor/miniz/miniz.h"
#import "../PhiMod/Sources/PMChapterExportPlan.h"
#include <cassert>
#include <cstdio>
static void testChapterScope() {
 NSDictionary *root = @{@"id":@"main", @"songs":@[@"start", @"native"]};
 NSDictionary *foreign = @{@"id":@"foreign", @"songs":@[@"hard", @"easy", @"unrelated"]};
 NSDictionary *required = @{@"id":@"required", @"songs":@[@"last", @"bonus"]};
 NSDictionary *start = @{@"id":@"start", @"coverSwitch":@{@"ref":@"group"}};
 NSDictionary *hard = @{@"id":@"hard", @"groupId":@"group", @"targetChapter":@"foreign",
                        @"unlock":@{@"chain":@{@"enabled":@YES, @"song":@"last"}}};
 NSDictionary *easy = @{@"id":@"easy", @"groupId":@"group", @"targetChapter":@"foreign"};
 NSMutableDictionary *last = [@{@"id":@"last", @"targetChapter":@"required"} mutableCopy];
 NSDictionary *db = @{@"chapters":@[root,foreign,required], @"songs":@[start,hard,easy,last,@{@"id":@"unrelated"},@{@"id":@"bonus"}]};
 NSDictionary *plan = PMChapterExportPlan(db,root,@"loose");
 assert(([plan[@"chapterIDs"] isEqual:@[@"main",@"loose"]]));
 assert(([plan[@"orders"][@"main"] isEqual:@[@"start",@"native"]]));
 assert(([plan[@"orders"][@"loose"] isEqual:@[@"hard",@"easy",@"last"]]));
 assert(([plan[@"locations"] isEqual:@{@"start":@"main",@"hard":@"loose",@"easy":@"loose",@"last":@"loose"}]));
 assert([plan[@"includedSongs"] count] == 4 && [plan[@"officialIDs"] isEqual:@[@"native"]]);
 // Discover a chapter through a song it contains. Import needs one owner for that chart.
 last[@"unlock"] = @{@"conditions":@[@{@"type":@"chapter", @"ref":@"required"}]};
 plan = PMChapterExportPlan(db,root,@"loose");
 assert(([plan[@"chapterIDs"] isEqual:@[@"main",@"required",@"loose"]]));
 assert(([plan[@"orders"][@"required"] isEqual:@[@"last",@"bonus"]]));
 assert(([plan[@"orders"][@"loose"] isEqual:@[@"hard",@"easy"]]));
 assert([plan[@"locations"][@"last"] isEqual:@"required"]);
 assert(![plan[@"includedSongs"] containsObject:@"unrelated"]);
}
int main(){@autoreleasepool{
 testChapterScope();
 NSFileManager*f=NSFileManager.defaultManager;NSError*error=nil;
 NSString*root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 NSString*source=[root stringByAppendingPathComponent:@"source"],*out=[root stringByAppendingPathComponent:@"export.zip"];
 assert([f createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:&error]);
 [@"{\"songs\":[]}" writeToFile:[source stringByAppendingPathComponent:@"chapter.json"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
 NSString*media=[source stringByAppendingPathComponent:@"music.ogg"];FILE*fp=fopen(media.fileSystemRepresentation,"wb");assert(fp);
 unsigned char chunk[65536];for(size_t i=0;i<sizeof(chunk);i++)chunk[i]=(unsigned char)(i*31);
 CC_SHA256_CTX expected;CC_SHA256_Init(&expected);
 for(int i=0;i<512;i++){assert(fwrite(chunk,1,sizeof(chunk),fp)==sizeof(chunk));CC_SHA256_Update(&expected,chunk,sizeof(chunk));}assert(fclose(fp)==0);
 unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(bytes,&expected);NSMutableString*hash=[NSMutableString new];for(unsigned char b:bytes)[hash appendFormat:@"%02x",b];
 assert([PMFileSHA256(media)isEqualToString:hash]);
 assert(PMFileSHA256([source stringByAppendingPathComponent:@"missing"])==nil);
 assert(PMCreateArchive(source,out,&error));
 mz_zip_archive z{};assert(mz_zip_reader_init_file(&z,out.fileSystemRepresentation,0));mz_zip_archive_file_stat st{};
 assert(mz_zip_reader_file_stat(&z,0,&st));assert(strcmp(st.m_filename,"chapter.json")==0);
 int n=mz_zip_reader_locate_file(&z,"music.ogg",nullptr,0);assert(n>=0);assert(mz_zip_reader_file_stat(&z,n,&st));assert(st.m_method==0);assert(st.m_uncomp_size==32ull*1024*1024);mz_zip_reader_end(&z);
 NSString*target=[root stringByAppendingPathComponent:@"roundtrip"];assert(PMExtractArchive(out,target,&error).count==2);assert([PMFileSHA256([target stringByAppendingPathComponent:@"music.ogg"])isEqualToString:hash]);
 // The coordinated extractor reports verified completion for this URL alone.
 NSURL *selectedURL=[NSURL fileURLWithPath:out];
 __block unsigned long long last=0, expected=0; __block bool started=false, completed=false;
 id observer=[NSNotificationCenter.defaultCenter addObserverForName:@"PMChartImportBytes" object:selectedURL queue:nil usingBlock:^(NSNotification *note){
  auto done=[note.userInfo[@"done"] unsignedLongLongValue], total=[note.userInfo[@"total"] unsignedLongLongValue];
  assert(total>0 && done<=total && done>=last && !completed);
  if(!started){assert(done==0);expected=total;started=true;}
  assert(total==expected);last=done;completed=done==total;
 }];
 assert(PMExtractArchiveURL(selectedURL,[root stringByAppendingPathComponent:@"progress"],&error).count==2);
 [NSNotificationCenter.defaultCenter removeObserver:observer];assert(started && completed && expected>32ull*1024*1024);
 NSError *limitError=nil; NSString *limited=[root stringByAppendingPathComponent:@"limited"];
 assert(!PMExtractArchiveLimited(out,limited,10,32ull*1024*1024,32ull*1024*1024,&limitError));
 assert(limitError && ![f fileExistsAtPath:limited]);
 // A bad member must not hide its error or poison the next member of a batch.
 NSString*bad=[root stringByAppendingPathComponent:@"broken.zip"];assert([@"not a zip" writeToFile:bad atomically:YES encoding:NSUTF8StringEncoding error:&error]);
 NSUInteger success=0,failure=0;NSArray*batch=@[out,bad,out];
 for(NSUInteger i=0;i<batch.count;++i){@autoreleasepool{NSError*itemError=nil;NSString*dest=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"batch-%lu",(unsigned long)i]];NSArray*files=PMExtractArchiveURL([NSURL fileURLWithPath:batch[i]],dest,&itemError);if(files){++success;assert(files.count==2&&itemError==nil);assert([PMFileSHA256([dest stringByAppendingPathComponent:@"music.ogg"])isEqualToString:hash]);}else{++failure;assert(itemError&&[itemError.domain isEqualToString:@"PhiMod.Archive"]);assert(![f fileExistsAtPath:dest]);}}}
 assert(success==2&&failure==1);
 // Re-export replaces the finalized output, but a failure preserves that last good file.
 assert(PMCreateArchive(source,out,&error));NSString*before=PMFileSHA256(out);
 assert([f createSymbolicLinkAtPath:[source stringByAppendingPathComponent:@"bad-link"] withDestinationPath:media error:&error]);error=nil;
 assert(!PMCreateArchive(source,out,&error));assert(error);assert([PMFileSHA256(out)isEqualToString:before]);
 for(NSString*name in [f contentsOfDirectoryAtPath:root error:nil])assert(![name hasSuffix:@".partial"]);
 assert([f removeItemAtPath:root error:&error]);puts("Export archive streaming/roundtrip/failure cleanup passed");
}return 0;}
