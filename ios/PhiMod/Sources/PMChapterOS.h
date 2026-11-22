#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef BOOL (^PMChapterDoorArm)(NSString *nativeGroup, int slot, NSString *resolvedChartID);
void PMChapterOSResumeAfterBoot(BOOL (^available)(NSString *chapter), BOOL (^navigate)(NSString *chapter));
FOUNDATION_EXPORT BOOL PMChapterOSHasRoutedCheckpoint(NSString *chapter);
// Main thread. Claims this chapter's routed boot record once. Compare scriptHash before
// dispatching the destination, then clear its persisted token with PMOSClearCheckpoint.
FOUNDATION_EXPORT NSDictionary * _Nullable PMChapterOSTakeCheckpoint(NSString *chapter);
NS_ASSUME_NONNULL_END
