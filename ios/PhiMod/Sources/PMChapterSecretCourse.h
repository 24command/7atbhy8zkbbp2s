#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Main thread, from the active owned chapter OS or a settled chapter selector.
// For an OS launch, prepare every member (including the fourth) with rows::prepare
// before entering the OS. Call before releasing its rows or leaving its scene.
// The course owns its queue and chart bindings once the call returns YES.
// Members are three ordered rows and an optional secret fourth row.
// Each row is {songID: installed ID, difficulty: label}.
// difficulty is optional. Authored IDs always resolve to that exact chart;
// for stock IDs specify EZ/HD/IN/AT, or omit to use the selector's available slot.
// tier: -1 = chapter default (index 1, 10 LIFE), 0..4 = explicit 4.0.4 LifeTiers index. No clamping.
// NO means nothing launched. No saved stock tier, unlock or ranking is changed.
FOUNDATION_EXPORT BOOL PMChapterStartSecretCourse(NSString *chapter, NSString *door,
    NSArray<NSDictionary *> *members, NSInteger tier);
FOUNDATION_EXPORT BOOL PMChapterStartSecretCourseWithPauseLock(NSString *chapter, NSString *door,
    NSArray<NSDictionary *> *members, NSInteger tier, BOOL noPause);
NS_ASSUME_NONNULL_END
