#pragma once
#import <Foundation/Foundation.h>
#import "PMDifficultyMetadata.h"
// A song-local optional presentation failure must never invalidate the chapter.
// Keep the failed binding explicit so Start cannot silently bypass its story.
static inline NSDictionary *PMOSBindInterruption(NSDictionary *row, NSString *declaredDifficulty,
 NSString *installedDifficulty, id (^prepare)(NSError **)) {
 NSMutableDictionary *result=[row mutableCopy];
 NSString *reason=nil;
 if(result[@"interruption"] || result[@"interruptionError"])reason=@"同一谱面存在重复的剧情中断配置";
 else if(declaredDifficulty.length && [PMDifficultyName(declaredDifficulty) caseInsensitiveCompare:PMDifficultyName(installedDifficulty)]!=NSOrderedSame)
  reason=[NSString stringWithFormat:@"剧情难度 %@ 与已安装谱面的难度 %@ 不一致",declaredDifficulty,PMDifficultyName(installedDifficulty)];
 else {
  NSError *error=nil;id prepared=prepare?prepare(&error):nil;
  if(prepared){result[@"interruption"]=prepared;return [result copy];}
  reason=error.localizedDescription ?: @"无法准备剧情图片，请检查章节 os-media 中的原图";
 }
 [result removeObjectForKey:@"interruption"];
 result[@"interruptionError"]=reason;
 return [result copy];
}