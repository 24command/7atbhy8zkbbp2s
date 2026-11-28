#pragma once
#import <Foundation/Foundation.h>
@class UIView;

NS_ASSUME_NONNULL_BEGIN
// Immutable decoded image + Lua declaration. Preparation does no UIKit host work.
@interface PMPreparedSongInterruption : NSObject
@property(nonatomic, readonly) double at;
@property(nonatomic, readonly) double delay;
@property(nonatomic, readonly) BOOL staged;
@property(nonatomic, readonly) double effectDuration;
@property(nonatomic, readonly) double blackDuration;
@property(nonatomic, readonly) double blueDuration;
@property(nonatomic, readonly, copy) NSString *effectAudioSrc; // Empty means silent.
@property(nonatomic, readonly, copy) NSString *blackAudioSrc;
@property(nonatomic, readonly, copy) NSString *blueAudioSrc;
@property(nonatomic, readonly) double audioVolume;
@property(nonatomic, readonly) double effectAudioDelay, blackAudioDelay, blueAudioDelay;
@property(nonatomic, readonly) BOOL audioTail;
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

// New optional keys: effectDuration=0, blackDuration=0, blueDuration=delay.
// Presence of ANY duration key opts into foreground-visible per-stage timing.
// Each duration is finite, 0...600 seconds; blackDuration=5, blueDuration=3 gives
// the requested strict black/blue holds. No effect visual is synthesized.
// effectAudioSrc / blackAudioSrc / blueAudioSrc are optional basenames in os-media
// (wav/mp3/m4a/aac/caf/aiff/aif), regular non-symlink files totaling <=32 MiB.
// Any audio configuration requires an explicitly enabled staged timeline.
// A supplied sound requires a positive duration for its stage. Each stage can
// play its own sound; audioVolume defaults to 1 (0...1) for all stage sounds.
// Each sound starts once at its phase AudioDelay (default 0, before stage end).
// audioTail=false stops at stage exit; true preserves original one-shot tails
// across visual transitions, with at most one instance for each of 3 phases.
// deactivation pauses its position; exit/cancel stops it. Playback failure mutes
// that stage without aborting the visual timeline. Preparation never activates an
// audio session; prepareToPlay/play occur only at the stage's first visible frame.
// We do not change the shared audio-session category or activation explicitly.
// Missing audio/effect assets must be supplied by the caller, not substituted.

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

typedef NS_ENUM(NSInteger, PMSongInterruptionEffectEvent) {
    PMSongInterruptionEffectStart,
    PMSongInterruptionEffectPause,
    PMSongInterruptionEffectResume,
    PMSongInterruptionEffectStop,
    PMSongInterruptionEffectFrame
};
// Configure before Begin. Captured per playing owner, just like the host guard.
// Main-thread handler owns ONLY visuals in this dedicated full-window container.
// Frame is delivered on visible display ticks; duration is the declared effect duration.
// Start attaches the supplied effect; Pause/Resume preserve progress; Stop releases
// it exactly once, including failed Start. Return NO on failure (Stop result ignored).
// May synchronously End/Begin; ticket checks protect replacement owners. Do not
// manipulate chart clocks, native audio, pause hooks, saves, navigation or quitting.
// effectDuration>0 requires a handler; Begin rejects a missing handler before freeze.
FOUNDATION_EXPORT void PMSetSongInterruptionEffectHandler(
    BOOL (^ _Nullable handler)(PMSongInterruptionEffectEvent event, UIView *container, NSTimeInterval duration));

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
// Legacy: after first attached frame, continuous delay (background time counts).
// Explicit timeline: optional effect -> black -> blue, each starting on its own
// attached frame, with background time excluded and no catch-up between stages.
// Then one animated native UIAlertController with one default action. Presentation
// waits for an active scene. quit is valid once, on user action only.
FOUNDATION_EXPORT BOOL PMTriggerSongInterruption(
    BOOL (^freeze)(void), void (^quit)(void));
FOUNDATION_EXPORT BOOL PMSongInterruptionBlocking(void);
NS_ASSUME_NONNULL_END
