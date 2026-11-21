#import "PMStorySequence.hpp"
#import "PMDoorRun.h"
#import "PMDiagnostics.h"

using pmstorysequence::handoff;

BOOL PMStorySequenceArm(NSString *chapter, NSArray<NSDictionary *> *nextSongs) {
    if (!NSThread.isMainThread || ![chapter isKindOfClass:NSString.class] || !chapter.length ||
        (nextSongs && ![nextSongs isKindOfClass:NSArray.class]) || nextSongs.count > 2) return NO;
    NSMutableArray *rows = [NSMutableArray new];
    for (id row in nextSongs) {
        if (![row isKindOfClass:NSDictionary.class]) return NO;
        NSString *sid = row[@"songID"], *difficulty = row[@"difficulty"];
        if (![sid isKindOfClass:NSString.class] || !sid.length ||
            (difficulty && ![difficulty isKindOfClass:NSString.class])) return NO;
        [rows addObject:difficulty.length ? @{@"songID":[sid copy], @"difficulty":[difficulty copy]} : @{@"songID":[sid copy]}];
    }
    return pmstorysequence::attachToPending(chapter, [rows copy]);
}

void PMStorySequenceDiscardHandoff() {
    if (NSThread.isMainThread) handoff.take();
}

BOOL PMStorySequenceRoute(BOOL (^available)(NSString *), BOOL (^navigate)(NSString *)) {
    if (!NSThread.isMainThread) return NO;
    return handoff.route([&](NSDictionary *run) {
        NSString *chapter = run[@"chapter"];
        BOOL ok = available && navigate && available(chapter) && handoff.holds(run) && navigate(chapter);
        if (!ok) PMDiagnosticsWrite("Chapter story sequence stopped: chapter unavailable");
        return ok;
    });
}

BOOL PMStorySequenceSelectorReady(NSString *chapter, PMStoryStartSong startSong) {
    if (!NSThread.isMainThread) return NO;
    NSDictionary *run = handoff.take(); // Consume before invoking any external code.
    if (!startSong || ![run[@"chapter"] isEqual:chapter]) return NO;
    NSArray *songs = run[@"nextSongs"];
    NSDictionary *next = songs.firstObject;
    NSArray *rest = [songs subarrayWithRange:NSMakeRange(1, songs.count - 1)];
    // Only a synchronous native identity check may bind the next leg. An
    // escaped block, a second invocation or an unchecked success cannot arm.
    __block BOOL open = YES, armed = NO;
    BOOL accepted = NO;
    @try {
        accepted = startSong(next[@"songID"], next[@"difficulty"], ^BOOL(NSString *group, int slot, NSString *chart) {
            if (!open || !NSThread.isMainThread) return NO;
            open = NO;
            if (!PMDoorArm(chapter, run[@"door"], group, slot, chart, [run[@"hp"] doubleValue], run[@"delta"])) return NO;
            armed = pmstorysequence::attachToPending(chapter, rest);
            if (!armed) PMDoorCancelPending();
            return armed;
        }) && armed;
    } @finally {
        open = NO;
        if (!accepted) {
            if (armed) PMDoorAbandon();
            PMDiagnosticsWrite("Chapter story sequence stopped: checked song launch rejected");
        }
    }
    return accepted;
}
