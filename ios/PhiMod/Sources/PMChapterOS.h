#pragma once
#import <Foundation/Foundation.h>
void PMOpenChapterOS(NSString *chapter, BOOL (^selectSong)(NSString *));
void PMCloseChapterOS(void);
BOOL PMChapterOSVisible(void);
