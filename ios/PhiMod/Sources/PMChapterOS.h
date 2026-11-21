#pragma once
#import <Foundation/Foundation.h>
void PMOpenChapterOS(NSString *chapter, BOOL (^selectSong)(NSString *), BOOL (^startSong)(NSString *songID,NSString *difficulty));
void PMChapterOSResumeAfterBoot(BOOL (^available)(NSString *chapter), BOOL (^navigate)(NSString *chapter));
void PMCloseChapterOS(void);
BOOL PMChapterOSVisible(void);
