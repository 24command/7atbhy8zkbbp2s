#pragma once
#import <Foundation/Foundation.h>

// The selected chapter and explicit chapter conditions include their entire order.
// Song/group references carry only their charts and transitive prerequisites.
static inline NSDictionary *PMChapterExportPlan(NSDictionary *db, NSDictionary *main, NSString *looseID) {
    auto array = [](id value) -> NSArray * { return [value isKindOfClass:NSArray.class] ? value : @[]; };
    NSMutableDictionary *songs = [NSMutableDictionary new], *groups = [NSMutableDictionary new];
    for (NSDictionary *song in array(db[@"songs"])) {
        NSString *sid = song[@"id"];
        if (![sid isKindOfClass:NSString.class]) continue;
        songs[sid] = song;
        NSString *group = song[@"groupId"];
        if (![group isKindOfClass:NSString.class] || !group.length) group = sid;
        if (!groups[group]) groups[group] = [NSMutableArray new];
        [groups[group] addObject:sid];
    }
    NSMutableDictionary *chapters = [NSMutableDictionary new], *orders = [NSMutableDictionary new];
    for (NSDictionary *chapter in array(db[@"chapters"])) {
        if ([chapter[@"id"] isKindOfClass:NSString.class]) chapters[chapter[@"id"]] = chapter;
    }
    NSMutableArray *chapterIDs = [NSMutableArray new], *queue = [NSMutableArray new];
    NSMutableOrderedSet *included = [NSMutableOrderedSet new], *official = [NSMutableOrderedSet new];
    NSMutableDictionary *locations = [NSMutableDictionary new];
    bool limitExceeded = false;
    auto addSong = [&](NSString *sid, NSString *owner) {
        if (limitExceeded || (owner ? [orders[owner] containsObject:sid] : [included containsObject:sid])) return;
        NSString *group = songs[sid][@"groupId"];
        NSArray *members = ([group isKindOfClass:NSString.class] && group.length) ? groups[group] : groups[sid];
        // Preserve the listed chart's position ahead of its other difficulties.
        auto addMember = [&](NSString *member) {
            if (![included containsObject:member]) {
                if (included.count >= 2000) { limitExceeded = true; return; }
                [included addObject:member];
                [queue addObject:songs[member]];
            }
            if (owner && ![orders[owner] containsObject:member]) {
                [orders[owner] addObject:member];
                if (!locations[member]) locations[member] = owner;
            }
        };
        addMember(sid);
        for (NSString *member in members) addMember(member);
    };
    auto addChapter = [&](NSString *cid) {
        if (limitExceeded || !cid.length || orders[cid] || !chapters[cid]) return;
        if (chapterIDs.count >= 129) { limitExceeded = true; return; }
        orders[cid] = [NSMutableArray new];
        [chapterIDs addObject:cid];
        [queue addObject:chapters[cid]];
        for (NSString *sid in array(chapters[cid][@"songs"])) {
            if (songs[sid]) addSong(sid,cid);
            else if ([sid isKindOfClass:NSString.class] && sid.length) {
                [official addObject:sid];
                [orders[cid] addObject:sid];
            }
        }
    };
    auto addReference = [&](NSString *ref) {
        if (![ref isKindOfClass:NSString.class] || !ref.length) return;
        NSArray *members = groups[ref];
        if (members.count) addSong(members.firstObject,nil);
        else if (songs[ref]) addSong(ref,nil);
        else [official addObject:ref];
    };
    addChapter(main[@"id"]);
    for (NSUInteger i = 0; i < queue.count; ++i) {
        if (limitExceeded) return nil;
        NSDictionary *entity = queue[i], *rule = entity[@"unlock"];
        for (NSDictionary *condition in array(rule[@"conditions"])) {
            NSString *type = condition[@"type"];
            if ([type isEqualToString:@"chapter"]) addChapter(condition[@"ref"]);
            else if (![type isEqualToString:@"rks"]) addReference(condition[@"ref"]);
        }
        if ([rule[@"chain"][@"enabled"] boolValue]) addReference(rule[@"chain"][@"song"]);
        addReference(entity[@"coverSwitch"][@"ref"]);
    }
    if (limitExceeded) return nil;
    // Assign only after traversal: a later chapter condition can supply a real owner.
    for (NSString *sid in included) {
        if (locations[sid]) continue;
        if (!orders[looseID]) {
            if (chapterIDs.count >= 129) return nil;
            orders[looseID] = [NSMutableArray new];
            [chapterIDs addObject:looseID];
            chapters[looseID] = @{@"id":looseID, @"name":[NSString stringWithFormat:@"%@ - Unlock prerequisites",main[@"name"] ?: @"Chapter"],
                                  @"subtitle":@"DEPENDENCIES", @"songs":orders[looseID], @"before":@""};
        }
        [orders[looseID] addObject:sid];
        locations[sid] = looseID;
    }
    return @{@"chapters":chapters, @"chapterIDs":chapterIDs, @"orders":orders, @"locations":locations,
             @"songs":songs, @"includedSongs":included.set, @"officialIDs":official.array};
}
