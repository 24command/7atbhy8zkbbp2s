#import <Foundation/Foundation.h>
#import "../PhiMod/Sources/PMChartConvert.h"
#import "../PhiMod/Sources/PMArchive.h"
#import "../PhiMod/Sources/PMUnlockRules.h"
#import "../PhiMod/Sources/PMChapterEditing.h"
#include "../PhiMod/Vendor/miniz/miniz.h"
#include <cassert>
#include <cmath>
int main(int argc,const char**argv){@autoreleasepool{
 NSArray*merged=@[@{@"id":@"song-in",@"groupId":@"song-in",@"level":@"IN"},@{@"id":@"song-at",@"groupId":@"song-in",@"level":@"AT"}];
 assert([PMUnlockReferenceSongs(merged,@"song-in")count]==1);
 assert([PMUnlockReferenceSongs(merged,@"song-at")[0][@"level"]isEqual:@"AT"]);
 assert([PMUnlockReferenceSongs(merged,@"missing")count]==0);
 NSArray*separateGroup=@[@{@"id":@"in",@"groupId":@"group"},@{@"id":@"at",@"groupId":@"group"}];
 assert([PMUnlockReferenceSongs(separateGroup,@"group")count]==2);
 NSDictionary*officialLibrary=@{@"songBase":@{@"mainSongs":@[@{@"songsId":@"official-a"},@{@"songsId":@"official-b"}]},@"chapters":@[@{@"chapterCode":@"Main",@"songInfo":@{@"songs":@[@{@"songsId":@"official-a"},@{@"songsId":@"official-b"}]}}]};
 NSDictionary*library=@{@"songs":@[@{@"id":@"pm_a",@"targetChapter":@"pm_one"},@{@"id":@"pm_b",@"targetChapter":@"pm_one"}],@"chapters":@[@{@"id":@"pm_one",@"songs":@[@"pm_a",@"pm_b"]},@{@"id":@"pm_two",@"songs":@[]}],@"chapterOverrides":@{@"Main":@{@"title":@"Keep title"}}};
 NSMutableDictionary*editing=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:library options:0 error:nil] options:NSJSONReadingMutableContainers error:nil];
 assert(PMAssignChapterSongs(editing,officialLibrary,@[@"pm_a",@"pm_b"],@"pm_two",YES,nil));
 assert([PMChapterSongIDs(editing,officialLibrary,@"pm_one")count]==0);
 assert([PMChapterSongIDs(editing,officialLibrary,@"pm_two")count]==2);
 assert(PMAssignChapterSongs(editing,officialLibrary,@[@"official-a"],@"pm_two",NO,nil));
 assert([PMChapterSongIDs(editing,officialLibrary,@"Main")containsObject:@"official-a"]);
 assert(PMAssignChapterSongs(editing,officialLibrary,@[@"official-a"],@"pm_two",YES,nil));
 assert(![PMChapterSongIDs(editing,officialLibrary,@"Main")containsObject:@"official-a"]);
 assert(PMAssignChapterSongs(editing,officialLibrary,@[@"official-a"],@"Main",YES,nil));
 assert([PMChapterSongIDs(editing,officialLibrary,@"Main")containsObject:@"official-a"]);
 assert(![PMChapterSongIDs(editing,officialLibrary,@"pm_two")containsObject:@"official-a"]);
 assert([editing[@"chapterOverrides"][@"Main"][@"title"]isEqual:@"Keep title"]);
 NSData*beforeInvalid=[NSJSONSerialization dataWithJSONObject:editing options:NSJSONWritingSortedKeys error:nil];
 assert(!PMAssignChapterSongs(editing,officialLibrary,@[@"pm_a",@"missing"],@"pm_two",YES,nil));
 assert([beforeInvalid isEqual:[NSJSONSerialization dataWithJSONObject:editing options:NSJSONWritingSortedKeys error:nil]]);
 // Exact failure: a literal custom chapter's songInfo cannot accept a new
 // songs array. Exercise production construction + all nested write paths.
 NSDictionary*immutableEntry=@{@"songsId":@"official-a",@"unlockType":@1,@"unlockInfo":@[@{@"value":@95}],@"secretInfo":@[]};
 NSArray*immutableSongs=@[immutableEntry];
 NSMutableDictionary*chapter=PMNativeChapter(@"pm_new",@"Custom",@"subtitle",nil,immutableSongs);
 assert([chapter isKindOfClass:NSMutableDictionary.class]);
 assert([chapter[@"songInfo"]isKindOfClass:NSMutableDictionary.class]);
 assert([chapter[@"songInfo"][@"songs"]isKindOfClass:NSMutableArray.class]);
 chapter[@"songInfo"][@"title"]=@"Edited";
 chapter[@"songInfo"][@"songs"][0][@"unlockType"]=@(-1);
 chapter[@"songInfo"][@"songs"][0][@"unlockInfo"][0][@"value"]=@99;
 [chapter[@"songInfo"][@"songs"] addObject:PMMutableContentTree(@{@"songsId":@"pm_a",@"unlockInfo":@[]})];
 chapter[@"songInfo"][@"songs"]=[NSMutableArray arrayWithArray:chapter[@"songInfo"][@"songs"]];
 chapter[@"unlockInfo"][@"unlockMode"]=@1;
 assert([immutableEntry[@"unlockType"]intValue]==1);
 assert([immutableEntry[@"unlockInfo"][0][@"value"]intValue]==95);
 assert(immutableSongs.count==1);
 assert([NSJSONSerialization isValidJSONObject:chapter]);
 NSMutableDictionary*copied=PMMutableContentTree(@{@"chapters":@[chapter],@"mainSongs":@[@{@"unlockInfo":@[@{@"unlockType":@1}]}]});
 copied[@"mainSongs"][0][@"unlockInfo"][0][@"unlockType"]=@(-1);
 copied[@"chapters"][0][@"songInfo"][@"banner"]=@"Changed";
 assert(![chapter[@"songInfo"][@"banner"]isEqual:@"Changed"]);
 assert(PMUnlockValidationError(nil)==nil);
 assert(PMUnlockValidationError(@{@"enabled":@YES,@"conditions":@[]})!=nil);
 NSDictionary *rks=@{@"type":@"rks",@"value":@15};
 assert(PMUnlockValidationError(@{@"enabled":@YES,@"conditions":@[rks],@"animation":@"unlock-demo.mp4",@"playTiming":@2})==nil);
 assert(PMUnlockValidationError(@{@"enabled":@YES,@"conditions":@[rks],@"animation":@"../unlock-demo.mp4"})!=nil);
 assert(PMUnlockValidationError(@{@"conditions":@[@{@"type":@"score",@"ref":@"pm_song",@"value":@1.5}]})!=nil);
 assert(PMUnlockValidationError(@{@"conditions":@[@{@"type":@"acc",@"ref":@"pm_song",@"value":@101}]})!=nil);
 assert(PMUnlockValidationError(@{@"conditions":@[@{@"type":@"fc",@"ref":@"pm_song",@"slot":@4}]})!=nil);
 assert(PMUnlockValidationError(@{@"conditions":@[@{@"type":@"chapter",@"ref":@"pm_chapter"}]})==nil);
 assert(PMUnlockValidationError(@{@"chain":@{@"enabled":@YES,@"song":@"pm_song",@"slot":@(-1)}})!=nil);
 assert(PMUnlockValidationError(@{@"conditions":@[@"bad"]})!=nil);
 assert(PMUnlockValidationError(@{@"enabled":NSNull.null})!=nil);
 NSDictionary*source=@{@"META":@{@"offset":@125},@"BPMList":@[@{@"bpm":@120,@"startTime":@[@0,@0,@1]}],@"judgeLineList":@[@{@"bpmfactor":@1,@"father":@(-1),@"eventLayers":@[@{@"moveXEvents":@[@{@"startTime":@[@0,@0,@1],@"endTime":@[@8,@0,@1],@"start":@0,@"end":@135}],@"moveYEvents":@[],@"rotateEvents":@[],@"alphaEvents":@[@{@"startTime":@[@0,@0,@1],@"endTime":@[@8,@0,@1],@"start":@255,@"end":@255}],@"speedEvents":@[@{@"startTime":@[@0,@0,@1],@"endTime":@[@8,@0,@1],@"start":@4.5,@"end":@4.5}]}],@"notes":@[@{@"type":@1,@"startTime":@[@2,@0,@1],@"endTime":@[@2,@0,@1],@"positionX":@0,@"above":@1},@{@"type":@2,@"startTime":@[@3,@0,@1],@"endTime":@[@4,@0,@1],@"positionX":@75,@"above":@2},@{@"type":@1,@"startTime":@[@5,@0,@1],@"endTime":@[@5,@0,@1],@"positionX":@0,@"isFake":@1}]}]};NSError*error=nil;NSDictionary*c=PMConvertChart([NSJSONSerialization dataWithJSONObject:source options:0 error:nil],&error);assert(c&&error==nil);assert([c[@"offset"]doubleValue]==.125);NSArray*lines=c[@"judgeLineList"];assert([lines[0][@"notesAbove"]count]==2);NSDictionary*n=PMNativeChart(c);assert([n[@"judgeLineList"][0][@"notesAbove"]count]==1);assert([n[@"judgeLineList"][0][@"notesBelow"][0][@"type"]intValue]==3);
 NSMutableDictionary*hidden=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:source options:0 error:nil] options:NSJSONReadingMutableContainers error:nil];
 hidden[@"judgeLineList"][0][@"eventLayers"][0][@"alphaEvents"][0][@"start"]=@(-1);hidden[@"judgeLineList"][0][@"eventLayers"][0][@"alphaEvents"][0][@"end"]=@(-1);
 NSDictionary*hiddenChart=PMConvertChart([NSJSONSerialization dataWithJSONObject:hidden options:0 error:nil],&error);
 assert(hiddenChart);assert([hiddenChart[@"judgeLineList"][0][@"pmDecor"][@"sourceAlphaEvents"][0][@"start"]doubleValue]<0);
 assert([hiddenChart[@"judgeLineList"][0][@"judgeLineDisappearEvents"][0][@"start"]doubleValue]==0);
 assert(!PMNativeChart(hiddenChart)[@"judgeLineList"][0][@"pmDecor"]);
 // Algebra hides real judgement notes behind fake-note artwork using signed
 // visibleTime. Conversion must preserve it on both sides and on fake notes.
 for(NSNumber*visible in @[@(-60),@(-10),@(-1),@0,@2.7119,@999999]){
  NSMutableDictionary*fixture=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:source options:0 error:nil] options:NSJSONReadingMutableContainers error:nil];
  NSArray*notes=fixture[@"judgeLineList"][0][@"notes"];
  for(NSMutableDictionary*note in notes){note[@"visibleTime"]=visible;note[@"alpha"]=@0;}
  error=nil;NSDictionary*converted=PMConvertChart([NSJSONSerialization dataWithJSONObject:fixture options:0 error:nil],&error);
  assert(converted&&error==nil);
  NSUInteger checked=0;for(NSString*side in @[@"notesAbove",@"notesBelow"])for(NSDictionary*note in converted[@"judgeLineList"][0][side]){
   assert([note[@"pmVisible"]doubleValue]==visible.doubleValue);
   assert([note[@"pmAlpha"]doubleValue]==0);++checked;
   double start=[note[@"pmTime"]doubleValue],lead=[note[@"pmVisible"]doubleValue];
   assert(start-(start-lead-.01)>lead); // still hidden just before its reveal
   assert(!(start-(start-lead+.01)>lead));
  }assert(checked==3);
  NSDictionary*native=PMNativeChart(converted); // visibility never removes scoring notes
  assert([native[@"judgeLineList"][0][@"notesAbove"]count]==1);
  assert([native[@"judgeLineList"][0][@"notesBelow"]count]==1);
 }
 assert([lines[0][@"notesAbove"][0][@"pmVisible"]doubleValue]==999999);
 NSString*pec=@"175\nbp 0 120\ncp 0 0 1024 700\ncm 0 0 4 2048 1400 1\ncv 0 0 7\nn1 0 2 0 1 0 # 1.5 & 2\nn2 0 3 4 0 1 0\n";c=PMConvertChart([pec dataUsingEncoding:NSUTF8StringEncoding],&error);assert(c);assert([c[@"judgeLineList"][0][@"judgeLineMoveEvents"]count]>1);assert([c[@"judgeLineList"][0][@"notesAbove"][0][@"pmSize"]intValue]==2);assert([c[@"judgeLineList"][0][@"notesAbove"][0][@"speed"]doubleValue]==1.5);
 NSDictionary*clean=PMNativeChart(c);assert(clean[@"blockAreaList"]);assert(!clean[@"pmFormat"]);assert(!clean[@"judgeLineList"][0][@"notesAbove"][0][@"pmSize"]);

 NSString*deepPEC=@"175\nbp 0 120\nbp 4 60\nn1 0 3 10 1 0 # 1.5 & 2\nn2 0 3 5 20 1 0\nn3 0 5 30 0 0\nn4 0 6 40 1 0\ncv 0 0 7\ncv 0 4 14\ncp 0 2 1024 700\ncm 0 0 4 2048 1400 1\n";error=nil;NSDictionary*deep=PMConvertChart([deepPEC dataUsingEncoding:NSUTF8StringEncoding],&error);assert(deep&&error==nil);NSArray*deepLines=deep[@"judgeLineList"];assert(deepLines.count==1);NSArray*deepAbove=deepLines[0][@"notesAbove"],*deepBelow=deepLines[0][@"notesBelow"];assert(deepAbove.count==3&&deepBelow.count==1);assert([deepAbove[0][@"type"]intValue]==1&&[deepAbove[1][@"type"]intValue]==3&&[deepAbove[2][@"type"]intValue]==2);assert([deepBelow[0][@"type"]intValue]==4);assert(std::fabs([deepAbove[0][@"speed"]doubleValue]-1.5)<1e-9&&[deepAbove[0][@"pmSize"]doubleValue]==2);assert([deepAbove[1][@"time"]longLongValue]==96&&[deepAbove[1][@"holdTime"]longLongValue]==96);assert(std::fabs([deepAbove[1][@"floorPosition"]doubleValue]-1.5)<1e-9&&std::fabs([deepAbove[1][@"pmEndFloor"]doubleValue]-4)<1e-9);assert([deepBelow[0][@"time"]longLongValue]==192&&[deepAbove[2][@"time"]longLongValue]==256);assert(deepLines[0][@"judgeLineMoveEvents"]&&[deepLines[0][@"judgeLineMoveEvents"]count]>2);
 NSString*temp=[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString];NSFileManager*f=NSFileManager.defaultManager;[f createDirectoryAtPath:temp withIntermediateDirectories:YES attributes:nil error:nil];NSString*folder=[temp stringByAppendingPathComponent:@"source"],*zip=[temp stringByAppendingPathComponent:@"valid.zip"];[f createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];[@"chart test" writeToFile:[folder stringByAppendingPathComponent:@"test.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];if(!PMCreateArchive(folder,zip,&error)){fprintf(stderr,"Archive creation failed: %s\n",error.localizedDescription.UTF8String);return 1;}NSArray*files=PMExtractArchive(zip,[temp stringByAppendingPathComponent:@"target"],&error);assert(files.count==1);
 NSString*bad=[temp stringByAppendingPathComponent:@"bad.zip"];mz_zip_archive archive{};assert(mz_zip_writer_init_file(&archive,bad.fileSystemRepresentation,0));assert(mz_zip_writer_add_mem(&archive,"../escape.txt","bad",3,0));assert(mz_zip_writer_finalize_archive(&archive));mz_zip_writer_end(&archive);error=nil;assert(PMExtractArchive(bad,[temp stringByAppendingPathComponent:@"unsafe"],&error)==nil);assert(error);assert(![f fileExistsAtPath:[temp stringByAppendingPathComponent:@"escape.txt"]]);if(argc>1){error=nil;NSString*sample=[NSString stringWithUTF8String:argv[1]];NSArray*extracted=PMExtractArchive(sample,[temp stringByAppendingPathComponent:@"sample"],&error);assert(extracted&&error==nil);NSString*chartPath=nil;for(NSString*file in extracted)if([file.lastPathComponent isEqualToString:@"14072798.json"])chartPath=file;assert(chartPath);NSDictionary*sampleChart=PMConvertChart([NSData dataWithContentsOfFile:chartPath],&error);assert(sampleChart&&error==nil);assert([sampleChart[@"pmFormat"]isEqualToString:@"PEC"]);NSDictionary*sampleNative=PMNativeChart(sampleChart);assert([NSJSONSerialization isValidJSONObject:sampleNative]);NSUInteger notes=0;for(NSDictionary*line in sampleNative[@"judgeLineList"])notes+=[line[@"notesAbove"]count]+[line[@"notesBelow"]count];assert(notes>0);printf("PASS supplied PEC archive: %lu notes\n",(unsigned long)notes);}
 // A chapter manifest is compact and appears first for streaming importers.
 NSDictionary*bundle=@{@"format":@"phigros-phi-chapter",@"version":@3,@"chapter":@{@"id":@"pm_test",@"songs":@[]},@"songs":@[],@"files":@[]};
 NSData*manifest=[NSJSONSerialization dataWithJSONObject:bundle options:0 error:&error];
 assert([manifest writeToFile:[folder stringByAppendingPathComponent:@"chapter.json"] atomically:YES]);
 NSString*bundleZip=[temp stringByAppendingPathComponent:@"manifest.phi-chapter.zip"];
 assert(PMCreateArchive(folder,bundleZip,&error));mz_zip_archive inspect{};assert(mz_zip_reader_init_file(&inspect,bundleZip.fileSystemRepresentation,0));mz_zip_archive_file_stat first{};assert(mz_zip_reader_file_stat(&inspect,0,&first));assert(strcmp(first.m_filename,"chapter.json")==0);mz_zip_reader_end(&inspect);
 [f removeItemAtPath:[folder stringByAppendingPathComponent:@"chapter.json"] error:nil];
 // A root alias is supported; symlinks inside the archive remain rejected.
 NSString*alias=[temp stringByAppendingPathComponent:@"source-alias"];
 assert([f createSymbolicLinkAtPath:alias withDestinationPath:folder error:&error]);
 error=nil;assert(PMCreateArchive(alias,[temp stringByAppendingPathComponent:@"alias.zip"],&error));
 NSArray*aliasFiles=PMExtractArchive([temp stringByAppendingPathComponent:@"alias.zip"],[temp stringByAppendingPathComponent:@"alias-out"],&error);
 assert(aliasFiles.count==1&&[aliasFiles[0]lastPathComponent]&&[[aliasFiles[0]lastPathComponent]isEqualToString:@"test.txt"]);
 [f removeItemAtPath:temp error:nil];printf("PASS content conversion, fake-note isolation, PEC commands, ZIP round-trip and path traversal rejection\n");}}
