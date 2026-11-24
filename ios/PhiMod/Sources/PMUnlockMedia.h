#pragma once
#import <UIKit/UIKit.h>
// Completion YES means completed or explicitly skipped; NO means scene cancellation.
BOOL PMPresentUnlockMedia(NSString *path, NSString *cover, NSString *title, void (^completion)(BOOL));
BOOL PMPresentUnlockMediaWithPolicy(NSString *path,NSString *cover,NSString *title,BOOL strict,void (^completion)(BOOL));
// Called immediately after accepting an MP4 presentation on the main thread.
void PMConfigureUnlockTimeline(UIView *overlay, double duration, void (^sample)(double));
void PMCancelUnlockMedia(void);
BOOL PMUnlockMediaBusy(void);

// Transient, input-blocking overlay in the existing window; never changes scenes.
// Present/cancel on main. NO rejects without callbacks (busy/inactive/no window or
// invalid timing). Accepted requests complete exactly once; all callbacks run on
// main, and resume may be called from any queue. sample/load/completion may be nil.
// nil path uses a transparent CADisplayLink code/texture overlay; the caller authors
// its coverage/alpha. Otherwise the caller supplies
// a validated MP4/MOV path. duration == 0 uses video duration (zero-length for code);
// duration > 0 is the code duration or a video cutoff, never an extension of video.
// loadAt < 0 holds the last frame; otherwise holds at min(loadAt, end). load is
// requested once, after a held-frame render turn and a main-queue turn. A nil
// load resumes immediately at that handoff. Only the first resume is accepted:
// YES plays the remainder, NO cancels. No Skip/unlock UI. PMCancelUnlockMedia works.
// Decode/missing-media failure holds opaque black, still requests load once, then
// completes NO. Load/stall timeouts also fail NO. Background pauses, never completes
// or routes; deadlines count foreground time (decode/stall 20s, load 60s, play 610s).
BOOL PMPresentTransitionMedia(NSString * _Nullable path, UIView * _Nullable overlay,
                              double duration, double loadAt,
                              void (^ _Nullable sample)(double),
                              void (^ _Nullable load)(void (^resume)(BOOL)),
                              void (^ _Nullable completion)(BOOL));
