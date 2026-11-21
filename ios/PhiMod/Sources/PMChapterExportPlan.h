#pragma once
#import "PMUnlockRules.h"

// Membership determines package contents. An unlock reference is not membership.
static inline NSDictionary *PMChapterExportPlan(NSDictionary *db, NSDictionary *main) {
    NSString *cid=main[@"id"];
    NSMutableDictionary *songs=[NSMutableDictionary new], *groups=[NSMutableDictionary new];
    for (NSDictionary *song in db[@"songs"]) {
        NSString *sid=song[@"id"], *group=song[@"groupId"] ?: sid;
        songs[sid]=song;
        if (!groups[group]) groups[group]=[NSMutableArray new];
        [groups[group] addObject:sid];
    }
    NSMutableOrderedSet *order=[NSMutableOrderedSet new], *included=[NSMutableOrderedSet new], *official=[NSMutableOrderedSet new];
    NSArray *members=PMChapterSongIDs(db,nil,cid);
    NSSet *owned=[NSSet setWithArray:members];
    for (NSString *member in members) {
        [order addObject:member];
        if (!songs[member]) [official addObject:member];
        else [included addObject:member];
        for (NSString *variant in groups[songs[member][@"groupId"] ?: member]) {
            if ([songs[variant][@"targetChapter"] length] && ![owned containsObject:variant]) continue;
            [included addObject:variant]; [order addObject:variant];
        }
        if (included.count>2000) return nil;
    }
    NSDictionary *aliases=PMUnlockScoreAliases(db[@"songs"]);
    NSMutableDictionary *refs=[NSMutableDictionary new];
    NSMutableOrderedSet *externalSongs=[NSMutableOrderedSet new], *externalChapters=[NSMutableOrderedSet new];
    auto reference=[&](NSString *ref,bool chapter){
        if (![ref isKindOfClass:NSString.class] || ![ref hasPrefix:@"pm_"]) return;
        if (chapter) { if (![ref isEqual:cid]) [externalChapters addObject:ref]; return; }
        if ([included containsObject:ref]) return;
        for (NSString *sid in aliases[ref]) if ([included containsObject:sid]) { refs[ref]=sid; return; }
        if (!songs[ref]) for (NSString *sid in groups[ref]) if ([included containsObject:sid]) return;
        [externalSongs addObject:ref];
    };
    NSMutableArray *entities=[NSMutableArray arrayWithObject:main];
    for (NSString *sid in included) [entities addObject:songs[sid]];
    for (NSDictionary *entity in entities) {
        NSDictionary *rule=entity[@"unlock"];
        for (NSDictionary *c in rule[@"conditions"]) if (![c[@"type"] isEqual:@"rks"]) reference(c[@"ref"],[c[@"type"] isEqual:@"chapter"]);
        if ([rule[@"chain"][@"enabled"] boolValue]) reference(rule[@"chain"][@"song"],false);
        reference(entity[@"coverSwitch"][@"ref"],false);
    }
    return @{@"order":order.array,@"songs":songs,@"includedSongs":included.array,@"officialIDs":official.array,@"refs":refs,
             @"omitSongs":externalSongs.set,@"omitChapters":externalChapters.set};
}

// Called on the deep export copy, after exact equivalent chart IDs are remapped.
static inline void PMTrimChapterExportRule(NSMutableDictionary *entity, NSDictionary *plan) {
    NSMutableDictionary *rule=entity[@"unlock"];
    if (rule) {
        NSMutableArray *conditions=[NSMutableArray new];
        for (NSDictionary *c in rule[@"conditions"]) {
            NSString *type=c[@"type"];
            NSSet *omit=[type isEqual:@"chapter"] ? plan[@"omitChapters"] : plan[@"omitSongs"];
            if ([type isEqual:@"rks"] || ![omit containsObject:c[@"ref"]]) [conditions addObject:c];
        }
        rule[@"conditions"]=conditions;
        if (!conditions.count) rule[@"enabled"]=@NO;
        if ([plan[@"omitSongs"] containsObject:rule[@"chain"][@"song"] ?: @""]) [rule removeObjectForKey:@"chain"];
    }
    if ([plan[@"omitSongs"] containsObject:entity[@"coverSwitch"][@"ref"] ?: @""]) [entity removeObjectForKey:@"coverSwitch"];
}
