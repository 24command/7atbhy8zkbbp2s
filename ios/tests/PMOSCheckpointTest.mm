#import "../PhiMod/Sources/PMOSCheckpoint.h"
#include <cassert>

#ifndef PMOS_CHECKPOINT_HOST_TEST
#error Build the checkpoint test and implementation with PMOS_CHECKPOINT_HOST_TEST.
#endif

static NSString *testRoot;
NSString *PMOSCheckpointTestRoot(void) { return testRoot; }

static NSDictionary *pageRecord() {
    return @{@"token": @"first", @"chapter": @"chapter-a", @"scriptHash": @"hash-a", @"page": @0};
}

static NSDictionary *songRecord() {
    return @{@"token": @"second", @"chapter": @"chapter-b", @"scriptHash": @"hash-b",
             @"songID": @"song-a", @"difficulty": @"IN"};
}

static void reject(NSDictionary *invalid) {
    NSError *error = nil;
    assert(!PMOSSaveCheckpoint(invalid, &error) && error);
    assert([PMOSLastCheckpoint() isEqual:pageRecord()]);
}

static void writePage() {
    assert(!PMOSLastCheckpoint() && !PMOSPendingCheckpoint());
    NSMutableDictionary *named = [pageRecord() mutableCopy];
    named[@"page"] = @"menu";
    assert(PMOSSaveCheckpoint(named, nullptr));
    assert([PMOSLastCheckpoint() isEqual:named]);
    assert(PMOSSaveCheckpoint(pageRecord(), nullptr));
    assert(!PMOSPendingCheckpoint());

    for (NSString *key in pageRecord()) {
        NSMutableDictionary *missing = [pageRecord() mutableCopy];
        [missing removeObjectForKey:key];
        reject(missing);
    }
    for (NSDictionary *change in @[@{@"token": @" "}, @{@"chapter": @7}, @{@"scriptHash": @""},
                                   @{@"songID": @"ambiguous"}, @{@"difficulty": @"IN"}, @{@"page": @(-1)},
                                   @{@"page": @YES}, @{@"page": @1.5}, @{@"page": NSNull.null}]) {
        NSMutableDictionary *invalid = [pageRecord() mutableCopy];
        [invalid addEntriesFromDictionary:change];
        reject(invalid);
    }
    for (NSDictionary *change in @[@{@"difficulty": @""}, @{@"songID": @0}]) {
        NSMutableDictionary *invalid = [songRecord() mutableCopy];
        [invalid addEntriesFromDictionary:change];
        reject(invalid);
    }
}

static void resumePage() {
    assert([PMOSPendingCheckpoint() isEqual:pageRecord()]);
    assert([PMOSPendingCheckpoint() isEqual:PMOSLastCheckpoint()]);
    assert(!PMOSClearCheckpoint(@"stale"));
    NSMutableDictionary *withoutDifficulty = [songRecord() mutableCopy];
    [withoutDifficulty removeObjectForKey:@"difficulty"];
    assert(PMOSSaveCheckpoint(withoutDifficulty, nullptr));
    assert([PMOSLastCheckpoint() isEqual:withoutDifficulty]);
    assert(PMOSSaveCheckpoint(songRecord(), nullptr));
    assert(!PMOSClearCheckpoint(pageRecord()[@"token"]));
    assert([PMOSLastCheckpoint() isEqual:songRecord()] && !PMOSPendingCheckpoint());
}

static void consumeSong() {
    assert([PMOSPendingCheckpoint() isEqual:songRecord()]);
    assert(PMOSClearCheckpoint(songRecord()[@"token"]));
    assert(!PMOSLastCheckpoint() && !PMOSPendingCheckpoint());
    assert(!PMOSClearCheckpoint(songRecord()[@"token"]));

    NSString *path = [testRoot stringByAppendingPathComponent:@"chapter-checkpoint.plist"];
    assert([@"corrupt" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nullptr]);
    assert(!PMOSLastCheckpoint() && !PMOSPendingCheckpoint());
    for (NSDictionary *envelope in @[@{@"record": pageRecord(), @"writer": @"invalid"},
                                     @{@"record": @{}, @"writer": NSUUID.UUID.UUIDString}]) {
        assert([envelope writeToFile:path atomically:YES]);
        assert(!PMOSLastCheckpoint() && !PMOSPendingCheckpoint());
    }
    assert(PMOSSaveCheckpoint(pageRecord(), nullptr));
    // A file in place of the injected directory must report an I/O error.
    NSString *directory = testRoot;
    testRoot = path;
    NSError *error = nil;
    assert(!PMOSSaveCheckpoint(songRecord(), &error) && error);
    testRoot = directory;
    assert([PMOSLastCheckpoint() isEqual:pageRecord()]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 3) return 2;
        testRoot = [NSString stringWithUTF8String:argv[1]];
        NSString *phase = [NSString stringWithUTF8String:argv[2]];
        if ([phase isEqual:@"write"]) writePage();
        else if ([phase isEqual:@"resume"]) resumePage();
        else if ([phase isEqual:@"consume"]) consumeSong();
        else return 2;
    }
    return 0;
}
