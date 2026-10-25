#pragma once
#import <UIKit/UIKit.h>
// Completion YES means completed or explicitly skipped; NO means scene cancellation.
BOOL PMPresentUnlockMedia(NSString *path, NSString *cover, NSString *title, void (^completion)(BOOL));
void PMCancelUnlockMedia(void);
BOOL PMUnlockMediaBusy(void);
