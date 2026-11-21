// Foundation host integration: real Lua VM, on-disk author store and asynchronous door writer.
#import "../PhiMod/Sources/PMChapterCover.h"
#import "../PhiMod/Sources/PMDiagnostics.h"
#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <thread>

static NSString *root;
NSString *PMDoorRunTestRoot() { return root; }
void PMDiagnosticsWrite(const char *message) { std::fprintf(stderr,"%s\n",message); std::abort(); }

static void pumpUntil(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    assert(done());
}

// Test-only fence: leave the worker's completion queued on main until we
// advance its stamp. A timeout is a failure, not a wait for main to run it.
static void finishWorkers() {
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    [pmchaptercover::previewQueue() addBarrierBlock:^{ dispatch_semaphore_signal(finished); }];
    assert(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC)) == 0);
}

int main() { @autoreleasepool {
    root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *chapter = @"pm_cover_test";
    NSString *dir = [root stringByAppendingPathComponent:chapter];
    NSString *media = [dir stringByAppendingPathComponent:@"os-media"];
    NSFileManager *fm = NSFileManager.defaultManager;
    assert([fm createDirectoryAtPath:media withIntermediateDirectories:YES attributes:nil error:nullptr]);
    NSString *script = [dir stringByAppendingPathComponent:@"os.lua"];
    NSString *source = @"progress.set('previewOnly',1); if progress.get('map')==1 then chapterCover('image.png') end; "
                        @"if challengeProgress('gate').cleared then chapterCover('clear #1.webp') end";
    assert([source writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:nullptr]);
    for (NSString *name in @[@"image.png",@"clear #1.webp"]) {
        assert([fm createFileAtPath:[media stringByAppendingPathComponent:name] contents:[NSData data] attributes:nil]);
    }
    auto read = [&](NSUInteger revision,pmchaptercover::CoverReady ready) {
        return pmchaptercover::preview(root,dir,chapter,1,revision,ready);
    };
    pmchaptercover::CoverReady unexpected = ^(NSString *) { assert(false); };
    __block int deliveries = 0;
    __block NSString *last = nil;
    pmchaptercover::CoverReady record = ^(NSString *name) {
        assert(NSThread.isMainThread); ++deliveries; last = name;
    };
    NSOperationQueue *queue = pmchaptercover::previewQueue();
    queue.suspended = YES;
    assert(!read(1,unexpected)); // Main returns even with worker execution disabled.
    assert(!read(1,record));     // Same operation; the latest subscriber owns the result.
    assert(queue.operationCount == 1 && deliveries == 0);
    queue.suspended = NO;
    pumpUntil(^BOOL{ return deliveries == 1; });
    finishWorkers();
    queue.suspended = YES;
    assert(!last && !read(1,unexpected) && queue.operationCount == 0); // cached negative
    queue.suspended = NO;

    PMOSAuthorProgress *store = [[PMOSAuthorProgress alloc] initWithRoot:root chapter:chapter];
    std::thread([&]{ @autoreleasepool {
        assert(store.snapshotValues.count == 0);
        assert([store commitValues:@{@"map":@1}]);
    }}).join();
    assert(!read(1,unexpected));
    finishWorkers(); // First operation has completed, but its main callback hasn't run.
    assert(!read(2,record));
    pumpUntil(^BOOL{ return deliveries == 2; });
    assert([last isEqual:@"image.png"] && [read(2,unexpected) isEqual:last]);
    std::thread([&]{ @autoreleasepool {
        PMOSAuthorProgress *other = [[PMOSAuthorProgress alloc] initWithRoot:root chapter:@"other"];
        assert([other commitValues:@{@"map":@1}]);
    }}).join();
    assert([read(2,unexpected) isEqual:last]); // An unrelated chapter did not invalidate this hit.

    // Start a preview of the old state. A real door commit must invalidate it
    // before main can publish, even when its completion was already queued.
    assert(!read(3,unexpected));
    finishWorkers();
    __block int changes=0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:PMOSAuthorProgressChanged
        object:chapter queue:nil usingBlock:^(NSNotification *){
            ++changes;
            pmchaptercover::preview(root,dir,chapter,1,3,record);
        }];
    assert(PMDoorArm(chapter,@"gate",@"group",1,@"chart",10,@[@0,@0,@0,@0]));
    double hp=0, delta[4]={}; assert(PMDoorBeginExactTrack(@"group",1,@"chart",&hp,delta));
    PMDoorFinish(YES);
    PMDoorProgressBarrier(); // test only; hold main callbacks until the stamp changes
    pumpUntil(^BOOL{ return deliveries == 3; });
    assert([last isEqual:@"clear #1.webp"] && [read(3,unexpected) isEqual:last]);
    assert(changes == 1);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    std::thread([&]{ @autoreleasepool {
        NSDictionary *flags = store.snapshotValues;
        assert(flags[@"previewOnly"] == nil && [flags[@"door.gate.clear"] intValue] == 1);
    }}).join();
    for (NSString *kind in @[@"image",@"chapterBlur"]) {
        NSString *prefix = [NSString stringWithFormat:@"PM/%@/%@@1",chapter,kind];
        auto path = [&](NSString *name,bool os){return pmchaptercover::pathForKey([prefix stringByAppendingString:pmchaptercover::variant(name,os)],dir);};
        assert([path(@"image.png",false) isEqual:[dir stringByAppendingPathComponent:@"image.png"]]);
        assert([path(@"image.png",true) isEqual:[media stringByAppendingPathComponent:@"image.png"]]);
        assert([path(@"clear #1.webp",true) isEqual:[media stringByAppendingPathComponent:@"clear #1.webp"]]);
        assert(!path(@"../escape.png",true));
    }
    assert([@"chapterCover('missing.png')" writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:nullptr]);
    assert(!read(4,record));
    pumpUntil(^BOOL{ return deliveries == 4; });
    assert(!last && !read(4,unexpected)); // Missing art falls back without another request.
    assert([fm removeItemAtPath:root error:nullptr]);
    puts("chapter cover reader tests passed");
} }
