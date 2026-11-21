#import "../PhiMod/Sources/PMDiagnostics.h"
#import "../PhiMod/Sources/PMDoorRun.h"
#import "../PhiMod/Sources/PMOSAuthorProgress.h"
#include <cstdio>
#include <cstdlib>
#include <thread>

#ifndef PMDOOR_RUN_HOST_TEST
#error Build the door run test and implementation with PMDOOR_RUN_HOST_TEST.
#endif

#define CHECK(...) do { if (!(__VA_ARGS__)) { std::fprintf(stderr, "line %d: %s\n", __LINE__, #__VA_ARGS__); std::abort(); } } while (0)

static NSString *testRoot;
NSString *PMDoorRunTestRoot(void) { return testRoot; }
void PMDiagnosticsWrite(const char *message) {
    std::fprintf(stderr, "Unexpected door diagnostic: %s\n", message);
    std::abort();
}

static void arm() {
    CHECK(PMDoorArm(@"chapter", @"gate", @"song", 2, @"chart-IN", 10.5, @[@1, @0, @(-2.5), @(-4)]));
    CHECK(!PMDoorActive());
}

static void begin() {
    arm();
    double hp = 0, delta[4] = {};
    CHECK(PMDoorBeginExactTrack(@"song", 2, @"chart-IN", &hp, delta));
    CHECK(PMDoorActive());
    CHECK(hp == 10.5 && delta[0] == 1 && delta[1] == 0 && delta[2] == -2.5 && delta[3] == -4);
}

static void expectProgress(int failures, int cleared) {
    // Read through a fresh store after the real queue barrier. Progress I/O requires a worker.
    PMDoorProgressBarrier();
    std::thread reader([=] { @autoreleasepool {
        PMOSAuthorProgress *store = [[PMOSAuthorProgress alloc] initWithRoot:testRoot chapter:@"chapter"];
        int value = -1;
        CHECK([store readKey:@"door.gate.fail" value:&value] && value == failures);
        CHECK([store readKey:@"door.gate.clear" value:&value] && value == cleared);
    }});
    reader.join();
}

int main() {
    @autoreleasepool {
        testRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        double hp = 0, delta[4] = {};
        arm();
        CHECK(!PMDoorBeginExactTrack(@"song", 2, @"chart-AT", &hp, delta));
        CHECK(!PMDoorActive());
        PMDoorFinish(NO);
        expectProgress(0, 0);

        arm();
        PMDoorAbandon();
        CHECK(!PMDoorBeginExactTrack(@"song", 2, @"chart-IN", &hp, delta));
        begin();
        PMDoorAbandon();
        CHECK(!PMDoorActive());
        PMDoorFinish(YES);
        PMDoorFinish(NO);
        expectProgress(0, 0);

        begin();
        PMDoorFinish(NO);
        CHECK(!PMDoorActive());
        PMDoorFinish(NO);
        expectProgress(1, 0);

        begin();
        PMDoorFinish(YES);
        expectProgress(1, 1);

        // Enqueue distinct failed replays back to back, then drain once before reading.
        constexpr int replays = 8;
        for (int i = 0; i < replays; ++i) {
            begin();
            PMDoorFinish(NO);
        }
        expectProgress(1 + replays, 1);
        // An ordinary door never owns the chapter LIFE ladder. Verify course
        // outcomes change a single revision even when all three keys change.
        uint64_t revision=PMOSAuthorProgressRevision();
        PMDoorRecordCourseOutcome(@"chapter",@"course",1,NO);
        PMDoorProgressBarrier();CHECK(PMOSAuthorProgressRevision()==revision+1);
        std::thread([&]{ @autoreleasepool {
            auto store=[[PMOSAuthorProgress alloc]initWithRoot:testRoot chapter:@"chapter"];
            NSDictionary *v=[store snapshotValues];
            CHECK([v[@"life.ceiling"] intValue]==2 && [v[@"life.choice"] intValue]==3);
            CHECK([v[@"door.course.fail"] intValue]==1 && !v[@"door.course.clear"]);
            // User changed the selection since launch. A result on tier 2
            // must use that launch tier, while preserving a valid lower choice.
            CHECK([store commitValues:@{@"life.choice":@1}]);
        }}).join();
        revision=PMOSAuthorProgressRevision();
        PMDoorRecordCourseOutcome(@"chapter",@"course",2,YES);
        PMDoorProgressBarrier();CHECK(PMOSAuthorProgressRevision()==revision+1);
        std::thread([&]{ @autoreleasepool {
            auto store=[[PMOSAuthorProgress alloc]initWithRoot:testRoot chapter:@"chapter"];
            NSDictionary *v=[store snapshotValues];
            CHECK([v[@"life.ceiling"] intValue]==1 && [v[@"life.choice"] intValue]==1);
            CHECK([v[@"door.course.clear"] intValue]==1 && [v[@"door.course.fail"] intValue]==1);
            auto other=[[PMOSAuthorProgress alloc]initWithRoot:testRoot chapter:@"other"];
            CHECK([other snapshotValues].count==0);
        }}).join();
        CHECK([NSFileManager.defaultManager removeItemAtPath:testRoot error:nullptr]);
    }
    std::puts("door run lifecycle tests passed");
    return 0;
}
