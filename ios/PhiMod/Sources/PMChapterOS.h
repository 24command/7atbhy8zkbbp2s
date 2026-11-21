#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef BOOL (^PMChapterDoorArm)(NSString *nativeGroup, int slot, NSString *resolvedChartID);
void PMOpenChapterOS(NSString *chapter, BOOL (^selectSong)(NSString *),
                     BOOL (^startSong)(NSString *songID, NSString * _Nullable difficulty, PMChapterDoorArm _Nullable arm));
void PMChapterOSResumeAfterBoot(BOOL (^available)(NSString *chapter), BOOL (^navigate)(NSString *chapter));
void PMCloseChapterOS(void);
BOOL PMChapterOSVisible(void);
NS_ASSUME_NONNULL_END
