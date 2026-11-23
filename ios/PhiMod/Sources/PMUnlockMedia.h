#pragma once
#import <UIKit/UIKit.h>
// Completion YES means completed or explicitly skipped; NO means scene cancellation.
BOOL PMPresentUnlockMedia(NSString *path, NSString *cover, NSString *title, void (^completion)(BOOL));
BOOL PMPresentUnlockMediaWithPolicy(NSString *path,NSString *cover,NSString *title,BOOL strict,void (^completion)(BOOL));
// Called immediately after accepting an MP4 presentation on the main thread.
void PMConfigureUnlockTimeline(UIView *overlay, double duration, void (^sample)(double));
void PMCancelUnlockMedia(void);
BOOL PMUnlockMediaBusy(void);
