#pragma once
#import "PMChapterOS.h"

NS_ASSUME_NONNULL_BEGIN
// Main-thread bridge. Call Arm immediately AFTER PMDoorArm inside startSong's
// checked arm callback. Zero to two remaining installed IDs, not Lua indices.
// Row form: @{@"songID": id, @"difficulty": optionalLabel}.
typedef BOOL (^PMStoryStartSong)(NSString *songID, NSString * _Nullable difficulty,
                                 PMChapterDoorArm _Nullable arm);
FOUNDATION_EXPORT BOOL PMStorySequenceArm(NSString *chapter, NSArray<NSDictionary *> * _Nullable nextSongs);
// At chapter-ready, before boot-checkpoint routing. YES owns this navigation.
FOUNDATION_EXPORT BOOL PMStorySequenceRoute(BOOL (^available)(NSString *chapter),
                                            BOOL (^navigate)(NSString *chapter));
// At settled song-selector entry, before opening the OS; YES accepted a launch.
FOUNDATION_EXPORT BOOL PMStorySequenceSelectorReady(NSString *chapter, PMStoryStartSong startSong);
// Expire a cleared handoff without disturbing an exact pending launch.
FOUNDATION_EXPORT void PMStorySequenceDiscardHandoff(void);
NS_ASSUME_NONNULL_END
