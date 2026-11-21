#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Main thread, settled chapter selector only. Three members, optionally followed by
// one secret fourth member. Each row is {songID: installed ID, difficulty: label}.
// difficulty is optional. Authored IDs always resolve to that exact chart;
// for stock IDs specify EZ/HD/IN/AT, or omit to use the selector's available slot.
// tier: -1 = chapter default (index 1, 10 LIFE), 0..4 = explicit 4.0.4 LifeTiers index. No clamping.
// NO means nothing launched. No saved stock tier, unlock or ranking is changed.
FOUNDATION_EXPORT BOOL PMChapterStartSecretCourse(NSString *chapter, NSString *door,
    NSArray<NSDictionary *> *members, NSInteger tier);
NS_ASSUME_NONNULL_END
