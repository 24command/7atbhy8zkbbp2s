#import "../PhiMod/Sources/PMOSAuthorProgress.h"
#import <dispatch/dispatch.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <thread>

#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "line %d: %s\n", __LINE__, #__VA_ARGS__); abort(); } } while (0)

static PMOSAuthorProgress *store(NSString *root, NSString *chapter) {
    PMOSAuthorProgress *result = [[PMOSAuthorProgress alloc] initWithRoot:root chapter:chapter];
    CHECK(result);
    return result;
}

static int get(PMOSAuthorProgress *store, NSString *key) {
    int value = -99;
    CHECK([store readKey:key value:&value]);
    return value;
}

static void checkMerge(NSString *root) {
    PMOSAuthorProgress *one = store(root, @"pm_Caf\u00e9");
    PMOSAuthorProgress *same = store(root, @"pm_Cafe\u0301");
    PMOSAuthorProgress *other = store(root, @"pm_caf\u00e9");
    CHECK(get(one, @"flag") == 0);
    CHECK([one commitValues:@{@"flag": @(INT32_MIN), @"FLAG": @(INT32_MAX)}]);
    CHECK([same commitValues:@{@"story.part-1_seen": @1}]);
    CHECK(get(same, @"flag") == INT32_MIN && get(one, @"FLAG") == INT32_MAX);
    CHECK(get(one, @"story.part-1_seen") == 1 && get(other, @"flag") == 0);
    CHECK([other commitValues:@{@"flag": @9}] && get(one, @"flag") == INT32_MIN);

    NSString *longest = [@"" stringByPaddingToLength:64 withString:@"k" startingAtIndex:0];
    CHECK([one commitValues:@{longest: @7}] && get(one, longest) == 7);
    for (NSString *bad in @[@"", @"a/b", @"a b", @"caf\u00e9", [longest stringByAppendingString:@"x"]]) {
        int value = 10;
        CHECK(![one readKey:bad value:&value] && value == 10);
        CHECK(![one commitValues:@{@"flag": @1, bad: @8}]);
    }
    for (id bad in @[@YES, @1.0, @1.5, @(INT64_MAX), @(-2147483649LL), @"9"]) {
        CHECK(![one commitValues:@{@"flag": @1, @"bad": bad}]);
    }
    CHECK(get(one, @"flag") == INT32_MIN);
    CHECK(![[PMOSAuthorProgress alloc] initWithRoot:root chapter:@"../exports"]);
    CHECK(![[PMOSAuthorProgress alloc] initWithRoot:@"relative" chapter:@"pm_test"]);
}

static void checkCapacityAndConcurrency(NSString *root) {
    PMOSAuthorProgress *full = store(root, @"full");
    NSMutableDictionary *batch = [NSMutableDictionary new];
    for (int i = 0; i < 512; ++i) batch[[@(i) stringValue]] = @(i);
    CHECK([full commitValues:batch]);
    CHECK(![full commitValues:@{@"extra": @1, @"0": @7}]);
    CHECK(get(full, @"0") == 0 && get(full, @"extra") == 0);
    CHECK([full commitValues:@{@"0": @7}] && get(full, @"0") == 7);

    dispatch_apply(32, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t i) {
        @autoreleasepool {
            CHECK([store(root, @"parallel") commitValues:@{[@(i) stringValue]: @(i + 1)}]);
        }
    });
    PMOSAuthorProgress *combined = store(root, @"parallel");
    for (int i = 0; i < 32; ++i) CHECK(get(combined, [@(i) stringValue]) == i + 1);
}

static void checkCorruption(NSString *root) {
    PMOSAuthorProgress *target = store(root, @"x");
    CHECK([target commitValues:@{@"valid": @3}]);
    NSString *path = [root stringByAppendingPathComponent:@"author-progress/78.plist"];
    NSMutableDictionary *oversize = [NSMutableDictionary new];
    for (int i = 0; i < 513; ++i) oversize[[@(i) stringValue]] = @0;
    NSMutableArray *badFiles = [NSMutableArray arrayWithObjects:[NSData data],
        [@"broken plist <" dataUsingEncoding:NSUTF8StringEncoding], [NSMutableData dataWithLength:128 * 1024 + 1], nil];
    for (id invalid in @[@[], @{@"bad/key": @1}, @{@"v": @YES}, @{@"v": @(INT64_MAX)}, oversize]) {
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:invalid format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0 error:nullptr];
        CHECK(data);
        [badFiles addObject:data];
    }
    for (NSData *bad in badFiles) {
        CHECK([bad writeToFile:path atomically:YES]);
        int untouched = 19;
        CHECK(![target readKey:@"valid" value:&untouched] && untouched == 19);
        CHECK(![target commitValues:@{}] && ![target commitValues:@{@"valid": @4}]);
        CHECK([[NSData dataWithContentsOfFile:path] isEqualToData:bad]);
    }

    NSFileManager *files = NSFileManager.defaultManager;
    CHECK([files removeItemAtPath:path error:nullptr]);
    NSString *outside = [root stringByAppendingPathComponent:@"outside.plist"];
    CHECK([@{@"valid": @99} writeToFile:outside atomically:YES]);
    CHECK([files createSymbolicLinkAtPath:path withDestinationPath:outside error:nullptr]);
    int value = 0;
    CHECK(![target readKey:@"valid" value:&value] && ![target commitValues:@{@"valid": @4}]);
    CHECK([[NSDictionary dictionaryWithContentsOfFile:outside][@"valid"] intValue] == 99);
}

int main() {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        PMOSAuthorProgress *progress = store(root, @"test");
        int value = 17;
        CHECK(![progress readKey:@"missing" value:&value] && value == 17);
        CHECK(![progress commitValues:@{@"flag": @1}]);
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:root]);
        std::thread worker([root] { @autoreleasepool {
            checkMerge(root);
            checkCapacityAndConcurrency(root);
            checkCorruption(root);
            CHECK([NSFileManager.defaultManager removeItemAtPath:root error:nullptr]);
        }});
        worker.join();
    }
    return 0;
}
