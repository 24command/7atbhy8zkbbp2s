#import <Foundation/Foundation.h>
#import "../PhiMod/Sources/PMArchive.h"
#import "../PhiMod/Sources/PMFileDigest.h"
#include "../PhiMod/Vendor/miniz/miniz.h"
#import "../PhiMod/Sources/PMChapterExportPlan.h"
#import "../PhiMod/Sources/PMAssetLayout.h"
#import "../PhiMod/Sources/PMChapterScript.h"
#import "../PhiMod/Sources/PMChapterArt.h"
#import "../PhiMod/Sources/PMStockIntroResolver.hpp"
#include <cassert>
#include <cstdio>
static void testChapterScope() {
 NSString *hash=[@"" stringByPaddingToLength:64 withString:@"e" startingAtIndex:0];
 NSDictionary *local=@{@"id":@"pm_local_in",@"level":@"IN",@"scoreIdentity":hash,@"targetChapter":@"pm_main"};
 NSDictionary *copy=@{@"id":@"pm_copy",@"level":@"IN",@"scoreIdentity":hash,@"targetChapter":@"pm_other"};
 NSDictionary *in=@{@"type":@"score",@"ref":@"pm_copy",@"slot":@2,@"value":@700000};
 NSDictionary *out=@{@"type":@"chapter",@"ref":@"pm_other"}, *stock=@{@"type":@"chapter",@"ref":@"Maimai"};
 NSDictionary *rule=@{@"enabled":@YES,@"mode":@"any",@"conditions":@[out,stock,in],@"chain":@{@"enabled":@YES,@"song":@"pm_out",@"slot":@2}};
 NSDictionary *root=@{@"id":@"pm_main",@"songs":@[@"pm_local_in",@"native"],@"unlock":rule,@"coverSwitch":@{@"ref":@"pm_out"}};
 NSDictionary *db=@{@"chapters":@[root,@{@"id":@"pm_other",@"songs":@[@"pm_copy",@"pm_out"]}],@"songs":@[local,copy,@{@"id":@"pm_out",@"groupId":@"pm_local_in",@"targetChapter":@"pm_other"}]};
 NSDictionary *plan=PMChapterExportPlan(db,root);
 assert(([plan[@"order"] isEqual:@[@"pm_local_in",@"native"]]));
 assert(([plan[@"includedSongs"] isEqual:@[@"pm_local_in"]]));
 assert([plan[@"refs"][@"pm_copy"] isEqual:@"pm_local_in"]);
 NSMutableDictionary *output=[root mutableCopy];output[@"unlock"]=[rule mutableCopy];
 PMTrimChapterExportRule(output,plan);
 assert(([output[@"unlock"][@"conditions"] isEqual:@[stock,in]]));
 assert(!output[@"unlock"][@"chain"] && !output[@"coverSwitch"] && [rule[@"conditions"] count]==3);
 output[@"unlock"]=[@{@"enabled":@YES,@"conditions":@[out]} mutableCopy];PMTrimChapterExportRule(output,plan);
 assert(![output[@"unlock"][@"enabled"] boolValue] && !PMUnlockValidationError(output[@"unlock"]));
}
int main(){@autoreleasepool{
 testChapterScope();
 NSFileManager*f=NSFileManager.defaultManager;NSError*error=nil;
 NSString*root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 NSString*source=[root stringByAppendingPathComponent:@"source"],*out=[root stringByAppendingPathComponent:@"export.zip"];
 assert([f createDirectoryAtPath:source withIntermediateDirectories:YES attributes:nil error:&error]);
 // Exercise the resolver with a private fixture, without a game install or save.
 NSString *dataDir=[root stringByAppendingPathComponent:@"Data"], *cache=[root stringByAppendingPathComponent:@"cache"];
 assert([f createDirectoryAtPath:dataDir withIntermediateDirectories:YES attributes:nil error:nil]);
 const PMStockIntro fixture={"@stock/test", "sample.resource", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", 3, 2, 7};
 NSString *sample=[dataDir stringByAppendingPathComponent:@"sample.resource"];
 assert(!PMStockIntroCopy(&fixture,dataDir,cache));
 assert([@"xxabcxx" writeToFile:sample atomically:YES encoding:NSUTF8StringEncoding error:nil]);
 NSString *movie=PMStockIntroCopy(&fixture,dataDir,cache);
 assert([movie.pathExtension isEqual:@"mp4"] && [PMFileSHA256(movie) isEqual:@(fixture.sha256)]);
 assert([movie isEqual:PMStockIntroCopy(&fixture,dataDir,cache)]);
 assert([@"xxxyzxx" writeToFile:sample atomically:YES encoding:NSUTF8StringEncoding error:nil]);
 assert(!PMStockIntroCopy(&fixture,dataDir,cache)); // same size, wrong digest
 assert([f removeItemAtPath:sample error:nil] && [f createSymbolicLinkAtPath:sample withDestinationPath:movie error:nil]);
 assert(!PMStockIntroCopy(&fixture,dataDir,cache));
 [@"{\"songs\":[]}" writeToFile:[source stringByAppendingPathComponent:@"chapter.json"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
 NSString*media=[source stringByAppendingPathComponent:@"music.ogg"];FILE*fp=fopen(media.fileSystemRepresentation,"wb");assert(fp);
 unsigned char chunk[65536];for(size_t i=0;i<sizeof(chunk);i++)chunk[i]=(unsigned char)(i*31);
 CC_SHA256_CTX expected;CC_SHA256_Init(&expected);
 for(int i=0;i<512;i++){assert(fwrite(chunk,1,sizeof(chunk),fp)==sizeof(chunk));CC_SHA256_Update(&expected,chunk,sizeof(chunk));}assert(fclose(fp)==0);
 unsigned char bytes[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(bytes,&expected);NSMutableString*hash=[NSMutableString new];for(unsigned char b:bytes)[hash appendFormat:@"%02x",b];
 assert([PMFileSHA256(media)isEqualToString:hash]);
 assert(PMFileSHA256([source stringByAppendingPathComponent:@"missing"])==nil);
 NSString *old=PMAssetPath(root,nil,@"pm_demo"),*chapter=PMAssetPath(root,@"chapters",@"pm_demo");
 assert([f createDirectoryAtPath:old withIntermediateDirectories:YES attributes:nil error:&error]);
 assert([f createDirectoryAtPath:chapter.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]);
 NSData *script=[@"-- OS\nreturn {}\n" dataUsingEncoding:NSUTF8StringEncoding];
 NSString *installed=[chapter stringByAppendingPathComponent:PMChapterScriptName];
 assert([script writeToFile:[old stringByAppendingPathComponent:PMChapterScriptName] atomically:YES]);
 assert([PMRelocateAsset(root,@"chapters",@"pm_demo") isEqual:chapter] && ![f fileExistsAtPath:old]);
 assert([PMChapterScriptData([NSURL fileURLWithPath:installed],&error) isEqual:script]);
 assert([f createDirectoryAtPath:old withIntermediateDirectories:YES attributes:nil error:&error]);
 NSData *binary=[NSData dataWithBytes:"\033Lua" length:4];NSString *legacy=[old stringByAppendingPathComponent:PMChapterScriptName];
 assert([binary writeToFile:legacy atomically:YES]);assert(!PMChapterScriptData([NSURL fileURLWithPath:legacy],nil));
 assert([PMRelocateAsset(root,@"chapters",@"pm_demo") isEqual:chapter] && [f fileExistsAtPath:legacy]);
 // Seed the installed chapter so export staging must preserve the OS art subtree.
 NSString *artName=@"Panel.png";
 NSString *artPath=PMOSArtPath(chapter,artName);
 assert(artPath);
 assert([f createDirectoryAtPath:artPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error]);
 NSData *art=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNQaPgPAAJjAaB56d6tAAAAAElFTkSuQmCC" options:0];
 assert(art.length && [art writeToFile:artPath atomically:YES]);
 assert([f copyItemAtPath:chapter toPath:[source stringByAppendingPathComponent:@"chapter"] error:&error]);
 assert(PMCreateArchive(source,out,&error));
 mz_zip_archive z{};assert(mz_zip_reader_init_file(&z,out.fileSystemRepresentation,0));mz_zip_archive_file_stat st{};
 assert(mz_zip_reader_file_stat(&z,0,&st));assert(strcmp(st.m_filename,"chapter.json")==0);
 assert(mz_zip_reader_locate_file(&z,"chapter/os-media/Panel.png",nullptr,MZ_ZIP_FLAG_CASE_SENSITIVE)>=0);
 int n=mz_zip_reader_locate_file(&z,"music.ogg",nullptr,0);assert(n>=0);assert(mz_zip_reader_file_stat(&z,n,&st));assert(st.m_method==0);assert(st.m_uncomp_size==32ull*1024*1024);mz_zip_reader_end(&z);
 const NSUInteger expectedFileCount=4; // manifest, music, chapter script and OS art
 NSString*target=[root stringByAppendingPathComponent:@"roundtrip"];assert(PMExtractArchive(out,target,&error).count==expectedFileCount);assert([PMFileSHA256([target stringByAppendingPathComponent:@"music.ogg"])isEqualToString:hash]);
 assert([PMChapterScriptData([NSURL fileURLWithPath:[target stringByAppendingPathComponent:@"chapter/os.lua"]],&error) isEqual:script]);
 NSString *restoredArt=PMOSArtPath([target stringByAppendingPathComponent:@"chapter"],artName);
 assert(restoredArt && [[NSData dataWithContentsOfFile:restoredArt] isEqualToData:art]);
 // The coordinated extractor reports verified completion for this URL alone.
 NSURL *selectedURL=[NSURL fileURLWithPath:out];
 __block unsigned long long last=0, expectedBytes=0; __block bool started=false, completed=false;
 id observer=[NSNotificationCenter.defaultCenter addObserverForName:@"PMChartImportBytes" object:selectedURL queue:nil usingBlock:^(NSNotification *note){
  auto done=[note.userInfo[@"done"] unsignedLongLongValue], total=[note.userInfo[@"total"] unsignedLongLongValue];
  assert(total>0 && done<=total && done>=last && !completed);
  if(!started){assert(done==0);expectedBytes=total;started=true;}
  assert(total==expectedBytes);last=done;completed=done==total;
 }];
 assert(PMExtractArchiveURL(selectedURL,[root stringByAppendingPathComponent:@"progress"],&error).count==expectedFileCount);
 [NSNotificationCenter.defaultCenter removeObserver:observer];assert(started && completed && expectedBytes>32ull*1024*1024);
 NSError *limitError=nil; NSString *limited=[root stringByAppendingPathComponent:@"limited"];
 assert(!PMExtractArchiveLimited(out,limited,10,32ull*1024*1024,32ull*1024*1024,&limitError));
 assert(limitError && ![f fileExistsAtPath:limited]);
 // A bad member must not hide its error or poison the next member of a batch.
 NSString*bad=[root stringByAppendingPathComponent:@"broken.zip"];assert([@"not a zip" writeToFile:bad atomically:YES encoding:NSUTF8StringEncoding error:&error]);
 NSUInteger success=0,failure=0;NSArray*batch=@[out,bad,out];
 for(NSUInteger i=0;i<batch.count;++i){@autoreleasepool{NSError*itemError=nil;NSString*dest=[root stringByAppendingPathComponent:[NSString stringWithFormat:@"batch-%lu",(unsigned long)i]];NSArray*files=PMExtractArchiveURL([NSURL fileURLWithPath:batch[i]],dest,&itemError);if(files){++success;assert(files.count==expectedFileCount&&itemError==nil);assert([PMFileSHA256([dest stringByAppendingPathComponent:@"music.ogg"])isEqualToString:hash]);}else{++failure;assert(itemError&&[itemError.domain isEqualToString:@"PhiMod.Archive"]);assert(![f fileExistsAtPath:dest]);}}}
 assert(success==2&&failure==1);
 // Re-export replaces the finalized output, but a failure preserves that last good file.
 assert(PMCreateArchive(source,out,&error));NSString*before=PMFileSHA256(out);
 assert([f createSymbolicLinkAtPath:[source stringByAppendingPathComponent:@"bad-link"] withDestinationPath:media error:&error]);error=nil;
 assert(!PMCreateArchive(source,out,&error));assert(error);assert([PMFileSHA256(out)isEqualToString:before]);
 for(NSString*name in [f contentsOfDirectoryAtPath:root error:nil])assert(![name hasSuffix:@".partial"]);
 assert([f removeItemAtPath:root error:&error]);puts("Export archive streaming/roundtrip/failure cleanup passed");
}return 0;}
