#pragma once
#import <Foundation/Foundation.h>
inline NSDictionary* PMOfficialSongMap(NSDictionary*official){NSMutableDictionary*out=[NSMutableDictionary new];for(NSString*k in @[@"mainSongs",@"extraSongs",@"sideStorySongs",@"otherSongs"])for(NSDictionary*s in official[@"songBase"][k])if(s[@"songsId"])out[s[@"songsId"]]=s;return out;}
inline NSArray* PMChapterSongIDs(NSDictionary*db,NSDictionary*official,NSString*chapter){
 NSMutableArray*out=[NSMutableArray new];
 void(^add)(NSString*)=^(NSString*id){if(id.length&&![out containsObject:id])[out addObject:id];};
 for(NSDictionary*c in official[@"chapters"])if([c[@"chapterCode"]isEqual:chapter])for(NSDictionary*s in c[@"songInfo"][@"songs"]){NSString*id=s[@"songsId"],*moved=db[@"officialMoves"][id];if(!moved||[moved isEqual:chapter])add(id);}
 for(NSDictionary*c in db[@"chapters"])if([c[@"id"]isEqual:chapter])for(NSString*id in c[@"songs"])add(id);
 for(NSString*id in db[@"chapterOverrides"][chapter][@"addedSongs"])add(id);
 for(NSDictionary*s in db[@"songs"])if([s[@"targetChapter"]isEqual:chapter])add(s[@"id"]);
 for(NSString*id in db[@"officialMoves"])if([db[@"officialMoves"][id]isEqual:chapter])add(id);
 return out;
}
inline BOOL PMAssignChapterSongs(NSMutableDictionary*db,NSDictionary*official,NSArray*ids,NSString*destination,BOOL move,NSError**error){
 NSMutableDictionary*target=nil;BOOL valid=NO;for(NSMutableDictionary*c in db[@"chapters"])if([c[@"id"]isEqual:destination]){target=c;valid=YES;}
 for(NSDictionary*c in official[@"chapters"])if([c[@"chapterCode"]isEqual:destination])valid=YES;
 NSMutableDictionary*custom=[NSMutableDictionary new];for(NSMutableDictionary*s in db[@"songs"])custom[s[@"id"]]=s;
 NSDictionary*original=PMOfficialSongMap(official);
 for(NSString*id in ids)if(!custom[id]&&!original[id])valid=NO;
 if(!valid||!ids.count){if(error)*error=[NSError errorWithDomain:@"PhiMod.Chapter" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Song or destination chapter no longer exists"}];return NO;}
 NSMutableDictionary*overrides=[db[@"chapterOverrides"]mutableCopy]?:[NSMutableDictionary new],*moves=[db[@"officialMoves"]mutableCopy]?:[NSMutableDictionary new];
 for(NSString*id in ids){
  if(move){for(NSMutableDictionary*c in db[@"chapters"]){NSMutableArray*a=[c[@"songs"]mutableCopy]?:[NSMutableArray new];[a removeObject:id];c[@"songs"]=a;}
   for(NSString*key in [overrides.allKeys copy]){NSMutableDictionary*c=[overrides[key]mutableCopy];NSMutableArray*a=[c[@"addedSongs"]mutableCopy]?:[NSMutableArray new];[a removeObject:id];c[@"addedSongs"]=a;overrides[key]=c;}
   if(custom[id])custom[id][@"targetChapter"]=destination;else moves[id]=destination;
  }
  if(target){NSMutableArray*a=[target[@"songs"]mutableCopy]?:[NSMutableArray new];if(![a containsObject:id])[a addObject:id];target[@"songs"]=a;}
  else{NSMutableDictionary*c=[overrides[destination]mutableCopy]?:[NSMutableDictionary new];NSMutableArray*a=[c[@"addedSongs"]mutableCopy]?:[NSMutableArray new];if(![a containsObject:id])[a addObject:id];c[@"addedSongs"]=a;overrides[destination]=c;}
 }
 db[@"chapterOverrides"]=overrides;db[@"officialMoves"]=moves;return YES;
}

// Build an independent mutable JSON tree. mutableCopy alone is shallow and
// leaves songInfo/unlockInfo and dictionary literals inside arrays immutable.
inline id PMMutableContentTree(id value){
 if([value isKindOfClass:NSDictionary.class]){NSMutableDictionary*out=[NSMutableDictionary dictionaryWithCapacity:[value count]];for(id key in value)out[key]=PMMutableContentTree(value[key]);return out;}
 if([value isKindOfClass:NSArray.class]){NSMutableArray*out=[NSMutableArray arrayWithCapacity:[value count]];for(id child in value)[out addObject:PMMutableContentTree(child)];return out;}
 return value;
}
inline NSMutableDictionary* PMNativeChapter(NSString*identifier,NSString*name,NSString*subtitle,NSString*banner,NSArray*songs){
 return PMMutableContentTree(@{@"chapterCode":identifier,@"songInfo":@{@"title":name?:@"",@"subTitle":subtitle?:@"",@"banner":banner?:@"Custom Chapter - Local Practice",@"songs":songs?:@[]},@"unlockInfo":@{@"unlockMode":@0,@"unlockFlag":@"",@"unlockTip":@"",@"fakeCoverFlag":@"",@"fakeCoverCode":@"",@"fakeCoverBlurCode":@""}});
}

// Android OfficialPlacement.entries uses native chapter rows, not every entry
// in SongBase (which can contain unplaced/internal tracks).
inline NSDictionary* PMOfficialChapterEntries(NSDictionary*official){
 NSMutableDictionary*out=[NSMutableDictionary new];for(NSDictionary*c in official[@"chapters"])for(NSDictionary*row in c[@"songInfo"][@"songs"]){NSString*id=row[@"songsId"];if([id isKindOfClass:NSString.class]&&id.length&&!out[id])out[id]=row;}return out;
}
inline NSArray* PMChapterOfficialReferences(id raw,NSDictionary*available,NSError**error){
 if(!raw)return @[];
 NSString*problem=nil;
 if(![raw isKindOfClass:NSArray.class])problem=@"officialSongs must be an array";
 else if([raw count]>2000)problem=@"Too many official song references";
 NSMutableSet*seen=[NSMutableSet new];NSMutableArray*order=[NSMutableArray new];
 if(!problem)for(id entry in raw){
  if(![entry isKindOfClass:NSDictionary.class]){problem=@"Invalid officialSongs entry";break;}
  NSString*id=entry[@"id"];
  if(![id isKindOfClass:NSString.class]||![id length]||[id hasPrefix:@"pm_"]||[seen containsObject:id]||!available[id]){problem=@"Duplicate, custom or unavailable official song reference";break;}
  [seen addObject:id];[order addObject:id];
 }
 if(problem){if(error)*error=[NSError errorWithDomain:@"PhiMod.Chapter" code:1 userInfo:@{NSLocalizedDescriptionKey:problem}];return nil;}return order;
}
