#import "../PhiMod/Sources/PMStorySequence.h"
#import "../PhiMod/Sources/PMDoorRun.h"
#import "../PhiMod/Sources/PMOSAuthorProgress.h"
#import "../PhiMod/Sources/PMDiagnostics.h"
#include <cassert>
#include <thread>

static NSString *root;
NSString *PMDoorRunTestRoot() { return root; }
void PMDiagnosticsWrite(const char *) {}
static BOOL first(NSArray *songs) {
    return PMDoorArm(@"chapter", @"gate", @"one", 1, @"one-HD", 20, @[@1,@0,@(-2),@(-3)]) &&
           PMStorySequenceArm(@"chapter", songs);
}
static BOOL begin(NSString *group, int slot, NSString *chart) {
    double hp=0, delta[4]={};
    BOOL ok=PMDoorBeginExactTrack(group,slot,chart,&hp,delta);
    if (ok) assert(hp==20 && delta[0]==1 && delta[3]==-3);
    return ok;
}
static void expect(int clears,int fails) {
    PMDoorProgressBarrier();
    std::thread([=] { @autoreleasepool {
        PMOSAuthorProgress *store=[[PMOSAuthorProgress alloc] initWithRoot:root chapter:@"chapter"];
        int val=-1; assert([store readKey:@"door.gate.clear" value:&val] && val==clears);
        assert([store readKey:@"door.gate.fail" value:&val] && val==fails);
    }}).join();
}
static BOOL launch(NSString *sid, NSString *diff) {
    return PMStorySequenceSelectorReady(@"chapter", ^BOOL(NSString *id_,NSString *difficulty,PMChapterDoorArm arm){
        assert([sid isEqual:id_] && (difficulty==diff || [difficulty isEqual:diff]));
        return arm(@"native",3,sid);
    });
}
int main() { @autoreleasepool {
    root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSArray *one=@[@{@"songID":@"two",@"difficulty":@"SP"}];
    NSArray *two=[one arrayByAddingObject:@{@"songID":@"three"}];
    assert(!PMStorySequenceArm(@"chapter", one));
    assert(!first([two arrayByAddingObject:one[0]])); PMDoorAbandon();
    assert(first(two)); assert(!begin(@"one",1,@"wrong")); PMDoorFinish(YES);
    assert(!launch(@"two",@"SP")); expect(0,0);
    assert(first(two) && begin(@"one",1,@"one-HD")); PMDoorFinish(NO);
    assert(!launch(@"two",@"SP")); expect(0,1);
    assert(first(two) && begin(@"one",1,@"one-HD")); PMDoorAbandon();
    PMDoorFinish(YES); assert(!launch(@"two",@"SP")); expect(0,1);
    assert(first(two) && begin(@"one",1,@"one-HD")); PMDoorFinish(YES); PMDoorFinish(YES); expect(0,1);
    PMDoorCancelPending(); // Chapter scene entry must not erase an earned clear.
    __block int calls=0;
    BOOL (^available)(NSString*)=^BOOL(NSString *c){return [c isEqual:@"chapter"];};
    BOOL (^navigate)(NSString*)=^BOOL(NSString *c){++calls;return [c isEqual:@"chapter"];};
    assert(PMStorySequenceRoute(available,navigate) && PMStorySequenceRoute(available,navigate) && calls==1);
    assert(launch(@"two",@"SP") && !launch(@"two",@"SP") && begin(@"native",3,@"two"));
    PMDoorFinish(YES); expect(0,1);
    assert(launch(@"three",nil) && begin(@"native",3,@"three")); PMDoorFinish(YES);
    expect(1,1); assert(!launch(@"three",nil));
    assert(first(one) && begin(@"one",1,@"one-HD")); PMDoorFinish(YES);
    assert(launch(@"two",@"SP") && begin(@"native",3,@"two")); PMDoorFinish(NO); expect(1,2);
    assert(first(one) && begin(@"one",1,@"one-HD")); PMDoorFinish(YES);
    __block PMChapterDoorArm late=nil;
    assert(!PMStorySequenceSelectorReady(@"chapter", ^BOOL(NSString *,NSString *,PMChapterDoorArm arm){late=[arm copy];return YES;}));
    assert(!late(@"native",3,@"two") && !launch(@"two",@"SP"));
    assert(first(one) && begin(@"one",1,@"one-HD")); PMDoorFinish(YES);
    assert(!PMStorySequenceSelectorReady(@"chapter", ^BOOL(NSString *,NSString *,PMChapterDoorArm arm){assert(arm(@"native",3,@"two"));return NO;}));
    assert(!begin(@"native",3,@"two")); PMDoorFinish(YES); expect(1,2);
    // Result Retry may skip bindDoor entirely (practice, course, invalid metadata).
    assert(first(one) && begin(@"one",1,@"one-HD")); PMDoorFinish(YES);
    PMStorySequenceDiscardHandoff();
    assert(!launch(@"two",@"SP")); expect(1,2);
    // Awake also visits the same boundary on a legitimate next-song launch.
    assert(first(one) && begin(@"one",1,@"one-HD")); PMDoorFinish(YES);
    assert(launch(@"two",@"SP")); PMStorySequenceDiscardHandoff();
    assert(begin(@"native",3,@"two")); PMDoorAbandon(); expect(1,2);
    assert(first(@[]) && begin(@"one",1,@"one-HD")); PMDoorFinish(YES);
    assert(!launch(@"two",@"SP")); expect(1,2);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:nullptr]);
}}
