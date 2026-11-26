#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Immutable decoded image + Lua declaration. Preparation does no UIKit host work.
@interface PMPreparedSongInterruption : NSObject
@property(nonatomic, readonly) double at;
@property(nonatomic, readonly) double delay;
@property(nonatomic, readonly) NSInteger song; // One-based chapter-order metadata, NOT chartID.
@property(nonatomic, readonly, copy) NSString *difficulty;
@property(nonatomic, readonly, copy) NSString *src;
@property(nonatomic, readonly, copy) NSString *title;
@property(nonatomic, readonly, copy) NSString *message;
@property(nonatomic, readonly, copy) NSString *button;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

// Call on the Program preparation worker, NOT main. Required: at, song, src,
// title, message, button. delay defaults to 2; difficulty defaults to "".
// Optional action must be "quit". src is a PNG/JPG/JPEG/WebP basename inside
// chapterDir/os-media; only regular non-symlink files <=32 MiB are decoded.
FOUNDATION_EXPORT PMPreparedSongInterruption * _Nullable PMPrepareSongInterruption(
    NSDictionary *config, NSString *chapterDir, NSError * _Nullable * _Nullable error);

// ALL remaining entry points are main-thread-only (off-main BOOL calls return NO).
// Configure before Begin (before Arm also works). Blocks are copied into the
// accepted playing owner, never read from a newer launch. guard checks the caller's
// native chart/coordinator lifetime in addition
// to our real Unity view/window checks. nil guard uses only those UIKit checks.
// invalidated runs once on main when a playing owner is retired (including End,
// replacement, host loss or freeze failure), AFTER its UI/tickets are invalidated.
// It must not route, save, quit or unfreeze a newer owner. Use it to cancel old async
// coordinator work. A successful close invokes ONLY quit, not invalidated, until End.
FOUNDATION_EXPORT void PMSetSongInterruptionHostGuard(
    BOOL (^ _Nullable guard)(void), void (^ _Nullable invalidated)(void));

// Arm has no HP dependency. May precompose PMCompleteCover for the current real
// game window aspect; Trigger corrects a changed orientation with the same helper.
// nil clears pending and returns YES, without touching a playing interruption.
FOUNDATION_EXPORT BOOL PMArmSongInterruption(
    PMPreparedSongInterruption * _Nullable prepared, NSString * _Nullable chartID, int slot);
FOUNDATION_EXPORT BOOL PMSongInterruptionPending(void);
// Always retires old playing; consumes pending exactly once. A wrong tuple drops it.
FOUNDATION_EXPORT BOOL PMBeginSongInterruption(NSString * _Nullable chartID, int slot);
FOUNDATION_EXPORT void PMCancelSongInterruptionLaunch(void); // Pending only.
FOUNDATION_EXPORT void PMEndSongInterruption(void); // Pending AND playing.
FOUNDATION_EXPORT BOOL PMSongInterruptionDue(double songTime);
// Obtain real game host, reserve once, call freeze before attaching the image.
// NO from freeze never enables blocking; caller restores any partial native freeze.
// NO also means unavailable/invalid host or presentation failure; if freeze already
// succeeded, the caller must restore it on that failure/invalidation. The owner never
// calls native Pause/Play/coroutines, writes progress, or exits the process itself.
// After first attached CADisplayLink frame: continuous monotonic delay, then one
// native UIAlertController with one default action. Background elapsed time counts,
// but presentation waits for an active scene. quit is valid once, on user action only.
FOUNDATION_EXPORT BOOL PMTriggerSongInterruption(
    BOOL (^freeze)(void), void (^quit)(void));
FOUNDATION_EXPORT BOOL PMSongInterruptionBlocking(void);
NS_ASSUME_NONNULL_END
